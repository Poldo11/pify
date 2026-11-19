import fixtures
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import pify/api_version
import pify/error
import pify/inventory
import pify/location
import scripted

const location_id = "gid://shopify/Location/6600000001"

const compared = [
  inventory.Quantity(
    inventory_item_id: "gid://shopify/InventoryItem/5500000001",
    available: 9,
    change_from: option.Some(12),
  ),
  inventory.Quantity(
    inventory_item_id: "gid://shopify/InventoryItem/5500000002",
    available: 0,
    change_from: option.Some(1),
  ),
]

const half_compared = [
  inventory.Quantity(
    inventory_item_id: "gid://shopify/InventoryItem/5500000001",
    available: 9,
    change_from: option.Some(12),
  ),
  inventory.Quantity(
    inventory_item_id: "gid://shopify/InventoryItem/5500000002",
    available: 0,
    change_from: option.None,
  ),
]

fn one_batch(quantities: List(inventory.Quantity)) -> inventory.Batch {
  let assert [batch] = inventory.batches(quantities)
  batch
}

fn set(version: api_version.ApiVersion, reply: String) {
  set_quantities(version, compared, reply)
}

fn set_quantities(
  version: api_version.ApiVersion,
  quantities: List(inventory.Quantity),
  reply: String,
) {
  inventory.set_available(
    scripted.client(version),
    location_id:,
    batch: one_batch(quantities),
    reference_document_uri: option.Some("gid://loja/StockCount/1"),
    idempotency_key: "stock-count-1-batch-0",
  )
  |> scripted.run([scripted.ok(reply)])
}

pub fn shape_follows_the_version_test() {
  inventory.shape(v2025_10())
  |> should.equal(inventory.ShapeCompareQuantity)
  inventory.shape(api_version.v2026_01)
  |> should.equal(inventory.ShapeIdempotent)
  inventory.shape(api_version.v2026_07)
  |> should.equal(inventory.ShapeIdempotent)
}

fn quantity_decoder(compare_field: String) {
  use item <- decode.field("inventoryItemId", decode.string)
  use location <- decode.field("locationId", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  use compare <- decode.field(compare_field, decode.optional(decode.int))
  decode.success(#(item, location, quantity, compare))
}

pub fn set_available_before_2026_01_sends_compare_quantity_test() {
  let assert #(result, [sent]) =
    set(v2025_10(), fixtures.inventory_set_quantities())
  result
  |> should.equal(
    Ok([
      inventory.Change(name: "available", delta: -3),
      inventory.Change(name: "on_hand", delta: -3),
    ]),
  )
  scripted.query(sent) |> string.contains("@idempotent") |> should.be_false
  scripted.has_variable(sent, ["input", "ignoreCompareQuantity"])
  |> should.be_false
  scripted.has_variable(sent, ["idempotencyKey"]) |> should.be_false
  scripted.body(sent)
  |> string.contains("changeFromQuantity")
  |> should.be_false
  scripted.variable(
    sent,
    ["input", "quantities"],
    decode.list(quantity_decoder("compareQuantity")),
  )
  |> should.equal([
    #("gid://shopify/InventoryItem/5500000001", location_id, 9, option.Some(12)),
    #("gid://shopify/InventoryItem/5500000002", location_id, 0, option.Some(1)),
  ])
  scripted.variable(sent, ["input", "name"], decode.string)
  |> should.equal("available")
  scripted.variable(sent, ["input", "reason"], decode.string)
  |> should.equal("correction")
  scripted.variable(sent, ["input", "referenceDocumentUri"], decode.string)
  |> should.equal("gid://loja/StockCount/1")
}

pub fn set_available_before_2026_01_ignores_a_partial_compare_test() {
  let assert #(_, [sent]) =
    set_quantities(
      v2025_10(),
      half_compared,
      fixtures.inventory_set_quantities(),
    )
  scripted.variable(sent, ["input", "ignoreCompareQuantity"], decode.bool)
  |> should.be_true
  scripted.body(sent)
  |> string.contains("\"compareQuantity\"")
  |> should.be_false
}

pub fn set_available_from_2026_01_is_idempotent_test() {
  list.each(
    [api_version.v2026_01, api_version.v2026_04, api_version.v2026_07],
    fn(version) {
      let assert #(_, [sent]) =
        set(version, fixtures.inventory_set_quantities())
      scripted.query(sent)
      |> string.contains("@idempotent(key: $idempotencyKey)")
      |> should.be_true
      scripted.variable(sent, ["idempotencyKey"], decode.string)
      |> should.equal("stock-count-1-batch-0")
      scripted.has_variable(sent, ["input", "ignoreCompareQuantity"])
      |> should.be_false
      scripted.variable(
        sent,
        ["input", "quantities"],
        decode.list(quantity_decoder("changeFromQuantity")),
      )
      |> should.equal([
        #(
          "gid://shopify/InventoryItem/5500000001",
          location_id,
          9,
          option.Some(12),
        ),
        #(
          "gid://shopify/InventoryItem/5500000002",
          location_id,
          0,
          option.Some(1),
        ),
      ])
    },
  )
}

