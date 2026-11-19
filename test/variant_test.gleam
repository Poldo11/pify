import fixtures
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/order
import gleam/string
import gleeunit/should
import pify/api_version
import pify/decimal
import pify/error
import pify/variant
import scripted

fn amount(text: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(text)
  value
}

pub fn find_by_skus_keeps_exact_matches_only_test() {
  let assert #(result, [sent]) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), [
      "9786500000001",
      "9786500000002",
      "9786500000001",
    ])
    |> scripted.run([scripted.ok(fixtures.variants_by_sku())])
  let assert Ok(found) = result
  found
  |> list.map(fn(found_variant) { found_variant.sku })
  |> should.equal([option.Some("9786500000001"), option.Some("9786500000002")])
  let assert [first, second] = found
  first
  |> should.equal(variant.Variant(
    id: "gid://shopify/ProductVariant/4400000001",
    sku: option.Some("9786500000001"),
    barcode: option.Some("9786500000001"),
    price: amount("49.90"),
    compare_at_price: option.Some(amount("59.90")),
    product_id: "gid://shopify/Product/7700000001",
    inventory_item_id: "gid://shopify/InventoryItem/5500000001",
    tracked: True,
    inventory_policy: option.Some(variant.InventoryPolicyContinue),
  ))
  second.tracked |> should.be_false
  second.inventory_policy |> should.equal(option.None)
  second.compare_at_price |> should.equal(option.None)
  scripted.variable(sent, ["query"], decode.string)
  |> should.equal("sku:\"9786500000001\" OR sku:\"9786500000002\"")
}

pub fn find_by_skus_searches_fifty_at_a_time_test() {
  let skus =
    list.repeat(Nil, 120)
    |> list.index_map(fn(_, index) { "SKU-" <> int.to_string(index + 1) })
  let empty =
    scripted.ok(
      "{\"data\":{\"productVariants\":{\"nodes\":[],\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null}}}}",
    )
  let #(result, sent) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), skus)
    |> scripted.run([empty, empty, empty])
  result |> should.equal(Ok([]))
  list.length(sent) |> should.equal(3)
  let assert [first, ..] = sent
  scripted.variable(first, ["query"], decode.string)
  |> string.split(" OR ")
  |> list.length
  |> should.equal(variant.skus_per_search)
}

pub fn find_by_skus_escapes_quotes_test() {
  let assert #(_, [sent]) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), ["A\"B"])
    |> scripted.run([
      scripted.ok(
        "{\"data\":{\"productVariants\":{\"nodes\":[],\"pageInfo\":{\"hasNextPage\":false}}}}",
      ),
    ])
  scripted.variable(sent, ["query"], decode.string)
  |> should.equal("sku:\"A\\\"B\"")
}

