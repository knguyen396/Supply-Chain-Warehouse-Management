const find = (selector, root = document) => root.querySelector(selector);
const screen = find("#screen");
const modal = find("#modal");
const modalContent = find("#modal-content");
const pageAction = find("#page-action");
const dashboardShortcuts = find("#dashboard-shortcuts");
let account = null;
const roleLabels = { admin: "Quản trị viên", warehouse: "Nhân viên kho", procurement: "Nhân viên mua hàng", logistics: "Nhân viên vận chuyển" };
const canRead = (key) => account?.read.includes(key);
const canWrite = (key) => account?.write.includes(key);
const number = new Intl.NumberFormat("vi-VN");
const currency = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 2 });
const shipmentStates = ["Pending", "In-Transit", "Completed", "Canceled"];
const orderStates = ["Pending", "Completed", "Canceled"];
const statusLabels = {
  Pending: "Chờ xử lý", "In-Transit": "Đang vận chuyển", Completed: "Hoàn tất",
  Canceled: "Đã hủy", Resolved: "Đã xử lý", "Low Stock": "Dưới ngưỡng", "Sufficient Stock": "Đủ tồn"
};
const headings = {
  dashboard: ["Tổng quan", "Theo dõi tồn kho, vận chuyển và cảnh báo nhập hàng."],
  warehouses: ["Kho hàng", "Quản lý kho và xem sản phẩm đang lưu tại từng địa điểm."],
  products: ["Sản phẩm & BOM", "Quản lý sản phẩm, ngưỡng nhập và cấu trúc linh kiện."],
  inventory: ["Tồn kho", "Tra cứu và điều chỉnh số lượng theo kho và sản phẩm."],
  suppliers: ["Nhà cung cấp", "Quản lý thông tin liên hệ và xem các đơn nhập liên quan."],
  orders: ["Đơn nhập hàng", "Tạo đơn nháp, thêm sản phẩm và theo dõi tổng tiền."],
  shipments: ["Chuyển kho", "Tạo chuyến và theo dõi hàng đi giữa các kho."],
  alerts: ["Cảnh báo nhập hàng", "Kiểm tra các mặt hàng dưới ngưỡng nhập và xử lý cảnh báo."],
  users: ["Tài khoản", "Tạo tài khoản và gán vai trò cho từng người dùng."]
};
const iconPaths = [
  "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  "M3 21V9l9-6 9 6v12z M8 21V12h8v9",
  "M3 7l9-4 9 4v10l-9 4-9-4z M3 7l9 4 9-4 M12 11v10",
  "M4 5h16v15H4z M4 9h16 M9 13h6",
  "M3 21v-3a4 4 0 0 1 4-4h5a4 4 0 0 1 4 4v3 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M20 21v-4",
  "M6 3h12v18H6z M9 8h6 M9 12h6 M9 16h3",
  "M3 6h12v11H3z M15 10h4l2 3v4h-6 M7 19h.1 M18 19h.1",
  "M5 17c1-2 2-3 2-7a5 5 0 0 1 10 0c0 4 1 5 2 7z M10 21h4"
];

function element(tag, className = "", ...children) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  for (const child of children.flat()) {
    if (child !== undefined && child !== null && child !== false) node.append(child instanceof Node ? child : String(child));
  }
  return node;
}

function icon(index) {
  const namespace = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(namespace, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(namespace, "path");
  Object.entries({ d: iconPaths[index], fill: "none", stroke: "currentColor", "stroke-width": "1.7",
    "stroke-linecap": "round", "stroke-linejoin": "round" }).forEach(([name, value]) => path.setAttribute(name, value));
  svg.append(path);
  return svg;
}

function button(label, action, kind = "secondary") {
  const node = element("button", kind, label);
  node.type = "button";
  node.addEventListener("click", async () => {
    node.disabled = true;
    try { await action(); }
    catch (error) { notify(error.message, true); }
    finally { node.disabled = false; }
  });
  return node;
}

async function api(path, method = "GET", payload) {
  const options = { method, headers: { "X-G3-Request": "1" } };
  if (payload !== undefined) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(payload);
  }
  const response = await fetch("/api/" + path, options).catch(() => {
    throw new Error("Không kết nối được ứng dụng. Hãy tải lại trang.");
  });
  if (response.status === 204) return;
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401 && account) showLogin("Phiên đăng nhập đã hết hạn.");
    const error = new Error(body.detail || "Yêu cầu không thành công.");
    error.status = response.status;
    throw error;
  }
  return body;
}

