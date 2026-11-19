//// Available stock per inventory item per location.
////
//// A write is a compare-and-set: each quantity carries the value read just
//// before, and Shopify refuses the write when its value moved since. The
//// request shape depends on the version. Before 2026-01 the compare value
//// is `compareQuantity`. From 2026-01 it is `changeFromQuantity`, sent with
//// an `@idempotent` key, which 2026-04 makes mandatory. The client's version
//// picks the shape.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/set
import midas/effect.{type Effect}
import pify.{type Client}
import pify/api_version.{type ApiVersion}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request

/// The available quantity to write for one item. `change_from` is the
/// quantity read just before; `None` writes without the compare.
pub type Quantity {
  Quantity(inventory_item_id: String, available: Int, change_from: Option(Int))
}

/// Up to `max_batch_size` quantities for one location. Only `batches`
/// builds one, so no call can pass Shopify's array limit.
pub opaque type Batch {
  Batch(quantities: List(Quantity))
}

/// One line of the adjustment Shopify recorded.
pub type Change {
  Change(name: String, delta: Int)
}

/// The request shape a version takes.
pub type Shape {
  /// Before 2026-01: `compareQuantity` on each quantity and no key. A batch
  /// with a quantity that has no compare value sends
  /// `ignoreCompareQuantity: true` instead.
  ShapeCompareQuantity
  /// From 2026-01: `changeFromQuantity` on each quantity, null when there is
  /// no compare value, and an `@idempotent` key.
  ShapeIdempotent
}

/// The level of one item at one location.
pub type Level {
  Level(inventory_item_id: String, state: LevelState)
}

pub type LevelState {
  /// Stocked at the location, with its available quantity.
  LevelStateActive(available: Int)
  /// Stocked once and then taken off the location. From 2026-04
  /// `activate` keeps this quantity, so the first write after it compares
  /// against it. Earlier versions read such a level as not stocked.
  LevelStateInactive(available: Int)
  /// No level at the location. `activate` stocks the item at zero.
  LevelStateNotStocked
}

pub const max_batch_size = 250

/// From this version the writes take `changeFromQuantity` and an
/// idempotency key.
pub const idempotent_since = api_version.v2026_01

/// From this version a level read returns inactive levels on request, and
/// `activate` keeps the quantity an inactive level holds.
pub const inactive_levels_since = api_version.v2026_04

/// The `userErrors` codes of a compare value that differs from Shopify's
/// quantity: from 2026-01 and before it.
pub const stale_codes = ["CHANGE_FROM_QUANTITY_STALE", "COMPARE_QUANTITY_STALE"]

pub fn shape(version: ApiVersion) -> Shape {
  case api_version.at_least(version, idempotent_since) {
    True -> ShapeIdempotent
    False -> ShapeCompareQuantity
  }
}

pub fn batches(quantities: List(Quantity)) -> List(Batch) {
  quantities
  |> list.sized_chunk(max_batch_size)
  |> list.map(Batch)
}

pub fn batch_quantities(batch: Batch) -> List(Quantity) {
  batch.quantities
}

/// Shopify's quantity moved after it was read. Read the level again and
/// retry on a later run.
pub fn is_stale(error: ShopifyError) -> Bool {
  case error {
    error.ShopifyErrorUserErrors(errors) -> {
      let codes = set.from_list(stale_codes)
      list.any(errors, fn(user_error) {
        case user_error.code {
          option.Some(code) -> set.contains(codes, code)
          option.None -> False
        }
      })
    }
    error.ShopifyErrorApi(..)
    | error.ShopifyErrorAuthentication
    | error.ShopifyErrorForbidden(_)
    | error.ShopifyErrorNotFound
    | error.ShopifyErrorShopUnavailable(_)
    | error.ShopifyErrorThrottled(_)
    | error.ShopifyErrorServer(_)
    | error.ShopifyErrorNetwork(_)
    | error.ShopifyErrorDecode(_)
    | error.ShopifyErrorMalformedJson(_)
    | error.ShopifyErrorSignatureInvalid
    | error.ShopifyErrorSignatureMissing
    | error.ShopifyErrorTopicBodyMismatch(_)
    | error.ShopifyErrorTopicUnsupported(_) -> False
  }
}