pub fn bulk_update_request_shape_test() {
  let updates = [
    variant.VariantUpdate(
      id: "gid://shopify/ProductVariant/4400000001",
      price: decimal.from_hundredths(4490),
      compare_at_price: option.None,
      barcode: option.Some("9786500000001"),
      sku: option.None,
      option: option.None,
    ),
    variant.VariantUpdate(
      id: "gid://shopify/ProductVariant/4400000002",
      price: decimal.from_hundredths(7990),
      compare_at_price: option.Some(decimal.from_hundredths(8990)),
      barcode: option.None,
      sku: option.None,
      option: option.None,
    ),
  ]
  let assert #(result, [sent]) =
    variant.bulk_update(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Product/7700000001",
      updates,
    )
    |> scripted.run([scripted.ok(fixtures.variants_bulk_update())])
  result
  |> should.equal(
    Ok([
      variant.UpdatedVariant(
        id: "gid://shopify/ProductVariant/4400000001",
        price: amount("44.90"),
        compare_at_price: option.None,
        barcode: option.Some("9786500000001"),
      ),
    ]),
  )
  scripted.variable(sent, ["productId"], decode.string)
  |> should.equal("gid://shopify/Product/7700000001")
  let input_decoder = {
    use price <- decode.field("price", decode.string)
    use compare_at_price <- decode.field(
      "compareAtPrice",
      decode.optional(decode.string),
    )
    use barcode <- decode.optional_field(
      "barcode",
      option.None,
      decode.optional(decode.string),
    )
    decode.success(#(price, compare_at_price, barcode))
  }
  scripted.variable(sent, ["variants"], decode.list(input_decoder))
  |> should.equal([
    #("44.90", option.None, option.Some("9786500000001")),
    #("79.90", option.Some("89.90"), option.None),
  ])
  scripted.body(sent)
  |> string.split("\"barcode\"")
  |> list.length
  |> should.equal(2)
}

pub fn bulk_update_chunks_and_stops_at_the_first_error_test() {
  let updates =
    list.repeat(Nil, 251)
    |> list.index_map(fn(_, index) {
      variant.VariantUpdate(
        id: "gid://shopify/ProductVariant/" <> int.to_string(index),
        price: decimal.from_hundredths(100),
        compare_at_price: option.None,
        barcode: option.None,
        sku: option.None,
        option: option.None,
      )
    })
  let ok =
    scripted.ok(
      "{\"data\":{\"productVariantsBulkUpdate\":{\"productVariants\":[],\"userErrors\":[]}}}",
    )
  let client = scripted.client(api_version.v2026_07)
  let product_id = "gid://shopify/Product/7700000001"
  let #(_, sent) =
    variant.bulk_update(client, product_id, updates)
    |> scripted.run([ok, ok])
  sent
  |> list.map(fn(sent_request) {
    scripted.variable(sent_request, ["variants"], decode.list(decode.dynamic))
    |> list.length
  })
  |> should.equal([250, 1])
  let failing = scripted.Reply(status: 503, headers: [], body: "")
  let #(result, sent) =
    variant.bulk_update(client, product_id, list.append(updates, updates))
    |> scripted.run([ok, failing, ok])
  result |> should.equal(Error(error.ShopifyErrorServer(503)))
  list.length(sent) |> should.equal(2)
  let #(result, sent) =
    variant.bulk_update(client, product_id, []) |> scripted.run([])
  result |> should.equal(Ok([]))
  sent |> should.equal([])
}

pub fn bulk_update_surfaces_user_errors_test() {
  let #(result, _) =
    variant.bulk_update(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Product/7700000001",
      [
        variant.VariantUpdate(
          id: "gid://shopify/ProductVariant/4400000001",
          price: decimal.from_hundredths(-100),
          compare_at_price: option.None,
          barcode: option.None,
          sku: option.None,
          option: option.None,
        ),
      ],
    )
    |> scripted.run([scripted.ok(fixtures.variants_bulk_update_user_errors())])
  result
  |> should.equal(
    Error(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: ["variants", "0", "price"],
          message: "Price must be greater than or equal to 0",
          code: option.Some("GREATER_THAN_OR_EQUAL_TO"),
        ),
      ]),
    ),
  )
}

fn variant_node(id: String, sku: String) -> String {
  "{\"id\":\""
  <> id
  <> "\",\"sku\":"
  <> sku
  <> ",\"barcode\":null,\"price\":\"1.00\",\"compareAtPrice\":null,"
  <> "\"product\":{\"id\":\"gid://shopify/Product/1\"},"
  <> "\"inventoryItem\":{\"id\":\"gid://shopify/InventoryItem/1\",\"tracked\":true}}"
}

fn variant_page(nodes: List(String), next: option.Option(String)) -> String {
  let page_info = case next {
    option.Some(cursor) ->
      "{\"hasNextPage\":true,\"endCursor\":\"" <> cursor <> "\"}"
    option.None -> "{\"hasNextPage\":false,\"endCursor\":null}"
  }
  "{\"data\":{\"productVariants\":{\"nodes\":["
  <> string.join(nodes, ",")
  <> "],\"pageInfo\":"
  <> page_info
  <> "}}}"
}

pub fn find_by_skus_returns_each_variant_once_across_chunks_test() {
  let fillers =
    list.repeat(Nil, 49)
    |> list.index_map(fn(_, index) { "F-" <> int.to_string(index) })
  let skus = list.flatten([["A"], fillers, ["A-CAPA"]])
  let #(result, sent) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), skus)
    |> scripted.run([
      scripted.ok(variant_page(
        [
          variant_node("gid://shopify/ProductVariant/1", "\"A\""),
          variant_node("gid://shopify/ProductVariant/2", "\"A-CAPA\""),
        ],
        option.None,
      )),
      scripted.ok(variant_page(
        [variant_node("gid://shopify/ProductVariant/2", "\"A-CAPA\"")],
        option.None,
      )),
    ])
  list.length(sent) |> should.equal(2)
  let assert Ok(found) = result
  found
  |> list.map(fn(found_variant) { found_variant.id })
  |> should.equal([
    "gid://shopify/ProductVariant/1",
    "gid://shopify/ProductVariant/2",
  ])
}

pub fn find_by_skus_never_searches_a_blank_sku_test() {
  let #(result, sent) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), ["", "  "])
    |> scripted.run([
      scripted.ok(variant_page(
        [variant_node("gid://shopify/ProductVariant/7", "\"\"")],
        option.None,
      )),
    ])
  result |> should.equal(Ok([]))
  sent |> should.equal([])
}

