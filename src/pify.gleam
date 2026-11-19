//// The Admin API client. Build one with `new` and pass it to the modules
//// under `pify/`. Each of their functions returns a midas `Effect`, which
//// your runner runs.
////
//// The API version is part of the `Client`. The request URL and every
//// request shape that differs between versions follow from it.

import gleam/list
import gleam/string
import pify/api_version.{type ApiVersion}

pub type Client {
  Client(
    /// An offline `shpat_` token or a client-credentials token.
    access_token: String,
    /// `<handle>.myshopify.com`, as `parse_shop_domain` returns it.
    shop_domain: String,
    version: ApiVersion,
    timeout_ms: Int,
  )
}

pub const default_timeout_ms = 20_000

pub fn new(
  access_token access_token: String,
  shop_domain shop_domain: String,
  version version: ApiVersion,
) -> Client {
  Client(access_token:, shop_domain:, version:, timeout_ms: default_timeout_ms)
}

pub fn endpoint_url(client: Client) -> String {
  "https://"
  <> client.shop_domain
  <> "/admin/api/"
  <> api_version.to_string(client.version)
  <> "/graphql.json"
}

const shop_domain_suffix = ".myshopify.com"

/// Why a text is not a shop domain. Each variant holds the normalised text
/// that failed.
pub type ShopDomainError {
  /// The host does not end in `.myshopify.com`, e.g. a custom storefront
  /// domain.
  ShopDomainNotMyshopify(domain: String)
  /// The part before `.myshopify.com` is not a lowercase handle of letters,
  /// digits and inner hyphens.
  ShopDomainInvalidHandle(handle: String)
}

pub fn shop_domain_error_to_string(error: ShopDomainError) -> String {
  case error {
    ShopDomainNotMyshopify(domain:) ->
      domain <> " is not a " <> shop_domain_suffix <> " domain"
    ShopDomainInvalidHandle(handle:) ->
      "\"" <> handle <> "\" is not a valid shop handle"
  }
}

/// Accept only `<handle>.myshopify.com`. Lowercases and trims the text and
/// strips a scheme and trailing slashes first. A custom storefront domain
/// is refused because the Admin API and webhooks name the shop by its
/// `myshopify.com` domain.
pub fn parse_shop_domain(text: String) -> Result(String, ShopDomainError) {
  let domain =
    text
    |> string.trim
    |> string.lowercase
    |> strip_scheme
    |> strip_trailing_slashes
  case string.ends_with(domain, shop_domain_suffix) {
    False -> Error(ShopDomainNotMyshopify(domain:))
    True -> {
      let handle = string.drop_end(domain, string.length(shop_domain_suffix))
      case is_handle(handle) {
        True -> Ok(domain)
        False -> Error(ShopDomainInvalidHandle(handle:))
      }
    }
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

fn is_handle(handle: String) -> Bool {
  case string.to_graphemes(handle) {
    [] -> False
    [first, ..rest] ->
      is_lower_alphanumeric(first)
      && list.all(rest, fn(grapheme) {
        is_lower_alphanumeric(grapheme) || grapheme == "-"
      })
  }
}

fn is_lower_alphanumeric(grapheme: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789", grapheme)
}
