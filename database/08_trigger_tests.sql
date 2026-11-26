-- G3 Phase 3 | Non-destructive test suite (MySQL 8.0.16+).
-- Run after 01_schema.sql, 02_mock_data.sql, 07_triggers.sql.
-- Each positive test uses a transaction and ROLLBACK so the demo data is preserved.
-- The temporary procedure runs rejected cases and rolls back their fixtures.
USE supply_chain_g3;

-- TEST A: order totals reflect insert/update/delete (BR-304).
START TRANSACTION;
INSERT INTO supplier_order(order_id, supplier_id, order_date, status, total_amount)
VALUES ('OT999', 'S001', CURRENT_DATE(), 'Pending', 0);
INSERT INTO supplier_order_detail(order_id, product_id, order_quantity, unit_price)
VALUES ('OT999', 'P001', 2, 100.00);
SELECT 'A1: insert total=200' AS test,
       IF(total_amount=200.00,'PASS','FAIL') AS result
FROM supplier_order WHERE order_id='OT999';
UPDATE supplier_order_detail SET order_quantity=3 WHERE order_id='OT999' AND product_id='P001';
SELECT 'A2: update total=300' AS test,
       IF(total_amount=300.00,'PASS','FAIL') AS result
FROM supplier_order WHERE order_id='OT999';
DELETE FROM supplier_order_detail WHERE order_id='OT999' AND product_id='P001';
SELECT 'A3: delete total=0' AS test,
       IF(total_amount=0.00,'PASS','FAIL') AS result
FROM supplier_order WHERE order_id='OT999';
ROLLBACK;

-- TEST B: low-stock alert is generated once, then auto-resolved (BR-103).
START TRANSACTION;
UPDATE inventory SET quantity_on_hand=15 WHERE warehouse_id='W001' AND product_id='P002';
SELECT 'B1: exactly one pending alert' AS test,
       IF(COUNT(*)=1,'PASS','FAIL') AS result
FROM restock_alert WHERE warehouse_id='W001' AND product_id='P002' AND status='Pending';
UPDATE inventory SET quantity_on_hand=10 WHERE warehouse_id='W001' AND product_id='P002';
SELECT 'B2: no duplicate pending alert' AS test,
       IF(COUNT(*)=1,'PASS','FAIL') AS result
FROM restock_alert WHERE warehouse_id='W001' AND product_id='P002' AND status='Pending';
UPDATE inventory SET quantity_on_hand=55 WHERE warehouse_id='W001' AND product_id='P002';
SELECT 'B3: pending alert resolved' AS test,
       IF(COUNT(*)=0,'PASS','FAIL') AS result
FROM restock_alert WHERE warehouse_id='W001' AND product_id='P002' AND status='Pending';
ROLLBACK;

-- TEST C: new inventory row below threshold creates an alert.
START TRANSACTION;
INSERT INTO inventory(warehouse_id,product_id,quantity_on_hand)
VALUES('W004','P012',1);
SELECT 'C: insert low stock' AS test, IF(COUNT(*)=1,'PASS','FAIL') AS result
FROM restock_alert WHERE warehouse_id='W004' AND product_id='P012' AND status='Pending';
ROLLBACK;

-- TEST D: increasing a product threshold creates a new alert for newly low pairs.
START TRANSACTION;
UPDATE product SET min_reorder_level=60 WHERE product_id='P002';
SELECT 'D: threshold increase' AS test,
       IF(COUNT(*)=1,'PASS','FAIL') AS result
FROM restock_alert WHERE warehouse_id='W001' AND product_id='P002' AND status='Pending';
ROLLBACK;

-- TEST E: valid shipment transfer: Pending -> In-Transit -> Completed.
START TRANSACTION;
UPDATE shipment SET status='In-Transit' WHERE shipment_id='SH004';
UPDATE shipment SET status='Completed' WHERE shipment_id='SH004';
SELECT 'E1: shipment status' AS test,
       IF(status='Completed','PASS','FAIL') AS result
