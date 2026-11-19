//// Target-agnostic request building. Execution lives in `execute`.

import gleam/bit_array
import gleam/http
import gleam/http/request.{type Request}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import pify.{type Client}

pub type ShopifyRequest {
  ShopifyRequest(url: String, headers: List(#(String, String)), body: String)
}

/// The header that carries `Client.timeout_ms` to whatever runs the
/// effect. midas `Fetch` has no timeout slot, so the runner reads this
/// header, strips it and bounds the call. It never reaches Shopify.
pub const timeout_header = "x-pify-timeout-ms"

pub fn graphql(
  client: Client,
  query: String,
  variables: Json,
) -> ShopifyRequest {
  graphql_at(
    url: pify.endpoint_url(client),
    token_headers: [#("x-shopify-access-token", client.access_token)],
    query:,
    variables:,
    timeout_ms: client.timeout_ms,
  )
}

/// A GraphQL POST to `url` with the token headers of the Admin or the
/// Storefront API.
pub fn graphql_at(
  url url: String,
  token_headers token_headers: List(#(String, String)),
  query query: String,
  variables variables: Json,
  timeout_ms timeout_ms: Int,
) -> ShopifyRequest {
  ShopifyRequest(
    url:,
    headers: list.append(token_headers, json_headers(timeout_ms)),
    body: json.to_string(
      json.object([#("query", json.string(query)), #("variables", variables)]),
    ),
  )
}

/// A JSON POST with no access token, such as the client-credentials grant.
pub fn post_json(url: String, body: Json, timeout_ms: Int) -> ShopifyRequest {
  ShopifyRequest(
    url:,
    headers: json_headers(timeout_ms),
    body: json.to_string(body),
  )
}

/// A request url the http request type cannot hold. `text` stops before
/// the query, which can carry a token.
pub type ShopifyRequestError {
  ShopifyRequestUrlInvalid(text: String)
}

pub fn to_http_request(
  shopify_request: ShopifyRequest,
) -> Result(Request(BitArray), ShopifyRequestError) {
  use base <- result.try(case request.to(shopify_request.url) {
    Ok(base) -> Ok(base)
    Error(Nil) ->
      Error(ShopifyRequestUrlInvalid(text: without_query(shopify_request.url)))
  })
  base
  |> request.set_method(http.Post)
  |> set_headers(shopify_request.headers)
  |> request.set_body(bit_array.from_string(shopify_request.body))
  |> Ok
}

fn without_query(url: String) -> String {
  case string.split(url, "?") {
    [head, ..] -> head
    [] -> url
  }
}

fn json_headers(timeout_ms: Int) -> List(#(String, String)) {
  [
    #("content-type", "application/json"),
    #("accept", "application/json"),
    #(timeout_header, int.to_string(timeout_ms)),
  ]
}

fn set_headers(
  http_request: Request(String),
  headers: List(#(String, String)),
) -> Request(String) {
  list.fold(headers, http_request, fn(built, header) {
    request.set_header(built, header.0, header.1)
  })
}
