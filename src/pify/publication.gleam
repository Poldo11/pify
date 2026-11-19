//// Sales channel publications. `productSet` puts a product on no sales
//// channel; `publish` lists it on one. Both calls need `write_scope`.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import midas/effect.{type Effect}
import pify.{type Client}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request

/// The scope `publications` and `publishablePublish` need. It grants
/// `read_publications`.
pub const write_scope = "write_publications"

/// The name Shopify gives the Online Store publication.
pub const online_store_name = "Online Store"

pub type Publication {
  Publication(id: String, name: String)
}

/// The Online Store publication's id, or `None` when the shop has no
/// Online Store channel. `Publication.name` is the only field that names
/// the channel: 2026-07 marks it deprecated, and the `catalog` it points
/// to reads null for the Online Store.
pub fn online_store(
  client: Client,
) -> Effect(Result(Option(String), ShopifyError), key) {
  all(client)
  |> execute.map(fn(publications) {
    publications
    |> list.find(fn(publication) { publication.name == online_store_name })
    |> result.map(fn(publication) { publication.id })
    |> option.from_result
  })
}

/// Every publication, across pages.
fn all(client: Client) -> Effect(Result(List(Publication), ShopifyError), key) {
  execute.collect_pages(fn(cursor) {
    request.graphql(client, list_query, list_variables(cursor))
    |> execute.run(page_decoder())
  })
}

pub const list_query =
  "query PublicationList($after: String) {"
  <> " publications(first: 50, after: $after) {"
  <> " nodes { id name }"
  <> " pageInfo { hasNextPage endCursor } } }"

pub fn list_variables(after: Option(String)) -> Json {
  json.object([#("after", json.nullable(after, json.string))])
}

fn page_decoder() -> decode.Decoder(graphql.Connection(Publication)) {
  decode.field(
    "publications",
    graphql.connection_decoder({
      use id <- decode.field("id", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(Publication(id:, name:))
    }),
    decode.success,
  )
}

/// List the product (or another publishable resource) on one publication.
/// Publishing it again changes nothing.
pub fn publish(
  client: Client,
  resource_id: String,
  publication_id: String,
) -> Effect(Result(Nil, ShopifyError), key) {
  request.graphql(
    client,
    publish_mutation,
    publish_variables(resource_id, publication_id),
  )
  |> execute.run_mutation("publishablePublish", decode.success(Nil))
}

pub const publish_mutation =
  "mutation PublishablePublish($id: ID!, $input: [PublicationInput!]!) {"
  <> " publishablePublish(id: $id, input: $input) {"
  <> " userErrors { field message } } }"

pub fn publish_variables(resource_id: String, publication_id: String) -> Json {
  json.object([
    #("id", json.string(resource_id)),
    #(
      "input",
      json.preprocessed_array([
        json.object([#("publicationId", json.string(publication_id))]),
      ]),
    ),
  ])
}