pub fn set_available_from_2026_01_sends_null_without_a_compare_test() {
  let assert #(_, [sent]) =
    set_quantities(
      api_version.v2026_07,
      half_compared,
      fixtures.inventory_set_quantities(),
    )
  scripted.variable(
    sent,
    ["input", "quantities"],
    decode.list(quantity_decoder("changeFromQuantity")),
  )
  |> should.equal([
    #("gid://shopify/InventoryItem/5500000001", location_id, 9, option.Some(12)),
    #("gid://shopify/InventoryItem/5500000002", location_id, 0, option.None),
  ])
}

pub fn a_stale_compare_is_stale_test() {
  list.each(["CHANGE_FROM_QUANTITY_STALE", "COMPARE_QUANTITY_STALE"], fn(code) {
    inventory.is_stale(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: ["input", "quantities", "0", "changeFromQuantity"],
          message: "The quantity changed",
          code: option.Some(code),
        ),
      ]),
    )
    |> should.be_true
  })
  inventory.is_stale(
    error.ShopifyErrorUserErrors([
      error.UserError(
        field: [],
        message: "A request with this idempotency key is already in progress",
        code: option.Some("IDEMPOTENCY_CONCURRENT_REQUEST"),
      ),
    ]),
  )
  |> should.be_false
  inventory.is_stale(error.ShopifyErrorThrottled(option.None))
  |> should.be_false
}

pub fn set_available_surfaces_coded_user_errors_test() {
  let #(result, _) =
    set(api_version.v2026_07, fixtures.inventory_set_quantities_user_errors())
  result
  |> should.equal(
    Error(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: [],
          message: "A request with this idempotency key is already in progress",
          code: option.Some("IDEMPOTENCY_CONCURRENT_REQUEST"),
        ),
      ]),
    ),
  )
}

pub fn set_available_with_no_change_is_empty_test() {
  let #(result, _) =
    set(
      api_version.v2026_07,
      "{\"data\":{\"inventorySetQuantities\":{\"inventoryAdjustmentGroup\":null,\"userErrors\":[]}}}",
    )
  result |> should.equal(Ok([]))
}

pub fn batches_hold_at_most_250_test() {
  let quantities =
    list.repeat(Nil, 600)
    |> list.index_map(fn(_, index) {
      inventory.Quantity(
        inventory_item_id: "gid://shopify/InventoryItem/"
          <> int.to_string(index),
        available: index,
        change_from: option.None,
      )
    })
  inventory.batches(quantities)
  |> list.map(fn(batch) { list.length(inventory.batch_quantities(batch)) })
  |> should.equal([250, 250, 100])
}

pub fn activate_follows_the_version_test() {
  let activate = fn(version) {
    inventory.activate(
      scripted.client(version),
      inventory_item_id: "gid://shopify/InventoryItem/5500000002",
      location_id:,
      idempotency_key: "activate-5500000002",
    )
    |> scripted.run([
      scripted.ok(
        "{\"data\":{\"inventoryActivate\":{\"inventoryLevel\":{\"id\":\"gid://shopify/InventoryLevel/1\"},\"userErrors\":[]}}}",
      ),
    ])
  }
  let assert #(result, [old]) = activate(v2025_10())
  result |> should.equal(Ok(Nil))
  scripted.query(old) |> string.contains("@idempotent") |> should.be_false
  let assert #(_, [current]) = activate(api_version.v2026_04)
  scripted.query(current)
  |> string.contains("@idempotent(key: $idempotencyKey)")
  |> should.be_true
  scripted.variable(current, ["idempotencyKey"], decode.string)
  |> should.equal("activate-5500000002")
}