/// Shopify's search ignores case, so the match does too; a variant without
/// a SKU and a near SKU stay out.
pub fn find_by_skus_keeps_case_variants_and_drops_null_test() {
  let #(result, _) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), ["abc-1"])
    |> scripted.run([
      scripted.ok(variant_page(
        [
          variant_node("gid://shopify/ProductVariant/1", "null"),
          variant_node("gid://shopify/ProductVariant/2", "\"ABC-1\""),
          variant_node("gid://shopify/ProductVariant/3", "\" abc-1 \""),
          variant_node("gid://shopify/ProductVariant/4", "\"ABC-10\""),
        ],
        option.None,
      )),
    ])
  let assert Ok(found) = result
  found
  |> list.map(fn(found_variant) { found_variant.id })
  |> should.equal([
    "gid://shopify/ProductVariant/2",
    "gid://shopify/ProductVariant/3",
  ])
}

pub fn find_by_skus_follows_the_cursor_test() {
  let #(result, sent) =
    variant.find_by_skus(scripted.client(api_version.v2026_07), ["A"])
    |> scripted.run([
      scripted.ok(variant_page(
        [variant_node("gid://shopify/ProductVariant/1", "\"A\"")],
        option.Some("page-2"),
      )),
      scripted.ok(variant_page(
        [variant_node("gid://shopify/ProductVariant/9", "\"A\"")],
        option.None,
      )),
    ])
  let assert [first, second] = sent
  scripted.variable(first, ["after"], decode.optional(decode.string))
  |> should.equal(option.None)
  scripted.variable(second, ["after"], decode.string)
  |> should.equal("page-2")
  let assert Ok(found) = result
  list.length(found) |> should.equal(2)
}

pub fn set_inventory_policies_request_shape_test() {
  variant.set_inventory_policies_variables("gid://shopify/Product/1", [
    #("gid://shopify/ProductVariant/2", variant.InventoryPolicyContinue),
    #("gid://shopify/ProductVariant/3", variant.InventoryPolicyDeny),
  ])
  |> json.to_string
  |> should.equal(
    "{\"productId\":\"gid://shopify/Product/1\",\"variants\":["
    <> "{\"id\":\"gid://shopify/ProductVariant/2\",\"inventoryPolicy\":\"CONTINUE\"},"
    <> "{\"id\":\"gid://shopify/ProductVariant/3\",\"inventoryPolicy\":\"DENY\"}]}",
  )
}

pub fn bulk_update_writes_sku_and_option_value_test() {
  variant.bulk_update_variables("gid://shopify/Product/1", [
    variant.VariantUpdate(
      id: "gid://shopify/ProductVariant/2",
      price: decimal.from_hundredths(4990),
      compare_at_price: option.None,
      barcode: option.None,
      sku: option.Some("9786500000010"),
      option: option.Some(variant.OptionValue(
        option_name: "Formato",
        name: "Brochura (9786500000010)",
      )),
    ),
  ])
  |> json.to_string
  |> should.equal(
    "{\"productId\":\"gid://shopify/Product/1\",\"variants\":[{"
    <> "\"id\":\"gid://shopify/ProductVariant/2\",\"price\":\"49.90\",\"compareAtPrice\":null,"
    <> "\"inventoryItem\":{\"sku\":\"9786500000010\"},"
    <> "\"optionValues\":[{\"optionName\":\"Formato\",\"name\":\"Brochura (9786500000010)\"}]}]}",
  )
}

