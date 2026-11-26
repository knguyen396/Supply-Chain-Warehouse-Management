import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pymysql import MySQLError

from .database import ROOT
from .routes import api

app = FastAPI(title="Warehouse Logistics API", version="1.0.0")
app.include_router(api)
app.mount("/assets", StaticFiles(directory=ROOT / "frontend" / "assets"), name="assets")

BUSINESS_MESSAGES = {
    "Insufficient source inventory": "Kho nguồn không đủ hàng để hoàn tất chuyến.",
    "Cannot dispatch or complete shipment without details": "Chuyến hàng cần ít nhất một dòng sản phẩm.",
    "Cannot complete supplier order without details": "Đơn nhập cần ít nhất một dòng sản phẩm.",
    "Invalid shipment status transition": "Không thể chuyển chuyến sang trạng thái này.",
    "Invalid supplier order status transition": "Không thể chuyển đơn nhập sang trạng thái này.",
}


@app.get("/", include_in_schema=False)
def home():
    return FileResponse(ROOT / "frontend" / "index.html")


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    error = exc.errors()[0]
    field = ".".join(str(part) for part in error["loc"][1:])
    return JSONResponse({"detail": f"{field}: {error['msg']}"}, status_code=422)


@app.exception_handler(MySQLError)
async def database_error(request: Request, exc: MySQLError):
    code = exc.args[0] if exc.args else None
    if code == 1644:
        detail = BUSINESS_MESSAGES.get(exc.args[1] if len(exc.args) > 1 else None,
                                       "Thao tác vi phạm quy tắc nghiệp vụ.")
        return JSONResponse({"detail": detail}, status_code=409)
    messages = {
        1062: (409, "Mã hoặc giá trị duy nhất đã tồn tại."),
        1451: (409, "Dữ liệu đang được tham chiếu và chưa thể xóa."),
        1217: (409, "Dữ liệu đang được tham chiếu và chưa thể xóa."),
        1452: (409, "Kho, sản phẩm hoặc bản ghi liên quan không tồn tại."),
        1264: (422, "Giá trị vượt giới hạn lưu trữ."),
        3819: (422, "Giá trị không thỏa ràng buộc của cơ sở dữ liệu."),
        1205: (409, "Dữ liệu đang được cập nhật. Hãy thử lại."),
        1213: (409, "Có thao tác đồng thời trên cùng dữ liệu. Hãy thử lại."),
        1045: (503, "Không thể đăng nhập MySQL. Hãy kiểm tra cấu hình .env."),
        1049: (503, "Chưa tìm thấy schema. Hãy cài bộ SQL Phase 3."),
        1146: (503, "Thiếu bảng hoặc view. Hãy cài bộ SQL Phase 3."),
        2003: (503, "Không kết nối được MySQL. Hãy kiểm tra máy chủ và .env."),
    }
    if code not in messages:
        logging.getLogger(__name__).error("MySQL operation failed with code %s", code)
    status, message = messages.get(code, (500, "Cơ sở dữ liệu không thể hoàn thành thao tác."))
    return JSONResponse({"detail": message}, status_code=status)
