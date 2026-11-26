-- Load once on a fresh schema before installing the operational triggers.
USE supply_chain_g3;

START TRANSACTION;

INSERT INTO warehouse (warehouse_id, warehouse_name, location_address, capacity) VALUES
('W001', 'Ho Chi Minh Central', 'District 7, Ho Chi Minh City', 5000),
('W002', 'Ha Noi North', 'Long Bien, Ha Noi', 4000),
('W003', 'Da Nang Hub', 'Hai Chau, Da Nang', 3000),
('W004', 'Can Tho Depot', 'Ninh Kieu, Can Tho', 2000);

INSERT INTO product (product_id, product_name, unit, min_reorder_level, unit_price) VALUES
('P001', 'Laptop Kit', 'set', 10, 15000000.00),
('P002', 'Mainboard', 'piece', 20, 2500000.00),
('P003', 'RAM 16GB', 'piece', 30, 1000000.00),
('P004', 'SSD 512GB', 'piece', 25, 1200000.00),
('P005', 'Battery Pack', 'piece', 15, 900000.00),
('P006', 'Desktop Kit', 'set', 8, 18000000.00),
('P007', 'Power Supply', 'piece', 20, 1500000.00),
('P008', 'Cooling Fan', 'piece', 25, 300000.00),
('P009', 'Controller Module', 'piece', 15, 800000.00),
('P010', 'Sensor Chip', 'piece', 40, 100000.00),
('P011', 'Packing Box', 'piece', 50, 25000.00),
('P012', 'Display Panel', 'piece', 12, 3500000.00);

INSERT INTO supplier (supplier_id, supplier_name, contact_email, phone_number, address) VALUES
('S001', 'Tech Components VN', 'sales@techcomponents.example', '02811110001', 'Ho Chi Minh City'),
('S002', 'Northern Electronics', 'contact@northernelectronics.example', '02411110002', 'Ha Noi'),
('S003', 'Central Hardware', 'hello@centralhardware.example', '02361110003', 'Da Nang'),
('S004', 'Mekong Packaging', 'orders@mekongpackaging.example', '02921110004', 'Can Tho'),
('S005', 'Global Display Parts', 'sales@globaldisplay.example', '02811110005', 'Binh Duong');

INSERT INTO supplier_order (order_id, supplier_id, order_date, status, total_amount) VALUES
('O001', 'S001', '2026-10-01', 'Completed', 125000000.00),
('O002', 'S002', '2026-10-03', 'Pending', 78000000.00),
('O003', 'S003', '2026-10-05', 'Completed', 25000000.00),
('O004', 'S004', '2026-10-06', 'Canceled', 12500000.00),
('O005', 'S005', '2026-10-10', 'Pending', 70000000.00),
('O006', 'S001', '2026-10-15', 'Completed', 36000000.00),
('O007', 'S002', '2026-10-20', 'Pending', 30000000.00),
('O008', 'S003', '2026-10-22', 'Completed', 15000000.00);

INSERT INTO shipment (shipment_id, tracking_number, source_warehouse_id, dest_warehouse_id, dispatch_date, estimated_arrival, status) VALUES
('SH001', 'G3-TRACK-001', 'W001', 'W002', '2026-10-10 08:00:00', '2026-10-12 18:00:00', 'Completed'),
('SH002', 'G3-TRACK-002', 'W002', 'W003', '2026-10-13 09:00:00', '2026-10-15 18:00:00', 'Completed'),
('SH003', 'G3-TRACK-003', 'W001', 'W004', '2026-10-25 08:00:00', '2026-10-27 18:00:00', 'In-Transit'),
('SH004', 'G3-TRACK-004', 'W003', 'W001', '2026-11-03 09:00:00', '2026-11-05 18:00:00', 'Pending'),
('SH005', 'G3-TRACK-005', 'W004', 'W002', '2026-10-18 08:00:00', '2026-10-20 18:00:00', 'Canceled'),
('SH006', 'G3-TRACK-006', 'W001', 'W003', '2026-10-21 08:00:00', '2026-10-23 18:00:00', 'Completed');

