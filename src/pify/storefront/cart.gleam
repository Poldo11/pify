//// The Storefront cart: create one, read it, add, change and remove its
//// lines, and set its note. Every write answers the whole cart. The buyer
//// pays at `checkout_url`.
////
//// A refused write fails with `ShopifyErrorUserErrors`, which holds the
//// cart's `userErrors`. A write Shopify adjusted, such as a quantity cut to
//// the stock, succeeds and reports the adjustment in `warnings`.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/money.{type Money}
import pify/request.{type ShopifyRequest}
import pify/storefront.{type StorefrontClient}
import pify/storefront/product.{type Variant}

pub type Cart {
  Cart(
    id: String,
    checkout_url: String,
    total_quantity: Int,
    note: Option(String),
    subtotal: Money,
    total: Money,
    lines: List(CartLine),
    /// The cart has more than `max_lines` lines.
    has_more_lines: Bool,
  )
}

pub type CartLine {
  CartLine(
    id: String,
    quantity: Int,
    total: Money,
    attributes: List(Attribute),
    merchandise: Merchandise,
  )
}

/// The variant a line buys and the product it belongs to.
pub type Merchandise {
  Merchandise(
    variant: Variant,
    product_id: String,
    product_handle: String,
    product_title: String,
  )
}

pub type Attribute {
  Attribute(key: String, value: Option(String))
}

pub type LineInput {
  LineInput(merchandise_id: String, quantity: Int, attributes: List(Attribute))
}

pub type LineUpdate {
  LineUpdate(line_id: String, quantity: Int)
}

/// A change Shopify made to a write instead of refusing it. `code` is a
/// `CartWarningCode`, such as `MERCHANDISE_NOT_ENOUGH_STOCK`, and `target` the
/// id of the line or merchandise it concerns.
pub type CartWarning {
  CartWarning(code: String, message: String, target: String)
}

/// The cart a write answers and the warnings it raised.
pub type CartWrite {
  CartWrite(cart: Cart, warnings: List(CartWarning))
}

pub const max_lines = 100

pub const fields =
  " id checkoutUrl totalQuantity note"
  <> " cost { subtotalAmount {"
  <> money.fields
  <> " } totalAmount {"
  <> money.fields
  <> " } }"
  <> " lines(first: 100) { nodes { id quantity"
  <> " attributes { key value }"
  <> " cost { totalAmount {"
  <> money.fields
  <> " } }"
  <> " merchandise { ... on ProductVariant {"
  <> product.variant_fields
  <> " product { id handle title } } } }"
  <> " pageInfo { hasNextPage } }"

const payload =
  " cart {"
  <> fields
  <> " } userErrors { field message code }"
  <> " warnings { code message target }"

pub const get_query =
  "query StorefrontCart($cartId: ID!) { cart(id: $cartId) {" <> fields <> " } }"