let noticeTimer;
function notify(message, error = false) {
  const notice = find("#notice");
  notice.textContent = message;
  notice.className = error ? "error" : "";
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => { notice.textContent = ""; }, 5000);
}

function pill(value) {
  return element("span", "pill " + String(value).toLowerCase().replaceAll(" ", "-"), statusLabels[value] || value);
}

const formatNumber = (value) => /^[0-9]+$/.test(String(value)) ? number.format(BigInt(value)) : number.format(Number(value) || 0);
const formatDate = (value) => value ? value.replace("T", " ").slice(0, 16) : "—";
const money = (value) => currency.format(Number(value));
const actionCell = (...items) => element("div", "actions", items);
const linked = (label, hash) => Object.assign(element("a", "", label), { href: hash });
const column = (label, key, format = (value) => value ?? "—") => [label, (row) => format(row[key])];

function table(data, columns) {
  if (!data.length) return element("p", "state", "Không có dữ liệu phù hợp.");
  const header = element("tr", "", columns.map(([label]) => {
    const cell = element("th", "", label);
    cell.scope = "col";
    return cell;
  }));
  const body = data.map((row) => element("tr", "", columns.map(([, render]) => element("td", "", render(row)))));
  return element("div", "table-wrap", element("table", "", element("thead", "", header), element("tbody", "", body)));
}

function panel(title, content, link) {
  return element("section", "panel", title && element("div", "panel-heading", element("h2", "", title), link), content);
}

function selectInput(options, value = "") {
  const input = element("select");
  for (const [key, label] of options) input.append(Object.assign(element("option", "", label), { value: key }));
  input.value = value;
  return input;
}

function filtered(data, columns, config = {}) {
  const { filters = [], searchKeys = [], initialQuery = "" } = config;
  const toolbar = element("div", "toolbar");
  const input = Object.assign(element("input"), { type: "search", placeholder: "Tìm theo mã hoặc tên", value: initialQuery });
  input.setAttribute("aria-label", "Tìm theo mã hoặc tên");
  if (searchKeys.length) toolbar.append(input);
  const criteria = filters.map(([label, key, options, initial]) => {
    const control = selectInput([["", label], ...options], initial);
    control.setAttribute("aria-label", label);
    toolbar.append(control);
    return [key, control];
  });
  const result = element("div");
  function refresh() {
    const q = input.value.trim().toLocaleLowerCase("vi");
    const shown = data.filter((row) =>
      (!q || searchKeys.some((key) => String(row[key] ?? "").toLocaleLowerCase("vi").includes(q))) &&
      criteria.every(([key, control]) => !control.value || String(row[key]) === control.value));
    result.replaceChildren(table(shown, columns));
  }
  input.addEventListener("input", refresh);
  criteria.forEach(([, control]) => control.addEventListener("change", refresh));
  refresh();
  return element("div", "panel", toolbar, result);
}

function openModal(title, content) {
  find("#modal-title").textContent = title;
  modalContent.replaceChildren(content);
  if (!modal.open) modal.showModal();
}

function makeForm(fields, onSubmit, label = "Lưu") {
  const form = element("form");
  const inputs = fields.map((field) => {
    const input = field.options
      ? selectInput([["", "Chọn " + field.label.toLowerCase()], ...field.options], String(field.value ?? ""))
      : Object.assign(element("input"), { type: field.type || "text", value: field.value ?? "" });
    input.name = field.name;
    if (field.autocomplete) input.autocomplete = field.autocomplete;
    input.required = !field.optional;
    input.readOnly = Boolean(field.readOnly);
    if (field.maxLength) input.maxLength = field.maxLength;
    if (field.pattern) input.pattern = field.pattern;
    if (field.min !== undefined) input.min = field.min;
    if (field.step) input.step = field.step;
    return [field, input];
  });
  const errorBox = element("p", "form-error");
  errorBox.setAttribute("role", "alert");
  const submit = Object.assign(element("button", "primary", label), { type: "submit" });
  form.append(
    element("div", "fields", inputs.map(([field, input]) => element("label", "", field.label, input))),
    errorBox,
    element("div", "form-actions", submit)
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    submit.disabled = true;
    errorBox.textContent = "";
    const payload = Object.fromEntries(inputs.map(([field, input]) => [
      field.name, field.optional && !input.value ? null : field.type === "number" && field.step !== "0.01" ? Number(input.value) : input.value
    ]));
    try { await onSubmit(payload); }
    catch (error) { errorBox.textContent = error.message; }
    finally { submit.disabled = false; }
  });
  return form;
}

