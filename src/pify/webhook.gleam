//// Inbound webhook deliveries.
////
//// Shopify signs the raw body with base64(HMAC-SHA256(client secret, body))
//// in `X-Shopify-Hmac-Sha256`. Every other header is unsigned. The body is
//// the REST form of the resource (snake_case, integer ids), not the GraphQL
//// form, so a consumer reads a reference from it and fetches the resource
//// through the Admin API before it applies anything. Deliveries can arrive
//// out of order and more than once.
////
//// An `orders/delete` body and a `products/delete` body are both
//// `{"id": N}`, so no check can tell them apart. A consumer deletes an
//// order only after `order.get` confirms that the order is absent.

import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import pify/error.{type ShopifyError}

pub type Topic {
  TopicOrdersCreate
  TopicOrdersUpdated
  TopicOrdersCancelled
  TopicOrdersDelete
  TopicOrdersFulfilled
  TopicOrdersPaid
  TopicOrdersPartiallyFulfilled
  TopicOrdersEdited
  TopicProductsCreate
  TopicProductsUpdate
  TopicProductsDelete
  TopicInventoryLevelsUpdate
  TopicAppUninstalled
  /// A topic this library does not know. Kept verbatim, never dropped.
  TopicUnknown(raw: String)
}

/// The headers Shopify sets on every delivery.
pub type Delivery {
  Delivery(
    topic: Topic,
    hmac: String,
    shop_domain: String,
    /// The version that serialized the body. It can differ from the version
    /// the subscription asked for.
    api_version: String,
    /// Unique per delivery and stable across retries of it.
    webhook_id: String,
    /// Shared by every subscription that one merchant action triggered.
    event_id: Option(String),
    triggered_at: Option(String),
    name: Option(String),
  )
}

pub type HeaderError {
  HeaderErrorMissing(name: String)
}

/// The order a delivery is about. Re-read the order through
/// `order.get(admin_graphql_api_id)` before applying it.
pub type OrderRef {
  OrderRef(
    id: Int,
    admin_graphql_api_id: String,
    name: Option(String),
    updated_at: Option(String),
  )
}

pub const header_topic = "x-shopify-topic"

pub const header_hmac = "x-shopify-hmac-sha256"

pub const header_shop_domain = "x-shopify-shop-domain"

pub const header_api_version = "x-shopify-api-version"

pub const header_webhook_id = "x-shopify-webhook-id"

pub const header_event_id = "x-shopify-event-id"

pub const header_triggered_at = "x-shopify-triggered-at"

pub const header_name = "x-shopify-name"

const known_topics = [
  TopicOrdersCreate,
  TopicOrdersUpdated,
  TopicOrdersCancelled,
  TopicOrdersDelete,
  TopicOrdersFulfilled,
  TopicOrdersPaid,
  TopicOrdersPartiallyFulfilled,
  TopicOrdersEdited,
  TopicProductsCreate,
  TopicProductsUpdate,
  TopicProductsDelete,
  TopicInventoryLevelsUpdate,
  TopicAppUninstalled,
]

