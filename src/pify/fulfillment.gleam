//// Fulfillments of an order: read the fulfillment orders and the
//// fulfillments already made, create a fulfillment with its tracking,
//// change the tracking of a fulfillment, cancel a fulfillment, and record
//// an event of a fulfillment, such as its delivery. A fulfillment order can
//// be released from its holds, reported in progress and marked open again.
////
//// Shopify splits an order into fulfillment orders, one per location that
//// ships it. A fulfillment takes units from the open fulfillment orders of
//// one location. `fulfillmentCreate` takes no idempotency key, so a caller
//// reads `for_order` before it creates, to find a fulfillment an earlier
//// call made.
////
//// Every call needs one of the `write_*_fulfillment_orders` scopes; a
//// merchant's own locations need `write_merchant_managed_fulfillment_orders`.
//// `create_event` needs `write_fulfillments` as well. `release_hold`,
//// `report_progress` and `open` need only the first.

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify.{type Client}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request

/// The scope that lets an app fulfil the orders of the merchant's own
/// locations. It grants the read scope too.
pub const merchant_managed_scope = "write_merchant_managed_fulfillment_orders"

/// The scope that lets an app record the events of a fulfillment.
pub const events_scope = "write_fulfillments"

/// What an order holds to fulfil and what it already shipped.
pub type OrderFulfillments {
  OrderFulfillments(
    fulfillment_orders: List(FulfillmentOrder),
    fulfillments: List(Fulfillment),
    /// Whether the read holds every fulfillment order, line and fulfillment.
    read: Read,
  )
}

pub type Read {
  ReadComplete
  /// The order has more fulfillment orders, lines or fulfillments than one
  /// read returns.
  ReadTruncated
}

pub type FulfillmentOrder {
  FulfillmentOrder(
    id: String,
    status: FulfillmentOrderStatus,
    /// The location that ships it. `None` when the location is gone.
    location_id: Option(String),
    /// The holds on it (`fulfillmentHolds`).
    holds: List(FulfillmentHold),
    /// What Shopify lets the app do with it now (`supportedActions`).
    supported_actions: List(FulfillmentOrderAction),
    line_items: List(FulfillmentOrderLineItem),
  )
}

pub type FulfillmentHold {
  FulfillmentHold(id: String, reason: FulfillmentHoldReason)
}

/// Why a fulfillment order is on hold.
pub type FulfillmentHoldReason {
  FulfillmentHoldReasonAwaitingPayment
  FulfillmentHoldReasonAwaitingReturnItems
  FulfillmentHoldReasonHighRiskOfFraud
  FulfillmentHoldReasonIncorrectAddress
  FulfillmentHoldReasonInventoryOutOfStock
  FulfillmentHoldReasonOnlineStorePostPurchaseCrossSell
  /// Shopify's `OTHER`, such as a hold the merchant placed by hand.
  FulfillmentHoldReasonOther
  FulfillmentHoldReasonUnknownDeliveryDate
  /// A value this library does not know.
  FulfillmentHoldReasonUnknown(raw: String)
}

/// An action Shopify supports on a fulfillment order.
pub type FulfillmentOrderAction {
  FulfillmentOrderActionCancelFulfillmentOrder
  FulfillmentOrderActionCreateFulfillment
  FulfillmentOrderActionExternal
  FulfillmentOrderActionHold
  FulfillmentOrderActionMarkAsOpen
  FulfillmentOrderActionMerge
  FulfillmentOrderActionMove
  FulfillmentOrderActionReleaseHold
  FulfillmentOrderActionReportProgress
  FulfillmentOrderActionRequestCancellation
  FulfillmentOrderActionRequestFulfillment
  FulfillmentOrderActionSplit
  /// A value this library does not know.
  FulfillmentOrderActionOther(raw: String)
}

pub type FulfillmentOrderStatus {
  FulfillmentOrderStatusOpen
  FulfillmentOrderStatusInProgress
  FulfillmentOrderStatusScheduled
  FulfillmentOrderStatusOnHold
  FulfillmentOrderStatusClosed
  FulfillmentOrderStatusCancelled
  FulfillmentOrderStatusIncomplete
  /// A value this library does not know.
  FulfillmentOrderStatusOther(raw: String)
}