const id = (name, label) => ({ name, label, maxLength: 10, pattern: "[A-Za-z0-9_\\-]+" });
const textField = (name, label, maxLength = 100, optional = false) => ({ name, label, maxLength, optional });
const qty = (name, label, min = 0) => ({ name, label, type: "number", min, step: "1" });
const price = (label) => ({ name: "unit_price", label, type: "number", min: 0, step: "0.01" });
const optionsFor = (records, idKey, nameKey) => records.map((record) => [record[idKey], record[idKey] + " · " + record[nameKey]]);
const statusOptions = (values) => values.map((value) => [value, statusLabels[value]]);

function formModal(title, fields, save) {
  openModal(title, makeForm(fields, async (data) => {
    await save(data);
    modal.close();
    notify("Đã lưu thay đổi.");
    await render();
  }));
}

const catalogs = {
  warehouses: {
    label: "kho", fields: [id("warehouse_id", "Mã kho"), textField("warehouse_name", "Tên kho"),
      textField("location_address", "Địa chỉ", 4000), qty("capacity", "Sức chứa", 1)],
    columns: [column("Mã kho", "warehouse_id"), column("Tên kho", "warehouse_name"),
      column("Địa chỉ", "location_address"), column("Sức chứa", "capacity", formatNumber)],
    extra: (row) => button("Xem tồn kho", () => { location.hash = "inventory/" + encodeURIComponent(row.warehouse_id); })
  },
  products: {
    label: "sản phẩm", fields: [id("product_id", "Mã sản phẩm"), textField("product_name", "Tên sản phẩm"),
      textField("unit", "Đơn vị", 20), qty("min_reorder_level", "Ngưỡng nhập"), price("Đơn giá")],
    columns: [column("Mã", "product_id"), column("Sản phẩm", "product_name"), column("Đơn vị", "unit"),
      column("Ngưỡng nhập", "min_reorder_level", formatNumber), column("Đơn giá", "unit_price", money)],
    extra: (row) => button("Xem BOM", async () => {
      const data = await api("products/" + encodeURIComponent(row.product_id) + "/bom");
      openModal("BOM · " + row.product_name, table(data, [column("Cấp", "depth"), column("Mã cha", "parent_product_id"),
        column("Linh kiện", "product_name"), column("SL mỗi cấp", "quantity_required", formatNumber),
        column("SL quy đổi", "total_quantity", formatNumber)]));
    })
  },
  suppliers: {
    label: "nhà cung cấp", fields: [id("supplier_id", "Mã nhà cung cấp"), textField("supplier_name", "Tên nhà cung cấp"),
      { ...textField("contact_email", "Email", 100, true), type: "email" },
      textField("phone_number", "Điện thoại", 20, true), textField("address", "Địa chỉ", 4000, true)],
    columns: [column("Mã", "supplier_id"), column("Nhà cung cấp", "supplier_name"), column("Email", "contact_email"),
      column("Điện thoại", "phone_number"), column("Địa chỉ", "address")],
    extra: (row) => button("Xem đơn nhập", () => { location.hash = "orders/" + encodeURIComponent(row.supplier_id); })
  }
};

