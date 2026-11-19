//// Shopify Storefront GraphQL API client and the values its reads share.
////
//// The Storefront API is the buyer-facing API: products, collections and
//// the cart. A public token is safe in a browser. A private token belongs
//// on a server, which forwards the buyer's IP.

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import pify/api_version.{type ApiVersion}
import pify/graphql
import pify/request.{type ShopifyRequest}

pub type StorefrontToken {
  /// Sent as `X-Shopify-Storefront-Access-Token`. Safe in a browser.
  PublicToken(token: String)
  /// Sent as `Shopify-Storefront-Private-Token`, from a server only. The
  /// buyer's IP rides `Shopify-Storefront-Buyer-IP`, so Shopify throttles
  /// each buyer apart.
  PrivateToken(token: String, buyer_ip: Option(BuyerIp))
}

/// Only `new` builds one, so the host a token goes to is always checked.
pub opaque type StorefrontClient {
  StorefrontClient(
    token: StorefrontToken,
    shop_domain: String,
    version: ApiVersion,
    timeout_ms: Int,
  )
}

pub type StorefrontDomainError {
  /// Not a host name of dot-separated labels of letters, digits and inner
  /// hyphens. Holds the normalised text.
  StorefrontDomainInvalid(domain: String)
}

pub const default_timeout_ms = 20_000

/// `shop_domain` is `<handle>.myshopify.com` or the shop's own domain.
pub fn new(
  token token: StorefrontToken,
  shop_domain shop_domain: String,
  version version: ApiVersion,
) -> Result(StorefrontClient, StorefrontDomainError) {
  use shop_domain <- result.map(parse_domain(shop_domain))
  StorefrontClient(
    token:,
    shop_domain:,
    version:,
    timeout_ms: default_timeout_ms,
  )
}

pub fn with_timeout(
  client: StorefrontClient,
  timeout_ms: Int,
) -> StorefrontClient {
  StorefrontClient(..client, timeout_ms:)
}

/// Lowercases and trims the text and strips a scheme and trailing slashes.
/// Anything that could move the request to another host, such as `/`, `@`,
/// `:`, `?` or `#`, is refused.
pub fn parse_domain(text: String) -> Result(String, StorefrontDomainError) {
  let domain =
    text
    |> string.trim
    |> string.lowercase
    |> strip_scheme
    |> strip_trailing_slashes
  let labels = string.split(domain, ".")
  let is_host =
    string.length(domain) <= 253
    && list.length(labels) >= 2
    && list.all(labels, is_label)
  case is_host {
    True -> Ok(domain)
    False -> Error(StorefrontDomainInvalid(domain:))
  }
}

fn strip_scheme(text: String) -> String {
  case text {
    "https://" <> rest -> rest
    "http://" <> rest -> rest
    _ -> text
  }
}

fn strip_trailing_slashes(text: String) -> String {
  case string.ends_with(text, "/") {
    True -> strip_trailing_slashes(string.drop_end(text, 1))
    False -> text
  }
}

fn is_label(label: String) -> Bool {
  let graphemes = string.to_graphemes(label)
  case graphemes, list.last(graphemes) {
    [first, ..], Ok(last) ->
      first != "-"
      && last != "-"
      && list.length(graphemes) <= 63
      && list.all(graphemes, fn(grapheme) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", grapheme)
      })
    _, _ -> False
  }
}

/// The buyer's IPv4 or IPv6 address. Take it from the trusted proxy's view
/// of the client, never from a raw `X-Forwarded-For` the buyer can write.
pub opaque type BuyerIp {
  BuyerIp(text: String)
}

pub type BuyerIpError {
  BuyerIpInvalid(text: String)
}

/// Accepts hex digits, `.` and `:` only, so the value cannot break a header.
pub fn parse_buyer_ip(text: String) -> Result(BuyerIp, BuyerIpError) {
  let trimmed = string.trim(text)
  let graphemes = string.to_graphemes(trimmed)
  let separated = list.contains(graphemes, ".") || list.contains(graphemes, ":")
  let allowed =
    list.all(graphemes, fn(grapheme) {
      string.contains("0123456789abcdefABCDEF.:", grapheme)
    })
  case separated && allowed && list.length(graphemes) <= 45 {
    True -> Ok(BuyerIp(trimmed))
    False -> Error(BuyerIpInvalid(text: trimmed))
  }
}