/// `Ok(None)` when the cart does not exist or was checked out.
pub fn get(
  client: StorefrontClient,
  cart_id: String,
) -> Effect(Result(Option(Cart), ShopifyError), key) {
  storefront.graphql(
    client,
    get_query,
    json.object([#("cartId", json.string(cart_id))]),
  )
  |> execute.run(decode.field(
    "cart",
    decode.optional(decoder()),
    decode.success,
  ))
}

pub const create_mutation =
  "mutation StorefrontCartCreate($input: CartInput!) {"
  <> " cartCreate(input: $input) {"
  <> payload
  <> " } }"

pub fn create(
  client: StorefrontClient,
  lines: List(LineInput),
) -> Effect(Result(CartWrite, ShopifyError), key) {
  storefront.graphql(
    client,
    create_mutation,
    json.object([
      #(
        "input",
        json.object([#("lines", json.array(lines, line_input_to_json))]),
      ),
    ]),
  )
  |> run_cart_mutation("cartCreate")
}

pub const lines_add_mutation =
  "mutation StorefrontCartLinesAdd($cartId: ID!, $lines: [CartLineInput!]!) {"
  <> " cartLinesAdd(cartId: $cartId, lines: $lines) {"
  <> payload
  <> " } }"

pub fn add_lines(
  client: StorefrontClient,
  cart_id: String,
  lines: List(LineInput),
) -> Effect(Result(CartWrite, ShopifyError), key) {
  storefront.graphql(
    client,
    lines_add_mutation,
    cart_variables(cart_id, #("lines", json.array(lines, line_input_to_json))),
  )
  |> run_cart_mutation("cartLinesAdd")
}

pub const lines_update_mutation =
  "mutation StorefrontCartLinesUpdate($cartId: ID!, $lines: [CartLineUpdateInput!]!) {"
  <> " cartLinesUpdate(cartId: $cartId, lines: $lines) {"
  <> payload
  <> " } }"

/// A quantity of zero removes the line.
pub fn update_lines(
  client: StorefrontClient,
  cart_id: String,
  updates: List(LineUpdate),
) -> Effect(Result(CartWrite, ShopifyError), key) {
  storefront.graphql(
    client,
    lines_update_mutation,
    cart_variables(cart_id, #("lines", json.array(updates, line_update_to_json))),
  )
  |> run_cart_mutation("cartLinesUpdate")
}

pub const lines_remove_mutation =
  "mutation StorefrontCartLinesRemove($cartId: ID!, $lineIds: [ID!]!) {"
  <> " cartLinesRemove(cartId: $cartId, lineIds: $lineIds) {"
  <> payload
  <> " } }"

pub fn remove_lines(
  client: StorefrontClient,
  cart_id: String,
  line_ids: List(String),
) -> Effect(Result(CartWrite, ShopifyError), key) {
  storefront.graphql(
    client,
    lines_remove_mutation,
    cart_variables(cart_id, #("lineIds", json.array(line_ids, json.string))),
  )
  |> run_cart_mutation("cartLinesRemove")
}

pub const note_update_mutation =
  "mutation StorefrontCartNoteUpdate($cartId: ID!, $note: String!) {"
  <> " cartNoteUpdate(cartId: $cartId, note: $note) {"
  <> payload
  <> " } }"

pub fn update_note(
  client: StorefrontClient,
  cart_id: String,
  note: String,
) -> Effect(Result(CartWrite, ShopifyError), key) {
  storefront.graphql(
    client,
    note_update_mutation,
    cart_variables(cart_id, #("note", json.string(note))),
  )
  |> run_cart_mutation("cartNoteUpdate")
}

fn run_cart_mutation(
  shopify_request: ShopifyRequest,
  field: String,
) -> Effect(Result(CartWrite, ShopifyError), key) {
  execute.run_mutation(shopify_request, field, write_decoder())
}

fn write_decoder() -> decode.Decoder(CartWrite) {
  use cart <- decode.field("cart", decoder())
  use warnings <- decode.optional_field(
    "warnings",
    [],
    decode.list(warning_decoder()),
  )
  decode.success(CartWrite(cart:, warnings:))
}

fn warning_decoder() -> decode.Decoder(CartWarning) {
  use code <- decode.field("code", decode.string)
  use message <- decode.field("message", decode.string)
  use target <- decode.field("target", decode.string)
  decode.success(CartWarning(code:, message:, target:))
}

fn cart_variables(cart_id: String, argument: #(String, Json)) -> Json {
  json.object([#("cartId", json.string(cart_id)), argument])
}

pub fn line_input_to_json(line: LineInput) -> Json {
  json.object([
    #("merchandiseId", json.string(line.merchandise_id)),
    #("quantity", json.int(line.quantity)),
    #("attributes", json.array(line.attributes, attribute_to_json)),
  ])
}

pub fn line_update_to_json(update: LineUpdate) -> Json {
  json.object([
    #("id", json.string(update.line_id)),
    #("quantity", json.int(update.quantity)),
  ])
}

fn attribute_to_json(attribute: Attribute) -> Json {
  json.object([
    #("key", json.string(attribute.key)),
    #("value", json.nullable(attribute.value, json.string)),
  ])
}

pub fn decoder() -> decode.Decoder(Cart) {
  use id <- decode.field("id", decode.string)
  use checkout_url <- decode.field("checkoutUrl", decode.string)
  use total_quantity <- decode.field("totalQuantity", decode.int)
  use note <- graphql.optional("note", decode.string)
  use subtotal <- decode.subfield(["cost", "subtotalAmount"], money.decoder())
  use total <- decode.subfield(["cost", "totalAmount"], money.decoder())
  use lines <- decode.field("lines", graphql.connection_decoder(line_decoder()))
  decode.success(Cart(
    id:,
    checkout_url:,
    total_quantity:,
    note:,
    subtotal:,
    total:,
    lines: lines.nodes,
    has_more_lines: lines.page_info.has_next_page,
  ))
}

fn line_decoder() -> decode.Decoder(CartLine) {
  use id <- decode.field("id", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  use total <- decode.subfield(["cost", "totalAmount"], money.decoder())
  use attributes <- decode.field("attributes", decode.list(attribute_decoder()))
  use merchandise <- decode.field("merchandise", merchandise_decoder())
  decode.success(CartLine(id:, quantity:, total:, attributes:, merchandise:))
}

fn attribute_decoder() -> decode.Decoder(Attribute) {
  use key <- decode.field("key", decode.string)
  use value <- graphql.optional("value", decode.string)
  decode.success(Attribute(key:, value:))
}

fn merchandise_decoder() -> decode.Decoder(Merchandise) {
  use variant <- decode.then(product.variant_decoder())
  use product_id <- decode.subfield(["product", "id"], decode.string)
  use product_handle <- decode.subfield(["product", "handle"], decode.string)
  use product_title <- decode.subfield(["product", "title"], decode.string)
  decode.success(Merchandise(
    variant:,
    product_id:,
    product_handle:,
    product_title:,
  ))
}