async function catalog(key) {
  const data = await api(key);
  const config = catalogs[key];
  const keyField = config.fields[0].name;
  function edit(row) {
    const editing = Boolean(row);
    formModal((editing ? "Sửa " : "Thêm ") + config.label, config.fields.map((field) => ({
      ...field, value: row?.[field.name] ?? (field.name === "min_reorder_level" ? 0 : ""), readOnly: editing && field.name === keyField
    })), (payload) => api(editing ? key + "/" + encodeURIComponent(row[keyField]) : key, editing ? "PUT" : "POST", payload));
  }
  const columns = [...config.columns, ["Thao tác", (row) => actionCell(
    config.extra(row),
    canWrite(key) && button("Sửa", () => edit(row)),
    canWrite(key) && button("Xóa", async () => {
      if (!confirm("Xóa " + config.label + " " + row[keyField] + "?")) return;
      await api(key + "/" + encodeURIComponent(row[keyField]), "DELETE");
      notify("Đã xóa bản ghi.");
      await render();
    }, "danger")
  )]];
  return { body: filtered(data, columns, { searchKeys: config.fields.slice(0, 2).map((field) => field.name) }),
    action: canWrite(key) && ["Thêm " + config.label, () => edit()] };
}

const alertColumns = [column("Sản phẩm", "product_name"), column("Kho", "warehouse_name"),
  column("Tồn hiện tại", "quantity_on_hand", formatNumber), column("Ngưỡng nhập", "min_reorder_level", formatNumber),
  column("Trạng thái", "status", pill)];

async function dashboard() {
  const data = await api("dashboard");
  const metricsConfig = [
    ["warehouses", "Kho hàng", 1, "warehouses"],
    ["products", "Sản phẩm", 2, "products"],
    ["stock", "Tổng số lượng tồn", 3, "inventory"],
    ["shipments", "Chuyến hàng", 6, "shipments"],
    ["alerts", "Cảnh báo đang mở", 7, "alerts"]
  ];
  const metrics = element("div", "metrics", metricsConfig.filter(([key]) => Object.hasOwn(data.metrics, key)).map(([key, label, symbol, page]) =>
    Object.assign(element("a", "metric metric-" + key,
      element("span", "metric-icon", icon(symbol)),
      element("div", "metric-value", element("span", "", label), element("strong", "", formatNumber(data.metrics[key])))),
    { href: "#" + page })));
  const maxStock = Math.max(1, ...data.by_warehouse.map((row) => Number(row.stock)));
  const chart = element("div", "chart", data.by_warehouse.length ? data.by_warehouse.map((row) => {
    const bar = element("span", "bar");
    bar.style.width = Number(row.stock) / maxStock * 100 + "%";
    return element("div", "", element("div", "bar-label", row.warehouse_name, element("strong", "", formatNumber(row.stock))),
      element("div", "bar-track", bar));
  }) : element("p", "state", "Chưa có kho hàng."));
  const counts = new Map(data.shipment_status.map((row) => [row.status, row.total]));
  const statuses = element("div", "summary", shipmentStates.map((state) =>
    element("div", "", pill(state), element("strong", "", formatNumber(counts.get(state) ?? 0)))));
  return { body: element("div", "", metrics, element("div", "dashboard-grid",
    panel("Tồn kho theo địa điểm", chart, linked("Xem tồn kho", "#inventory")),
    canRead("shipments") && panel("Trạng thái chuyến hàng", statuses, linked("Xem chuyến hàng", "#shipments"))),
  canRead("alerts") && panel("Cảnh báo đang mở", table(data.alerts, alertColumns), linked("Tất cả cảnh báo", "#alerts"))) };
}

async function inventory(initial) {
  const [data, warehouses, products] = await Promise.all([
    api("inventory"), canWrite("inventory") ? api("warehouses") : [],
    canWrite("inventory") ? api("products") : []
  ]);
  const warehouseOptions = canWrite("inventory") ? optionsFor(warehouses, "warehouse_id", "warehouse_name")
    : [...new Map(optionsFor(data, "warehouse_id", "warehouse_name"))];
  const productOptions = optionsFor(products, "product_id", "product_name");
  function adjust(row) {
    const fields = row
      ? [id("warehouse_id", "Kho"), id("product_id", "Sản phẩm")].map((field) => ({ ...field, readOnly: true, value: row[field.name] }))
      : [{ name: "warehouse_id", label: "Kho", options: warehouseOptions, value: initial },
        { name: "product_id", label: "Sản phẩm", options: productOptions }];
    formModal("Cập nhật tồn kho", [...fields, { ...qty("quantity_on_hand", "Số lượng thực tế"), value: row?.quantity_on_hand ?? 0 }],
      ({ warehouse_id, product_id, quantity_on_hand }) =>
        api("inventory/" + encodeURIComponent(warehouse_id) + "/" + encodeURIComponent(product_id), "PUT", { quantity_on_hand }));
  }
  return { body: filtered(data, [
    column("Kho", "warehouse_name"), column("Mã sản phẩm", "product_id"), column("Sản phẩm", "product_name"),
    column("Số lượng", "quantity_on_hand", formatNumber), column("Đơn vị", "unit"),
    column("Ngưỡng nhập", "min_reorder_level", formatNumber), column("Tình trạng", "stock_status", pill),
    column("Cập nhật", "last_updated", formatDate),
    ...(canWrite("inventory") ? [["Thao tác", (row) => button("Điều chỉnh", () => adjust(row))]] : [])
  ], { searchKeys: ["product_id", "product_name"], filters: [
    ["Tất cả kho", "warehouse_id", warehouseOptions, initial],
    ["Tất cả tình trạng", "stock_status", statusOptions(["Low Stock", "Sufficient Stock"])]
  ] }), action: canWrite("inventory") && ["Cập nhật tồn", () => adjust()] };
}

