import hashlib
import hmac
import os
import secrets
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from .database import session

Role = Literal["admin", "warehouse", "procurement", "logistics"]
Username = Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_.-]{3,32}$")]
COOKIE = "g3_session"
SESSION_SECONDS = 8 * 3600
SAFE = {"GET", "HEAD", "OPTIONS"}
READ = {
    "warehouse": {"dashboard", "warehouses", "products", "inventory", "alerts"},
    "procurement": {"dashboard", "products", "inventory", "suppliers", "orders"},
    "logistics": {"dashboard", "warehouses", "products", "inventory", "shipments"},
}
WRITE = {
    "warehouse": {"inventory", "alerts"},
    "procurement": {"suppliers", "orders"},
    "logistics": {"shipments"},
}
auth = APIRouter(prefix="/api", tags=["auth"])


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    username: Username
    password: str = Field(min_length=1, max_length=128)


class NewUser(Credentials):
    password: str = Field(min_length=12, max_length=128)
    role: Role


class RoleChange(BaseModel):
    role: Role


def password_hash(password, salt=None):
    salt = salt if salt is not None else secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 600_000)
    return f"{salt.hex()}:{digest.hex()}"


def hash_token(token):
    return hashlib.sha256(token.encode()).digest()


def protect_write(request):
    if request.method not in SAFE and request.headers.get("X-G3-Request") != "1":
        raise HTTPException(403, "Thiếu header X-G3-Request: 1.")


def current_user(request: Request):
    token = request.cookies.get(COOKIE)
    if not token or len(token) != 43:
        raise HTTPException(401, "Bạn cần đăng nhập.")
    with session() as cursor:
        cursor.execute("""
            SELECT u.user_id, u.username, u.role FROM app_session s
            JOIN app_user u ON u.user_id = s.user_id
            WHERE s.token_hash = %s AND s.expires_at > UTC_TIMESTAMP()
        """, (hash_token(token),))
        user = cursor.fetchone()
    if user is None:
        raise HTTPException(401, "Phiên đăng nhập đã hết hạn.")
    return user


def permissions(user):
    role = user["role"]
    modules = set().union(*READ.values())
    return {**user, "read": sorted(modules if role == "admin" else READ[role]),
            "write": sorted(modules - {"dashboard"} if role == "admin" else WRITE[role])}


def authorized(request: Request, user=Depends(current_user)):
    protect_write(request)
    resource = request.url.path.split("/")[2]
    operation = "read" if request.method in SAFE else "write"
    if resource not in permissions(user)[operation]:
        raise HTTPException(403, "Tài khoản không có quyền thực hiện thao tác này.")
    return user


def admin_only(request: Request, user=Depends(current_user)):
    protect_write(request)
    if user["role"] != "admin":
        raise HTTPException(403, "Chức năng chỉ dành cho quản trị viên.")
    return user


@auth.post("/auth/login")
def login(payload: Credentials, request: Request, response: Response):
    protect_write(request)
    user = None
    token = secrets.token_urlsafe(32)
    with session() as cursor:
        cursor.execute("""
            SELECT user_id, username, role, password_hash, failed_attempts,
                   COALESCE(retry_after > UTC_TIMESTAMP(), 0) AS blocked,
                   retry_after IS NOT NULL AS previous_lock
            FROM app_user WHERE username = %s FOR UPDATE
        """, (payload.username,))
        row = cursor.fetchone()
        if row and row["blocked"]:
            raise HTTPException(429, "Thử lại sau 5 phút.")
        stored = row["password_hash"] if row else "0" * 32 + ":" + "0" * 64
        salt = bytes.fromhex(stored.split(":")[0])
        if hmac.compare_digest(password_hash(payload.password, salt), stored) and row:
            user = {key: row[key] for key in ("user_id", "username", "role")}
            cursor.execute("UPDATE app_user SET failed_attempts = 0, retry_after = NULL WHERE user_id = %s",
                           (user["user_id"],))
            cursor.execute("DELETE FROM app_session WHERE expires_at <= UTC_TIMESTAMP()")
            old_token = request.cookies.get(COOKIE)
            if old_token and len(old_token) == 43:
                cursor.execute("DELETE FROM app_session WHERE token_hash = %s", (hash_token(old_token),))
            cursor.execute("""
                INSERT INTO app_session (token_hash, user_id, expires_at)
                VALUES (%s, %s, TIMESTAMPADD(SECOND, %s, UTC_TIMESTAMP()))
            """, (hash_token(token), user["user_id"], SESSION_SECONDS))
        elif row:
            count = 1 if row["previous_lock"] else row["failed_attempts"] + 1
            cursor.execute("""
                UPDATE app_user SET failed_attempts = %s,
                retry_after = IF(%s >= 5, UTC_TIMESTAMP() + INTERVAL 5 MINUTE, NULL)
                WHERE user_id = %s
            """, (count, count, row["user_id"]))
    if user is None:
        raise HTTPException(401, "Tên đăng nhập hoặc mật khẩu chưa đúng.")
    response.headers["Cache-Control"] = "no-store"
    response.set_cookie(COOKIE, token, max_age=SESSION_SECONDS, httponly=True,
                        secure=request.url.scheme == "https" or os.getenv("AUTH_SECURE_COOKIE") == "1",
                        samesite="strict", path="/api")
    return permissions(user)


@auth.get("/auth/me")
def me(response: Response, user=Depends(current_user)):
    response.headers["Cache-Control"] = "no-store"
    return permissions(user)


@auth.post("/auth/logout", status_code=204)
def logout(request: Request, response: Response):
    protect_write(request)
    token = request.cookies.get(COOKIE)
    if token and len(token) == 43:
        with session() as cursor:
            cursor.execute("DELETE FROM app_session WHERE token_hash = %s", (hash_token(token),))
    response.delete_cookie(COOKIE, path="/api", httponly=True, samesite="strict",
                           secure=request.url.scheme == "https" or os.getenv("AUTH_SECURE_COOKIE") == "1")


@auth.get("/users", dependencies=[Depends(admin_only)])
def list_users():
    with session() as cursor:
        cursor.execute("SELECT user_id, username, role FROM app_user ORDER BY username")
        return cursor.fetchall()


@auth.post("/users", status_code=201, dependencies=[Depends(admin_only)])
def create_user(payload: NewUser):
    hashed = password_hash(payload.password)
    with session() as cursor:
        cursor.execute("INSERT INTO app_user (username, password_hash, role) VALUES (%s, %s, %s)",
                       (payload.username.lower(), hashed, payload.role))
    return {"username": payload.username.lower(), "role": payload.role}


@auth.patch("/users/{user_id}/role")
def change_role(user_id: int, payload: RoleChange, actor=Depends(admin_only)):
    if user_id == actor["user_id"]:
        raise HTTPException(409, "Bạn không thể tự đổi vai trò của mình.")
    with session() as cursor:
        cursor.execute("SELECT user_id, role FROM app_user WHERE user_id IN (%s, %s) ORDER BY user_id FOR UPDATE",
                       (actor["user_id"], user_id))
        accounts = {row["user_id"]: row["role"] for row in cursor.fetchall()}
        if accounts.get(actor["user_id"]) != "admin":
            raise HTTPException(403, "Tài khoản không còn quyền quản trị.")
        if user_id not in accounts:
            raise HTTPException(404, "Không tìm thấy tài khoản.")
        if accounts[user_id] != payload.role:
            cursor.execute("UPDATE app_user SET role = %s WHERE user_id = %s", (payload.role, user_id))
            cursor.execute("DELETE FROM app_session WHERE user_id = %s", (user_id,))
    return {"role": payload.role}
