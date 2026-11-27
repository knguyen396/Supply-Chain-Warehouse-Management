from fastapi import APIRouter, Depends, HTTPException, Response

from .auth import authorized, permissions
from .database import rows, session
from .schemas import (
    Identifier, Order, OrderLine, OrderStatus, Product, Shipment, ShipmentLine,
    ShipmentStatus, Stock, Supplier, Warehouse,
)

api = APIRouter(prefix="/api", dependencies=[Depends(authorized)])


def required(value):
    if value is None:
        raise HTTPException(404, "Không tìm thấy bản ghi.")
    return value


def register_catalog(path, table, model):
    columns = list(model.model_fields)
    id_column, *editable = columns
    selection = ", ".join(columns)
    assignments = ", ".join(f"{name} = %s" for name in editable)
    placeholders = ", ".join(["%s"] * len(columns))

    @api.get(path, name=f"list_{table}", tags=[table])
    def list_records():
        return rows(f"SELECT {selection} FROM {table} ORDER BY {id_column}")

    @api.post(path, name=f"create_{table}", tags=[table], status_code=201)
    def create_record(payload: model):
        with session() as cursor:
            cursor.execute(
                f"INSERT INTO {table} ({selection}) VALUES ({placeholders})",
                tuple(getattr(payload, column) for column in columns),
            )
        return payload

    @api.put(path + "/{record_id}", name=f"update_{table}", tags=[table])
    def update_record(record_id: Identifier, payload: model):
        if record_id != getattr(payload, id_column):
            raise HTTPException(422, "Không thể đổi mã của bản ghi.")
        with session() as cursor:
            cursor.execute(f"SELECT {id_column} FROM {table} WHERE {id_column} = %s FOR UPDATE", (record_id,))
            required(cursor.fetchone())
            cursor.execute(
                f"UPDATE {table} SET {assignments} WHERE {id_column} = %s",
                (*[getattr(payload, name) for name in editable], record_id),
            )
        return payload

    @api.delete(path + "/{record_id}", name=f"delete_{table}", tags=[table], status_code=204)
    def delete_record(record_id: Identifier):
        with session() as cursor:
            cursor.execute(f"DELETE FROM {table} WHERE {id_column} = %s", (record_id,))
            if not cursor.rowcount:
                required(None)
        return Response(status_code=204)


register_catalog("/warehouses", "warehouse", Warehouse)
register_catalog("/products", "product", Product)
register_catalog("/suppliers", "supplier", Supplier)


@api.get("/dashboard", tags=["dashboard"])
def dashboard(user=Depends(authorized)):
    readable = permissions(user)["read"]
    with session() as cursor:
        cursor.execute("""
            SELECT (SELECT COUNT(*) FROM warehouse) AS warehouses,
                   (SELECT COUNT(*) FROM product) AS products,
                   (SELECT COALESCE(SUM(quantity_on_hand), 0) FROM inventory) AS stock,
                   (SELECT COUNT(*) FROM shipment) AS shipments,
                   (SELECT COUNT(*) FROM restock_alert WHERE status = 'Pending') AS alerts
        """)
        metrics = cursor.fetchone()
        cursor.execute("""
            SELECT w.warehouse_id, w.warehouse_name, COALESCE(SUM(i.quantity_on_hand), 0) AS stock
            FROM warehouse w LEFT JOIN inventory i ON i.warehouse_id = w.warehouse_id
            GROUP BY w.warehouse_id, w.warehouse_name ORDER BY stock DESC, w.warehouse_id
        """)
        by_warehouse = cursor.fetchall()
        cursor.execute("SELECT status, COUNT(*) AS total FROM shipment GROUP BY status")
        shipment_status = cursor.fetchall()
    if "shipments" not in readable:
        del metrics["shipments"]
        shipment_status = []
    if "alerts" not in readable:
        del metrics["alerts"]
    if "warehouses" not in readable:
        del metrics["warehouses"]
    return {"metrics": metrics, "by_warehouse": by_warehouse, "shipment_status": shipment_status,
            "alerts": alert_rows(limit=5, status="Pending") if "alerts" in readable else []}