async function alerts() {
  const data = await api("alerts");
  return { body: filtered(data, [...alertColumns, column("Thời điểm", "alert_date", formatDate),
    ["Thao tác", (row) => row.status === "Pending" && canWrite("alerts") ? button("Đánh dấu đã xử lý", async () => {
      await api("alerts/" + encodeURIComponent(row.alert_id) + "/resolve", "PATCH");
      notify("Đã xử lý cảnh báo.");
      await render();
    }) : "—"]
  ], { searchKeys: ["product_name", "product_id", "warehouse_name", "alert_id"],
    filters: [["Tất cả trạng thái", "status", statusOptions(["Pending", "Resolved"])]] }) };
}

function localDateTime() {
  const now = new Date();
  return new Date(now.valueOf() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

async function workflow(key, initial) {
  const shipping = key === "shipments";
  const lookup = shipping ? "warehouses" : "suppliers";
  const [data, records] = await Promise.all([api(key), api(lookup)]);
  const lookupOptions = shipping ? optionsFor(records, "warehouse_id", "warehouse_name") : optionsFor(records, "supplier_id", "supplier_name");
  const keyField = shipping ? "shipment_id" : "order_id";
  const columns = shipping
    ? [column("Mã chuyến", keyField), column("Mã theo dõi", "tracking_number"), column("Kho nguồn", "source_name"),
      column("Kho đích", "destination_name"), column("Ngày đi", "dispatch_date", formatDate)]
    : [column("Mã đơn", keyField), column("Nhà cung cấp", "supplier_name"), column("Ngày đặt", "order_date"),
      column("Tổng tiền", "total_order_value", money)];
  function create() {
    const now = localDateTime();
    const fields = shipping
      ? [id(keyField, "Mã chuyến"), textField("tracking_number", "Mã theo dõi", 50),
        { name: "source_warehouse_id", label: "Kho nguồn", options: lookupOptions },
        { name: "dest_warehouse_id", label: "Kho đích", options: lookupOptions },
        { name: "dispatch_date", label: "Ngày đi", type: "datetime-local", value: now },
        { name: "estimated_arrival", label: "Ngày đến dự kiến", type: "datetime-local", value: now }]
      : [id(keyField, "Mã đơn"), { name: "supplier_id", label: "Nhà cung cấp", options: lookupOptions, value: initial },
        { name: "order_date", label: "Ngày đặt", type: "date", value: now.slice(0, 10) }];
    openModal(shipping ? "Tạo chuyến nháp" : "Tạo đơn nháp", makeForm(fields, async (payload) => {
      const created = await api(key, "POST", payload);
      notify("Đã tạo bản nháp.");
      await render();
      await detail(key, created[keyField]);
    }, "Tạo bản nháp"));
  }
  return { body: filtered(data, [...columns, column("Trạng thái", "status", pill),
    ["Thao tác", (row) => button("Xem chi tiết", () => detail(key, row[keyField]))]
  ], { searchKeys: shipping ? [keyField, "tracking_number", "source_name", "destination_name"] : [keyField, "supplier_name"],
    filters: [["Tất cả trạng thái", "status", statusOptions(shipping ? shipmentStates : orderStates)],
      [shipping ? "Tất cả kho nguồn" : "Tất cả nhà cung cấp", shipping ? "source_warehouse_id" : "supplier_id", lookupOptions, initial]] }),
  action: [shipping ? "Tạo chuyến hàng" : "Tạo đơn nhập", create] };
}

async function detail(key, recordId) {
  const shipping = key === "shipments";
  const base = key + "/" + encodeURIComponent(recordId);
  const { item, lines } = await api(base);
  const draft = item.status === "Pending";
  const products = draft ? await api("products") : [];
  const quantityKey = shipping ? "shipped_quantity" : "order_quantity";
  const header = element("div", "detail-header", pill(item.status), element("span", "muted", shipping
    ? item.source_name + " · " + item.destination_name + " · " + formatDate(item.dispatch_date) + " / " + formatDate(item.estimated_arrival)
    : item.supplier_name + " · Tổng " + money(item.total_order_value)));

  function lineForm(line) {
    const field = line ? { ...id("product_id", "Mã sản phẩm"), readOnly: true, value: line.product_id }
      : { name: "product_id", label: "Sản phẩm", options: optionsFor(products, "product_id", "product_name") };
    const fields = [field, { ...qty(quantityKey, "Số lượng", 1), value: line?.[quantityKey] ?? 1 }];
    if (!shipping) fields.push({ ...price("Đơn giá"), value: line?.unit_price ?? "" });
    const form = makeForm(fields, async ({ product_id, ...payload }) => {
      await api(base + "/lines/" + encodeURIComponent(product_id), "PUT", payload);
      notify("Đã lưu dòng sản phẩm.");
      await render();
      await detail(key, recordId);
    }, line ? "Lưu dòng" : "Thêm hoặc cập nhật");
    lineEditor.replaceChildren(form);
    if (line) lineEditor.append(button("Quay lại thêm sản phẩm", () => lineForm()));
    if (line) find("input[name='" + quantityKey + "']", form).focus();
  }

  function change(label, status, kind = "secondary") {
    return button(label, async () => {
      if (!confirm(label + " cho " + recordId + "?")) return;
      await api(base + "/status", "PATCH", { status });
      notify("Đã cập nhật trạng thái.");
      await render();
      await detail(key, recordId);
    }, kind);
  }

  if (draft) header.append(change(shipping ? "Bắt đầu vận chuyển" : "Hoàn tất đơn", shipping ? "In-Transit" : "Completed", "primary"),
    change(shipping ? "Hủy chuyến" : "Hủy đơn", "Canceled", "danger"));
  if (shipping && item.status === "In-Transit") header.append(change("Hoàn tất chuyển kho", "Completed", "primary"));

  const columns = [column("Mã sản phẩm", "product_id"), column("Sản phẩm", "product_name"), column("Số lượng", quantityKey, formatNumber)];
  if (shipping) columns.push(column("Tồn tại kho nguồn", "source_stock", formatNumber));
  else columns.push(column("Đơn giá", "unit_price", money), column("Thành tiền", "line_total", money));
  const lineEditor = element("div", "line-form");
  if (draft) {
    columns.push(["Thao tác", (line) => actionCell(button("Sửa", () => lineForm(line)), button("Xóa", async () => {
      if (!confirm("Xóa " + line.product_name + " khỏi bản nháp?")) return;
      await api(base + "/lines/" + encodeURIComponent(line.product_id), "DELETE");
      notify("Đã xóa dòng sản phẩm.");
      await render();
      await detail(key, recordId);
    }, "danger"))]);
    lineForm();
  }
  openModal((shipping ? "Chuyến " : "Đơn ") + recordId, element("div", "", header, table(lines, columns), draft && lineEditor));
}

async function users() {
  const records = await api("users");
  const options = Object.entries(roleLabels);
  const roleField = { name: "role", label: "Vai trò", options };
  return {
    body: panel("Danh sách tài khoản", table(records, [
      column("Tên đăng nhập", "username"), column("Vai trò", "role", (role) => roleLabels[role]),
      ["Thao tác", (row) => row.user_id === account.user_id ? "Tài khoản của bạn" :
        button("Đổi vai trò", () => formModal("Đổi vai trò · " + row.username,
          [{ ...roleField, value: row.role }],
          (payload) => api("users/" + row.user_id + "/role", "PATCH", payload)))]
    ])),
    action: ["Thêm tài khoản", () => formModal("Tạo tài khoản", [
      textField("username", "Tên đăng nhập", 32),
      { name: "password", label: "Mật khẩu (ít nhất 12 ký tự)", type: "password", maxLength: 128, autocomplete: "new-password" },
      roleField
    ], (payload) => api("users", "POST", payload))]
  };
}

const navigation = find("#navigation");
function openWorkspace(user) {
  account = user;
  find("#login-screen").hidden = true;
  find(".layout").hidden = false;
  find("#account-label").textContent = user.username + " · " + roleLabels[user.role];
  navigation.replaceChildren();
  Object.entries(headings).forEach(([key, [title]], index) => {
    if (!canRead(key) && !(key === "users" && user.role === "admin")) return;
    const link = linked(title, "#" + key);
    link.prepend(icon(key === "users" ? 4 : index));
    navigation.append(link);
  });
  render();
}

function showLogin(message = "") {
  account = null;
  if (modal.open) modal.close();
  screen.replaceChildren();
  find(".layout").hidden = true;
  find("#login-screen").hidden = false;
  const form = makeForm([
    { ...textField("username", "Tên đăng nhập", 32), autocomplete: "username" },
    { name: "password", label: "Mật khẩu", type: "password", maxLength: 128, autocomplete: "current-password" }
  ], async (payload) => openWorkspace(await api("auth/login", "POST", payload)), "Đăng nhập");
  find(".form-error", form).textContent = message;
  find("#login-form").replaceChildren(form);
}

let renderId = 0;
async function render() {
  if (!account) return;
  const requestId = ++renderId;
  let [key = "", initial = ""] = location.hash.slice(1).split("/");
  if (!Object.hasOwn(headings, key)) key = "dashboard";
  if (!canRead(key) && !(key === "users" && account.role === "admin")) key = "dashboard";
  if (!/^[A-Za-z0-9_-]{0,10}$/.test(initial)) initial = "";
  for (const link of navigation.children) {
    if (link.hash === "#" + key) {
      link.setAttribute("aria-current", "page");
      const frame = navigation.getBoundingClientRect();
      const item = link.getBoundingClientRect();
      if (item.left < frame.left) navigation.scrollLeft += item.left - frame.left - 12;
      else if (item.right > frame.right) navigation.scrollLeft += item.right - frame.right + 12;
    } else link.removeAttribute("aria-current");
  }
  find("#page-title").textContent = headings[key][0];
  find("#page-description").textContent = headings[key][1];
  find(".page-heading").classList.toggle("dashboard-heading", key === "dashboard");
  dashboardShortcuts.hidden = key !== "dashboard";
  find('#dashboard-shortcuts a[href="#shipments"]').hidden = !canRead("shipments");
  pageAction.hidden = true;
  screen.setAttribute("aria-busy", "true");
  screen.replaceChildren(element("div", "panel state", "Đang tải dữ liệu…"));
  try {
    const view = await (key === "dashboard" ? dashboard() : key === "inventory" ? inventory(initial)
      : key === "alerts" ? alerts() : key === "users" ? users()
      : key === "orders" || key === "shipments" ? workflow(key, initial) : catalog(key));
    if (requestId !== renderId) return;
    screen.replaceChildren(view.body);
    if (view.action) {
      pageAction.textContent = view.action[0];
      pageAction.onclick = view.action[1];
      pageAction.hidden = false;
    }
  } catch (error) {
    if (requestId === renderId) screen.replaceChildren(element("div", "panel state", element("p", "", error.message), button("Thử lại", render)));
  } finally {
    if (requestId === renderId) screen.removeAttribute("aria-busy");
  }
}

find("#modal-close").addEventListener("click", () => modal.close());
find(".skip-link").addEventListener("click", (event) => {
  event.preventDefault();
  find("#main-content").focus();
});
window.addEventListener("hashchange", () => {
  if (modal.open) modal.close();
  render();
});
find("#logout").addEventListener("click", async () => {
  try {
    await api("auth/logout", "POST");
    showLogin();
  } catch (error) {
    notify(error.message, true);
  }
});
api("auth/me").then(openWorkspace).catch((error) => showLogin(error.status === 401 ? "" : error.message));