/// Header names are matched case-insensitively.
pub fn parse_headers(
  headers: List(#(String, String)),
) -> Result(Delivery, HeaderError) {
  let lowered =
    list.map(headers, fn(header) { #(string.lowercase(header.0), header.1) })
  use topic <- result.try(required(lowered, header_topic))
  use hmac <- result.try(required(lowered, header_hmac))
  use shop_domain <- result.try(required(lowered, header_shop_domain))
  use api_version <- result.try(required(lowered, header_api_version))
  use webhook_id <- result.try(required(lowered, header_webhook_id))
  Ok(Delivery(
    topic: parse_topic(topic),
    hmac:,
    shop_domain:,
    api_version:,
    webhook_id:,
    event_id: optional(lowered, header_event_id),
    triggered_at: optional(lowered, header_triggered_at),
    name: optional(lowered, header_name),
  ))
}

/// Verify the signature over the raw body bytes. Run this before any JSON
/// parse. An empty secret never verifies, because anyone can sign with it.
pub fn verify(
  secret: String,
  body: BitArray,
  hmac: String,
) -> Result(Nil, ShopifyError) {
  case string.trim(hmac), string.is_empty(secret) {
    "", _ -> Error(error.ShopifyErrorSignatureMissing)
    _, True -> Error(error.ShopifyErrorSignatureInvalid)
    signature, False -> {
      let matches =
        bit_array.base64_decode(signature)
        |> result.map(crypto.secure_compare(_, digest(secret, body)))
      case matches {
        Ok(True) -> Ok(Nil)
        Ok(False) | Error(Nil) -> Error(error.ShopifyErrorSignatureInvalid)
      }
    }
  }
}

/// Lowercase hex SHA-256 of the topic, a newline and the raw body. Only the
/// body is signed, so the key reads no unsigned id. A retry resends the same
/// body and gets the same key; two topics with one body get two keys.
pub fn dedupe_key(topic: Topic, body: BitArray) -> String {
  let topic_bytes = bit_array.from_string(topic_to_string(topic) <> "\n")
  crypto.hash(crypto.Sha256, bit_array.append(topic_bytes, body))
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Hold the unsigned topic header to the signed body's shape. A delete
/// body is `{"id": N}`; an order or product body carries its own GraphQL id;
/// an `orders/edited` body wraps the edit in `order_edit`.
pub fn check_topic(topic: Topic, body: BitArray) -> Result(Nil, ShopifyError) {
  let fields =
    json.parse_bits(body, decode.dict(decode.string, decode.dynamic))
    |> result.unwrap(dict.new())
  let fits = case topic {
    TopicOrdersDelete | TopicProductsDelete -> is_bare_int_id(fields)
    TopicOrdersCreate
    | TopicOrdersUpdated
    | TopicOrdersCancelled
    | TopicOrdersFulfilled
    | TopicOrdersPaid
    | TopicOrdersPartiallyFulfilled -> has_gid(fields, "gid://shopify/Order/")
    TopicOrdersEdited ->
      dict.has_key(fields, "order_edit")
      || has_gid(fields, "gid://shopify/Order/")
    TopicProductsCreate | TopicProductsUpdate ->
      has_gid(fields, "gid://shopify/Product/")
    TopicInventoryLevelsUpdate ->
      dict.has_key(fields, "inventory_item_id")
      && dict.has_key(fields, "location_id")
    TopicAppUninstalled -> dict.has_key(fields, "myshopify_domain")
    TopicUnknown(_) -> True
  }
  case fits {
    True -> Ok(Nil)
    False -> Error(error.ShopifyErrorTopicBodyMismatch(topic_to_string(topic)))
  }
}

/// Read the order reference from an `orders/*` body. A delete body carries
/// only the numeric id and an `orders/edited` body only `order_edit.order_id`,
/// so the GraphQL id is built from the number.
pub fn order_ref(body: BitArray) -> Result(OrderRef, ShopifyError) {
  json.parse_bits(body, decode.one_of(order_body_decoder(), [edit_decoder()]))
  |> result.map_error(error.from_json)
}

pub fn parse_topic(raw: String) -> Topic {
  list.find(known_topics, fn(topic) { topic_to_string(topic) == raw })
  |> result.unwrap(TopicUnknown(raw))
}

pub fn topic_to_string(topic: Topic) -> String {
  case topic {
    TopicOrdersCreate -> "orders/create"
    TopicOrdersUpdated -> "orders/updated"
    TopicOrdersCancelled -> "orders/cancelled"
    TopicOrdersDelete -> "orders/delete"
    TopicOrdersFulfilled -> "orders/fulfilled"
    TopicOrdersPaid -> "orders/paid"
    TopicOrdersPartiallyFulfilled -> "orders/partially_fulfilled"
    TopicOrdersEdited -> "orders/edited"
    TopicProductsCreate -> "products/create"
    TopicProductsUpdate -> "products/update"
    TopicProductsDelete -> "products/delete"
    TopicInventoryLevelsUpdate -> "inventory_levels/update"
    TopicAppUninstalled -> "app/uninstalled"
    TopicUnknown(raw) -> raw
  }
}

/// The `WebhookSubscriptionTopic` enum value a subscription names. A topic
/// this library does not know has none and is `ShopifyErrorTopicUnsupported`.
pub fn topic_to_graphql_enum(topic: Topic) -> Result(String, ShopifyError) {
  case topic {
    TopicOrdersCreate -> Ok("ORDERS_CREATE")
    TopicOrdersUpdated -> Ok("ORDERS_UPDATED")
    TopicOrdersCancelled -> Ok("ORDERS_CANCELLED")
    TopicOrdersDelete -> Ok("ORDERS_DELETE")
    TopicOrdersFulfilled -> Ok("ORDERS_FULFILLED")
    TopicOrdersPaid -> Ok("ORDERS_PAID")
    TopicOrdersPartiallyFulfilled -> Ok("ORDERS_PARTIALLY_FULFILLED")
    TopicOrdersEdited -> Ok("ORDERS_EDITED")
    TopicProductsCreate -> Ok("PRODUCTS_CREATE")
    TopicProductsUpdate -> Ok("PRODUCTS_UPDATE")
    TopicProductsDelete -> Ok("PRODUCTS_DELETE")
    TopicInventoryLevelsUpdate -> Ok("INVENTORY_LEVELS_UPDATE")
    TopicAppUninstalled -> Ok("APP_UNINSTALLED")
    TopicUnknown(raw) -> Error(error.ShopifyErrorTopicUnsupported(topic: raw))
  }
}

fn digest(secret: String, body: BitArray) -> BitArray {
  crypto.hmac(body, crypto.Sha256, bit_array.from_string(secret))
}

/// Exactly `{"id": N}` with an integer `N`.
fn is_bare_int_id(fields: Dict(String, Dynamic)) -> Bool {
  case dict.to_list(fields) {
    [#("id", value)] -> result.is_ok(decode.run(value, decode.int))
    _ -> False
  }
}

fn has_gid(fields: Dict(String, Dynamic), prefix: String) -> Bool {
  case dict.get(fields, "admin_graphql_api_id") {
    Ok(value) ->
      case decode.run(value, decode.string) {
        Ok(gid) -> string.starts_with(gid, prefix)
        Error(_) -> False
      }
    Error(Nil) -> False
  }
}

/// A body whose `admin_graphql_api_id` is not the Order id built from `id`,
/// such as a product body, fails.
fn order_body_decoder() -> decode.Decoder(OrderRef) {
  use id <- decode.field("id", decode.int)
  let expected = order_gid(id)
  use admin_graphql_api_id <- decode.optional_field(
    "admin_graphql_api_id",
    expected,
    decode.string,
  )
  use name <- decode.optional_field(
    "name",
    option.None,
    decode.optional(decode.string),
  )
  use updated_at <- decode.optional_field(
    "updated_at",
    option.None,
    decode.optional(decode.string),
  )
  case admin_graphql_api_id == expected {
    True ->
      decode.success(OrderRef(id:, admin_graphql_api_id:, name:, updated_at:))
    False ->
      decode.failure(
        OrderRef(
          id:,
          admin_graphql_api_id: expected,
          name: option.None,
          updated_at: option.None,
        ),
        expected,
      )
  }
}

fn edit_decoder() -> decode.Decoder(OrderRef) {
  use id <- decode.subfield(["order_edit", "order_id"], decode.int)
  decode.success(OrderRef(
    id:,
    admin_graphql_api_id: order_gid(id),
    name: option.None,
    updated_at: option.None,
  ))
}

fn order_gid(id: Int) -> String {
  "gid://shopify/Order/" <> int.to_string(id)
}

fn required(
  headers: List(#(String, String)),
  name: String,
) -> Result(String, HeaderError) {
  list.key_find(headers, name)
  |> result.replace_error(HeaderErrorMissing(name))
}

fn optional(headers: List(#(String, String)), name: String) -> Option(String) {
  list.key_find(headers, name) |> option.from_result
}
