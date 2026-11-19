//// Stock locations. Inventory quantities live per item per location.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify.{type Client}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request

pub type Location {
  Location(
    id: String,
    name: String,
    is_active: Bool,
    fulfills_online_orders: Bool,
  )
}

/// Every active location, across pages.
pub fn list(
  client: Client,
) -> Effect(Result(List(Location), ShopifyError), key) {
  execute.collect_pages(fn(cursor) {
    request.graphql(client, query, variables(cursor))
    |> execute.run(page_decoder())
  })
}

pub const query =
  "query LocationList($after: String) {"
  <> " locations(first: 50, after: $after, includeInactive: false) {"
  <> " nodes { id name isActive fulfillsOnlineOrders }"
  <> " pageInfo { hasNextPage endCursor } } }"

pub fn variables(after: Option(String)) -> json.Json {
  json.object([#("after", json.nullable(after, json.string))])
}

pub fn page_decoder() -> decode.Decoder(graphql.Connection(Location)) {
  decode.field(
    "locations",
    graphql.connection_decoder(location_decoder()),
    decode.success,
  )
}

fn location_decoder() -> decode.Decoder(Location) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use is_active <- decode.field("isActive", decode.bool)
  use fulfills_online_orders <- decode.field(
    "fulfillsOnlineOrders",
    decode.bool,
  )
  decode.success(Location(id:, name:, is_active:, fulfills_online_orders:))
}
