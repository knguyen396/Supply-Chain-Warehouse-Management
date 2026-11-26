-- G3 Phase 3 | MySQL 8.0.16+
-- Install AFTER 01_schema.sql and 02_mock_data.sql.
-- Re-runnable: old triggers are dropped before creation.
-- Install only after importing the historical snapshot. New live orders and
-- shipments start Pending. Shipment lines are frozen once dispatched.
USE supply_chain_g3;

DELIMITER $$

-- BR-103: automatic alerts. Random base-36 IDs fit VARCHAR(10).
-- A pending alert is not duplicated on repeated low-stock updates.
DROP TRIGGER IF EXISTS trg_inventory_restock_alert_insert$$
CREATE TRIGGER trg_inventory_restock_alert_insert
AFTER INSERT ON inventory FOR EACH ROW
BEGIN
    DECLARE v_min INT;
    SELECT min_reorder_level INTO v_min FROM product WHERE product_id = NEW.product_id;
    IF NEW.quantity_on_hand < v_min
       AND NOT EXISTS (SELECT 1 FROM restock_alert
                       WHERE warehouse_id = NEW.warehouse_id AND product_id = NEW.product_id
                         AND status = 'Pending') THEN
        INSERT INTO restock_alert(alert_id, warehouse_id, product_id, status)
        VALUES (LPAD(CONV(HEX(RANDOM_BYTES(6)), 16, 36), 10, '0'),
                NEW.warehouse_id, NEW.product_id, 'Pending');
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_inventory_restock_alert_update$$
CREATE TRIGGER trg_inventory_restock_alert_update
AFTER UPDATE ON inventory FOR EACH ROW
BEGIN
    DECLARE v_min INT;
    SELECT min_reorder_level INTO v_min FROM product WHERE product_id = NEW.product_id;
    IF NEW.quantity_on_hand < v_min THEN
        IF NOT EXISTS (SELECT 1 FROM restock_alert
                       WHERE warehouse_id = NEW.warehouse_id AND product_id = NEW.product_id
                         AND status = 'Pending') THEN
            INSERT INTO restock_alert(alert_id, warehouse_id, product_id, status)
            VALUES (LPAD(CONV(HEX(RANDOM_BYTES(6)), 16, 36), 10, '0'),
                    NEW.warehouse_id, NEW.product_id, 'Pending');
        END IF;
    ELSE
        -- Replenishment resolves open alerts automatically.
        UPDATE restock_alert SET status = 'Resolved'
        WHERE warehouse_id = NEW.warehouse_id AND product_id = NEW.product_id
          AND status = 'Pending';
    END IF;
END$$

-- A higher product reorder threshold can also create a new low-stock condition.
DROP TRIGGER IF EXISTS trg_product_reorder_threshold_update$$
CREATE TRIGGER trg_product_reorder_threshold_update
AFTER UPDATE ON product FOR EACH ROW
BEGIN
    IF NEW.min_reorder_level <> OLD.min_reorder_level THEN
        -- Resolve alerts for pairs that no longer fall below the new threshold.
        UPDATE restock_alert ra
        JOIN inventory i ON i.warehouse_id = ra.warehouse_id
                        AND i.product_id = ra.product_id
        SET ra.status = 'Resolved'
        WHERE ra.product_id = NEW.product_id AND ra.status = 'Pending'
          AND i.quantity_on_hand >= NEW.min_reorder_level;

        INSERT INTO restock_alert(alert_id, warehouse_id, product_id, status)
        SELECT LPAD(CONV(HEX(RANDOM_BYTES(6)), 16, 36), 10, '0'),
               i.warehouse_id, i.product_id, 'Pending'
        FROM inventory i
        WHERE i.product_id = NEW.product_id
          AND i.quantity_on_hand < NEW.min_reorder_level
          AND NOT EXISTS (SELECT 1 FROM restock_alert ra
                          WHERE ra.warehouse_id = i.warehouse_id
                            AND ra.product_id = i.product_id AND ra.status = 'Pending');
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_restock_alert_initial_status$$
CREATE TRIGGER trg_restock_alert_initial_status
BEFORE INSERT ON restock_alert FOR EACH ROW
BEGIN
    IF NEW.status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New restock alerts must start Pending';
    END IF;
END$$

-- BR-202: reject direct or indirect cycles in the BOM graph.
-- Adding parent -> child creates a cycle iff child already reaches parent.
DROP TRIGGER IF EXISTS trg_bom_no_cycle_insert$$
CREATE TRIGGER trg_bom_no_cycle_insert
BEFORE INSERT ON product_structure FOR EACH ROW
BEGIN
    DECLARE v_count INT DEFAULT 0;
    IF NEW.parent_product_id = NEW.child_component_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BOM cycle: product cannot contain itself';
    END IF;
    WITH RECURSIVE descendants (product_id) AS (
        SELECT NEW.child_component_id
        UNION DISTINCT
        SELECT ps.child_component_id
        FROM product_structure ps JOIN descendants d ON ps.parent_product_id = d.product_id
    )
    SELECT COUNT(*) INTO v_count FROM descendants WHERE product_id = NEW.parent_product_id;
    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BOM cycle: indirect cycle detected';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_bom_no_cycle_update$$
