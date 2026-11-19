//// Orders read through the Admin API.
////
//// `list` and `get` select the same fields through one fragment, so a page
//// and a single read return the same record. Money comes from
//// `shopMoney`, in the shop's currency.
////
//// Shopify refuses a query whose requested cost is over 1000 points, and a
//// connection costs its `first` times the cost of one node. That caps the
//// line items per order: `get` reads up to 90 and `list` up to 10, and
//// `has_more_line_items` says when an order has more than were read. Only
//// `get` reads the refunds, four refunds of up to fifteen lines each.
////
//// `shipping_state` and `update_shipping_address` change the shipping
//// address of one order. They never touch the customer's address book.
//// `cancel` cancels one order.

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import midas/effect.{type Effect}
import pify.{type Client}
import pify/api_version
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/money
import pify/request

pub type Order {
  Order(
    id: String,
    /// The numeric id that REST and webhook bodies use.
    legacy_resource_id: String,
    name: String,
    created_at: String,
    updated_at: String,
    processed_at: String,
    cancelled_at: Option(String),
    cancel_reason: Option(CancelReason),
    closed_at: Option(String),
    /// A test order from a bootstrapped or test payment gateway.
    is_test: Bool,
    currency_code: String,
    tax_pricing: TaxPricing,
    /// The gateways that took the payment, such as `shopify_payments` or
    /// `manual`, in Shopify's order.
    payment_gateway_names: List(String),
    financial_status: Option(FinancialStatus),
    fulfillment_status: FulfillmentStatus,
    note: Option(String),
    email: Option(String),
    phone: Option(String),
    current_totals: CurrentTotals,
    original_totals: OriginalTotals,
    customer: Option(Customer),
    shipping_address: Option(Address),
    billing_address: Option(Address),
    localized_fields: List(LocalizedField),
    line_items: List(LineItem),
    has_more_line_items: Bool,
    shipping_lines: List(ShippingLine),
    refunds: RefundLines,
  )
}

/// The refunded line quantities and whether each went back to stock.
pub type RefundLines {
  /// `list` does not read refunds.
  RefundLinesUnread
  RefundLinesRead(lines: List(RefundLine))
  /// The order has more refunds or refund lines than one read returns.
  RefundLinesTruncated(lines: List(RefundLine))
}

pub type RefundLine {
  RefundLine(line_item_id: String, quantity: Int, restock: RestockType)
}

pub type RestockType {
  /// The units stay with the buyer.
  RestockTypeNoRestock
  /// Unfulfilled units, cancelled and back in stock.
  RestockTypeCancel
  RestockTypeReturn
  RestockTypeLegacyRestock
  RestockTypeOther(raw: String)
}

/// `taxesIncluded`: whether the line prices and the shipping already hold the
/// tax, or the tax comes on top of them.
pub type TaxPricing {
  TaxesIncluded
  TaxesAdded
}

/// Amounts after edits, refunds and returns, the same frame as
/// `LineItem.current_quantity`.
pub type CurrentTotals {
  CurrentTotals(
    subtotal: Money,
    shipping: Money,
    tax: Money,
    discounts: Money,
    total: Money,
  )
}

/// Amounts before returns. Shopify leaves three of them null on some orders.
pub type OriginalTotals {
  OriginalTotals(
    subtotal: Option(Money),
    shipping: Money,
    tax: Option(Money),
    discounts: Option(Money),
    total: Money,
  )
}

pub type Money =
  money.Money

/// Names and contact fields are protected customer data. Shopify redacts
/// them on some plans, so each one can be absent.
pub type Customer {
  Customer(
    id: String,
    first_name: Option(String),
    last_name: Option(String),
    display_name: String,
    email: Option(String),
    phone: Option(String),
  )
}

pub type Address {
  Address(
    name: Option(String),
    first_name: Option(String),
    last_name: Option(String),
    company: Option(String),
    address1: Option(String),
    address2: Option(String),
    city: Option(String),
    province: Option(String),
    province_code: Option(String),
    zip: Option(String),
    country: Option(String),
    country_code_v2: Option(String),
    phone: Option(String),
  )
}

/// A checkout field a country requires. Brazil stores the buyer's CPF or
/// CNPJ under the key `TAX_CREDENTIAL_BR`.
pub type LocalizedField {
  LocalizedField(
    key: String,
    value: String,
    country_code: String,
    purpose: String,
    title: String,
  )
}

pub type LineItem {
  LineItem(
    id: String,
    title: String,
    name: String,
    /// The quantity at checkout.
    quantity: Int,
    /// The quantity after edits, refunds and returns.
    current_quantity: Int,
    sku: Option(String),
    requires_shipping: Bool,
    /// Absent when the variant was deleted or the item is a custom sale.
    variant: Option(LineItemVariant),
    original_unit_price: Money,
    /// Each share of a discount on the line. A discount code is allocated
    /// here, never in `total_discount`.
    discount_allocations: List(DiscountAllocation),
    /// Only a discount set through a draft order, a script or the API.
    total_discount: Money,
  )
}