-- Inventory balances are a snapshot AFTER already-completed shipments.
-- Do not reapply completed historical shipments during initial data loading.
INSERT INTO inventory (warehouse_id, product_id, quantity_on_hand, last_updated) VALUES
('W001', 'P001', 6, '2026-11-01 12:00:00'),
('W001', 'P002', 55, '2026-11-01 12:00:00'),
('W001', 'P003', 70, '2026-11-01 12:00:00'),
('W001', 'P004', 12, '2026-11-01 12:00:00'),
('W001', 'P005', 35, '2026-11-01 12:00:00'),
('W001', 'P006', 15, '2026-11-01 12:00:00'),
('W001', 'P007', 35, '2026-11-01 12:00:00'),
('W001', 'P008', 50, '2026-11-01 12:00:00'),
('W001', 'P009', 20, '2026-11-01 12:00:00'),
('W001', 'P010', 80, '2026-11-01 12:00:00'),
('W001', 'P011', 100, '2026-11-01 12:00:00'),
('W002', 'P001', 18, '2026-11-01 12:00:00'),
('W002', 'P002', 10, '2026-11-01 12:00:00'),
('W002', 'P003', 45, '2026-11-01 12:00:00'),
('W002', 'P004', 40, '2026-11-01 12:00:00'),
('W002', 'P007', 12, '2026-11-01 12:00:00'),
('W002', 'P009', 10, '2026-11-01 12:00:00'),
('W002', 'P010', 55, '2026-11-01 12:00:00'),
('W002', 'P011', 60, '2026-11-01 12:00:00'),
('W003', 'P001', 12, '2026-11-01 12:00:00'),
('W003', 'P002', 35, '2026-11-01 12:00:00'),
('W003', 'P003', 15, '2026-11-01 12:00:00'),
('W003', 'P004', 32, '2026-11-01 12:00:00'),
('W003', 'P006', 4, '2026-11-01 12:00:00'),
('W003', 'P008', 60, '2026-11-01 12:00:00'),
('W003', 'P010', 30, '2026-11-01 12:00:00'),
('W004', 'P001', 11, '2026-11-01 12:00:00'),
('W004', 'P003', 35, '2026-11-01 12:00:00'),
('W004', 'P005', 5, '2026-11-01 12:00:00'),
('W004', 'P007', 30, '2026-11-01 12:00:00'),
('W004', 'P008', 10, '2026-11-01 12:00:00'),
('W004', 'P011', 30, '2026-11-01 12:00:00');

-- Multi-level BOM: P001 -> P009 -> P010, and P006 -> P009 -> P010.
INSERT INTO product_structure (parent_product_id, child_component_id, quantity_required) VALUES
('P001', 'P002', 1),
('P001', 'P003', 2),
('P001', 'P004', 1),
('P001', 'P005', 1),
('P001', 'P009', 1),
('P006', 'P002', 1),
('P006', 'P003', 2),
('P006', 'P007', 1),
('P006', 'P008', 2),
('P006', 'P009', 1),
('P009', 'P010', 3);

INSERT INTO supplier_order_detail (order_id, product_id, order_quantity, unit_price) VALUES
('O001', 'P002', 30, 2500000.00),
('O001', 'P003', 50, 1000000.00),
('O002', 'P004', 40, 1200000.00),
('O002', 'P005', 20, 900000.00),
('O002', 'P008', 40, 300000.00),
('O003', 'P007', 10, 1500000.00),
('O003', 'P009', 10, 800000.00),
('O003', 'P010', 20, 100000.00),
('O004', 'P011', 500, 25000.00),
('O005', 'P012', 20, 3500000.00),
('O006', 'P003', 30, 1000000.00),
('O006', 'P008', 20, 300000.00),
('O007', 'P002', 12, 2500000.00),
('O008', 'P010', 100, 100000.00),
('O008', 'P011', 200, 25000.00);

INSERT INTO shipment_detail (shipment_id, product_id, shipped_quantity) VALUES
('SH001', 'P002', 5),
('SH001', 'P003', 10),
('SH002', 'P003', 5),
('SH002', 'P004', 8),
('SH003', 'P001', 2),
('SH003', 'P005', 3),
('SH004', 'P002', 4),
('SH004', 'P008', 6),
('SH005', 'P007', 3),
('SH006', 'P003', 8),
('SH006', 'P010', 10);

-- Alerts represent existing low-stock observations; load before installing triggers.
INSERT INTO restock_alert (alert_id, warehouse_id, product_id, alert_date, status) VALUES
('A001', 'W001', 'P001', '2026-11-01 12:05:00', 'Pending'),
('A002', 'W001', 'P004', '2026-11-01 12:05:00', 'Pending'),
('A003', 'W002', 'P002', '2026-11-01 12:05:00', 'Pending'),
('A004', 'W002', 'P007', '2026-11-01 12:05:00', 'Pending'),
('A005', 'W003', 'P003', '2026-11-01 12:05:00', 'Pending'),
('A006', 'W003', 'P006', '2026-11-01 12:05:00', 'Pending'),
('A007', 'W004', 'P005', '2026-11-01 12:05:00', 'Pending'),
('A008', 'W004', 'P008', '2026-11-01 12:05:00', 'Pending'),
('A009', 'W002', 'P009', '2026-11-01 12:05:00', 'Pending'),
('A010', 'W003', 'P010', '2026-11-01 12:05:00', 'Pending'),
('A011', 'W004', 'P011', '2026-11-01 12:05:00', 'Pending');

COMMIT;

-- Quick verification: expected counts are 4,12,5,8,6,32,11,15,11,11.
SELECT 'warehouse' AS table_name, COUNT(*) AS row_count FROM warehouse
UNION ALL SELECT 'product', COUNT(*) FROM product
UNION ALL SELECT 'supplier', COUNT(*) FROM supplier
UNION ALL SELECT 'supplier_order', COUNT(*) FROM supplier_order
UNION ALL SELECT 'shipment', COUNT(*) FROM shipment
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'product_structure', COUNT(*) FROM product_structure
UNION ALL SELECT 'supplier_order_detail', COUNT(*) FROM supplier_order_detail
UNION ALL SELECT 'shipment_detail', COUNT(*) FROM shipment_detail
UNION ALL SELECT 'restock_alert', COUNT(*) FROM restock_alert;