pub type FulfillmentOrderLineItem {
  FulfillmentOrderLineItem(
    id: String,
    /// The order line item it fulfils.
    line_item_id: String,
    sku: Option(String),
    /// The units still to fulfil.
    remaining_quantity: Int,
  )
}

pub type Fulfillment {
  Fulfillment(
    id: String,
    status: FulfillmentStatus,
    /// The state the admin shows, which the latest event sets. `None` when
    /// Shopify sends none.
    display_status: Option(FulfillmentDisplayStatus),
    tracking_numbers: List(String),
    line_items: List(FulfillmentLineItem),
  )
}

pub type FulfillmentStatus {
  FulfillmentStatusSuccess
  FulfillmentStatusCancelled
  FulfillmentStatusFailure
  FulfillmentStatusPending
  FulfillmentStatusOpen
  FulfillmentStatusError
  /// A value this library does not know.
  FulfillmentStatusOther(raw: String)
}

pub type FulfillmentDisplayStatus {
  FulfillmentDisplayStatusAttemptedDelivery
  FulfillmentDisplayStatusCanceled
  FulfillmentDisplayStatusCarrierPickedUp
  FulfillmentDisplayStatusConfirmed
  FulfillmentDisplayStatusDelayed
  FulfillmentDisplayStatusDelivered
  FulfillmentDisplayStatusFailure
  FulfillmentDisplayStatusFulfilled
  FulfillmentDisplayStatusInTransit
  FulfillmentDisplayStatusLabelPrinted
  FulfillmentDisplayStatusLabelPurchased
  FulfillmentDisplayStatusLabelVoided
  FulfillmentDisplayStatusMarkedAsFulfilled
  FulfillmentDisplayStatusNotDelivered
  FulfillmentDisplayStatusOutForDelivery
  FulfillmentDisplayStatusPickedUp
  FulfillmentDisplayStatusReadyForPickup
  FulfillmentDisplayStatusSubmitted
  /// A value this library does not know.
  FulfillmentDisplayStatusOther(raw: String)
}

/// What an event of a fulfillment records.
pub type FulfillmentEventStatus {
  FulfillmentEventStatusAttemptedDelivery
  FulfillmentEventStatusCarrierPickedUp
  FulfillmentEventStatusConfirmed
  FulfillmentEventStatusDelayed
  FulfillmentEventStatusDelivered
  FulfillmentEventStatusFailure
  FulfillmentEventStatusInTransit
  FulfillmentEventStatusLabelPrinted
  FulfillmentEventStatusLabelPurchased
  FulfillmentEventStatusOutForDelivery
  FulfillmentEventStatusReadyForPickup
}

pub type FulfillmentLineItem {
  FulfillmentLineItem(line_item_id: String, sku: Option(String), quantity: Int)
}

/// The units of one fulfillment order a fulfillment takes.
pub type FulfillmentOrderLines {
  FulfillmentOrderLines(
    fulfillment_order_id: String,
    line_items: List(LineQuantity),
  )
}

/// Units of one fulfillment order line item.
pub type LineQuantity {
  LineQuantity(fulfillment_order_line_item_id: String, quantity: Int)
}

pub type Tracking {
  Tracking(number: String, company: Option(String), url: Option(String))
}

/// Whether Shopify e-mails the buyer about the fulfillment.
pub type Notice {
  NoticeNotifyCustomer
  NoticeSilent
}

/// A fulfillment as Shopify stored it after a write.
pub type Written {
  Written(id: String, status: FulfillmentStatus)
}

/// A fulfillment order as Shopify stored it after a write.
pub type FulfillmentOrderWritten {
  FulfillmentOrderWritten(
    id: String,
    status: FulfillmentOrderStatus,
    supported_actions: List(FulfillmentOrderAction),
  )
}

/// Fulfillment orders per read. Each costs its line items.
pub const fulfillment_orders_per_read = 5

/// Line items per fulfillment order read.
pub const line_items_per_fulfillment_order = 30