/// The part of one discount, such as a discount code, that falls on a line
/// item.
pub type DiscountAllocation {
  DiscountAllocation(allocated_amount: Money)
}

pub type LineItemVariant {
  LineItemVariant(id: String, sku: Option(String), barcode: Option(String))
}

pub type ShippingLine {
  ShippingLine(
    title: String,
    code: Option(String),
    source: Option(String),
    original_price: Money,
  )
}

pub type FinancialStatus {
  FinancialStatusPaid
  FinancialStatusPending
  FinancialStatusAuthorized
  FinancialStatusPartiallyPaid
  FinancialStatusPartiallyRefunded
  FinancialStatusRefunded
  FinancialStatusVoided
  FinancialStatusExpired
  FinancialStatusOther(raw: String)
}

pub type FulfillmentStatus {
  FulfillmentStatusFulfilled
  FulfillmentStatusUnfulfilled
  FulfillmentStatusPartiallyFulfilled
  FulfillmentStatusInProgress
  FulfillmentStatusOnHold
  FulfillmentStatusOpen
  FulfillmentStatusPendingFulfillment
  FulfillmentStatusRestocked
  FulfillmentStatusScheduled
  FulfillmentStatusRequestDeclined
  /// No unit is left to fulfil, such as after every line was removed. Sent
  /// from 2026-10; earlier versions say `UNFULFILLED`.
  FulfillmentStatusNotRequired
  FulfillmentStatusOther(raw: String)
}

pub type CancelReason {
  CancelReasonCustomer
  CancelReasonDeclined
  CancelReasonFraud
  CancelReasonInventory
  CancelReasonStaff
  /// Shopify's own `OTHER`.
  CancelReasonOther
  /// A value this library does not know.
  CancelReasonUnknown(raw: String)
}

pub type ListParams {
  ListParams(
    /// Orders per page. `list` lowers it to `max_list_first()`.
    first: Int,
    after: Option(String),
    /// An ISO 8601 UTC timestamp. Only orders updated at or after it.
    updated_at_min: Option(String),
  )
}

pub type OrderPage {
  OrderPage(
    orders: List(Order),
    next_cursor: Option(String),
    has_next_page: Bool,
  )
}

const max_query_cost = 1000

const list_line_items = 10

const get_line_items = 90

const get_refunds = 4

const get_refund_lines = 15

/// The requested cost of an order with `line_items` lines: 53 points for the
/// order, plus 9 per line, whose discount allocations count as one node.
pub fn order_cost(line_items: Int) -> Int {
  53 + 9 * line_items
}

/// The largest page `list` asks for without passing the cost limit.
pub fn max_list_first() -> Int {
  { max_query_cost - 3 } / order_cost(list_line_items)
}

pub fn list(
  client: Client,
  params: ListParams,
) -> Effect(Result(OrderPage, ShopifyError), key) {
  request.graphql(client, list_query(), list_variables(params))
  |> execute.run(page_decoder())
}

/// `None` when no order has this id, for example after `orders/delete`.
pub fn get(
  client: Client,
  id: String,
) -> Effect(Result(Option(Order), ShopifyError), key) {
  request.graphql(client, get_query(), get_variables(id))
  |> execute.run(get_decoder())
}

/// The newest orders a gateway read looks at. Each node is one point, so the
/// read costs about a tenth of the limit.
const gateway_orders = 100

/// The gateway names on the shop's newest orders, each once, in the order
/// first seen. A read of scalars only: no customer data leaves Shopify.
pub fn recent_gateway_names(
  client: Client,
) -> Effect(Result(List(String), ShopifyError), key) {
  request.graphql(client, gateway_names_query(), gateway_names_variables())
  |> execute.run(gateway_names_decoder())
}

pub fn gateway_names_query() -> String {
  "query OrderGateways($first: Int!) {"
  <> " orders(first: $first, sortKey: CREATED_AT, reverse: true) {"
  <> " nodes { paymentGatewayNames } } }"
}

