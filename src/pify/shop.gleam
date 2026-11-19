//// The shop the token belongs to and the scopes it holds. These are the
//// cheapest authenticated reads, so they make a good connection check.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify.{type Client}
import pify/error.{type ShopifyError}
import pify/execute.{type Served}
import pify/graphql
import pify/order
import pify/request

pub type Shop {
  Shop(
    name: String,
    myshopify_domain: String,
    /// The shop's currency. Order money read through `shopMoney` is in it.
    currency_code: String,
    plan_name: Option(String),
    /// `taxesIncluded`: whether the shop's product prices hold the tax.
    tax_pricing: order.TaxPricing,
  )
}

/// Keeps the served version, so a connection test can report that Shopify
/// fell forward from a retired version.
pub fn probe(
  client: Client,
) -> Effect(Result(Served(Shop), ShopifyError), key) {
  request.graphql(client, query, json.object([]))
  |> execute.run_served(decoder())
}

pub const query =
  "query ShopProbe { shop {"
  <> " name myshopifyDomain currencyCode taxesIncluded"
  <> " plan { publicDisplayName } } }"

/// The scope handles granted to the token, such as `read_orders`. A missing
/// write scope surfaces here before a write fails with `ACCESS_DENIED`.
pub fn access_scopes(
  client: Client,
) -> Effect(Result(List(String), ShopifyError), key) {
  request.graphql(client, access_scopes_query, json.object([]))
  |> execute.run(access_scopes_decoder())
}

pub const access_scopes_query =
  "query AppAccessScopes {"
  <> " currentAppInstallation { accessScopes { handle } } }"

pub fn access_scopes_decoder() -> decode.Decoder(List(String)) {
  decode.subfield(
    ["currentAppInstallation", "accessScopes"],
    decode.list(decode.field("handle", decode.string, decode.success)),
    decode.success,
  )
}

pub fn decoder() -> decode.Decoder(Shop) {
  use name <- decode.subfield(["shop", "name"], decode.string)
  use myshopify_domain <- decode.subfield(
    ["shop", "myshopifyDomain"],
    decode.string,
  )
  use currency_code <- decode.subfield(["shop", "currencyCode"], decode.string)
  use tax_pricing <- decode.subfield(
    ["shop", "taxesIncluded"],
    decode.bool |> decode.map(order.tax_pricing_from_bool),
  )
  use plan_name <- decode.field("shop", {
    use plan <- graphql.optional("plan", {
      use plan_name <- graphql.optional("publicDisplayName", decode.string)
      decode.success(plan_name)
    })
    decode.success(option.flatten(plan))
  })
  decode.success(Shop(
    name:,
    myshopify_domain:,
    currency_code:,
    plan_name:,
    tax_pricing:,
  ))
}
