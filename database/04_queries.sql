-- =====================================================================
-- 04_queries_hoangkhang.sql
-- Người thực hiện: Vũ Hoàng Khang
-- Phạm vi: Query 4 - 7 (đơn mua hàng, shipment, BOM)
-- Database: supply_chain_g3
-- =====================================================================
USE supply_chain_g3;

-- ---------------------------------------------------------------------
-- QUERY 4: Số đơn và giá trị mua hàng theo supplier
-- Mục đích : Tổng hợp mức độ giao dịch với từng nhà cung cấp.
-- Kỹ thuật : LEFT JOIN (điều kiện lọc đặt trong ON để supplier chưa có đơn
--            vẫn xuất hiện), GROUP BY, COUNT, SUM, AVG.
-- ---------------------------------------------------------------------
SELECT
    s.supplier_id,
    s.supplier_name,
    COUNT(o.order_id)                    AS so_don,
    COALESCE(SUM(o.total_amount), 0)     AS tong_gia_tri_mua,
    COALESCE(AVG(o.total_amount), 0)     AS gia_tri_trung_binh_moi_don
FROM supplier AS s
LEFT JOIN supplier_order AS o
    ON o.supplier_id = s.supplier_id
   AND o.status <> 'Canceled'
GROUP BY s.supplier_id, s.supplier_name
ORDER BY tong_gia_tri_mua DESC;


-- ---------------------------------------------------------------------
-- QUERY 5: Supplier có tổng giá trị đơn hàng cao hơn mức trung bình
--          giữa các supplier
-- Mục đích : Xác định các nhà cung cấp chủ lực (chi tiêu vượt mức TB).
-- Kỹ thuật : CTE (tính tổng theo supplier) + subquery scalar (AVG của các tổng),
--            JOIN, GROUP BY, so sánh với giá trị trung bình.
-- ---------------------------------------------------------------------
WITH supplier_total AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        COALESCE(SUM(o.total_amount), 0) AS tong_gia_tri
    FROM supplier AS s
    LEFT JOIN supplier_order AS o
        ON o.supplier_id = s.supplier_id
       AND o.status <> 'Canceled'
    GROUP BY s.supplier_id, s.supplier_name
)
SELECT
    st.supplier_id,
    st.supplier_name,
    st.tong_gia_tri,
    (SELECT AVG(tong_gia_tri) FROM supplier_total) AS trung_binh_theo_supplier
FROM supplier_total AS st
WHERE st.tong_gia_tri > (SELECT AVG(tong_gia_tri) FROM supplier_total)
ORDER BY st.tong_gia_tri DESC;


-- ---------------------------------------------------------------------
-- QUERY 6: Số shipment theo kho nguồn và trạng thái
-- Mục đích : Theo dõi khối lượng vận chuyển xuất từ mỗi kho theo từng
--            trạng thái (Pending / In-Transit / Completed / Canceled).
-- Kỹ thuật : JOIN (shipment - warehouse nguồn), GROUP BY 2 cột, COUNT.
-- ---------------------------------------------------------------------
SELECT
    w.warehouse_id   AS kho_nguon_id,
    w.warehouse_name AS kho_nguon,
    sh.status        AS trang_thai,
    COUNT(sh.shipment_id) AS so_shipment
FROM shipment AS sh
JOIN warehouse AS w
    ON w.warehouse_id = sh.source_warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name, sh.status
ORDER BY w.warehouse_id, sh.status;


-- ---------------------------------------------------------------------
-- QUERY 7: BOM nhiều cấp - các thành phần của một sản phẩm
-- Mục đích : Liệt kê toàn bộ thành phần (mọi cấp) của một sản phẩm, kèm cấp
--            cấu trúc, số lượng cần ở cấp đó và tổng số lượng quy đổi
--            cho 1 đơn vị sản phẩm gốc.
-- Kỹ thuật : Recursive CTE (anchor = cấp 1, phần đệ quy nối product_structure),
--            nhân dồn quantity_required, chuỗi path để dễ đọc cây,
--            dùng JSON để kiểm tra các mã đã xuất hiện trên từng đường đi.
-- ---------------------------------------------------------------------
SET @root_product_id = _utf8mb4'P001' COLLATE utf8mb4_unicode_ci;

WITH RECURSIVE bom AS (
    -- Anchor: thành phần trực tiếp (cấp 1)
    SELECT
        ps.parent_product_id,
        ps.child_component_id,
        1                              AS cap,
        ps.quantity_required           AS so_luong_tai_cap,
        CAST(ps.quantity_required AS DECIMAL(65, 0)) AS tong_so_luong_quy_doi,
        JSON_ARRAY(ps.parent_product_id, ps.child_component_id) AS duong_dan
    FROM product_structure AS ps
    WHERE ps.parent_product_id = @root_product_id

    UNION ALL

    -- Đệ quy: thành phần của thành phần
    SELECT
        ps.parent_product_id,
        ps.child_component_id,
        b.cap + 1,
        ps.quantity_required,
        b.tong_so_luong_quy_doi * ps.quantity_required,
        JSON_ARRAY_APPEND(b.duong_dan, '$', ps.child_component_id)
    FROM bom AS b
    JOIN product_structure AS ps
        ON ps.parent_product_id = b.child_component_id
    WHERE NOT JSON_CONTAINS(b.duong_dan, JSON_QUOTE(ps.child_component_id))
)
SELECT
    @root_product_id               AS san_pham_goc,
    b.cap,
    b.parent_product_id            AS thanh_phan_cha,
    b.child_component_id           AS thanh_phan_con,
    p.product_name                 AS ten_thanh_phan,
    p.unit,
    b.so_luong_tai_cap,
    b.tong_so_luong_quy_doi,
    b.duong_dan
FROM bom AS b
JOIN product AS p
    ON p.product_id = b.child_component_id
ORDER BY b.cap, b.parent_product_id, b.child_component_id;