/// Fulfillments per read. `Order.fulfillments` is a list, not a connection:
/// a full list may hold more.
pub const fulfillments_per_read = 10

/// Lines per fulfillment read.
pub const line_items_per_fulfillment = 20

const tracking_per_fulfillment = 3

/// The order's fulfillment orders of any status and its fulfillments, in
/// one read under the 1000-point cap. `Ok(None)` when no order has the id.
pub fn for_order(
  client: Client,
  order_id: String,
) -> Effect(Result(Option(OrderFulfillments), ShopifyError), key) {
  request.graphql(client, for_order_query(), for_order_variables(order_id))
  |> execute.run(for_order_decoder())
}

pub fn for_order_query() -> String {
  "query OrderFulfillments($id: ID!) { order(id: $id) {"
  <> " fulfillmentOrders(first: "
  <> int.to_string(fulfillment_orders_per_read)
  <> ") { nodes { id status assignedLocation { location { id } }"
  <> " fulfillmentHolds { id reason } supportedActions { action }"
  <> " lineItems(first: "
  <> int.to_string(line_items_per_fulfillment_order)
  <> ") { nodes { id sku remainingQuantity lineItem { id } }"
  <> " pageInfo { hasNextPage } } }"
  <> " pageInfo { hasNextPage } }"
  <> " fulfillments(first: "
  <> int.to_string(fulfillments_per_read)
  <> ") { id status displayStatus trackingInfo(first: "
  <> int.to_string(tracking_per_fulfillment)
  <> ") { number }"
  <> " fulfillmentLineItems(first: "
  <> int.to_string(line_items_per_fulfillment)
  <> ") { nodes { quantity lineItem { id sku } }"
  <> " pageInfo { hasNextPage } } } } }"
}