/// Set the `available` quantity with reason `correction`. A stale compare
/// value fails the whole call; `is_stale` says so. Derive one
/// idempotency key per batch and send the same key when retrying that
/// batch; Shopify keeps a key for 24 hours. `IDEMPOTENCY_CONCURRENT_REQUEST`
/// says the first attempt is still running, and the retry must reuse the
/// same key.
pub fn set_available(
  client: Client,
  location_id location_id: String,
  batch batch: Batch,
  reference_document_uri reference_document_uri: Option(String),
  idempotency_key idempotency_key: String,
) -> Effect(Result(List(Change), ShopifyError), key) {
  let shape = shape(client.version)
  request.graphql(
    client,
    set_available_mutation(shape),
    set_available_variables(
      shape,
      location_id,
      batch,
      reference_document_uri,
      idempotency_key,
    ),
  )
  |> execute.run_mutation("inventorySetQuantities", changes_decoder())
}

pub fn set_available_mutation(shape: Shape) -> String {
  let #(key_variable, directive) = idempotency_parts(shape)
  "mutation InventorySetAvailable($input: InventorySetQuantitiesInput!"
  <> key_variable
  <> ") { inventorySetQuantities(input: $input)"
  <> directive
  <> " { inventoryAdjustmentGroup { changes { name delta } }"
  <> " userErrors { code field message } } }"
}