pub fn gateway_names_variables() -> Json {
  json.object([#("first", json.int(gateway_orders))])
}

pub fn gateway_names_decoder() -> decode.Decoder(List(String)) {
  use names <- decode.subfield(
    ["orders", "nodes"],
    decode.list(decode.field(
      "paymentGatewayNames",
      decode.list(decode.string),
      decode.success,
    )),
  )
  decode.success(list.unique(list.flatten(names)))
}

/// The shipping line titles on the shop's newest orders, each once, in the
/// order first seen. A read of scalars only: no customer data leaves Shopify.
pub fn recent_shipping_titles(
  client: Client,
) -> Effect(Result(List(String), ShopifyError), key) {
  request.graphql(client, shipping_titles_query(), gateway_names_variables())
  |> execute.run(shipping_titles_decoder())
}

pub fn shipping_titles_query() -> String {
  "query OrderShippingTitles($first: Int!) {"
  <> " orders(first: $first, sortKey: CREATED_AT, reverse: true) {"
  <> " nodes { shippingLines(first: 5) { nodes { title } } } } }"
}

pub fn shipping_titles_decoder() -> decode.Decoder(List(String)) {
  let titles =
    decode.subfield(
      ["shippingLines", "nodes"],
      decode.list(decode.field("title", decode.string, decode.success)),
      decode.success,
    )
  use found <- decode.subfield(["orders", "nodes"], decode.list(titles))
  decode.success(list.unique(list.flatten(found)))
}

/// The scope that lets an app change an order, its shipping address
/// included. It grants `read_orders` too.
pub const write_scope = "write_orders"

/// What a shipping address write reads first: whether the order still
/// ships, and the address it holds now.
pub type ShippingState {
  ShippingState(
    id: String,
    fulfillment_status: FulfillmentStatus,
    cancelled_at: Option(String),
    /// `None` when the order has no shipping address.
    shipping_address: Option(Address),
  )
}

/// A new shipping address for an order. Shopify overwrites the order's
/// address with it, so every field is sent and a `None` sends null.
pub type MailingAddressInput {
  MailingAddressInput(
    first_name: Option(String),
    last_name: Option(String),
    address1: String,
    address2: Option(String),
    city: Option(String),
    /// The region code, such as `SP`.
    province_code: Option(String),
    zip: String,
    /// The two-letter country code, such as `BR`.
    country_code: String,
    /// E.164, such as `+5511900000000`.
    phone: Option(String),
  )
}

/// `None` when no order has this id, for example after `orders/delete`. A
/// read of a few scalars and one address.
pub fn shipping_state(
  client: Client,
  id: String,
) -> Effect(Result(Option(ShippingState), ShopifyError), key) {
  request.graphql(
    client,
    shipping_state_query(),
    json.object([#("id", json.string(id))]),
  )
  |> execute.run(shipping_state_decoder())
}

pub fn shipping_state_query() -> String {
  "query OrderShippingState($id: ID!) { order(id: $id) {"
  <> " id displayFulfillmentStatus cancelledAt"
  <> " shippingAddress { ...Address } } }"
  <> address_fragment
}

pub fn shipping_state_decoder() -> decode.Decoder(Option(ShippingState)) {
  use state <- graphql.optional("order", {
    use id <- decode.field("id", decode.string)
    use fulfillment_status <- decode.field(
      "displayFulfillmentStatus",
      decode.string |> decode.map(parse_fulfillment_status),
    )
    use cancelled_at <- graphql.optional("cancelledAt", decode.string)
    use shipping_address <- graphql.optional(
      "shippingAddress",
      address_decoder(),
    )
    decode.success(ShippingState(
      id:,
      fulfillment_status:,
      cancelled_at:,
      shipping_address:,
    ))
  })
  decode.success(state)
}

/// From this version a new shipping address on an unfulfilled order makes
/// Shopify recalculate its taxes and totals. Read the order again after it.
pub const taxes_recalculated_since = api_version.v2026_10

/// Overwrite the shipping address of one order through `orderUpdate`.
/// Answers the order id. Needs `write_scope`.
pub fn update_shipping_address(
  client: Client,
  order_id: String,
  address: MailingAddressInput,
) -> Effect(Result(String, ShopifyError), key) {
  request.graphql(
    client,
    update_shipping_address_mutation,
    update_shipping_address_variables(order_id, address),
  )
  |> execute.run_mutation(
    "orderUpdate",
    decode.field(
      "order",
      decode.field("id", decode.string, decode.success),
      decode.success,
    ),
  )
}

pub const update_shipping_address_mutation =
  "mutation OrderUpdate($input: OrderInput!) {"
  <> " orderUpdate(input: $input) {"
  <> " order { id }"
  <> " userErrors { field message } } }"

pub fn update_shipping_address_variables(
  order_id: String,
  address: MailingAddressInput,
) -> Json {
  json.object([
    #(
      "input",
      json.object([
        #("id", json.string(order_id)),
        #("shippingAddress", mailing_address_input(address)),
      ]),
    ),
  ])
}

/// Whether the order's address already holds every field the input writes.
pub fn holds_address(current: Address, input: MailingAddressInput) -> Bool {
  current.first_name == input.first_name
  && current.last_name == input.last_name
  && current.address1 == option.Some(input.address1)
  && current.address2 == input.address2
  && current.city == input.city
  && current.province_code == input.province_code
  && current.zip == option.Some(input.zip)
  && current.country_code_v2 == option.Some(input.country_code)
  && current.phone == input.phone
}

fn mailing_address_input(address: MailingAddressInput) -> Json {
  json.object([
    #("firstName", json.nullable(address.first_name, json.string)),
    #("lastName", json.nullable(address.last_name, json.string)),
    #("address1", json.string(address.address1)),
    #("address2", json.nullable(address.address2, json.string)),
    #("city", json.nullable(address.city, json.string)),
    #("provinceCode", json.nullable(address.province_code, json.string)),
    #("zip", json.string(address.zip)),
    #("countryCode", json.string(address.country_code)),
    #("phone", json.nullable(address.phone, json.string)),
  ])
}

/// What `cancel` does to the stock the order holds in Shopify.
pub type CancelRestock {
  /// Shopify keeps its stock as it is. An app that owns the stock pushes it.
  CancelRestockNone
  /// Shopify puts the order's committed units back on sale.
  CancelRestockCommitted
}

/// What `cancel` gives back to the buyer. Shopify voids an authorized
/// payment in either case.
pub type CancelRefund {
  CancelRefundNone
  /// Shopify refunds the captured payment to the payment methods it came from.
  CancelRefundOriginalPayment
}

/// Whether Shopify e-mails the buyer about the cancel.
pub type CancelNotice {
  CancelNoticeNone
  CancelNoticeEmail
}

pub type CancelInput {
  CancelInput(
    order_id: String,
    reason: CancelReason,
    restock: CancelRestock,
    refund: CancelRefund,
    notice: CancelNotice,
    /// Seen by staff only. Shopify takes up to `staff_note_max` characters,
    /// so a longer note is cut.
    staff_note: Option(String),
  )
}

/// The job that cancels the order. Shopify cancels in the background, so
/// `done` is often false in the answer.
pub type CancelJob {
  CancelJob(id: String, done: Bool)
}

/// The longest `staffNote` Shopify takes.
pub const staff_note_max = 255

/// Shopify counts the note in characters, so the cut counts code points, not
/// graphemes: a combining mark is one character more.
fn cut_staff_note(note: String) -> String {
  string.to_utf_codepoints(note)
  |> list.take(staff_note_max)
  |> string.from_utf_codepoints
}

/// Cancel one order through `orderCancel`. Shopify refuses an order that is
/// cancelled already, that has a pending payment authorization or a return
/// in progress, or whose fulfillments cannot be cancelled: the refusal is a
/// `ShopifyErrorUserErrors`. `None` when Shopify answers no job. Needs
/// `write_scope`.
pub fn cancel(
  client: Client,
  input: CancelInput,
) -> Effect(Result(Option(CancelJob), ShopifyError), key) {
  request.graphql(client, cancel_mutation, cancel_variables(input))
  |> execute.run_mutation("orderCancel", cancel_decoder())
}

/// The alias reads `orderCancelUserErrors` as `userErrors`, the field
/// `execute.run_mutation` checks. The `userErrors` field of this payload is
/// deprecated.
pub const cancel_mutation =
  "mutation OrderCancel($orderId: ID!, $reason: OrderCancelReason!,"
  <> " $restock: Boolean!, $notifyCustomer: Boolean, $staffNote: String,"
  <> " $refundMethod: OrderCancelRefundMethodInput) {"
  <> " orderCancel(orderId: $orderId, reason: $reason, restock: $restock,"
  <> " notifyCustomer: $notifyCustomer, staffNote: $staffNote,"
  <> " refundMethod: $refundMethod) {"
  <> " job { id done }"
  <> " userErrors: orderCancelUserErrors { field message code } } }"

pub fn cancel_variables(input: CancelInput) -> Json {
  json.object([
    #("orderId", json.string(input.order_id)),
    #("reason", json.string(cancel_reason_to_string(input.reason))),
    #("restock", json.bool(input.restock == CancelRestockCommitted)),
    #("notifyCustomer", json.bool(input.notice == CancelNoticeEmail)),
    #(
      "staffNote",
      json.nullable(option.map(input.staff_note, cut_staff_note), json.string),
    ),
    #("refundMethod", case input.refund {
      CancelRefundNone -> json.null()
      CancelRefundOriginalPayment ->
        json.object([#("originalPaymentMethodsRefund", json.bool(True))])
    }),
  ])
}

pub fn cancel_decoder() -> decode.Decoder(Option(CancelJob)) {
  use job <- graphql.optional("job", job_decoder())
  decode.success(job)
}

/// Whether the background Job of a cancel is done. `None` when Shopify
/// knows no Job with this id.
pub fn cancel_job(
  client: Client,
  id: String,
) -> Effect(Result(Option(CancelJob), ShopifyError), key) {
  request.graphql(
    client,
    cancel_job_query,
    json.object([#("id", json.string(id))]),
  )
  |> execute.run(cancel_decoder())
}

pub const cancel_job_query =
  "query CancelJob($id: ID!) { job(id: $id) { id done } }"

fn job_decoder() -> decode.Decoder(CancelJob) {
  use id <- decode.field("id", decode.string)
  use done <- decode.field("done", decode.bool)
  decode.success(CancelJob(id:, done:))
}

pub fn list_query() -> String {
  "query OrderList($first: Int!, $after: String, $query: String, $lineItems: Int!) {"
  <> " orders(first: $first, after: $after, query: $query, sortKey: UPDATED_AT) {"
  <> " nodes { ...OrderFields } pageInfo { hasNextPage endCursor } } }"
  <> fragments
}

pub fn list_variables(params: ListParams) -> Json {
  json.object([
    #("first", json.int(int.clamp(params.first, 1, max_list_first()))),
    #("after", json.nullable(params.after, json.string)),
    #("query", json.nullable(search_query(params), json.string)),
    #("lineItems", json.int(list_line_items)),
  ])
}

/// The search expression for `ListParams`. `None` lists every order the
/// token can read.
pub fn search_query(params: ListParams) -> Option(String) {
  option.map(params.updated_at_min, fn(timestamp) {
    "updated_at:>=" <> graphql.search_value(timestamp)
  })
}

pub fn get_query() -> String {
  "query OrderGet($id: ID!, $lineItems: Int!) {"
  <> " order(id: $id) { ...OrderFields"
  <> " refunds(first: "
  <> int.to_string(get_refunds)
  <> ") { refundLineItems(first: "
  <> int.to_string(get_refund_lines)
  <> ") { nodes { lineItem { id } quantity restockType }"
  <> " pageInfo { hasNextPage } } } } }"
  <> fragments
}

pub fn get_variables(id: String) -> Json {
  json.object([
    #("id", json.string(id)),
    #("lineItems", json.int(get_line_items)),
  ])
}

pub fn page_decoder() -> decode.Decoder(OrderPage) {
  use connection <- decode.field(
    "orders",
    graphql.connection_decoder(decoder()),
  )
  decode.success(OrderPage(
    orders: connection.nodes,
    next_cursor: connection.page_info.end_cursor,
    has_next_page: connection.page_info.has_next_page,
  ))
}

pub fn get_decoder() -> decode.Decoder(Option(Order)) {
  use order <- graphql.optional("order", decoder())
  decode.success(order)
}

const fragments =
  " fragment OrderFields on Order {"
  <> " id legacyResourceId name createdAt updatedAt processedAt"
  <> " cancelledAt cancelReason closedAt test currencyCode taxesIncluded"
  <> " paymentGatewayNames"
  <> " displayFinancialStatus displayFulfillmentStatus note email phone"
  <> " currentSubtotalPriceSet { ...ShopMoney }"
  <> " currentShippingPriceSet { ...ShopMoney }"
  <> " currentTotalTaxSet { ...ShopMoney }"
  <> " currentTotalDiscountsSet { ...ShopMoney }"
  <> " currentTotalPriceSet { ...ShopMoney }"
  <> " subtotalPriceSet { ...ShopMoney }"
  <> " totalShippingPriceSet { ...ShopMoney }"
  <> " totalTaxSet { ...ShopMoney }"
  <> " totalDiscountsSet { ...ShopMoney }"
  <> " totalPriceSet { ...ShopMoney }"
  <> " customer { id firstName lastName displayName"
  <> " defaultEmailAddress { emailAddress } defaultPhoneNumber { phoneNumber } }"
  <> " shippingAddress { ...Address } billingAddress { ...Address }"
  <> " localizedFields(first: 5) { nodes { key value countryCode purpose title } }"
  <> " lineItems(first: $lineItems) { nodes {"
  <> " id title name quantity currentQuantity sku requiresShipping"
  <> " variant { id sku barcode }"
  <> " originalUnitPriceSet { ...ShopMoney }"
  <> " discountAllocations { allocatedAmountSet { ...ShopMoney } }"
  <> " totalDiscountSet { ...ShopMoney } }"
  <> " pageInfo { hasNextPage } }"
  <> " shippingLines(first: 5) { nodes {"
  <> " title code source originalPriceSet { ...ShopMoney } } } }"
  <> " fragment ShopMoney on MoneyBag { shopMoney { amount currencyCode } }"
  <> address_fragment

const address_fragment =
  " fragment Address on MailingAddress {"
  <> " name firstName lastName company address1 address2 city province"
  <> " provinceCode zip country countryCodeV2 phone }"

pub fn decoder() -> decode.Decoder(Order) {
  use id <- decode.field("id", decode.string)
  use legacy_resource_id <- decode.field(
    "legacyResourceId",
    decode.one_of(decode.string, [decode.int |> decode.map(int.to_string)]),
  )
  use name <- decode.field("name", decode.string)
  use created_at <- decode.field("createdAt", decode.string)
  use updated_at <- decode.field("updatedAt", decode.string)
  use processed_at <- decode.field("processedAt", decode.string)
  use cancelled_at <- graphql.optional("cancelledAt", decode.string)
  use cancel_reason <- graphql.optional("cancelReason", cancel_reason_decoder())
  use closed_at <- graphql.optional("closedAt", decode.string)
  use is_test <- decode.field("test", decode.bool)
  use currency_code <- decode.field("currencyCode", decode.string)
  use tax_pricing <- decode.field("taxesIncluded", tax_pricing_decoder())
  use payment_gateway_names <- decode.field(
    "paymentGatewayNames",
    decode.list(decode.string),
  )
  use financial_status <- graphql.optional(
    "displayFinancialStatus",
    decode.string |> decode.map(parse_financial_status),
  )
  use fulfillment_status <- decode.field(
    "displayFulfillmentStatus",
    decode.string |> decode.map(parse_fulfillment_status),
  )
  use note <- graphql.optional("note", decode.string)
  use email <- graphql.optional("email", decode.string)
  use phone <- graphql.optional("phone", decode.string)
  use current_totals <- decode.then(current_totals_decoder())
  use original_totals <- decode.then(original_totals_decoder())
  use customer <- graphql.optional("customer", customer_decoder())
  use shipping_address <- graphql.optional("shippingAddress", address_decoder())
  use billing_address <- graphql.optional("billingAddress", address_decoder())
  use localized_fields <- decode.field(
    "localizedFields",
    graphql.nodes_decoder(localized_field_decoder()),
  )
  use line_items <- decode.field("lineItems", line_items_decoder())
  use shipping_lines <- decode.field("shippingLines", shipping_lines_decoder())
  use refunds <- decode.optional_field(
    "refunds",
    RefundLinesUnread,
    refunds_decoder(),
  )
  decode.success(Order(
    id:,
    legacy_resource_id:,
    name:,
    created_at:,
    updated_at:,
    processed_at:,
    cancelled_at:,
    cancel_reason:,
    closed_at:,
    is_test:,
    currency_code:,
    tax_pricing:,
    payment_gateway_names:,
    financial_status:,
    fulfillment_status:,
    note:,
    email:,
    phone:,
    current_totals:,
    original_totals:,
    customer:,
    shipping_address:,
    billing_address:,
    localized_fields:,
    line_items: line_items.nodes,
    has_more_line_items: line_items.page_info.has_next_page,
    shipping_lines:,
    refunds:,
  ))
}

fn cancel_reason_decoder() -> decode.Decoder(CancelReason) {
  decode.string |> decode.map(parse_cancel_reason)
}

fn tax_pricing_decoder() -> decode.Decoder(TaxPricing) {
  decode.bool |> decode.map(tax_pricing_from_bool)
}

fn line_items_decoder() -> decode.Decoder(graphql.Connection(LineItem)) {
  graphql.connection_decoder(line_item_decoder())
}

fn shipping_lines_decoder() -> decode.Decoder(List(ShippingLine)) {
  graphql.nodes_decoder(shipping_line_decoder())
}

/// `taxesIncluded` as a `TaxPricing`, on an order or on the shop.
pub fn tax_pricing_from_bool(included: Bool) -> TaxPricing {
  case included {
    True -> TaxesIncluded
    False -> TaxesAdded
  }
}

/// A full page of refunds, or a refund with more lines, is truncated.
fn refunds_decoder() -> decode.Decoder(RefundLines) {
  use refunds <- decode.then(
    decode.list(decode.field(
      "refundLineItems",
      graphql.connection_decoder(refund_line_decoder()),
      decode.success,
    )),
  )
  let lines = list.flat_map(refunds, fn(refund) { refund.nodes })
  let truncated =
    list.length(refunds) >= get_refunds
    || list.any(refunds, fn(refund) { refund.page_info.has_next_page })
  case truncated {
    True -> decode.success(RefundLinesTruncated(lines:))
    False -> decode.success(RefundLinesRead(lines:))
  }
}

fn refund_line_decoder() -> decode.Decoder(RefundLine) {
  use line_item_id <- decode.subfield(["lineItem", "id"], decode.string)
  use quantity <- decode.field("quantity", decode.int)
  use restock <- decode.field(
    "restockType",
    decode.string |> decode.map(parse_restock_type),
  )
  decode.success(RefundLine(line_item_id:, quantity:, restock:))
}

pub fn parse_restock_type(raw: String) -> RestockType {
  list.find(
    [
      RestockTypeNoRestock,
      RestockTypeCancel,
      RestockTypeReturn,
      RestockTypeLegacyRestock,
    ],
    fn(restock) { restock_type_to_string(restock) == raw },
  )
  |> result.unwrap(RestockTypeOther(raw))
}

pub fn restock_type_to_string(restock: RestockType) -> String {
  case restock {
    RestockTypeNoRestock -> "NO_RESTOCK"
    RestockTypeCancel -> "CANCEL"
    RestockTypeReturn -> "RETURN"
    RestockTypeLegacyRestock -> "LEGACY_RESTOCK"
    RestockTypeOther(raw) -> raw
  }
}

pub fn parse_financial_status(raw: String) -> FinancialStatus {
  list.find(
    [
      FinancialStatusPaid,
      FinancialStatusPending,
      FinancialStatusAuthorized,
      FinancialStatusPartiallyPaid,
      FinancialStatusPartiallyRefunded,
      FinancialStatusRefunded,
      FinancialStatusVoided,
      FinancialStatusExpired,
    ],
    fn(status) { financial_status_to_string(status) == raw },
  )
  |> result.unwrap(FinancialStatusOther(raw))
}

pub fn financial_status_to_string(status: FinancialStatus) -> String {
  case status {
    FinancialStatusPaid -> "PAID"
    FinancialStatusPending -> "PENDING"
    FinancialStatusAuthorized -> "AUTHORIZED"
    FinancialStatusPartiallyPaid -> "PARTIALLY_PAID"
    FinancialStatusPartiallyRefunded -> "PARTIALLY_REFUNDED"
    FinancialStatusRefunded -> "REFUNDED"
    FinancialStatusVoided -> "VOIDED"
    FinancialStatusExpired -> "EXPIRED"
    FinancialStatusOther(raw) -> raw
  }
}

pub fn parse_fulfillment_status(raw: String) -> FulfillmentStatus {
  list.find(
    [
      FulfillmentStatusFulfilled,
      FulfillmentStatusUnfulfilled,
      FulfillmentStatusPartiallyFulfilled,
      FulfillmentStatusInProgress,
      FulfillmentStatusOnHold,
      FulfillmentStatusOpen,
      FulfillmentStatusPendingFulfillment,
      FulfillmentStatusRestocked,
      FulfillmentStatusScheduled,
      FulfillmentStatusRequestDeclined,
      FulfillmentStatusNotRequired,
    ],
    fn(status) { fulfillment_status_to_string(status) == raw },
  )
  |> result.unwrap(FulfillmentStatusOther(raw))
}

pub fn fulfillment_status_to_string(status: FulfillmentStatus) -> String {
  case status {
    FulfillmentStatusFulfilled -> "FULFILLED"
    FulfillmentStatusUnfulfilled -> "UNFULFILLED"
    FulfillmentStatusPartiallyFulfilled -> "PARTIALLY_FULFILLED"
    FulfillmentStatusInProgress -> "IN_PROGRESS"
    FulfillmentStatusOnHold -> "ON_HOLD"
    FulfillmentStatusOpen -> "OPEN"
    FulfillmentStatusPendingFulfillment -> "PENDING_FULFILLMENT"
    FulfillmentStatusRestocked -> "RESTOCKED"
    FulfillmentStatusScheduled -> "SCHEDULED"
    FulfillmentStatusRequestDeclined -> "REQUEST_DECLINED"
    FulfillmentStatusNotRequired -> "FULFILLMENT_NOT_REQUIRED"
    FulfillmentStatusOther(raw) -> raw
  }
}

pub fn parse_cancel_reason(raw: String) -> CancelReason {
  list.find(
    [
      CancelReasonCustomer,
      CancelReasonDeclined,
      CancelReasonFraud,
      CancelReasonInventory,
      CancelReasonStaff,
      CancelReasonOther,
    ],
    fn(reason) { cancel_reason_to_string(reason) == raw },
  )
  |> result.unwrap(CancelReasonUnknown(raw))
}

pub fn cancel_reason_to_string(reason: CancelReason) -> String {
  case reason {
    CancelReasonCustomer -> "CUSTOMER"
    CancelReasonDeclined -> "DECLINED"
    CancelReasonFraud -> "FRAUD"
    CancelReasonInventory -> "INVENTORY"
    CancelReasonStaff -> "STAFF"
    CancelReasonOther -> "OTHER"
    CancelReasonUnknown(raw) -> raw
  }
}

fn current_totals_decoder() -> decode.Decoder(CurrentTotals) {
  use subtotal <- decode.field("currentSubtotalPriceSet", shop_money_decoder())
  use shipping <- decode.field("currentShippingPriceSet", shop_money_decoder())
  use tax <- decode.field("currentTotalTaxSet", shop_money_decoder())
  use discounts <- decode.field(
    "currentTotalDiscountsSet",
    shop_money_decoder(),
  )
  use total <- decode.field("currentTotalPriceSet", shop_money_decoder())
  decode.success(CurrentTotals(subtotal:, shipping:, tax:, discounts:, total:))
}

fn original_totals_decoder() -> decode.Decoder(OriginalTotals) {
  use subtotal <- graphql.optional("subtotalPriceSet", shop_money_decoder())
  use shipping <- decode.field("totalShippingPriceSet", shop_money_decoder())
  use tax <- graphql.optional("totalTaxSet", shop_money_decoder())
  use discounts <- graphql.optional("totalDiscountsSet", shop_money_decoder())
  use total <- decode.field("totalPriceSet", shop_money_decoder())
  decode.success(OriginalTotals(subtotal:, shipping:, tax:, discounts:, total:))
}

/// A `MoneyBag` read through its `shopMoney`.
pub fn shop_money_decoder() -> decode.Decoder(Money) {
  decode.field("shopMoney", money.decoder(), decode.success)
}

fn customer_decoder() -> decode.Decoder(Customer) {
  use id <- decode.field("id", decode.string)
  use first_name <- graphql.optional("firstName", decode.string)
  use last_name <- graphql.optional("lastName", decode.string)
  use display_name <- decode.field("displayName", decode.string)
  use email <- graphql.optional("defaultEmailAddress", {
    use address <- graphql.optional("emailAddress", decode.string)
    decode.success(address)
  })
  use phone <- graphql.optional("defaultPhoneNumber", {
    use number <- graphql.optional("phoneNumber", decode.string)
    decode.success(number)
  })
  decode.success(Customer(
    id:,
    first_name:,
    last_name:,
    display_name:,
    email: option.flatten(email),
    phone: option.flatten(phone),
  ))
}

fn address_decoder() -> decode.Decoder(Address) {
  use name <- graphql.optional("name", decode.string)
  use first_name <- graphql.optional("firstName", decode.string)
  use last_name <- graphql.optional("lastName", decode.string)
  use company <- graphql.optional("company", decode.string)
  use address1 <- graphql.optional("address1", decode.string)
  use address2 <- graphql.optional("address2", decode.string)
  use city <- graphql.optional("city", decode.string)
  use province <- graphql.optional("province", decode.string)
  use province_code <- graphql.optional("provinceCode", decode.string)
  use zip <- graphql.optional("zip", decode.string)
  use country <- graphql.optional("country", decode.string)
  use country_code_v2 <- graphql.optional("countryCodeV2", decode.string)
  use phone <- graphql.optional("phone", decode.string)
  decode.success(Address(
    name:,
    first_name:,
    last_name:,
    company:,
    address1:,
    address2:,
    city:,
    province:,
    province_code:,
    zip:,
    country:,
    country_code_v2:,
    phone:,
  ))
}

fn localized_field_decoder() -> decode.Decoder(LocalizedField) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.string)
  use country_code <- decode.field("countryCode", decode.string)
  use purpose <- decode.field("purpose", decode.string)
  use title <- decode.field("title", decode.string)
  decode.success(LocalizedField(key:, value:, country_code:, purpose:, title:))
}

fn line_item_decoder() -> decode.Decoder(LineItem) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use name <- decode.field("name", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  use current_quantity <- decode.field("currentQuantity", decode.int)
  use sku <- graphql.optional("sku", decode.string)
  use requires_shipping <- decode.field("requiresShipping", decode.bool)
  use variant <- graphql.optional("variant", line_item_variant_decoder())
  use original_unit_price <- decode.field(
    "originalUnitPriceSet",
    shop_money_decoder(),
  )
  use discount_allocations <- decode.field(
    "discountAllocations",
    decode.list(discount_allocation_decoder()),
  )
  use total_discount <- decode.field("totalDiscountSet", shop_money_decoder())
  decode.success(LineItem(
    id:,
    title:,
    name:,
    quantity:,
    current_quantity:,
    sku:,
    requires_shipping:,
    variant:,
    original_unit_price:,
    discount_allocations:,
    total_discount:,
  ))
}

fn discount_allocation_decoder() -> decode.Decoder(DiscountAllocation) {
  use allocated_amount <- decode.field(
    "allocatedAmountSet",
    shop_money_decoder(),
  )
  decode.success(DiscountAllocation(allocated_amount:))
}

fn line_item_variant_decoder() -> decode.Decoder(LineItemVariant) {
  use id <- decode.field("id", decode.string)
  use sku <- graphql.optional("sku", decode.string)
  use barcode <- graphql.optional("barcode", decode.string)
  decode.success(LineItemVariant(id:, sku:, barcode:))
}

fn shipping_line_decoder() -> decode.Decoder(ShippingLine) {
  use title <- decode.field("title", decode.string)
  use code <- graphql.optional("code", decode.string)
  use source <- graphql.optional("source", decode.string)
  use original_price <- decode.field("originalPriceSet", shop_money_decoder())
  decode.success(ShippingLine(title:, code:, source:, original_price:))
}