pub fn levels_reads_available_per_item_test() {
  let assert #(result, [sent]) =
    inventory.levels(
      scripted.client(api_version.v2026_07),
      location_id:,
      inventory_item_ids: [
        "gid://shopify/InventoryItem/5500000001",
        "gid://shopify/InventoryItem/5500000002",
        "gid://shopify/InventoryItem/404",
      ],
    )
    |> scripted.run([scripted.ok(fixtures.inventory_levels())])
  result
  |> should.equal(
    Ok([
      inventory.Level(
        inventory_item_id: "gid://shopify/InventoryItem/5500000001",
        state: inventory.LevelStateActive(available: 12),
      ),
      inventory.Level(
        inventory_item_id: "gid://shopify/InventoryItem/5500000002",
        state: inventory.LevelStateNotStocked,
      ),
    ]),
  )
  scripted.variable(sent, ["locationId"], decode.string)
  |> should.equal(location_id)
}

pub fn levels_ask_for_inactive_levels_from_2026_04_test() {
  let read = fn(version) {
    inventory.levels(
      scripted.client(version),
      location_id:,
      inventory_item_ids: ["gid://shopify/InventoryItem/5500000001"],
    )
    |> scripted.run([
      scripted.ok(
        "{\"data\":{\"nodes\":[{\"id\":\"gid://shopify/InventoryItem/5500000001\",\"inventoryLevel\":{\"isActive\":false,\"quantities\":[{\"name\":\"available\",\"quantity\":30}]}}]}}",
      ),
    ])
  }
  let assert #(result, [current]) = read(api_version.v2026_04)
  result
  |> should.equal(
    Ok([
      inventory.Level(
        inventory_item_id: "gid://shopify/InventoryItem/5500000001",
        state: inventory.LevelStateInactive(available: 30),
      ),
    ]),
  )
  scripted.query(current)
  |> string.contains("includeInactive: true")
  |> should.be_true
  scripted.query(current) |> string.contains("isActive") |> should.be_true
  let assert #(_, [old]) = read(api_version.v2026_01)
  scripted.query(old) |> string.contains("includeInactive") |> should.be_false
  scripted.query(old) |> string.contains("isActive") |> should.be_false
}

fn v2025_10() -> api_version.ApiVersion {
  let assert Ok(version) = api_version.parse("2025-10")
  version
}

pub fn list_decodes_locations_test() {
  let #(result, _) =
    location.list(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(fixtures.locations())])
  result
  |> should.equal(
    Ok([
      location.Location(
        id: "gid://shopify/Location/6600000001",
        name: "Deposito Central",
        is_active: True,
        fulfills_online_orders: True,
      ),
      location.Location(
        id: "gid://shopify/Location/6600000002",
        name: "Livraria",
        is_active: True,
        fulfills_online_orders: False,
      ),
    ]),
  )
}

pub fn list_follows_the_cursor_test() {
  let first_page =
    "{\"data\":{\"locations\":{\"nodes\":[{\"id\":\"gid://shopify/Location/1\","
    <> "\"name\":\"A\",\"isActive\":true,\"fulfillsOnlineOrders\":true}],"
    <> "\"pageInfo\":{\"hasNextPage\":true,\"endCursor\":\"next-page\"}}}}"
  let #(result, sent) =
    location.list(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(first_page), scripted.ok(fixtures.locations())])
  let assert Ok(found) = result
  list.length(found) |> should.equal(3)
  let assert [first, second] = sent
  scripted.variable(first, ["after"], decode.optional(decode.string))
  |> should.equal(option.None)
  scripted.variable(second, ["after"], decode.string)
  |> should.equal("next-page")
}