@api.get("/products/{product_id}/bom", tags=["product"])
def product_bom(product_id: Identifier):
    required(next(iter(rows("SELECT product_id FROM product WHERE product_id = %s", (product_id,))), None))
    return rows("""
        WITH RECURSIVE bom AS (
            SELECT parent_product_id, child_component_id, quantity_required, 1 AS depth,
                   CAST(quantity_required AS DECIMAL(65, 0)) AS total_quantity,
                   JSON_ARRAY(parent_product_id, child_component_id) AS path
            FROM product_structure WHERE parent_product_id = %s
            UNION ALL
            SELECT ps.parent_product_id, ps.child_component_id, ps.quantity_required, b.depth + 1,
                   b.total_quantity * ps.quantity_required, JSON_ARRAY_APPEND(b.path, '$', ps.child_component_id)
            FROM product_structure ps JOIN bom b ON b.child_component_id = ps.parent_product_id
            WHERE NOT JSON_CONTAINS(b.path, JSON_QUOTE(ps.child_component_id))
        )
        SELECT b.parent_product_id, b.child_component_id, p.product_name, p.unit,
               b.quantity_required, CAST(b.total_quantity AS CHAR) AS total_quantity, b.depth
        FROM bom b JOIN product p ON p.product_id = b.child_component_id
        ORDER BY b.depth, b.parent_product_id, b.child_component_id
    """, (product_id,))


@api.get("/inventory", tags=["inventory"])
def inventory(warehouse_id: Identifier | None = None):
    return rows("""
        SELECT v.*, i.last_updated, p.unit FROM vw_inventory_status v
        JOIN inventory i ON i.warehouse_id = v.warehouse_id AND i.product_id = v.product_id
        JOIN product p ON p.product_id = v.product_id
        WHERE (%s IS NULL OR v.warehouse_id = %s)
        ORDER BY v.warehouse_id, v.product_id
    """, (warehouse_id, warehouse_id))


@api.put("/inventory/{warehouse_id}/{product_id}", tags=["inventory"])
def set_stock(warehouse_id: Identifier, product_id: Identifier, payload: Stock):
    with session() as cursor:
        cursor.execute("""
            INSERT INTO inventory (warehouse_id, product_id, quantity_on_hand)
            VALUES (%s, %s, %s)
            ON DUPLICATE KEY UPDATE quantity_on_hand = %s
        """, (warehouse_id, product_id, payload.quantity_on_hand, payload.quantity_on_hand))
    return payload


def alert_rows(limit=None, status=None):
    return rows("""
        SELECT a.*, w.warehouse_name, p.product_name, p.min_reorder_level, i.quantity_on_hand
        FROM restock_alert a
        JOIN warehouse w ON w.warehouse_id = a.warehouse_id
        JOIN product p ON p.product_id = a.product_id
        JOIN inventory i ON i.warehouse_id = a.warehouse_id AND i.product_id = a.product_id
        WHERE (%s IS NULL OR a.status = %s)
        ORDER BY (a.status = 'Pending') DESC, a.alert_date DESC, a.alert_id
        LIMIT %s
    """, (status, status, limit if limit is not None else 18446744073709551615))


@api.get("/alerts", tags=["alerts"])
def alerts():
    return alert_rows()


@api.patch("/alerts/{alert_id}/resolve", tags=["alerts"])
def resolve_alert(alert_id: Identifier):
    with session() as cursor:
        cursor.execute("SELECT alert_id FROM restock_alert WHERE alert_id = %s FOR UPDATE", (alert_id,))
        required(cursor.fetchone())
        cursor.execute("UPDATE restock_alert SET status = 'Resolved' WHERE alert_id = %s", (alert_id,))
    return {"status": "Resolved"}


@api.get("/orders", tags=["orders"])
def orders():
    return rows("SELECT * FROM vw_supplier_order_summary ORDER BY order_date DESC, order_id")


@api.post("/orders", tags=["orders"], status_code=201)
def create_order(payload: Order):
    with session() as cursor:
        cursor.execute("INSERT INTO supplier_order (order_id, supplier_id, order_date) VALUES (%s, %s, %s)",
                       (payload.order_id, payload.supplier_id, payload.order_date))
    return {"order_id": payload.order_id}


@api.get("/orders/{order_id}", tags=["orders"])
def order_detail(order_id: Identifier):
    with session() as cursor:
        cursor.execute("SELECT * FROM vw_supplier_order_summary WHERE order_id = %s", (order_id,))
        item = required(cursor.fetchone())
        cursor.execute("""
            SELECT d.product_id, p.product_name, d.order_quantity, d.unit_price,
                   d.order_quantity * d.unit_price AS line_total
            FROM supplier_order_detail d JOIN product p ON p.product_id = d.product_id
            WHERE d.order_id = %s ORDER BY d.product_id
        """, (order_id,))
        return {"item": item, "lines": cursor.fetchall()}


