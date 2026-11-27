from getpass import getpass

from pymysql.err import IntegrityError
from pydantic import ValidationError

from .auth import NewUser, password_hash
from .database import session


def main():
    username = input("Tên đăng nhập admin: ").strip()
    password = getpass("Mật khẩu (ít nhất 12 ký tự): ")
    if password != getpass("Nhập lại mật khẩu: "):
        raise SystemExit("Hai mật khẩu chưa khớp.")
    try:
        account = NewUser(username=username, password=password, role="admin")
    except ValidationError:
        raise SystemExit("Tên đăng nhập hoặc mật khẩu không đúng định dạng.") from None
    hashed = password_hash(account.password)
    try:
        with session() as cursor:
            cursor.execute("INSERT INTO app_user (username, password_hash, role) VALUES (%s, %s, 'admin')",
                           (account.username.lower(), hashed))
    except IntegrityError:
        raise SystemExit("Tên đăng nhập đã tồn tại.") from None
    print("Đã tạo tài khoản admin.")


if __name__ == "__main__":
    main()
