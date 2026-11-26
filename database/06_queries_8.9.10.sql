USE supply_chain_g3;


-- =========================================
-- QUERY 8: PRODUCTS NEVER ORDERED
-- Purpose: Find products that have never
-- appeared in any supplier order.
-- =========================================

SELECT
    p.product_id,
    p.product_name,
    p.unit,
    p.unit_price
FROM product p
WHERE NOT EXISTS (
    SELECT 1
    FROM supplier_order_detail sod
    WHERE sod.product_id = p.product_id
)
ORDER BY p.product_id;


-- =========================================
-- QUERY 9: WAREHOUSE WITH HIGHEST INVENTORY
-- Purpose: Find the warehouse(s) with the
-- highest total inventory quantity.
-- =========================================

WITH warehouse_totals AS (
    SELECT
        w.warehouse_id,
        w.warehouse_name,
        SUM(COALESCE(i.quantity_on_hand, 0)) AS total_inventory_quantity
    FROM warehouse w
    LEFT JOIN inventory i
        ON w.warehouse_id = i.warehouse_id
    GROUP BY
        w.warehouse_id,
        w.warehouse_name
)
SELECT
    warehouse_id,
    warehouse_name,
    total_inventory_quantity
FROM warehouse_totals
WHERE total_inventory_quantity = (
    SELECT MAX(total_inventory_quantity)
    FROM warehouse_totals
)
ORDER BY warehouse_id;


-- =========================================
-- QUERY 10: RANK PRODUCTS BY SHIPPED QUANTITY
-- Purpose: Rank products based on their
-- quantities on completed shipments. Products without completed
-- shipments remain in the result with a quantity of zero.
-- =========================================

SELECT
    p.product_id,
    p.product_name,
    COALESCE(SUM(CASE WHEN sh.status = 'Completed' THEN sd.shipped_quantity ELSE 0 END), 0) AS total_shipped_quantity,
    RANK() OVER (
        ORDER BY COALESCE(SUM(CASE WHEN sh.status = 'Completed' THEN sd.shipped_quantity ELSE 0 END), 0) DESC
    ) AS product_rank
FROM product p
LEFT JOIN shipment_detail sd
    ON p.product_id = sd.product_id
LEFT JOIN shipment sh
    ON sh.shipment_id = sd.shipment_id
GROUP BY
    p.product_id,
    p.product_name
ORDER BY
    product_rank,
    p.product_id;
