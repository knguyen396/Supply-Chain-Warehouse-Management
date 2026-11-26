-- Phase 3 schema installation for MySQL 8.0.16+.
-- Run on a fresh schema. Existing tables and data are never dropped.
CREATE DATABASE IF NOT EXISTS supply_chain_g3
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE supply_chain_g3;

CREATE TABLE warehouse (
    warehouse_id VARCHAR(10) PRIMARY KEY,
    warehouse_name VARCHAR(100) NOT NULL,
    location_address TEXT NOT NULL,
    capacity INT NOT NULL,
    CONSTRAINT chk_warehouse_capacity CHECK (capacity > 0)
) ENGINE = InnoDB;

CREATE TABLE product (
    product_id VARCHAR(10) PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    min_reorder_level INT NOT NULL DEFAULT 0,
    unit_price DECIMAL(10, 2) NOT NULL,
    CONSTRAINT chk_product_reorder CHECK (min_reorder_level >= 0),
    CONSTRAINT chk_product_price CHECK (unit_price >= 0)
) ENGINE = InnoDB;

CREATE TABLE supplier (
    supplier_id VARCHAR(10) PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_email VARCHAR(100),
    phone_number VARCHAR(20),
    address TEXT
) ENGINE = InnoDB;

CREATE TABLE supplier_order (
    order_id VARCHAR(10) PRIMARY KEY,
    supplier_id VARCHAR(10) NOT NULL,
    order_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0,
    INDEX idx_order_supplier_status (supplier_id, status),
    CONSTRAINT fk_order_supplier FOREIGN KEY (supplier_id)
        REFERENCES supplier (supplier_id),
    CONSTRAINT chk_order_status CHECK (status IN ('Pending', 'Completed', 'Canceled')),
    CONSTRAINT chk_order_amount CHECK (total_amount >= 0)
) ENGINE = InnoDB;

CREATE TABLE shipment (
    shipment_id VARCHAR(10) PRIMARY KEY,
    tracking_number VARCHAR(50) NOT NULL UNIQUE,
    source_warehouse_id VARCHAR(10) NOT NULL,
    dest_warehouse_id VARCHAR(10) NOT NULL,
    dispatch_date DATETIME NOT NULL,
    estimated_arrival DATETIME NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    INDEX idx_shipment_source_status (source_warehouse_id, status),
    CONSTRAINT fk_shipment_source FOREIGN KEY (source_warehouse_id)
        REFERENCES warehouse (warehouse_id),
    CONSTRAINT fk_shipment_dest FOREIGN KEY (dest_warehouse_id)
        REFERENCES warehouse (warehouse_id),
    CONSTRAINT chk_shipment_warehouses CHECK (source_warehouse_id <> dest_warehouse_id),
    CONSTRAINT chk_shipment_dates CHECK (estimated_arrival >= dispatch_date),
    CONSTRAINT chk_shipment_status CHECK (status IN ('Pending', 'In-Transit', 'Completed', 'Canceled'))
) ENGINE = InnoDB;

CREATE TABLE inventory (
    warehouse_id VARCHAR(10) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    quantity_on_hand INT NOT NULL DEFAULT 0,
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (warehouse_id, product_id),
    CONSTRAINT fk_inventory_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES warehouse (warehouse_id),
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id)
        REFERENCES product (product_id),
    CONSTRAINT chk_inventory_quantity CHECK (quantity_on_hand >= 0)
) ENGINE = InnoDB;

CREATE TABLE product_structure (
    parent_product_id VARCHAR(10) NOT NULL,
    child_component_id VARCHAR(10) NOT NULL,
    quantity_required INT NOT NULL,
    PRIMARY KEY (parent_product_id, child_component_id),
    CONSTRAINT fk_bom_parent FOREIGN KEY (parent_product_id)
        REFERENCES product (product_id),
    CONSTRAINT fk_bom_child FOREIGN KEY (child_component_id)
        REFERENCES product (product_id),
    CONSTRAINT chk_bom_quantity CHECK (quantity_required > 0),
    CONSTRAINT chk_bom_no_self CHECK (parent_product_id <> child_component_id)
) ENGINE = InnoDB;

CREATE TABLE supplier_order_detail (
    order_id VARCHAR(10) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    order_quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT fk_order_detail_order FOREIGN KEY (order_id)
        REFERENCES supplier_order (order_id),
    CONSTRAINT fk_order_detail_product FOREIGN KEY (product_id)
        REFERENCES product (product_id),
    CONSTRAINT chk_order_detail_quantity CHECK (order_quantity > 0),
    CONSTRAINT chk_order_detail_price CHECK (unit_price >= 0)
) ENGINE = InnoDB;

CREATE TABLE shipment_detail (
    shipment_id VARCHAR(10) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    shipped_quantity INT NOT NULL,
    PRIMARY KEY (shipment_id, product_id),
    CONSTRAINT fk_shipment_detail_shipment FOREIGN KEY (shipment_id)
        REFERENCES shipment (shipment_id),
    CONSTRAINT fk_shipment_detail_product FOREIGN KEY (product_id)
        REFERENCES product (product_id),
    CONSTRAINT chk_shipped_quantity CHECK (shipped_quantity > 0)
) ENGINE = InnoDB;

CREATE TABLE restock_alert (
    alert_id VARCHAR(10) PRIMARY KEY,
    warehouse_id VARCHAR(10) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    alert_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    INDEX idx_alert_inventory_status (warehouse_id, product_id, status),
    CONSTRAINT fk_alert_inventory FOREIGN KEY (warehouse_id, product_id)
        REFERENCES inventory (warehouse_id, product_id),
    CONSTRAINT chk_alert_status CHECK (status IN ('Pending', 'Resolved'))
) ENGINE = InnoDB;

-- Notes for teammates:
-- (1) Preventing indirect BOM cycles requires a recursive check (trigger/procedure/application).
-- (2) Order total consistency, status transitions, stock transfers and
--     automatic restock alerts are handled by trigger or application logic.
-- (3) Pending orders and shipments may have no details. Completing an order
--     requires at least one detail. A shipment must have at least one detail
--     when entering In-Transit and while In-Transit or Completed.
