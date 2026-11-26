from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

Identifier = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=10, pattern=r"^[A-Za-z0-9_-]+$")]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
PositiveInt = Annotated[int, Field(gt=0, le=2147483647)]
NonnegativeInt = Annotated[int, Field(ge=0, le=2147483647)]
Price = Annotated[Decimal, Field(ge=0, max_digits=10, decimal_places=2)]


class Payload(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Warehouse(Payload):
    warehouse_id: Identifier
    warehouse_name: Name
    location_address: str = Field(min_length=1, max_length=4000)
    capacity: PositiveInt


class Product(Payload):
    product_id: Identifier
    product_name: Name
    unit: str = Field(min_length=1, max_length=20)
    min_reorder_level: NonnegativeInt
    unit_price: Price


class Supplier(Payload):
    supplier_id: Identifier
    supplier_name: Name
    contact_email: str | None = Field(default=None, max_length=100)
    phone_number: str | None = Field(default=None, max_length=20)
    address: str | None = Field(default=None, max_length=4000)


class Stock(Payload):
    quantity_on_hand: NonnegativeInt


class Order(Payload):
    order_id: Identifier
    supplier_id: Identifier
    order_date: date


class Shipment(Payload):
    shipment_id: Identifier
    tracking_number: str = Field(min_length=1, max_length=50)
    source_warehouse_id: Identifier
    dest_warehouse_id: Identifier
    dispatch_date: datetime
    estimated_arrival: datetime

    @model_validator(mode="after")
    def check_route(self):
        if self.source_warehouse_id.lower() == self.dest_warehouse_id.lower():
            raise ValueError("Kho nguồn và kho đích phải khác nhau")
        if self.dispatch_date.tzinfo is not None or self.estimated_arrival.tzinfo is not None:
            raise ValueError("Sử dụng giờ địa phương cho chuyến hàng")
        if self.estimated_arrival < self.dispatch_date:
            raise ValueError("Ngày đến dự kiến phải sau hoặc bằng ngày đi")
        return self


class OrderLine(Payload):
    order_quantity: PositiveInt
    unit_price: Price


class ShipmentLine(Payload):
    shipped_quantity: PositiveInt


class OrderStatus(Payload):
    status: Literal["Completed", "Canceled"]


class ShipmentStatus(Payload):
    status: Literal["In-Transit", "Completed", "Canceled"]