pub fn bulk_create_request_shape_test() {
  let new_variant =
    variant.VariantCreate(
      option_value: "E-book",
      sku: "9786500000012",
      barcode: option.None,
      price: decimal.from_hundredths(2990),
      compare_at_price: option.None,
      inventory_policy: variant.InventoryPolicyDeny,
      tracking: variant.InventoryUntracked,
    )
  let assert #(result, [sent]) =
    variant.bulk_create(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Product/7700000010",
      "Formato",
      [new_variant],
    )
    |> scripted.run([scripted.ok(fixtures.variants_bulk_create())])
  scripted.query(sent) |> string.contains("strategy: DEFAULT") |> should.be_true
  scripted.variable(sent, ["productId"], decode.string)
  |> should.equal("gid://shopify/Product/7700000010")
  scripted.variable(
    sent,
    ["variants"],
    decode.list({
      use option_names <- decode.field(
        "optionValues",
        decode.list(decode.field("optionName", decode.string, decode.success)),
      )
      use sku <- decode.subfield(["inventoryItem", "sku"], decode.string)
      use tracked <- decode.subfield(["inventoryItem", "tracked"], decode.bool)
      decode.success(#(option_names, sku, tracked))
    }),
  )
  |> should.equal([#(["Formato"], "9786500000012", False)])
  result
  |> should.equal(
    Ok([
      variant.VariantSummary(
        id: "gid://shopify/ProductVariant/4400000012",
        sku: option.Some("9786500000012"),
        inventory_item_id: "gid://shopify/InventoryItem/5500000012",
        tracking: variant.InventoryUntracked,
        selected_options: [
          variant.OptionValue(option_name: "Formato", name: "E-book"),
        ],
      ),
    ]),
  )
}

pub fn bulk_create_sends_nothing_for_no_variants_test() {
  let #(result, sent) =
    variant.bulk_create(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Product/7700000010",
      "Formato",
      [],
    )
    |> scripted.run([])
  result |> should.equal(Ok([]))
  sent |> should.equal([])
}

pub fn parse_to_hundredths_test() {
  let hundredths = fn(text) {
    let assert Ok(value) = decimal.parse(text)
    decimal.to_scaled(value, 2)
  }
  hundredths("49.9") |> should.equal(Ok(4990))
  hundredths("49.90") |> should.equal(Ok(4990))
  hundredths("0") |> should.equal(Ok(0))
  hundredths("-1.5") |> should.equal(Ok(-150))
  hundredths("0.05") |> should.equal(Ok(5))
  hundredths("1.000") |> should.equal(Ok(100))
}

pub fn to_scaled_refuses_to_drop_digits_test() {
  let assert Ok(value) = decimal.parse("1.005")
  decimal.to_scaled(value, 2)
  |> should.equal(Error(decimal.ScaleDropsDigits(scale: 2)))
  decimal.to_scaled(value, 3) |> should.equal(Ok(1005))
  decimal.to_scaled(value, 4) |> should.equal(Ok(10_050))
}

pub fn parse_rejects_junk_test() {
  decimal.parse("")
  |> should.equal(Error(decimal.DecimalInvalid(text: "")))
  decimal.parse(".5")
  |> should.equal(Error(decimal.DecimalInvalid(text: ".5")))
  decimal.parse("1.")
  |> should.equal(Error(decimal.DecimalInvalid(text: "1.")))
  decimal.parse("+1")
  |> should.equal(Error(decimal.DecimalInvalid(text: "+1")))
  decimal.parse("1e3")
  |> should.equal(Error(decimal.DecimalInvalid(text: "1e3")))
  decimal.parse("1,50")
  |> should.equal(Error(decimal.DecimalInvalid(text: "1,50")))
  decimal.parse("1.2.3")
  |> should.equal(Error(decimal.DecimalInvalid(text: "1.2.3")))
  decimal.parse("--1")
  |> should.equal(Error(decimal.DecimalInvalid(text: "--1")))
}

pub fn from_hundredths_formats_for_writes_test() {
  decimal.from_hundredths(4990) |> decimal.to_string |> should.equal("49.90")
  decimal.from_hundredths(5) |> decimal.to_string |> should.equal("0.05")
  decimal.from_hundredths(-150) |> decimal.to_string |> should.equal("-1.50")
  decimal.from_hundredths(0) |> decimal.to_string |> should.equal("0.00")
}

pub fn to_string_keeps_the_parsed_scale_test() {
  let assert Ok(value) = decimal.parse("49.9")
  decimal.to_string(value) |> should.equal("49.9")
  let assert Ok(whole) = decimal.parse("12")
  decimal.to_string(whole) |> should.equal("12")
}

pub fn compare_ignores_trailing_zeros_test() {
  let assert Ok(short) = decimal.parse("49.9")
  let assert Ok(long) = decimal.parse("49.90")
  decimal.compare(short, long) |> should.equal(order.Eq)
  decimal.compare(short, decimal.from_hundredths(5000))
  |> should.equal(order.Lt)
}

pub fn decoder_reads_json_strings_only_test() {
  json.parse("\"19.99\"", decimal.decoder())
  |> should.equal(Ok(decimal.from_hundredths(1999)))
  json.parse("19.99", decimal.decoder()) |> should.be_error
}

pub fn negative_and_scale_edges_test() {
  decimal.from_hundredths(-5) |> decimal.to_string |> should.equal("-0.05")
  let assert Ok(negative) = decimal.parse("-1.005")
  decimal.to_scaled(negative, 2)
  |> should.equal(Error(decimal.ScaleDropsDigits(scale: 2)))
  let assert Ok(negative_small) = decimal.parse("-0.05")
  decimal.to_scaled(negative_small, 2) |> should.equal(Ok(-5))
  decimal.parse("-")
  |> should.equal(Error(decimal.DecimalInvalid(text: "-")))
  decimal.parse("-.5")
  |> should.equal(Error(decimal.DecimalInvalid(text: "-.5")))
  decimal.parse("- 1")
  |> should.equal(Error(decimal.DecimalInvalid(text: "- 1")))
  let assert Ok(value) = decimal.parse("49.9")
  decimal.to_scaled(value, 0)
  |> should.equal(Error(decimal.ScaleDropsDigits(scale: 0)))
  decimal.from_scaled(units: 5, scale: -1)
  |> decimal.to_scaled(0)
  |> should.equal(Ok(50))
  decimal.from_scaled(units: 5, scale: -1)
  |> decimal.to_string
  |> should.equal("50")
}
