### 3.3 Normalization Proofs

The ten relations are evaluated using their functional dependencies and candidate keys. All attributes contain atomic values, so every relation satisfies 1NF. The analysis assumes no additional dependencies or uniqueness constraints beyond the stated business rules.

#### 3.3.1 Functional Dependencies and Candidate Keys

In the table below, each candidate key determines all attributes listed in the last column (key → dependent attributes).

| Relation | Candidate key | Dependent attributes |
| --- | --- | --- |
| WAREHOUSE | warehouse_id | warehouse_name, location_address, capacity |
| PRODUCT | product_id | product_name, unit, min_reorder_level, unit_price |
| SUPPLIER | supplier_id | supplier_name, contact_email, phone_number, address |
| SUPPLIER_ORDER | order_id | supplier_id, order_date, status, total_amount |
| SHIPMENT | shipment_id | tracking_number, source_warehouse_id, dest_warehouse_id, dispatch_date, estimated_arrival, status |
| RESTOCK_ALERT | alert_id | warehouse_id, product_id, alert_date, status |
| INVENTORY | {warehouse_id, product_id} | quantity_on_hand, last_updated |
| PRODUCT_STRUCTURE | {parent_product_id, child_component_id} | quantity_required |
| SUPPLIER_ORDER_DETAIL | {order_id, product_id} | order_quantity, unit_price |
| SHIPMENT_DETAIL | {shipment_id, product_id} | shipped_quantity |

For each relation, the listed key determines all attributes, and no proper subset determines the entire relation. Therefore, each listed key is a candidate key.

#### 3.3.2 Second Normal Form

The six relations with single-attribute keys have no partial dependencies. For the four relations with composite keys, every non-key attribute depends on the complete key:

- INVENTORY: Stock quantity and update time depend on both the warehouse and the product.

- PRODUCT_STRUCTURE: Required quantity depends on both the parent product and the child component.

- SUPPLIER_ORDER_DETAIL: Ordered quantity and purchase price depend on both the order and the product.

- SHIPMENT_DETAIL: Shipped quantity depends on both the shipment and the product.

In SUPPLIER_ORDER_DETAIL, unit_price is the purchase price for a specific order, so product_id alone does not determine it. Therefore, all relations satisfy 2NF.

#### 3.3.3 Third Normal Form and BCNF

A relation satisfies 3NF if, for every nontrivial dependency X → A, X is a superkey or A is a prime attribute. BCNF requires every such determinant X to be a superkey.

Under the dependencies listed above, there are no dependencies between non-key attributes. Supplier descriptions remain in SUPPLIER, product descriptions remain in PRODUCT, and warehouse descriptions remain in WAREHOUSE, avoiding transitive dependencies within other relations.

For each relation, a set of attributes that does not contain the complete candidate key cannot determine any additional attribute using the stated dependencies. Thus, every nontrivial determinant is a superkey.

Therefore, all ten relations satisfy BCNF and consequently 3NF.

#### 3.3.4 Conclusion

The schema satisfies the required 3NF/BCNF normalization level under the stated business rules. No further decomposition is necessary.

Although total_amount does not violate BCNF, it must be calculated from order details or maintained consistently when those details change.
