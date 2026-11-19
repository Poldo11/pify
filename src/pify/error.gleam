//// One error type for the whole library.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type ShopifyError {
  /// Shopify answered with a GraphQL error that no other variant names,
  /// or with an HTTP status outside the mapped set.
  ShopifyErrorApi(message: String, code: Option(String))
  /// HTTP 401, or a token request refused with 400 or 401. The token is
  /// wrong or expired.
  ShopifyErrorAuthentication
  /// HTTP 403, or `ACCESS_DENIED` in a 200. The token lacks a scope.
  ShopifyErrorForbidden(message: String)
  /// HTTP 404: the shop domain or the version path is wrong.
  ShopifyErrorNotFound
  /// HTTP 402 (the shop is frozen for payment) or 423 (the shop is locked).
  ShopifyErrorShopUnavailable(status: Int)
  /// HTTP 429, or `THROTTLED` in a 200. Wait `retry_after_ms` when known.
  ShopifyErrorThrottled(retry_after_ms: Option(Int))
  ShopifyErrorServer(status: Int)
  /// The request never got an answer, including a call the effect runner
  /// stopped at `Client.timeout_ms`.
  ShopifyErrorNetwork(message: String)
  /// The body is JSON, but not the shape the decoder expects.
  ShopifyErrorDecode(errors: List(decode.DecodeError))
  /// The body is not JSON.
  ShopifyErrorMalformedJson(cause: json.DecodeError)
  /// A mutation ran and refused the input.
  ShopifyErrorUserErrors(errors: List(UserError))
  ShopifyErrorSignatureInvalid
  ShopifyErrorSignatureMissing
  /// The unsigned topic header does not fit the signed body's shape.
  ShopifyErrorTopicBodyMismatch(topic: String)
  /// The topic has no subscription enum, so it cannot be subscribed to.
  ShopifyErrorTopicUnsupported(topic: String)
}

/// One entry of a mutation's `userErrors`. `field` is the input path.
pub type UserError {
  UserError(field: List(String), message: String, code: Option(String))
}

/// The one place a `json.DecodeError` becomes a `ShopifyError`: a shape
/// mismatch keeps its field errors, anything else keeps the parser's cause.
pub fn from_json(json_error: json.DecodeError) -> ShopifyError {
  case json_error {
    json.UnableToDecode(errors) -> ShopifyErrorDecode(errors)
    json.UnexpectedEndOfInput
    | json.UnexpectedByte(_)
    | json.UnexpectedSequence(_) -> ShopifyErrorMalformedJson(json_error)
  }
}

/// A line for logs. It carries no token, secret or body.
pub fn to_string(error: ShopifyError) -> String {
  case error {
    ShopifyErrorApi(message:, code: option.Some(code)) ->
      "Shopify API error " <> code <> ": " <> message
    ShopifyErrorApi(message:, code: option.None) ->
      "Shopify API error: " <> message
    ShopifyErrorAuthentication -> "Shopify rejected the access token"
    ShopifyErrorForbidden(message:) -> "Shopify denied access: " <> message
    ShopifyErrorNotFound -> "Shopify answered 404 for the shop or version"
    ShopifyErrorShopUnavailable(status:) ->
      "Shopify shop unavailable (HTTP " <> int.to_string(status) <> ")"
    ShopifyErrorThrottled(retry_after_ms: option.Some(wait_ms)) ->
      "Shopify throttled the request, retry after "
      <> int.to_string(wait_ms)
      <> " ms"
    ShopifyErrorThrottled(retry_after_ms: option.None) ->
      "Shopify throttled the request"
    ShopifyErrorServer(status:) ->
      "Shopify server error (HTTP " <> int.to_string(status) <> ")"
    ShopifyErrorNetwork(message:) -> "Network error: " <> message
    ShopifyErrorDecode(errors:) ->
      "Unexpected Shopify response shape: " <> describe_decode_errors(errors)
    ShopifyErrorMalformedJson(cause:) ->
      "Shopify response is not JSON: " <> string.inspect(cause)
    ShopifyErrorUserErrors(errors:) ->
      "Shopify refused the input: "
      <> string.join(list.map(errors, describe_user_error), "; ")
    ShopifyErrorSignatureInvalid -> "Webhook signature does not match the body"
    ShopifyErrorSignatureMissing -> "Webhook signature header is empty"
    ShopifyErrorTopicBodyMismatch(topic:) ->
      "Webhook body does not fit topic " <> topic
    ShopifyErrorTopicUnsupported(topic:) ->
      "Webhook topic has no subscription enum: " <> topic
  }
}

fn describe_user_error(user_error: UserError) -> String {
  let field = case user_error.field {
    [] -> ""
    path -> string.join(path, ".") <> ": "
  }
  let code = case user_error.code {
    option.Some(code) -> " (" <> code <> ")"
    option.None -> ""
  }
  field <> user_error.message <> code
}

fn describe_decode_errors(errors: List(decode.DecodeError)) -> String {
  errors
  |> list.map(fn(decode_error) {
    "expected "
    <> decode_error.expected
    <> " at "
    <> string.join(decode_error.path, ".")
    <> ", found "
    <> decode_error.found
  })
  |> string.join("; ")
}
