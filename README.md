# Supply-Chain-Warehouse-Management

Ứng dụng Phase 4 cho đồ án quản lý kho và chuỗi cung ứng. FastAPI phục vụ giao diện HTML/CSS/JavaScript và REST API, còn MySQL lưu dữ liệu và xử lý các quy tắc trong trigger Phase 3.

## Chuẩn bị MySQL

Dùng MySQL 8.0.16 trở lên và một schema trống cho lần cài mới. Các file SQL mặc định dùng schema `supply_chain_g3`. Trong MySQL Workbench, chạy `database/01_schema.sql`, `02_mock_data.sql`, `05_views.sql`, rồi `07_triggers.sql`. Dữ liệu mẫu có bản ghi lịch sử nên cần nạp trước khi tạo trigger. Nếu schema đã được cài đủ bảng, view và trigger, bỏ qua bước khởi tạo.

Các file `03_queries.sql`, `04_queries.sql` và `06_queries_8.9.10.sql` chứa các truy vấn báo cáo. File `08_trigger_tests.sql` dùng để kiểm tra trigger trên bộ dữ liệu mẫu ban đầu.

Sao chép `.env.example` thành `.env` rồi điền thông tin tài khoản MySQL của bạn. Tài khoản ứng dụng cần quyền SELECT, INSERT, UPDATE và DELETE trên schema đã cài.

## Chạy ứng dụng trên Windows

Mở PowerShell tại thư mục gốc của repo. Dùng Python 3.10 trở lên:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
Copy-Item .env.example .env
```

Sau khi điền `.env`, chạy:

```powershell
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Giao diện tại <http://127.0.0.1:8000>, tài liệu Swagger tại <http://127.0.0.1:8000/docs>. Bản demo chạy local và chưa có đăng nhập/phân quyền.

## Kịch bản demo

1. Mở Tổng quan và Tồn kho, ghi lại số lượng của sản phẩm ở hai kho.
2. Tạo chuyến nháp, thêm một hoặc nhiều sản phẩm rồi bấm **Bắt đầu vận chuyển**.
3. Bấm **Hoàn tất chuyển kho**. Tab Tồn kho sẽ hiển thị số mới khi mở lại.
4. Thử một chuyến khác có số lượng vượt tồn kho nguồn. Ứng dụng báo lỗi, chuyến vẫn đang vận chuyển và không thay đổi tồn kho.
5. Tạo đơn nhập nháp, thêm/sửa/xóa dòng và xem tổng tiền thay đổi.

Kiểm thử API với một schema demo mới có dữ liệu mẫu và ứng dụng đang chạy tại cổng 8000:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests
```

Kiểm thử tích hợp có tạo và hoàn tất một chuyến demo trên schema đang kết nối. Mỗi lần chạy cần một schema test riêng hoặc bộ dữ liệu được khôi phục.
