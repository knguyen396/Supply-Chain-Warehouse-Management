# Supply Chain & Warehouse Logistics Network Management System

Đồ án **Cơ sở dữ liệu (INT1313)** · **Nhóm G3** · **Học kỳ 1, năm học 2026–2027**

- **Mã lớp học phần:** Cần điền theo danh sách lớp chính thức trước khi nộp.
- **Repository:** [Supply-Chain-Warehouse-Management](https://github.com/knguyen396/Supply-Chain-Warehouse-Management)

Hệ thống quản lý tồn kho nhiều kho, đơn nhập từ nhà cung cấp, chuyển hàng giữa các kho, cấu trúc sản phẩm nhiều cấp (BOM) và cảnh báo nhập hàng. FastAPI phục vụ giao diện HTML/CSS/JavaScript và REST API trên cùng địa chỉ. MySQL lưu dữ liệu, kiểm tra ràng buộc và chạy trigger cho các nghiệp vụ như đồng bộ tổng tiền đơn nhập và cập nhật tồn kho khi hoàn tất chuyển hàng.

## Thành viên

| Họ và tên | Mã số sinh viên | GitHub |
| --- | --- | --- |
| Phạm Cao Gia Khang | N24DECE076 | [giakhangcd](https://github.com/giakhangcd) |
| Nguyễn Gia Kiệt | N24DECE079 | [knguyen396](https://github.com/knguyen396) |
| Vũ Hoàng Khang | N24DECE077 | [hkang263](https://github.com/hkang263) |

## Mã nguồn, tài liệu và dữ liệu

| Vị trí | Nội dung |
| --- | --- |
| [`backend/`](backend/) | FastAPI, kết nối MySQL, API nghiệp vụ, đăng nhập, phân quyền và công cụ tạo Admin. |
| [`frontend/`](frontend/) | Giao diện quản lý kho bằng HTML, CSS và JavaScript. |
| [`database/`](database/) | Schema, dữ liệu mẫu, 10 truy vấn phân tích, views, triggers và kiểm thử SQL. |
| [`tests/`](tests/) | Kiểm thử tích hợp API với MySQL, gồm xác thực, phân quyền, đơn nhập và chuyển kho. |
| [`docs/`](docs/) | Yêu cầu nghiệp vụ, sơ đồ EER, ánh xạ lược đồ, Data Dictionary và chứng minh chuẩn hóa. |
| [Báo cáo Phase 1](REPORT%20PHASE%201_G3.pdf) | Báo cáo giai đoạn thiết kế ban đầu. |

**Bộ dữ liệu demo:** [`02_mock_data.sql`](database/02_mock_data.sql) chứa dữ liệu giả lập cho 10 bảng nghiệp vụ; không cần tải CSV riêng. Báo cáo tổng hợp Phase 1–4 cần được đặt trong `docs/` và liên kết tại đây trước khi nộp.

## Cài đặt và chạy local

**Yêu cầu:** Git, Python 3.10 trở lên và MySQL Server 8.0.16 trở lên. MySQL Workbench chỉ dùng để chạy SQL và xem dữ liệu; không cần mở Workbench khi sử dụng web.

### 1. Lấy mã nguồn và cài thư viện

Các lệnh dưới đây dùng PowerShell trên Windows. Nếu đã clone repo, mở terminal tại thư mục repo thay vì clone lại.

```powershell
git clone https://github.com/knguyen396/Supply-Chain-Warehouse-Management.git
cd Supply-Chain-Warehouse-Management
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
Copy-Item .env.example .env
```

Chỉ sao chép `.env.example` ở lần cài đầu; không ghi đè `.env` đã cấu hình.

### 2. Khởi tạo database

Trên MySQL Server của bạn, dùng tài khoản có quyền tạo schema, bảng, view và trigger. Với một môi trường mới, chạy lần lượt:

| Thứ tự | File | Tác dụng |
| --- | --- | --- |
| 1 | [`01_schema.sql`](database/01_schema.sql) | Tạo schema `supply_chain_g3`, 10 bảng nghiệp vụ, khóa, ràng buộc và index. |
| 2 | [`02_mock_data.sql`](database/02_mock_data.sql) | Nạp dữ liệu mẫu. Chạy trước khi cài trigger vì bộ mẫu có bản ghi lịch sử. |
| 3 | [`05_views.sql`](database/05_views.sql) | Tạo các view báo cáo. |
| 4 | [`07_triggers.sql`](database/07_triggers.sql) | Cài trigger nghiệp vụ. |
| 5 | [`09_app_auth.sql`](database/09_app_auth.sql) | Tạo `app_user` và `app_session`. Chọn schema `supply_chain_g3` trước khi chạy vì file không có lệnh `USE`. |

Các script hệ thống dùng tên schema `supply_chain_g3`; đổi `DB_NAME` trong `.env` không đổi schema mà script tạo hoặc chọn. Nếu schema đã có đủ bảng, view, trigger và dữ liệu, không chạy lại bộ khởi tạo.

### 3. Cấu hình và tạo Admin đầu tiên

Mở `.env` và điền thông tin kết nối của máy bạn theo [`.env.example`](.env.example):

| Biến | Giá trị hoặc ý nghĩa |
| --- | --- |
| `DB_HOST`, `DB_PORT` | Thường là `127.0.0.1` và `3306` khi MySQL chạy local. |
| `DB_NAME` | `supply_chain_g3` nếu dùng bộ SQL nguyên bản. |
| `DB_USER`, `DB_PASSWORD` | Tài khoản MySQL cho FastAPI. Tên trong file mẫu không tự tạo tài khoản MySQL. Cấp `SELECT`, `INSERT`, `UPDATE`, `DELETE` trên schema ứng dụng; dùng tài khoản khác để cài schema. |
| `AUTH_SECURE_COOKIE` | Có thể bỏ qua khi chạy local qua HTTP; đặt `1` khi chạy qua HTTPS. |

Không commit `.env` hoặc mật khẩu lên GitHub. Tài khoản MySQL ở trên khác với tài khoản đăng nhập website. Để tạo Admin đầu tiên, chạy:

```powershell
.\.venv\Scripts\python.exe -m backend.create_admin
```

Nhập tên đăng nhập và mật khẩu ít nhất 12 ký tự. Script băm mật khẩu và lưu tài khoản với vai trò Admin. Sau đó chạy ứng dụng:

```powershell
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Mở [giao diện](http://127.0.0.1:8000/) hoặc [Swagger](http://127.0.0.1:8000/docs). Giữ terminal chạy trong lúc sử dụng; nhấn `Ctrl+C` để dừng FastAPI.

## Triển khai trên máy chủ

1. Chuẩn bị MySQL riêng cho bản triển khai, dùng lưu trữ bền vững và chỉ cho backend truy cập qua máy cục bộ hoặc mạng riêng. Nạp các script theo thứ tự ở trên nếu schema còn trống. Không mở cổng MySQL ra Internet.
2. Đưa mã nguồn lên máy chủ. Đặt các biến `DB_*` trong cấu hình bí mật của môi trường chạy. `127.0.0.1` chỉ phù hợp nếu MySQL chạy trên cùng máy với FastAPI; nếu MySQL ở máy khác, dùng địa chỉ mạng riêng của nó.
3. Tại thư mục repo trên máy chủ Linux, cài thư viện rồi tạo Admin với cùng cấu hình MySQL mà app sẽ dùng. Tài khoản local không tự chuyển lên máy chủ.

   ```bash
   python3 -m venv .venv
   .venv/bin/python -m pip install -r backend/requirements.txt
   .venv/bin/python -m backend.create_admin
   ```

4. Chạy Uvicorn sau reverse proxy HTTPS (máy chủ nhận kết nối web và chuyển tiếp về FastAPI). Lệnh sau dùng khi proxy và FastAPI cùng máy. Cấu hình trình quản lý dịch vụ như systemd để chạy lệnh với cùng thư mục làm việc và biến môi trường sau khi máy khởi động lại.

   ```bash
   .venv/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
   ```

5. Cấu hình proxy chuyển tiếp tên miền HTTPS tới `127.0.0.1:8000` và đặt `AUTH_SECURE_COOKIE=1` trong môi trường FastAPI. Từ thiết bị khác, mở link HTTPS và kiểm tra đăng nhập, Dashboard và một luồng nghiệp vụ bằng dữ liệu demo. Không cần deploy frontend riêng.

## Sử dụng và trình diễn

Admin quản lý danh mục kho, sản phẩm và tài khoản. Trong menu **Tài khoản**, Admin có thể tạo người dùng và gán vai trò. Nhân viên kho chỉnh tồn và xử lý cảnh báo; nhân viên mua hàng quản lý nhà cung cấp và đơn nhập; nhân viên vận chuyển quản lý chuyến hàng. Đổi vai trò sẽ kết thúc các phiên của tài khoản đó.

1. Trên bộ dữ liệu mới, đăng nhập bằng tài khoản có quyền vận chuyển. Mở **Tồn kho**, ghi lại tồn của `P002` ở kho `W003` và `W001`.
2. Mở chuyến nháp `SH004`, bấm **Bắt đầu vận chuyển** rồi **Hoàn tất chuyển kho**. Mở lại **Tồn kho**: `P002` giảm 4 ở `W003` và tăng 4 ở `W001`.
3. Tạo chuyến khác có một dòng vượt tồn kho nguồn. Khi hoàn tất, app phải báo lỗi, chuyến vẫn đang vận chuyển và tồn ở cả hai kho không đổi.
4. Với tài khoản có quyền mua hàng, tạo đơn nhập nháp rồi thử thêm, sửa và xóa chi tiết. Đối chiếu tổng tiền sau mỗi thao tác.

API bảo vệ bằng cookie phiên. Các yêu cầu ghi, gồm đăng nhập và đăng xuất, cần header `X-G3-Request: 1`; giao diện tự thêm header này.

## Kiểm thử và làm việc nhóm

- **SQL:** Chạy [`03_queries.sql`](database/03_queries.sql), [`04_queries.sql`](database/04_queries.sql) và [`06_queries_8.9.10.sql`](database/06_queries_8.9.10.sql) để xem 10 truy vấn. Chạy [`08_trigger_tests.sql`](database/08_trigger_tests.sql) trên database kiểm thử có dữ liệu mẫu ban đầu và trigger đã cài; xem các dòng `PASS`/`FAIL`.
- **API:** Khởi động app trỏ đến database test riêng. Đặt `G3_TEST_ADMIN_USERNAME` và `G3_TEST_ADMIN_PASSWORD` trong môi trường terminal; đặt `G3_TEST_URL` nếu app không chạy ở địa chỉ mặc định `http://127.0.0.1:8000`. Sau đó chạy:

  ```powershell
  .\.venv\Scripts\python.exe -m unittest discover -s tests
  ```

  Bộ test có ghi dữ liệu. Dùng database riêng có thể tạo lại; không chạy trên bản demo đang dùng chung hoặc dữ liệu cần giữ. Nếu thiếu tài khoản kiểm thử, bộ test sẽ bị bỏ qua, không phải đã vượt qua.
- **Git:** Mỗi thành viên dùng MySQL local của mình, sửa trên nhánh riêng và mở Pull Request để thành viên khác kiểm tra trước khi merge vào `main`.
