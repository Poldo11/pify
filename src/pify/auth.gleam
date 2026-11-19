//// The client-credentials grant for apps made in the Dev Dashboard.
////
//// Such an app has no static token. It trades its client id and secret for
//// an access token that lasts about 24 hours. The library holds no state:
//// the consumer caches the token and asks for a new one before
//// `expires_in_seconds` runs out. A legacy custom app keeps its static
//// `shpat_` token and never calls this module.

import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import midas/effect.{type Effect}
import pify
import pify/error.{type ShopifyError}
import pify/execute
import pify/request.{type ShopifyRequest}

pub type AccessToken {
  AccessToken(token: String, scope: List(String), expires_in_seconds: Int)
}

pub fn client_credentials(
  shop_domain shop_domain: String,
  client_id client_id: String,
  client_secret client_secret: String,
) -> Effect(Result(AccessToken, ShopifyError), key) {
  client_credentials_request(shop_domain:, client_id:, client_secret:)
  |> execute.send(handle_response)
}

pub fn client_credentials_request(
  shop_domain shop_domain: String,
  client_id client_id: String,
  client_secret client_secret: String,
) -> ShopifyRequest {
  request.post_json(
    "https://" <> shop_domain <> "/admin/oauth/access_token",
    json.object([
      #("client_id", json.string(client_id)),
      #("client_secret", json.string(client_secret)),
      #("grant_type", json.string("client_credentials")),
    ]),
    pify.default_timeout_ms,
  )
}

/// Shopify answers a wrong id or secret with 400 or 401.
pub fn handle_response(
  response: Response(BitArray),
) -> Result(AccessToken, ShopifyError) {
  case response.status {
    400 | 401 -> Error(error.ShopifyErrorAuthentication)
    _ -> {
      use Nil <- result.try(execute.check_status(response))
      json.parse_bits(response.body, access_token_decoder())
      |> result.map_error(error.from_json)
    }
  }
}

fn access_token_decoder() -> decode.Decoder(AccessToken) {
  use token <- decode.field("access_token", decode.string)
  use scope <- decode.optional_field(
    "scope",
    "",
    decode.optional(decode.string) |> decode.map(option.unwrap(_, "")),
  )
  use expires_in_seconds <- decode.field("expires_in", decode.int)
  decode.success(AccessToken(
    token:,
    scope: split_scope(scope),
    expires_in_seconds:,
  ))
}

fn split_scope(scope: String) -> List(String) {
  scope
  |> string.split(",")
  |> list.map(string.trim)
  |> list.filter(fn(entry) { !string.is_empty(entry) })
}
