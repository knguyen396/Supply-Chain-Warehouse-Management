import json
import os
import unittest
from http.cookiejar import CookieJar
from urllib.error import HTTPError
from urllib.request import HTTPCookieProcessor, Request, build_opener

BASE = os.getenv("G3_TEST_URL", "http://127.0.0.1:8000")


def request(path, method="GET", body=None, client=None, include_header=True):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if include_header:
        headers["X-G3-Request"] = "1"
    req = Request(BASE + path, data=data, method=method, headers=headers)
    try:
        response = (client or build_opener()).open(req, timeout=10)
    except HTTPError as error:
        response = error
    with response:
        raw = response.read()
        if raw and "application/json" in response.headers.get("Content-Type", ""):
            return response.status, json.loads(raw)
        return response.status, raw


class WarehouseIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.admin_username = os.getenv("G3_TEST_ADMIN_USERNAME")
        cls.admin_password = os.getenv("G3_TEST_ADMIN_PASSWORD")
        if not (cls.admin_username and cls.admin_password):
            raise unittest.SkipTest("Set G3_TEST_ADMIN_USERNAME and G3_TEST_ADMIN_PASSWORD for a disposable database.")

    def setUp(self):
        self.client = build_opener(HTTPCookieProcessor(CookieJar()))
        self.call("/api/auth/login", "POST", {"username": self.admin_username, "password": self.admin_password})

    def call(self, path, method="GET", body=None, expected=200):
        status, result = request(path, method, body, self.client)
        self.assertEqual(status, expected, result)
        return result

    def test_authentication_and_roles(self):
        self.assertEqual(request("/api/dashboard")[0], 401)
        self.assertEqual(request("/api/auth/login", "POST", {}, include_header=False)[0], 422)
        self.assertEqual(request("/api/auth/logout", "POST", client=self.client, include_header=False)[0], 403)
        users = {}
        for role in ("warehouse", "procurement", "logistics"):
            username = "test_" + role
            self.call("/api/users", "POST", {"username": username, "password": self.admin_password, "role": role}, 201)
            client = build_opener(HTTPCookieProcessor(CookieJar()))
            status, user = request("/api/auth/login", "POST", {"username": username, "password": self.admin_password}, client)
            self.assertEqual((status, user["role"]), (200, role))
            self.assertEqual(request("/api/inventory", client=client)[0], 200)
            self.assertEqual(request("/api/users", client=client)[0], 403)
            users[role] = (client, user)
        procurement, user = users["procurement"]
        warehouse, _ = users["warehouse"]
        logistics, _ = users["logistics"]
        self.assertEqual(request("/api/shipments/SH004/status", "PATCH", {"status": "In-Transit"}, procurement)[0], 403)
        self.assertEqual(self.call("/api/shipments/SH004")["item"]["status"], "Pending")
        self.assertEqual(request("/api/orders", client=warehouse)[0], 403)
        self.assertEqual(request("/api/alerts", client=warehouse)[0], 200)
        self.assertEqual(request("/api/shipments/SH004/status", "PATCH", {"status": "In-Transit"}, logistics, False)[0], 403)
        self.assertEqual(request("/api/shipments/SH004/status", "PATCH", {"status": "In-Transit"}, logistics)[0], 200)
        self.call(f"/api/users/{user['user_id']}/role", "PATCH", {"role": "warehouse"})
        self.assertEqual(request("/api/orders", client=procurement)[0], 401)
        self.assertEqual(request("/api/auth/logout", "POST", client=logistics)[0], 204)
        self.assertEqual(request("/api/shipments", client=logistics)[0], 401)

    def stock(self, warehouse, product):
        items = self.call("/api/inventory?warehouse_id=" + warehouse)
        return next(item["quantity_on_hand"] for item in items if item["product_id"] == product)

    def test_pages_and_catalogs(self):
        self.assertIn(b'id="screen"', self.call("/"))
        self.assertIn(b"async function render", self.call("/assets/app.js"))
        spec = self.call("/openapi.json")
        self.assertIn("/api/shipments/{record_id}/status", spec["paths"])
        metrics = self.call("/api/dashboard")["metrics"]
        self.assertGreaterEqual(metrics["warehouses"], 4)
        for route in ("warehouses", "products", "inventory", "suppliers", "orders", "shipments", "alerts"):
            self.assertTrue(self.call("/api/" + route))
        bom = self.call("/api/products/P001/bom")
        self.assertTrue(any(item["depth"] >= 2 for item in bom))
        self.call("/api/warehouses/W001", "DELETE", expected=409)
        self.call("/api/inventory/W001/P002", "PUT", {"quantity_on_hand": -1}, expected=422)
        self.call("/api/inventory/W001/P002", "PUT", {"quantity_on_hand": 15})
        alert = next(a for a in self.call("/api/alerts") if a["warehouse_id"] == "W001" and a["product_id"] == "P002" and a["status"] == "Pending")
        self.call("/api/alerts/" + alert["alert_id"] + "/resolve", "PATCH")
        self.call("/api/inventory/W001/P002", "PUT", {"quantity_on_hand": 55})

        warehouse = {"warehouse_id": "TW001", "warehouse_name": "Test warehouse", "location_address": "Test address", "capacity": 5}
        self.call("/api/warehouses", "POST", warehouse, 201)
        self.call("/api/warehouses", "POST", warehouse, 409)
        warehouse["capacity"] = 8
        self.call("/api/warehouses/TW001", "PUT", warehouse)
        self.call("/api/warehouses/TW001", "DELETE", expected=204)

    def test_order_totals(self):
        order = {"order_id": "TO001", "supplier_id": "S001", "order_date": "2026-11-26"}
        self.call("/api/orders", "POST", order, 201)
        base = "/api/orders/TO001"
        self.call(base + "/status", "PATCH", {"status": "Completed"}, 409)
        self.call(base + "/lines/P002", "PUT", {"order_quantity": 2, "unit_price": "15.25"})
        self.assertEqual(self.call(base)["item"]["total_order_value"], 30.5)
        self.call(base + "/lines/P002", "PUT", {"order_quantity": 3, "unit_price": "15.25"})
        self.call(base + "/lines/P003", "PUT", {"order_quantity": 1, "unit_price": "9.00"})
        self.call(base + "/lines/P003", "DELETE", expected=204)
        self.assertEqual(self.call(base)["item"]["total_order_value"], 45.75)
        self.call(base + "/status", "PATCH", {"status": "Completed"})

    def test_shipment_and_rollback(self):
        shipment = {"shipment_id": "TS001", "tracking_number": "TEST-TS001", "source_warehouse_id": "W001",
                    "dest_warehouse_id": "W002", "dispatch_date": "2026-11-26T09:00",
                    "estimated_arrival": "2026-11-26T12:00"}
        first_source, first_dest = self.stock("W001", "P002"), self.stock("W002", "P002")
        self.call("/api/shipments", "POST", shipment, 201)
        base = "/api/shipments/TS001"
        self.call(base + "/status", "PATCH", {"status": "In-Transit"}, 409)
        self.call(base + "/lines/P002", "PUT", {"shipped_quantity": 3})
        self.call(base + "/status", "PATCH", {"status": "In-Transit"})
        self.call(base + "/lines/P002", "DELETE", expected=409)
        self.call(base + "/status", "PATCH", {"status": "Completed"})
        self.assertEqual(self.stock("W001", "P002"), first_source - 3)
        self.assertEqual(self.stock("W002", "P002"), first_dest + 3)
        self.call(base + "/status", "PATCH", {"status": "Completed"})
        self.assertEqual(self.stock("W001", "P002"), first_source - 3)

        shipment.update(shipment_id="TS002", tracking_number="TEST-TS002")
        self.call("/api/shipments", "POST", shipment, 201)
        base = "/api/shipments/TS002"
        self.call(base + "/lines/P002", "PUT", {"shipped_quantity": 1})
        self.call(base + "/lines/P003", "PUT", {"shipped_quantity": self.stock("W001", "P003") + 1})
        self.call(base + "/status", "PATCH", {"status": "In-Transit"})
        self.call(base + "/status", "PATCH", {"status": "Completed"}, 409)
        self.assertEqual(self.call(base)["item"]["status"], "In-Transit")
        self.assertEqual(self.stock("W001", "P002"), first_source - 3)
        self.assertEqual(self.stock("W002", "P002"), first_dest + 3)