@api.get("/shipments", tags=["shipments"])
def shipments():
    return rows(shipment_query() + " ORDER BY sh.dispatch_date DESC, sh.shipment_id")


def shipment_query():
    return """
        SELECT sh.*, src.warehouse_name AS source_name, dest.warehouse_name AS destination_name
        FROM shipment sh JOIN warehouse src ON src.warehouse_id = sh.source_warehouse_id
        JOIN warehouse dest ON dest.warehouse_id = sh.dest_warehouse_id
    """


@api.post("/shipments", tags=["shipments"], status_code=201)
def create_shipment(payload: Shipment):
    with session() as cursor:
        cursor.execute("""
            INSERT INTO shipment (shipment_id, tracking_number, source_warehouse_id, dest_warehouse_id,
                                  dispatch_date, estimated_arrival)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (payload.shipment_id, payload.tracking_number, payload.source_warehouse_id,
              payload.dest_warehouse_id, payload.dispatch_date, payload.estimated_arrival))
    return {"shipment_id": payload.shipment_id}


@api.get("/shipments/{shipment_id}", tags=["shipments"])
def shipment_detail(shipment_id: Identifier):
    with session() as cursor:
        cursor.execute(shipment_query() + " WHERE sh.shipment_id = %s", (shipment_id,))
        item = required(cursor.fetchone())
        cursor.execute("""
            SELECT d.product_id, p.product_name, d.shipped_quantity,
                   COALESCE(i.quantity_on_hand, 0) AS source_stock
            FROM shipment_detail d JOIN product p ON p.product_id = d.product_id
            LEFT JOIN inventory i ON i.product_id = d.product_id AND i.warehouse_id = %s
            WHERE d.shipment_id = %s ORDER BY d.product_id
        """, (item["source_warehouse_id"], shipment_id))
        return {"item": item, "lines": cursor.fetchall()}


def register_workflow(path, table, id_column, status_model, line_model):
    detail_table = f"{table}_detail"
    columns = list(line_model.model_fields)
    assignments = ", ".join(f"{name} = %s" for name in columns)
    placeholders = ", ".join(["%s"] * (2 + len(columns)))

    def locked_parent(cursor, record_id, draft=False):
        cursor.execute(f"SELECT status FROM {table} WHERE {id_column} = %s FOR UPDATE", (record_id,))
        parent = required(cursor.fetchone())
        if draft and parent["status"] != "Pending":
            raise HTTPException(409, "Chỉ có thể sửa chi tiết của bản nháp.")

    @api.patch(path + "/{record_id}/status", name=f"set_{table}_status", tags=[table])
    def set_status(record_id: Identifier, payload: status_model):
        with session() as cursor:
            locked_parent(cursor, record_id)
            cursor.execute(f"UPDATE {table} SET status = %s WHERE {id_column} = %s", (payload.status, record_id))
        return payload

    @api.put(path + "/{record_id}/lines/{product_id}", name=f"set_{table}_line", tags=[table])
    def set_line(record_id: Identifier, product_id: Identifier, payload: line_model):
        values = tuple(getattr(payload, column) for column in columns)
        with session() as cursor:
            locked_parent(cursor, record_id, draft=True)
            cursor.execute(
                f"INSERT INTO {detail_table} ({id_column}, product_id, {', '.join(columns)}) "
                f"VALUES ({placeholders}) ON DUPLICATE KEY UPDATE {assignments}",
                (record_id, product_id, *values, *values),
            )
        return payload

    @api.delete(path + "/{record_id}/lines/{product_id}", name=f"delete_{table}_line", tags=[table], status_code=204)
    def delete_line(record_id: Identifier, product_id: Identifier):
        with session() as cursor:
            locked_parent(cursor, record_id, draft=True)
            cursor.execute(f"DELETE FROM {detail_table} WHERE {id_column} = %s AND product_id = %s", (record_id, product_id))
            if not cursor.rowcount:
                required(None)
        return Response(status_code=204)


register_workflow("/orders", "supplier_order", "order_id", OrderStatus, OrderLine)
register_workflow("/shipments", "shipment", "shipment_id", ShipmentStatus, ShipmentLine)