pub fn set_available_variables(
  shape shape: Shape,
  location_id location_id: String,
  batch batch: Batch,
  reference_document_uri reference_document_uri: Option(String),
  idempotency_key idempotency_key: String,
) -> Json {
  let every_compared =
    list.all(batch.quantities, fn(quantity) {
      option.is_some(quantity.change_from)
    })
  let #(compare, ignore_compare, key) = case shape, every_compared {
    ShapeIdempotent, _ -> #(
      fn(change_from) {
        [#("changeFromQuantity", json.nullable(change_from, json.int))]
      },
      [],
      [#("idempotencyKey", json.string(idempotency_key))],
    )
    ShapeCompareQuantity, True -> #(
      fn(change_from) {
        [#("compareQuantity", json.nullable(change_from, json.int))]
      },
      [],
      [],
    )
    ShapeCompareQuantity, False -> #(
      fn(_change_from) { [] },
      [#("ignoreCompareQuantity", json.bool(True))],
      [],
    )
  }
  let reference = case reference_document_uri {
    option.Some(uri) -> [#("referenceDocumentUri", json.string(uri))]
    option.None -> []
  }
  let quantities =
    json.array(batch.quantities, fn(quantity) {
      json.object(list.append(
        [
          #("inventoryItemId", json.string(quantity.inventory_item_id)),
          #("locationId", json.string(location_id)),
          #("quantity", json.int(quantity.available)),
        ],
        compare(quantity.change_from),
      ))
    })
  let input =
    json.object(
      list.flatten([
        [
          #("name", json.string("available")),
          #("reason", json.string("correction")),
          #("quantities", quantities),
        ],
        reference,
        ignore_compare,
      ]),
    )
  json.object([#("input", input), ..key])
}

/// Stock an item at a location that does not carry it yet. Before 2026-04
/// the level starts at zero; from 2026-04 an inactive level keeps its
/// quantity.
pub fn activate(
  client: Client,
  inventory_item_id inventory_item_id: String,
  location_id location_id: String,
  idempotency_key idempotency_key: String,
) -> Effect(Result(Nil, ShopifyError), key) {
  let shape = shape(client.version)
  request.graphql(
    client,
    activate_mutation(shape),
    activate_variables(shape, inventory_item_id, location_id, idempotency_key),
  )
  |> execute.run_mutation("inventoryActivate", decode.success(Nil))
}

pub fn activate_mutation(shape: Shape) -> String {
  let #(key_variable, directive) = idempotency_parts(shape)
  "mutation InventoryActivate($inventoryItemId: ID!, $locationId: ID!"
  <> key_variable
  <> ") { inventoryActivate(inventoryItemId: $inventoryItemId, locationId: $locationId)"
  <> directive
  <> " { inventoryLevel { id } userErrors { field message } } }"
}

pub fn activate_variables(
  shape: Shape,
  inventory_item_id: String,
  location_id: String,
  idempotency_key: String,
) -> Json {
  let key = case shape {
    ShapeIdempotent -> [#("idempotencyKey", json.string(idempotency_key))]
    ShapeCompareQuantity -> []
  }
  json.object([
    #("inventoryItemId", json.string(inventory_item_id)),
    #("locationId", json.string(location_id)),
    ..key
  ])
}

/// The available quantity of each item at one location, `max_batch_size`
/// items per call. Ids that match no inventory item are left out.
pub fn levels(
  client: Client,
  location_id location_id: String,
  inventory_item_ids inventory_item_ids: List(String),
) -> Effect(Result(List(Level), ShopifyError), key) {
  inventory_item_ids
  |> list.unique
  |> list.sized_chunk(max_batch_size)
  |> execute.try_each(fn(chunk) {
    request.graphql(
      client,
      levels_query(client.version),
      levels_variables(location_id, chunk),
    )
    |> execute.run(levels_decoder())
  })
  |> execute.map(list.flatten)
}

/// From 2026-04 the read asks for inactive levels too, and whether each
/// level is active.
pub fn levels_query(version: ApiVersion) -> String {
  let reads_inactive = api_version.at_least(version, inactive_levels_since)
  let #(level_arguments, active_field) = case reads_inactive {
    True -> #("locationId: $locationId, includeInactive: true", " isActive")
    False -> #("locationId: $locationId", "")
  }
  "query InventoryLevels($ids: [ID!]!, $locationId: ID!) {"
  <> " nodes(ids: $ids) { ... on InventoryItem { id"
  <> " inventoryLevel("
  <> level_arguments
  <> ") {"
  <> active_field
  <> " quantities(names: [\"available\"]) { name quantity } } } } }"
}

pub fn levels_variables(location_id: String, ids: List(String)) -> Json {
  json.object([
    #("ids", json.array(ids, json.string)),
    #("locationId", json.string(location_id)),
  ])
}

pub fn levels_decoder() -> decode.Decoder(List(Level)) {
  use nodes <- decode.field(
    "nodes",
    decode.list(decode.optional(node_decoder())),
  )
  decode.success(nodes |> list.map(option.flatten) |> option.values)
}

fn node_decoder() -> decode.Decoder(Option(Level)) {
  use id <- graphql.optional("id", decode.string)
  use level <- graphql.optional("inventoryLevel", level_state_decoder())
  decode.success(
    option.map(id, fn(inventory_item_id) {
      Level(
        inventory_item_id:,
        state: option.unwrap(level, LevelStateNotStocked),
      )
    }),
  )
}

/// A level without `isActive` comes from a version before 2026-04, which
/// returns active levels only. A level without an `available` quantity
/// reads as not stocked.
fn level_state_decoder() -> decode.Decoder(LevelState) {
  use is_active <- graphql.optional("isActive", decode.bool)
  use quantities <- decode.field(
    "quantities",
    decode.list({
      use name <- decode.field("name", decode.string)
      use quantity <- decode.field("quantity", decode.int)
      decode.success(#(name, quantity))
    }),
  )
  decode.success(case list.key_find(quantities, "available"), is_active {
    Error(Nil), _ -> LevelStateNotStocked
    Ok(available), option.Some(False) -> LevelStateInactive(available:)
    Ok(available), option.Some(True) | Ok(available), option.None ->
      LevelStateActive(available:)
  })
}

fn changes_decoder() -> decode.Decoder(List(Change)) {
  use group <- graphql.optional("inventoryAdjustmentGroup", {
    decode.field(
      "changes",
      decode.list({
        use name <- decode.field("name", decode.string)
        use delta <- decode.field("delta", decode.int)
        decode.success(Change(name:, delta:))
      }),
      decode.success,
    )
  })
  decode.success(option.unwrap(group, []))
}

fn idempotency_parts(shape: Shape) -> #(String, String) {
  case shape {
    ShapeIdempotent -> #(
      ", $idempotencyKey: String!",
      " @idempotent(key: $idempotencyKey)",
    )
    ShapeCompareQuantity -> #("", "")
  }
}
