//// Decoders and text helpers shared by the query modules.

import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import gleam/string
import pify/error.{type UserError, UserError}

pub type PageInfo {
  PageInfo(has_next_page: Bool, end_cursor: Option(String))
}

/// One page of a connection read through `nodes`.
pub type Connection(a) {
  Connection(nodes: List(a), page_info: PageInfo)
}

/// `{ nodes { ... } pageInfo { hasNextPage endCursor } }`.
pub fn connection_decoder(
  node_decoder: decode.Decoder(a),
) -> decode.Decoder(Connection(a)) {
  use nodes <- decode.field("nodes", decode.list(node_decoder))
  use page_info <- decode.field("pageInfo", page_info_decoder())
  decode.success(Connection(nodes:, page_info:))
}

/// `{ nodes { ... } }` without paging.
pub fn nodes_decoder(
  node_decoder: decode.Decoder(a),
) -> decode.Decoder(List(a)) {
  decode.field("nodes", decode.list(node_decoder), decode.success)
}

pub fn page_info_decoder() -> decode.Decoder(PageInfo) {
  use has_next_page <- decode.field("hasNextPage", decode.bool)
  use end_cursor <- optional("endCursor", decode.string)
  decode.success(PageInfo(has_next_page:, end_cursor:))
}

/// A nullable field that may also be absent.
pub fn optional(
  name: String,
  field_decoder: decode.Decoder(a),
  next: fn(Option(a)) -> decode.Decoder(b),
) -> decode.Decoder(b) {
  decode.optional_field(name, option.None, decode.optional(field_decoder), next)
}

/// A mutation's `userErrors`. `field` is nullable in the schema.
pub fn user_errors_decoder() -> decode.Decoder(List(UserError)) {
  decode.list({
    use field <- optional("field", decode.list(decode.string))
    use message <- decode.field("message", decode.string)
    use code <- optional("code", decode.string)
    decode.success(UserError(field: option.unwrap(field, []), message:, code:))
  })
}

/// A value for Shopify search syntax (`query:` arguments). Double quotes
/// keep spaces and the operators `: ( )` inside the value, as in the
/// documented `created_at:>'2020-10-21T23:39:20Z'`. Only the backslash and
/// the double quote are escaped inside them.
pub fn search_value(text: String) -> String {
  "\"" <> escape_graphql_string(text) <> "\""
}

/// `field:"value" OR field:"value"` over every value.
pub fn search_any(field: String, values: List(String)) -> String {
  values
  |> list.map(fn(value) { field <> ":" <> search_value(value) })
  |> string.join(" OR ")
}

fn escape_graphql_string(text: String) -> String {
  text
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}