CREATE TRIGGER trg_bom_no_cycle_update
BEFORE UPDATE ON product_structure FOR EACH ROW
BEGIN
    DECLARE v_count INT DEFAULT 0;
    IF NEW.parent_product_id = NEW.child_component_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BOM cycle: product cannot contain itself';
    END IF;
    IF NEW.parent_product_id <> OLD.parent_product_id
       OR NEW.child_component_id <> OLD.child_component_id THEN
        WITH RECURSIVE descendants (product_id) AS (
            SELECT NEW.child_component_id
            UNION DISTINCT
            SELECT ps.child_component_id
            FROM product_structure ps JOIN descendants d ON ps.parent_product_id = d.product_id
            WHERE NOT (ps.parent_product_id = OLD.parent_product_id
                       AND ps.child_component_id = OLD.child_component_id)
        )
        SELECT COUNT(*) INTO v_count FROM descendants WHERE product_id = NEW.parent_product_id;
        IF v_count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BOM cycle: indirect cycle detected';
        END IF;
    END IF;
END$$

-- BR-305: supplier orders may only move Pending -> Completed/Canceled.
DROP TRIGGER IF EXISTS trg_supplier_order_initial_state$$
CREATE TRIGGER trg_supplier_order_initial_state
BEFORE INSERT ON supplier_order FOR EACH ROW
BEGIN
    IF NEW.status <> 'Pending' OR NEW.total_amount <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New orders must start Pending with a zero total';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_supplier_order_status_guard$$
