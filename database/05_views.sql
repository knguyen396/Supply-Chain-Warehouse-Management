USE supply_chain_g3;

-- =========================================
-- VIEW 1: INVENTORY STATUS
-- Purpose: Display inventory status of
-- products across all warehouses.
-- =========================================

CREATE OR REPLACE VIEW vw_inventory_status AS
SELECT
    w.warehouse_id,
    w.warehouse_name,
    p.product_id,
    p.product_name,
    i.quantity_on_hand,
    p.min_reorder_level,
    CASE
        WHEN i.quantity_on_hand < p.min_reorder_level
            THEN 'Low Stock'
        ELSE 'Sufficient Stock'
    END AS stock_status
FROM inventory i
JOIN warehouse w
    ON i.warehouse_id = w.warehouse_id
JOIN product p
    ON i.product_id = p.product_id;


-- =========================================
-- VIEW 2: SUPPLIER ORDER SUMMARY
-- Purpose: Display supplier order information
-- and calculate the total value of each order.
-- =========================================

CREATE OR REPLACE VIEW vw_supplier_order_summary AS
SELECT
    so.order_id,
    so.order_date,
    s.supplier_id,
    s.supplier_name,
    so.status,
    COALESCE(od.total_order_value, 0) AS total_order_value
FROM supplier_order so
JOIN supplier s
    ON so.supplier_id = s.supplier_id
LEFT JOIN (
    SELECT
        order_id,
        SUM(order_quantity * unit_price) AS total_order_value
    FROM supplier_order_detail
    GROUP BY order_id
) od
    ON so.order_id = od.order_id;


-- =========================================
-- TEST VIEWS
-- =========================================

SELECT * FROM vw_inventory_status ORDER BY warehouse_id, product_id;

SELECT * FROM vw_supplier_order_summary ORDER BY order_id;