FROM shipment WHERE shipment_id='SH004';
SELECT 'E2: source P002=31' AS test,
       IF(quantity_on_hand=31,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W003' AND product_id='P002';
SELECT 'E3: destination P002=59' AS test,
       IF(quantity_on_hand=59,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W001' AND product_id='P002';
SELECT 'E4: source P008=54' AS test,
       IF(quantity_on_hand=54,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W003' AND product_id='P008';
SELECT 'E5: destination P008=56' AS test,
       IF(quantity_on_hand=56,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W001' AND product_id='P008';
ROLLBACK;

-- TEST F: completed shipment creates inventory row at a previously empty destination.
START TRANSACTION;
INSERT INTO shipment(shipment_id,tracking_number,source_warehouse_id,dest_warehouse_id,
                     dispatch_date,estimated_arrival,status)
VALUES('SH997','G3-TRACK-997','W001','W002',NOW(),DATE_ADD(NOW(),INTERVAL 2 DAY),'Pending');
INSERT INTO shipment_detail(shipment_id,product_id,shipped_quantity) VALUES('SH997','P006',3);
UPDATE shipment SET status='In-Transit' WHERE shipment_id='SH997';
UPDATE shipment SET status='Completed' WHERE shipment_id='SH997';
SELECT 'F1: source=12' AS test, IF(quantity_on_hand=12,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W001' AND product_id='P006';
SELECT 'F2: new destination=3' AS test, IF(quantity_on_hand=3,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W002' AND product_id='P006';
ROLLBACK;

-- TEST G: shipment completion can generate low-stock alert in source warehouse.
START TRANSACTION;
INSERT INTO shipment(shipment_id,tracking_number,source_warehouse_id,dest_warehouse_id,
                     dispatch_date,estimated_arrival,status)
VALUES('SH998','G3-TRACK-998','W004','W002',NOW(),DATE_ADD(NOW(),INTERVAL 2 DAY),'Pending');
INSERT INTO shipment_detail(shipment_id,product_id,shipped_quantity) VALUES('SH998','P001',8);
UPDATE shipment SET status='In-Transit' WHERE shipment_id='SH998';
UPDATE shipment SET status='Completed' WHERE shipment_id='SH998';
SELECT 'G1: source P001=3' AS test, IF(quantity_on_hand=3,'PASS','FAIL') AS result
FROM inventory WHERE warehouse_id='W004' AND product_id='P001';
SELECT 'G2: low-stock alert' AS test, IF(COUNT(*)=1,'PASS','FAIL') AS result
FROM restock_alert WHERE warehouse_id='W004' AND product_id='P001' AND status='Pending';
ROLLBACK;

-- TEST H: BOM valid multilevel paths can be queried without cycles.
WITH RECURSIVE bom AS (
  SELECT parent_product_id,child_component_id,1 AS depth
  FROM product_structure WHERE parent_product_id='P001'
  UNION ALL
  SELECT ps.parent_product_id,ps.child_component_id,b.depth+1
  FROM product_structure ps JOIN bom b ON ps.parent_product_id=b.child_component_id
  WHERE b.depth<20
)
SELECT 'H: multilevel BOM exists' AS test,
       IF(COALESCE(MAX(depth),0)>=2,'PASS','FAIL') AS result FROM bom;

DELIMITER $$
DROP PROCEDURE IF EXISTS phase3_test_rejected_changes$$
CREATE PROCEDURE phase3_test_rejected_changes()
BEGIN
    DECLARE v_rejected BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        INSERT INTO product_structure VALUES ('P010', 'P001', 1);
    END;
    SELECT 'I1: indirect BOM cycle rejected' AS test, IF(v_rejected,'PASS','FAIL') AS result;

    SET v_rejected = FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        UPDATE supplier_order SET total_amount = 1 WHERE order_id = 'O002';
    END;
    SELECT 'I2: invalid order total rejected' AS test, IF(v_rejected,'PASS','FAIL') AS result;

    INSERT INTO supplier_order(order_id, supplier_id, order_date)
    VALUES ('OT999', 'S001', CURRENT_DATE());
    SET v_rejected = FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        UPDATE supplier_order SET status = 'Completed' WHERE order_id = 'OT999';
    END;
    SELECT 'I3: empty order cannot complete' AS test, IF(v_rejected,'PASS','FAIL') AS result;

    SET v_rejected = FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        UPDATE shipment SET status = 'Completed' WHERE shipment_id = 'SH004';
    END;
    SELECT 'I4: Pending cannot skip In-Transit' AS test, IF(v_rejected,'PASS','FAIL') AS result;

    INSERT INTO shipment(shipment_id,tracking_number,source_warehouse_id,dest_warehouse_id,
                         dispatch_date,estimated_arrival)
    VALUES ('SH999','G3-TRACK-999','W004','W002',NOW(),DATE_ADD(NOW(),INTERVAL 2 DAY));
    SET v_rejected = FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        UPDATE shipment SET status = 'In-Transit' WHERE shipment_id = 'SH999';
    END;
    SELECT 'I5: empty shipment cannot dispatch' AS test, IF(v_rejected,'PASS','FAIL') AS result;

    INSERT INTO shipment_detail VALUES ('SH999','P001',2), ('SH999','P005',10);
    UPDATE shipment SET status = 'In-Transit' WHERE shipment_id = 'SH999';
    SET v_rejected = FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        DELETE FROM shipment_detail WHERE shipment_id = 'SH999' AND product_id = 'P001';
    END;
    SELECT 'I6: dispatched shipment lines are frozen' AS test, IF(v_rejected,'PASS','FAIL') AS result;

    SET v_rejected = FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_rejected = TRUE;
        UPDATE shipment SET status = 'Completed' WHERE shipment_id = 'SH999';
    END;
    SELECT 'I7: partial shortage rolls back the transfer' AS test,
           IF(v_rejected
              AND (SELECT status FROM shipment WHERE shipment_id = 'SH999') = 'In-Transit'
              AND (SELECT quantity_on_hand FROM inventory WHERE warehouse_id = 'W004' AND product_id = 'P001') = 11
              AND (SELECT quantity_on_hand FROM inventory WHERE warehouse_id = 'W004' AND product_id = 'P005') = 5
              AND (SELECT quantity_on_hand FROM inventory WHERE warehouse_id = 'W002' AND product_id = 'P001') = 18
              AND NOT EXISTS (SELECT 1 FROM restock_alert WHERE warehouse_id = 'W004' AND product_id = 'P001'),
              'PASS','FAIL') AS result;
    ROLLBACK;
END$$
DELIMITER ;

CALL phase3_test_rejected_changes();
DROP PROCEDURE phase3_test_rejected_changes;