CREATE TRIGGER trg_supplier_order_status_guard
BEFORE UPDATE ON supplier_order FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status AND
       NOT (OLD.status = 'Pending' AND NEW.status IN ('Completed', 'Canceled')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid supplier order status transition';
    END IF;
    IF NEW.status = 'Completed' AND OLD.status <> 'Completed'
       AND NOT EXISTS (SELECT 1 FROM supplier_order_detail WHERE order_id = NEW.order_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot complete supplier order without details';
    END IF;
    IF NEW.total_amount <> (
        SELECT COALESCE(SUM(order_quantity * unit_price), 0)
        FROM supplier_order_detail WHERE order_id = NEW.order_id
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order total must match its line items';
    END IF;
END$$

-- BR-304: keep total_amount equal to the detail-line sum.
-- Details of terminal orders cannot be modified.
DROP TRIGGER IF EXISTS trg_order_detail_guard_insert$$
CREATE TRIGGER trg_order_detail_guard_insert
BEFORE INSERT ON supplier_order_detail FOR EACH ROW
BEGIN
    IF (SELECT status FROM supplier_order WHERE order_id = NEW.order_id) <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot add detail to terminal supplier order';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_order_detail_guard_update$$
CREATE TRIGGER trg_order_detail_guard_update
BEFORE UPDATE ON supplier_order_detail FOR EACH ROW
BEGIN
    IF (SELECT status FROM supplier_order WHERE order_id = OLD.order_id) <> 'Pending'
       OR (SELECT status FROM supplier_order WHERE order_id = NEW.order_id) <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change detail of terminal supplier order';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_order_detail_guard_delete$$
CREATE TRIGGER trg_order_detail_guard_delete
BEFORE DELETE ON supplier_order_detail FOR EACH ROW
BEGIN
    IF (SELECT status FROM supplier_order WHERE order_id = OLD.order_id) <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete detail from terminal supplier order';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_order_detail_total_insert$$
CREATE TRIGGER trg_order_detail_total_insert
AFTER INSERT ON supplier_order_detail FOR EACH ROW
BEGIN
    UPDATE supplier_order SET total_amount =
      (SELECT COALESCE(SUM(order_quantity * unit_price), 0)
       FROM supplier_order_detail WHERE order_id = NEW.order_id)
    WHERE order_id = NEW.order_id;
END$$

DROP TRIGGER IF EXISTS trg_order_detail_total_update$$
CREATE TRIGGER trg_order_detail_total_update
AFTER UPDATE ON supplier_order_detail FOR EACH ROW
BEGIN
    UPDATE supplier_order SET total_amount =
      (SELECT COALESCE(SUM(order_quantity * unit_price), 0)
       FROM supplier_order_detail WHERE order_id = NEW.order_id)
    WHERE order_id = NEW.order_id;
    IF NEW.order_id <> OLD.order_id THEN
        UPDATE supplier_order SET total_amount =
          (SELECT COALESCE(SUM(order_quantity * unit_price), 0)
           FROM supplier_order_detail WHERE order_id = OLD.order_id)
        WHERE order_id = OLD.order_id;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_order_detail_total_delete$$
CREATE TRIGGER trg_order_detail_total_delete
AFTER DELETE ON supplier_order_detail FOR EACH ROW
BEGIN
    UPDATE supplier_order SET total_amount =
      (SELECT COALESCE(SUM(order_quantity * unit_price), 0)
       FROM supplier_order_detail WHERE order_id = OLD.order_id)
    WHERE order_id = OLD.order_id;
END$$

-- BR-406/404/405: legal shipment transitions and atomic inventory transfer.
DROP TRIGGER IF EXISTS trg_shipment_initial_status$$
CREATE TRIGGER trg_shipment_initial_status
BEFORE INSERT ON shipment FOR EACH ROW
BEGIN
    IF NEW.status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New shipments must start Pending';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_shipment_before_complete$$
CREATE TRIGGER trg_shipment_before_complete
BEFORE UPDATE ON shipment FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'Pending' AND NEW.status IN ('In-Transit', 'Canceled'))
        OR (OLD.status = 'In-Transit' AND NEW.status = 'Completed')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid shipment status transition';
    END IF;
    IF OLD.status <> 'Pending' AND (
        NEW.source_warehouse_id <> OLD.source_warehouse_id
        OR NEW.dest_warehouse_id <> OLD.dest_warehouse_id
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Pending shipments may change warehouses';
    END IF;
    IF NEW.status <> OLD.status AND NEW.status IN ('In-Transit', 'Completed') THEN
        IF NOT EXISTS (SELECT 1 FROM shipment_detail WHERE shipment_id = NEW.shipment_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot dispatch or complete shipment without details';
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_shipment_after_complete$$
CREATE TRIGGER trg_shipment_after_complete
AFTER UPDATE ON shipment FOR EACH ROW
BEGIN
    DECLARE v_line_count INT;
    IF OLD.status = 'In-Transit' AND NEW.status = 'Completed' THEN
        SELECT COUNT(*) INTO v_line_count
        FROM shipment_detail WHERE shipment_id = NEW.shipment_id;

        UPDATE inventory i
        JOIN shipment_detail sd ON sd.product_id = i.product_id
        SET i.quantity_on_hand = i.quantity_on_hand - sd.shipped_quantity,
            i.last_updated = NOW()
        WHERE sd.shipment_id = NEW.shipment_id
          AND i.warehouse_id = NEW.source_warehouse_id
          AND i.quantity_on_hand >= sd.shipped_quantity;

        -- If any line could not be deducted, InnoDB rolls back the statement
        -- including earlier deductions and alerts generated by this transfer.
        IF ROW_COUNT() <> v_line_count THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient source inventory';
        END IF;

        INSERT INTO inventory(warehouse_id, product_id, quantity_on_hand, last_updated)
        SELECT NEW.dest_warehouse_id, sd.product_id, sd.shipped_quantity, NOW()
        FROM shipment_detail sd WHERE sd.shipment_id = NEW.shipment_id
        ON DUPLICATE KEY UPDATE
            quantity_on_hand = inventory.quantity_on_hand + sd.shipped_quantity,
            last_updated = NOW();
    END IF;
END$$

-- Lock the parent during detail edits, then allow changes only to drafts.
DROP TRIGGER IF EXISTS trg_shipment_detail_protect_insert$$
CREATE TRIGGER trg_shipment_detail_protect_insert
BEFORE INSERT ON shipment_detail FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM shipment WHERE shipment_id = NEW.shipment_id FOR UPDATE;
    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Pending shipments may add details';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_shipment_detail_protect_update$$
CREATE TRIGGER trg_shipment_detail_protect_update
BEFORE UPDATE ON shipment_detail FOR EACH ROW
BEGIN
    DECLARE v_old_status VARCHAR(20);
    DECLARE v_new_status VARCHAR(20);
    SELECT status INTO v_old_status FROM shipment WHERE shipment_id = OLD.shipment_id FOR UPDATE;
    SELECT status INTO v_new_status FROM shipment WHERE shipment_id = NEW.shipment_id FOR UPDATE;
    IF v_old_status <> 'Pending' OR v_new_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Pending shipments may change details';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_shipment_detail_protect_delete$$
CREATE TRIGGER trg_shipment_detail_protect_delete
BEFORE DELETE ON shipment_detail FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM shipment WHERE shipment_id = OLD.shipment_id FOR UPDATE;
    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Pending shipments may delete details';
    END IF;
END$$

DELIMITER ;
