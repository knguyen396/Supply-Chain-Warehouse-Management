-- =====================================================================
-- 03_queries_khang.sql
-- Người thực hiện: Vũ Hoàng Khang
-- Phạm vi: Query 1 - 3 (truy vấn tồn kho)
-- Database: supply_chain_g3
-- =====================================================================
USE supply_chain_g3;

-- ---------------------------------------------------------------------
-- QUERY 1: Tổng tồn kho của từng sản phẩm trên tất cả warehouse
-- Mục đích : Biết mỗi sản phẩm hiện còn bao nhiêu trên toàn hệ thống
--            và đang nằm ở bao nhiêu kho.
-- Kỹ thuật : LEFT JOIN (product - inventory), GROUP BY, SUM, COUNT.
-- ---------------------------------------------------------------------
SELECT
    p.product_id,
    p.product_name,
    p.unit,
    COUNT(CASE WHEN i.quantity_on_hand > 0 THEN i.warehouse_id END) AS so_kho_dang_chua,
    COALESCE(SUM(i.quantity_on_hand), 0) AS tong_ton_kho
FROM product AS p
LEFT JOIN inventory AS i
    ON i.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.unit
ORDER BY tong_ton_kho DESC, p.product_id;


-- ---------------------------------------------------------------------
-- QUERY 2: Sản phẩm tại từng kho có tồn thấp hơn ngưỡng nhập lại
-- Mục đích : Phát hiện các cặp (kho, sản phẩm) cần nhập thêm hàng;
--            hiển thị tồn hiện tại, ngưỡng và số lượng còn thiếu.
-- Kỹ thuật : JOIN 3 bảng (inventory - warehouse - product),
--            so sánh 2 cột trong WHERE, cột tính toán (thiếu hụt).
-- ---------------------------------------------------------------------
SELECT
    w.warehouse_id,
    w.warehouse_name,
    p.product_id,
    p.product_name,
    i.quantity_on_hand                          AS ton_hien_tai,
    p.min_reorder_level                         AS nguong_nhap_lai,
    (p.min_reorder_level - i.quantity_on_hand)  AS so_luong_thieu
FROM inventory AS i
JOIN warehouse AS w
    ON w.warehouse_id = i.warehouse_id
JOIN product AS p
    ON p.product_id = i.product_id
WHERE i.quantity_on_hand < p.min_reorder_level
ORDER BY so_luong_thieu DESC, w.warehouse_id, p.product_id;


-- ---------------------------------------------------------------------
-- QUERY 3: Tổng giá trị hàng tồn kho của từng warehouse
-- Mục đích : Định giá hàng tồn của mỗi kho = SUM(quantity_on_hand x unit_price).
-- Kỹ thuật : JOIN 3 bảng, SUM trên biểu thức, GROUP BY.
--            Dùng LEFT JOIN từ warehouse để kho trống vẫn hiện với giá trị 0.
-- ---------------------------------------------------------------------
SELECT
    w.warehouse_id,
    w.warehouse_name,
    COALESCE(SUM(i.quantity_on_hand * p.unit_price), 0) AS tong_gia_tri_ton_kho
FROM warehouse AS w
LEFT JOIN inventory AS i
    ON i.warehouse_id = w.warehouse_id
LEFT JOIN product AS p
    ON p.product_id = i.product_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY tong_gia_tri_ton_kho DESC;