pub fn buyer_ip_to_string(buyer_ip: BuyerIp) -> String {
  buyer_ip.text
}

pub fn endpoint_url(client: StorefrontClient) -> String {
  "https://"
  <> client.shop_domain
  <> "/api/"
  <> api_version.to_string(client.version)
  <> "/graphql.json"
}

pub fn graphql(
  client: StorefrontClient,
  query: String,
  variables: Json,
) -> ShopifyRequest {
  request.graphql_at(
    url: endpoint_url(client),
    token_headers: token_headers(client.token),
    query:,
    variables:,
    timeout_ms: client.timeout_ms,
  )
}

fn token_headers(token: StorefrontToken) -> List(#(String, String)) {
  case token {
    PublicToken(token:) -> [#("x-shopify-storefront-access-token", token)]
    PrivateToken(token:, buyer_ip: option.Some(buyer_ip)) -> [
      #("shopify-storefront-private-token", token),
      #("shopify-storefront-buyer-ip", buyer_ip.text),
    ]
    PrivateToken(token:, buyer_ip: option.None) -> [
      #("shopify-storefront-private-token", token),
    ]
  }
}

/// One page of a list read.
pub type Page {
  Page(first: Int, after: Option(String))
}

pub const max_page_size = 250

/// `first` and `after`, then `arguments`. `first` is held between 1 and
/// `max_page_size`.
pub fn page_variables(
  first: Int,
  after: Option(String),
  arguments: List(#(String, Json)),
) -> Json {
  json.object([
    #("first", json.int(int.clamp(first, 1, max_page_size))),
    #("after", json.nullable(after, json.string)),
    ..arguments
  ])
}

pub type Image {
  Image(
    url: String,
    alt_text: Option(String),
    width: Option(Int),
    height: Option(Int),
  )
}

pub const image_fields = " url altText width height"

pub fn image_decoder() -> decode.Decoder(Image) {
  use url <- decode.field("url", decode.string)
  use alt_text <- graphql.optional("altText", decode.string)
  use width <- graphql.optional("width", decode.int)
  use height <- graphql.optional("height", decode.int)
  decode.success(Image(url:, alt_text:, width:, height:))
}

pub type Seo {
  Seo(title: Option(String), description: Option(String))
}

pub const seo_fields = " seo { title description }"

pub fn seo_decoder() -> decode.Decoder(Seo) {
  use title <- graphql.optional("title", decode.string)
  use description <- graphql.optional("description", decode.string)
  decode.success(Seo(title:, description:))
}

pub type SelectedOption {
  SelectedOption(name: String, value: String)
}

pub const selected_options_fields = " selectedOptions { name value }"

pub fn selected_option_decoder() -> decode.Decoder(SelectedOption) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(SelectedOption(name:, value:))
}

/// A metafield a read asks for. The Storefront API answers only the
/// metafields the shop exposes to it.
pub type MetafieldIdentifier {
  MetafieldIdentifier(namespace: String, key: String)
}

pub type Metafield {
  Metafield(namespace: String, key: String, value: String, value_type: String)
}

/// Selects the metafields named by the `$identifiers` variable.
pub const metafields_fields =
  " metafields(identifiers: $identifiers) { namespace key value type }"

pub fn metafield_identifiers_to_json(
  identifiers: List(MetafieldIdentifier),
) -> Json {
  json.array(identifiers, fn(identifier) {
    json.object([
      #("namespace", json.string(identifier.namespace)),
      #("key", json.string(identifier.key)),
    ])
  })
}

/// A metafield the shop does not have reads as null and is left out.
pub fn metafields_decoder() -> decode.Decoder(List(Metafield)) {
  decode.list(decode.optional(metafield_decoder()))
  |> decode.map(option.values)
}

fn metafield_decoder() -> decode.Decoder(Metafield) {
  use namespace <- decode.field("namespace", decode.string)
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.string)
  use value_type <- decode.field("type", decode.string)
  decode.success(Metafield(namespace:, key:, value:, value_type:))
}