pub fn for_order_variables(order_id: String) -> Json {
  json.object([#("id", json.string(order_id))])
}

/// Create one fulfillment over fulfillment orders of one location.
pub fn create(
  client: Client,
  lines: List(FulfillmentOrderLines),
  tracking: Option(Tracking),
  notice: Notice,
) -> Effect(Result(Written, ShopifyError), key) {
  request.graphql(
    client,
    create_mutation,
    create_variables(lines, tracking, notice),
  )
  |> execute.run_mutation(
    "fulfillmentCreate",
    decode.field("fulfillment", written_decoder(), decode.success),
  )
}

pub const create_mutation =
  "mutation FulfillmentCreate($fulfillment: FulfillmentInput!) {"
  <> " fulfillmentCreate(fulfillment: $fulfillment) {"
  <> " fulfillment { id status }"
  <> " userErrors { field message } } }"

pub fn create_variables(
  lines: List(FulfillmentOrderLines),
  tracking: Option(Tracking),
  notice: Notice,
) -> Json {
  let tracking_field = case tracking {
    option.Some(info) -> [#("trackingInfo", tracking_input(info))]
    option.None -> []
  }
  json.object([
    #(
      "fulfillment",
      json.object([
        #("lineItemsByFulfillmentOrder", json.array(lines, lines_input)),
        #("notifyCustomer", json.bool(notifies(notice))),
        ..tracking_field
      ]),
    ),
  ])
}

/// Replace the tracking of a fulfillment.
pub fn update_tracking(
  client: Client,
  fulfillment_id: String,
  tracking: Tracking,
  notice: Notice,
) -> Effect(Result(Written, ShopifyError), key) {
  request.graphql(
    client,
    update_tracking_mutation,
    update_tracking_variables(fulfillment_id, tracking, notice),
  )
  |> execute.run_mutation(
    "fulfillmentTrackingInfoUpdate",
    decode.field("fulfillment", written_decoder(), decode.success),
  )
}

pub const update_tracking_mutation =
  "mutation FulfillmentTrackingInfoUpdate("
  <> "$fulfillmentId: ID!, $trackingInfoInput: FulfillmentTrackingInput!,"
  <> " $notifyCustomer: Boolean) {"
  <> " fulfillmentTrackingInfoUpdate(fulfillmentId: $fulfillmentId,"
  <> " trackingInfoInput: $trackingInfoInput, notifyCustomer: $notifyCustomer) {"
  <> " fulfillment { id status }"
  <> " userErrors { field message } } }"

pub fn update_tracking_variables(
  fulfillment_id: String,
  tracking: Tracking,
  notice: Notice,
) -> Json {
  json.object([
    #("fulfillmentId", json.string(fulfillment_id)),
    #("trackingInfoInput", tracking_input(tracking)),
    #("notifyCustomer", json.bool(notifies(notice))),
  ])
}

/// Cancel a fulfillment. Shopify gives its units back to fulfillment orders,
/// so they can be fulfilled again.
pub fn cancel(
  client: Client,
  fulfillment_id: String,
) -> Effect(Result(Written, ShopifyError), key) {
  request.graphql(client, cancel_mutation, cancel_variables(fulfillment_id))
  |> execute.run_mutation(
    "fulfillmentCancel",
    decode.field("fulfillment", written_decoder(), decode.success),
  )
}

pub const cancel_mutation =
  "mutation FulfillmentCancel($id: ID!) {"
  <> " fulfillmentCancel(id: $id) {"
  <> " fulfillment { id status }"
  <> " userErrors { field message } } }"

pub fn cancel_variables(fulfillment_id: String) -> Json {
  json.object([#("id", json.string(fulfillment_id))])
}

/// Record an event of a fulfillment. `happened_at` is an ISO 8601 date and
/// time; without it Shopify takes the time of the call. Answers the event id.
pub fn create_event(
  client: Client,
  fulfillment_id: String,
  status: FulfillmentEventStatus,
  happened_at: Option(String),
) -> Effect(Result(String, ShopifyError), key) {
  request.graphql(
    client,
    create_event_mutation,
    create_event_variables(fulfillment_id, status, happened_at),
  )
  |> execute.run_mutation(
    "fulfillmentEventCreate",
    decode.field(
      "fulfillmentEvent",
      decode.field("id", decode.string, decode.success),
      decode.success,
    ),
  )
}

pub const create_event_mutation =
  "mutation FulfillmentEventCreate("
  <> "$fulfillmentEvent: FulfillmentEventInput!) {"
  <> " fulfillmentEventCreate(fulfillmentEvent: $fulfillmentEvent) {"
  <> " fulfillmentEvent { id }"
  <> " userErrors { field message } } }"

pub fn create_event_variables(
  fulfillment_id: String,
  status: FulfillmentEventStatus,
  happened_at: Option(String),
) -> Json {
  let happened_at_field = case happened_at {
    option.Some(text) -> [#("happenedAt", json.string(text))]
    option.None -> []
  }
  json.object([
    #(
      "fulfillmentEvent",
      json.object([
        #("fulfillmentId", json.string(fulfillment_id)),
        #("status", json.string(event_status_to_string(status))),
        ..happened_at_field
      ]),
    ),
  ])
}

/// Release holds of a fulfillment order. Shopify releases every hold when
/// `hold_ids` is empty, so a caller names the holds it read.
pub fn release_hold(
  client: Client,
  fulfillment_order_id: String,
  hold_ids: List(String),
) -> Effect(Result(FulfillmentOrderWritten, ShopifyError), key) {
  request.graphql(
    client,
    release_hold_mutation,
    release_hold_variables(fulfillment_order_id, hold_ids),
  )
  |> execute.run_mutation(
    "fulfillmentOrderReleaseHold",
    fulfillment_order_written_field(),
  )
}

pub const release_hold_mutation =
  "mutation FulfillmentOrderReleaseHold("
  <> "$id: ID!, $holdIds: [ID!]) {"
  <> " fulfillmentOrderReleaseHold(id: $id, holdIds: $holdIds) {"
  <> fulfillment_order_written_selection
  <> " userErrors { field message } } }"

pub fn release_hold_variables(
  fulfillment_order_id: String,
  hold_ids: List(String),
) -> Json {
  let holds_field = case hold_ids {
    [] -> []
    _ -> [#("holdIds", json.array(hold_ids, json.string))]
  }
  json.object([#("id", json.string(fulfillment_order_id)), ..holds_field])
}

/// Report that the merchant started on an open or in-progress fulfillment
/// order. An open one moves to `IN_PROGRESS`.
pub fn report_progress(
  client: Client,
  fulfillment_order_id: String,
) -> Effect(Result(FulfillmentOrderWritten, ShopifyError), key) {
  request.graphql(
    client,
    report_progress_mutation,
    fulfillment_order_variables(fulfillment_order_id),
  )
  |> execute.run_mutation(
    "fulfillmentOrderReportProgress",
    fulfillment_order_written_field(),
  )
}

pub const report_progress_mutation =
  "mutation FulfillmentOrderReportProgress("
  <> "$id: ID!) {"
  <> " fulfillmentOrderReportProgress(id: $id) {"
  <> fulfillment_order_written_selection
  <> " userErrors { field message } } }"

/// Mark a fulfillment order open: a scheduled one, or one of the
/// merchant's own locations that had progress reported.
pub fn open(
  client: Client,
  fulfillment_order_id: String,
) -> Effect(Result(FulfillmentOrderWritten, ShopifyError), key) {
  request.graphql(
    client,
    open_mutation,
    fulfillment_order_variables(fulfillment_order_id),
  )
  |> execute.run_mutation(
    "fulfillmentOrderOpen",
    fulfillment_order_written_field(),
  )
}

pub const open_mutation =
  "mutation FulfillmentOrderOpen($id: ID!) {"
  <> " fulfillmentOrderOpen(id: $id) {"
  <> fulfillment_order_written_selection
  <> " userErrors { field message } } }"

pub fn fulfillment_order_variables(fulfillment_order_id: String) -> Json {
  json.object([#("id", json.string(fulfillment_order_id))])
}

const fulfillment_order_written_selection =
  " fulfillmentOrder { id status" <> " supportedActions { action } }"

fn fulfillment_order_written_field() -> decode.Decoder(FulfillmentOrderWritten) {
  decode.field(
    "fulfillmentOrder",
    fulfillment_order_written_decoder(),
    decode.success,
  )
}

fn notifies(notice: Notice) -> Bool {
  case notice {
    NoticeNotifyCustomer -> True
    NoticeSilent -> False
  }
}

fn lines_input(lines: FulfillmentOrderLines) -> Json {
  json.object([
    #("fulfillmentOrderId", json.string(lines.fulfillment_order_id)),
    #(
      "fulfillmentOrderLineItems",
      json.array(lines.line_items, fn(entry) {
        json.object([
          #("id", json.string(entry.fulfillment_order_line_item_id)),
          #("quantity", json.int(entry.quantity)),
        ])
      }),
    ),
  ])
}

fn tracking_input(tracking: Tracking) -> Json {
  let optional = fn(name, value) {
    case value {
      option.Some(text) -> [#(name, json.string(text))]
      option.None -> []
    }
  }
  json.object(
    list.flatten([
      [#("number", json.string(tracking.number))],
      optional("company", tracking.company),
      optional("url", tracking.url),
    ]),
  )
}

pub fn for_order_decoder() -> decode.Decoder(Option(OrderFulfillments)) {
  use found <- graphql.optional("order", order_decoder())
  decode.success(found)
}

/// A value and whether the read holds all of it.
type Paged(a) {
  Paged(value: a, read: Read)
}

fn order_decoder() -> decode.Decoder(OrderFulfillments) {
  use orders <- decode.field(
    "fulfillmentOrders",
    paged_nodes(fulfillment_order_decoder()),
  )
  use fulfillments <- decode.field(
    "fulfillments",
    decode.list(fulfillment_decoder()),
  )
  let reads = [
    orders.read,
    case list.length(fulfillments) >= fulfillments_per_read {
      True -> ReadTruncated
      False -> ReadComplete
    },
    ..list.append(
      list.map(orders.value, fn(order: Paged(FulfillmentOrder)) { order.read }),
      list.map(fulfillments, fn(fulfillment: Paged(Fulfillment)) {
        fulfillment.read
      }),
    )
  ]
  decode.success(
    OrderFulfillments(
      fulfillment_orders: list.map(orders.value, fn(order) { order.value }),
      fulfillments: list.map(fulfillments, fn(fulfillment) { fulfillment.value }),
      read: case list.contains(reads, ReadTruncated) {
        True -> ReadTruncated
        False -> ReadComplete
      },
    ),
  )
}

/// `{ nodes { ... } pageInfo { hasNextPage } }`.
fn paged_nodes(
  node_decoder: decode.Decoder(a),
) -> decode.Decoder(Paged(List(a))) {
  use nodes <- decode.field("nodes", decode.list(node_decoder))
  use has_next_page <- decode.subfield(["pageInfo", "hasNextPage"], decode.bool)
  decode.success(
    Paged(value: nodes, read: case has_next_page {
      True -> ReadTruncated
      False -> ReadComplete
    }),
  )
}

fn fulfillment_order_decoder() -> decode.Decoder(Paged(FulfillmentOrder)) {
  use id <- decode.field("id", decode.string)
  use status <- decode.field(
    "status",
    decode.string |> decode.map(parse_fulfillment_order_status),
  )
  use location_id <- decode.field("assignedLocation", {
    use location <- graphql.optional(
      "location",
      decode.field("id", decode.string, decode.success),
    )
    decode.success(location)
  })
  use holds <- decode.optional_field(
    "fulfillmentHolds",
    [],
    decode.list({
      use id <- decode.field("id", decode.string)
      use reason <- decode.field(
        "reason",
        decode.string |> decode.map(parse_fulfillment_hold_reason),
      )
      decode.success(FulfillmentHold(id:, reason:))
    }),
  )
  use supported_actions <- decode.optional_field(
    "supportedActions",
    [],
    supported_actions_decoder(),
  )
  use line_items <- decode.field(
    "lineItems",
    paged_nodes(fulfillment_order_line_item_decoder()),
  )
  decode.success(Paged(
    value: FulfillmentOrder(
      id:,
      status:,
      location_id:,
      holds:,
      supported_actions:,
      line_items: line_items.value,
    ),
    read: line_items.read,
  ))
}

fn fulfillment_order_line_item_decoder() -> decode.Decoder(
  FulfillmentOrderLineItem,
) {
  use id <- decode.field("id", decode.string)
  use sku <- graphql.optional("sku", decode.string)
  use remaining_quantity <- decode.field("remainingQuantity", decode.int)
  use line_item_id <- decode.subfield(["lineItem", "id"], decode.string)
  decode.success(FulfillmentOrderLineItem(
    id:,
    line_item_id:,
    sku:,
    remaining_quantity:,
  ))
}

fn fulfillment_decoder() -> decode.Decoder(Paged(Fulfillment)) {
  use id <- decode.field("id", decode.string)
  use status <- decode.field(
    "status",
    decode.string |> decode.map(parse_fulfillment_status),
  )
  use display_status <- graphql.optional(
    "displayStatus",
    decode.string |> decode.map(parse_fulfillment_display_status),
  )
  use tracking_numbers <- decode.optional_field(
    "trackingInfo",
    [],
    decode.list({
      use number <- graphql.optional("number", decode.string)
      decode.success(number)
    })
      |> decode.map(option.values),
  )
  use line_items <- decode.field(
    "fulfillmentLineItems",
    paged_nodes(fulfillment_line_item_decoder()),
  )
  decode.success(Paged(
    value: Fulfillment(
      id:,
      status:,
      display_status:,
      tracking_numbers:,
      line_items: line_items.value,
    ),
    read: line_items.read,
  ))
}

fn fulfillment_line_item_decoder() -> decode.Decoder(FulfillmentLineItem) {
  use quantity <- decode.field("quantity", decode.int)
  use #(line_item_id, sku) <- decode.field("lineItem", {
    use line_item_id <- decode.field("id", decode.string)
    use sku <- graphql.optional("sku", decode.string)
    decode.success(#(line_item_id, sku))
  })
  decode.success(FulfillmentLineItem(line_item_id:, sku:, quantity:))
}

fn supported_actions_decoder() -> decode.Decoder(List(FulfillmentOrderAction)) {
  decode.list(decode.field(
    "action",
    decode.string |> decode.map(parse_fulfillment_order_action),
    decode.success,
  ))
}

fn fulfillment_order_written_decoder() -> decode.Decoder(
  FulfillmentOrderWritten,
) {
  use id <- decode.field("id", decode.string)
  use status <- decode.field(
    "status",
    decode.string |> decode.map(parse_fulfillment_order_status),
  )
  use supported_actions <- decode.optional_field(
    "supportedActions",
    [],
    supported_actions_decoder(),
  )
  decode.success(FulfillmentOrderWritten(id:, status:, supported_actions:))
}

fn written_decoder() -> decode.Decoder(Written) {
  use id <- decode.field("id", decode.string)
  use status <- decode.field(
    "status",
    decode.string |> decode.map(parse_fulfillment_status),
  )
  decode.success(Written(id:, status:))
}

pub fn parse_fulfillment_order_status(raw: String) -> FulfillmentOrderStatus {
  case raw {
    "OPEN" -> FulfillmentOrderStatusOpen
    "IN_PROGRESS" -> FulfillmentOrderStatusInProgress
    "SCHEDULED" -> FulfillmentOrderStatusScheduled
    "ON_HOLD" -> FulfillmentOrderStatusOnHold
    "CLOSED" -> FulfillmentOrderStatusClosed
    "CANCELLED" -> FulfillmentOrderStatusCancelled
    "INCOMPLETE" -> FulfillmentOrderStatusIncomplete
    other -> FulfillmentOrderStatusOther(other)
  }
}

/// Only an open or started fulfillment order takes a new fulfillment.
pub fn accepts_fulfillment(status: FulfillmentOrderStatus) -> Bool {
  case status {
    FulfillmentOrderStatusOpen | FulfillmentOrderStatusInProgress -> True
    FulfillmentOrderStatusScheduled
    | FulfillmentOrderStatusOnHold
    | FulfillmentOrderStatusClosed
    | FulfillmentOrderStatusCancelled
    | FulfillmentOrderStatusIncomplete
    | FulfillmentOrderStatusOther(_) -> False
  }
}

pub fn parse_fulfillment_hold_reason(raw: String) -> FulfillmentHoldReason {
  case raw {
    "AWAITING_PAYMENT" -> FulfillmentHoldReasonAwaitingPayment
    "AWAITING_RETURN_ITEMS" -> FulfillmentHoldReasonAwaitingReturnItems
    "HIGH_RISK_OF_FRAUD" -> FulfillmentHoldReasonHighRiskOfFraud
    "INCORRECT_ADDRESS" -> FulfillmentHoldReasonIncorrectAddress
    "INVENTORY_OUT_OF_STOCK" -> FulfillmentHoldReasonInventoryOutOfStock
    "ONLINE_STORE_POST_PURCHASE_CROSS_SELL" ->
      FulfillmentHoldReasonOnlineStorePostPurchaseCrossSell
    "OTHER" -> FulfillmentHoldReasonOther
    "UNKNOWN_DELIVERY_DATE" -> FulfillmentHoldReasonUnknownDeliveryDate
    other -> FulfillmentHoldReasonUnknown(other)
  }
}

pub fn parse_fulfillment_order_action(raw: String) -> FulfillmentOrderAction {
  case raw {
    "CANCEL_FULFILLMENT_ORDER" -> FulfillmentOrderActionCancelFulfillmentOrder
    "CREATE_FULFILLMENT" -> FulfillmentOrderActionCreateFulfillment
    "EXTERNAL" -> FulfillmentOrderActionExternal
    "HOLD" -> FulfillmentOrderActionHold
    "MARK_AS_OPEN" -> FulfillmentOrderActionMarkAsOpen
    "MERGE" -> FulfillmentOrderActionMerge
    "MOVE" -> FulfillmentOrderActionMove
    "RELEASE_HOLD" -> FulfillmentOrderActionReleaseHold
    "REPORT_PROGRESS" -> FulfillmentOrderActionReportProgress
    "REQUEST_CANCELLATION" -> FulfillmentOrderActionRequestCancellation
    "REQUEST_FULFILLMENT" -> FulfillmentOrderActionRequestFulfillment
    "SPLIT" -> FulfillmentOrderActionSplit
    other -> FulfillmentOrderActionOther(other)
  }
}

/// Whether Shopify listed `action` among the fulfillment order's supported
/// actions when it was read.
pub fn supports(
  actions: List(FulfillmentOrderAction),
  action: FulfillmentOrderAction,
) -> Bool {
  list.contains(actions, action)
}

pub fn parse_fulfillment_status(raw: String) -> FulfillmentStatus {
  case raw {
    "SUCCESS" -> FulfillmentStatusSuccess
    "CANCELLED" -> FulfillmentStatusCancelled
    "FAILURE" -> FulfillmentStatusFailure
    "PENDING" -> FulfillmentStatusPending
    "OPEN" -> FulfillmentStatusOpen
    "ERROR" -> FulfillmentStatusError
    other -> FulfillmentStatusOther(other)
  }
}

/// A cancelled, failed or refused fulfillment ships nothing.
pub fn ships_goods(status: FulfillmentStatus) -> Bool {
  case status {
    FulfillmentStatusSuccess
    | FulfillmentStatusPending
    | FulfillmentStatusOpen
    | FulfillmentStatusOther(_) -> True
    FulfillmentStatusCancelled
    | FulfillmentStatusFailure
    | FulfillmentStatusError -> False
  }
}

pub fn parse_fulfillment_display_status(
  raw: String,
) -> FulfillmentDisplayStatus {
  case raw {
    "ATTEMPTED_DELIVERY" -> FulfillmentDisplayStatusAttemptedDelivery
    "CANCELED" -> FulfillmentDisplayStatusCanceled
    "CARRIER_PICKED_UP" -> FulfillmentDisplayStatusCarrierPickedUp
    "CONFIRMED" -> FulfillmentDisplayStatusConfirmed
    "DELAYED" -> FulfillmentDisplayStatusDelayed
    "DELIVERED" -> FulfillmentDisplayStatusDelivered
    "FAILURE" -> FulfillmentDisplayStatusFailure
    "FULFILLED" -> FulfillmentDisplayStatusFulfilled
    "IN_TRANSIT" -> FulfillmentDisplayStatusInTransit
    "LABEL_PRINTED" -> FulfillmentDisplayStatusLabelPrinted
    "LABEL_PURCHASED" -> FulfillmentDisplayStatusLabelPurchased
    "LABEL_VOIDED" -> FulfillmentDisplayStatusLabelVoided
    "MARKED_AS_FULFILLED" -> FulfillmentDisplayStatusMarkedAsFulfilled
    "NOT_DELIVERED" -> FulfillmentDisplayStatusNotDelivered
    "OUT_FOR_DELIVERY" -> FulfillmentDisplayStatusOutForDelivery
    "PICKED_UP" -> FulfillmentDisplayStatusPickedUp
    "READY_FOR_PICKUP" -> FulfillmentDisplayStatusReadyForPickup
    "SUBMITTED" -> FulfillmentDisplayStatusSubmitted
    other -> FulfillmentDisplayStatusOther(other)
  }
}

pub fn event_status_to_string(status: FulfillmentEventStatus) -> String {
  case status {
    FulfillmentEventStatusAttemptedDelivery -> "ATTEMPTED_DELIVERY"
    FulfillmentEventStatusCarrierPickedUp -> "CARRIER_PICKED_UP"
    FulfillmentEventStatusConfirmed -> "CONFIRMED"
    FulfillmentEventStatusDelayed -> "DELAYED"
    FulfillmentEventStatusDelivered -> "DELIVERED"
    FulfillmentEventStatusFailure -> "FAILURE"
    FulfillmentEventStatusInTransit -> "IN_TRANSIT"
    FulfillmentEventStatusLabelPrinted -> "LABEL_PRINTED"
    FulfillmentEventStatusLabelPurchased -> "LABEL_PURCHASED"
    FulfillmentEventStatusOutForDelivery -> "OUT_FOR_DELIVERY"
    FulfillmentEventStatusReadyForPickup -> "READY_FOR_PICKUP"
  }
}
