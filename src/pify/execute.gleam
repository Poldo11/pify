//// Effect-based execution. Turns a `ShopifyRequest` plus a decoder into a
//// midas `Effect` that fetches, maps the HTTP status and the GraphQL
//// envelope, and decodes `data`.
////
//// Shopify reports some failures inside an HTTP 200: `THROTTLED` and
//// `ACCESS_DENIED` arrive as `errors[].extensions.code`. Any entry in
//// `errors` fails the call, even when `data` is present, because a field
//// that errored reads as null.

import gleam/dynamic/decode
import gleam/float
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import midas/effect.{type Effect}
import pify/decimal
import pify/error.{type ShopifyError, type UserError}
import pify/graphql.{type Connection}
import pify/request.{type ShopifyRequest}

/// A decoded response and the API version that served it, read from
/// `X-Shopify-API-Version`. Shopify serves the oldest accessible version
/// when the requested one is retired.
pub type Served(a) {
  Served(value: a, served_version: Option(String))
}

pub const served_version_header = "x-shopify-api-version"

/// Shopify's advice when a throttle carries no timing.
const minimum_throttle_wait_ms = 1000

pub fn run(
  shopify_request: ShopifyRequest,
  decoder: decode.Decoder(a),
) -> Effect(Result(a, ShopifyError), key) {
  run_served(shopify_request, decoder)
  |> map(fn(served) { served.value })
}

pub fn run_served(
  shopify_request: ShopifyRequest,
  decoder: decode.Decoder(a),
) -> Effect(Result(Served(a), ShopifyError), key) {
  send(shopify_request, fn(response) { handle_response(response, decoder) })
}

/// Run a mutation whose payload sits at `data.<field>` next to a
/// `userErrors` list. A non-empty list fails with `ShopifyErrorUserErrors`
/// before `decoder` reads the payload.
pub fn run_mutation(
  shopify_request: ShopifyRequest,
  field: String,
  decoder: decode.Decoder(a),
) -> Effect(Result(a, ShopifyError), key) {
  run(
    shopify_request,
    decode.field(field, payload_decoder(decoder), decode.success),
  )
  |> then(fn(payload) {
    case payload {
      Ok(value) -> Ok(value)
      Error(user_errors) -> Error(error.ShopifyErrorUserErrors(user_errors))
    }
  })
}

/// Fetch and hand the raw response to `handle`.
pub fn send(
  shopify_request: ShopifyRequest,
  handle: fn(Response(BitArray)) -> Result(a, ShopifyError),
) -> Effect(Result(a, ShopifyError), key) {
  case request.to_http_request(shopify_request) {
    Error(request.ShopifyRequestUrlInvalid(text:)) ->
      effect.Done(
        Error(error.ShopifyErrorNetwork("invalid request URL: " <> text)),
      )
    Ok(http_request) ->
      effect.Fetch(http_request, fn(fetch_result) {
        fetch_result
        |> result.map_error(map_fetch_error)
        |> result.try(handle)
        |> effect.Done
      })
  }
}

/// Follow `pageInfo.endCursor` until the last page and keep every node.
pub fn collect_pages(
  fetch_page: fn(Option(String)) ->
    Effect(Result(Connection(a), ShopifyError), key),
) -> Effect(Result(List(a), ShopifyError), key) {
  collect_pages_from(fetch_page, option.None, [])
}

fn collect_pages_from(
  fetch_page: fn(Option(String)) ->
    Effect(Result(Connection(a), ShopifyError), key),
  cursor: Option(String),
  collected: List(List(a)),
) -> Effect(Result(List(a), ShopifyError), key) {
  use page <- effect.do(fetch_page(cursor))
  case page {
    Error(shopify_error) -> effect.Done(Error(shopify_error))
    Ok(connection) -> {
      let collected = [connection.nodes, ..collected]
      case connection.page_info {
        graphql.PageInfo(has_next_page: True, end_cursor: option.Some(next)) ->
          collect_pages_from(fetch_page, option.Some(next), collected)
        graphql.PageInfo(has_next_page: True, end_cursor: option.None)
        | graphql.PageInfo(has_next_page: False, ..) ->
          effect.Done(Ok(list.flatten(list.reverse(collected))))
      }
    }
  }
}

/// Run one effect per item, in order, and stop at the first error.
pub fn try_each(
  items: List(a),
  run_one: fn(a) -> Effect(Result(b, ShopifyError), key),
) -> Effect(Result(List(b), ShopifyError), key) {
  try_each_from(items, run_one, [])
}

fn try_each_from(
  items: List(a),
  run_one: fn(a) -> Effect(Result(b, ShopifyError), key),
  done: List(b),
) -> Effect(Result(List(b), ShopifyError), key) {
  case items {
    [] -> effect.Done(Ok(list.reverse(done)))
    [item, ..rest] -> {
      use outcome <- effect.do(run_one(item))
      case outcome {
        Error(shopify_error) -> effect.Done(Error(shopify_error))
        Ok(value) -> try_each_from(rest, run_one, [value, ..done])
      }
    }
  }
}

pub fn map(
  task: Effect(Result(a, ShopifyError), key),
  transform: fn(a) -> b,
) -> Effect(Result(b, ShopifyError), key) {
  then(task, fn(value) { Ok(transform(value)) })
}

pub fn then(
  task: Effect(Result(a, ShopifyError), key),
  next: fn(a) -> Result(b, ShopifyError),
) -> Effect(Result(b, ShopifyError), key) {
  use outcome <- effect.do(task)
  effect.Done(result.try(outcome, next))
}

/// Map the HTTP status, then the GraphQL envelope, then decode `data`.
pub fn handle_response(
  response: Response(BitArray),
  decoder: decode.Decoder(a),
) -> Result(Served(a), ShopifyError) {
  use Nil <- result.try(check_status(response))
  decode_envelope(response.body, decoder)
  |> result.map(Served(
    _,
    served_version: header(response, served_version_header),
  ))
}

/// Fail on every status outside 2xx with the mapped `ShopifyError`.
pub fn check_status(response: Response(BitArray)) -> Result(Nil, ShopifyError) {
  case response.status {
    status if status >= 200 && status < 300 -> Ok(Nil)
    401 -> Error(error.ShopifyErrorAuthentication)
    402 -> Error(error.ShopifyErrorShopUnavailable(402))
    403 -> Error(error.ShopifyErrorForbidden(body_message(response.body)))
    404 -> Error(error.ShopifyErrorNotFound)
    423 -> Error(error.ShopifyErrorShopUnavailable(423))
    429 ->
      Error(
        error.ShopifyErrorThrottled(
          retry_after_ms(header(response, "retry-after")),
        ),
      )
    status if status >= 500 -> Error(error.ShopifyErrorServer(status))
    status ->
      Error(error.ShopifyErrorApi(
        message: "HTTP "
          <> int.to_string(status)
          <> ": "
          <> body_message(response.body),
        code: option.None,
      ))
  }
}

pub fn decode_envelope(
  body: BitArray,
  decoder: decode.Decoder(a),
) -> Result(a, ShopifyError) {
  use envelope <- result.try(
    json.parse_bits(body, envelope_decoder())
    |> result.map_error(error.from_json),
  )
  case envelope.errors {
    [] ->
      json.parse_bits(body, decode.at(["data"], decoder))
      |> result.map_error(error.from_json)
    errors -> Error(classify_errors(errors, envelope.throttle))
  }
}

pub fn header(response: Response(a), name: String) -> Option(String) {
  response.headers
  |> list.find(fn(entry) { string.lowercase(entry.0) == name })
  |> result.map(fn(entry) { entry.1 })
  |> option.from_result
}

type GraphqlError {
  GraphqlError(message: String, code: Option(String))
}

type Throttle {
  Throttle(requested: Int, available: Int, restore_rate: Int)
}

type Envelope {
  Envelope(errors: List(GraphqlError), throttle: Option(Throttle))
}

fn classify_errors(
  errors: List(GraphqlError),
  throttle: Option(Throttle),
) -> ShopifyError {
  let has_code = fn(code) {
    list.any(errors, fn(entry) { entry.code == option.Some(code) })
  }
  case has_code("THROTTLED"), has_code("ACCESS_DENIED"), errors {
    True, _, _ ->
      error.ShopifyErrorThrottled(option.map(throttle, throttle_wait_ms))
    False, True, _ ->
      error.ShopifyErrorForbidden(
        errors
        |> list.filter(fn(entry) { entry.code == option.Some("ACCESS_DENIED") })
        |> list.map(fn(entry) { entry.message })
        |> string.join("; "),
      )
    False, False, [first, ..] ->
      error.ShopifyErrorApi(message: first.message, code: first.code)
    False, False, [] ->
      error.ShopifyErrorApi(message: "empty errors list", code: option.None)
  }
}

/// Seconds until the bucket holds the requested cost, rounded up, at least
/// one second.
fn throttle_wait_ms(throttle: Throttle) -> Int {
  let missing = throttle.requested - throttle.available
  let seconds = case missing > 0 && throttle.restore_rate > 0 {
    True -> { missing + throttle.restore_rate - 1 } / throttle.restore_rate
    False -> 1
  }
  int.max(seconds * 1000, minimum_throttle_wait_ms)
}

/// `Retry-After` is in seconds and may carry a fraction, such as `2.0`. A
/// zero or negative value waits the minimum.
fn retry_after_ms(value: Option(String)) -> Option(Int) {
  use text <- option.then(value)
  use seconds <- option.then(decimal.parse(text) |> option.from_result)
  decimal.to_scaled(seconds, 3)
  |> option.from_result
  |> option.map(int.max(_, minimum_throttle_wait_ms))
}

fn envelope_decoder() -> decode.Decoder(Envelope) {
  use errors <- decode.optional_field("errors", [], errors_decoder())
  use throttle <- decode.optional_field(
    "extensions",
    option.None,
    decode.one_of(
      decode.at(["cost"], throttle_decoder()) |> decode.map(option.Some),
      [decode.success(option.None)],
    ),
  )
  decode.success(Envelope(errors:, throttle:))
}

fn errors_decoder() -> decode.Decoder(List(GraphqlError)) {
  decode.one_of(decode.list(graphql_error_decoder()), [
    decode.string
      |> decode.map(fn(message) { [GraphqlError(message:, code: option.None)] }),
    decode.success([]),
  ])
}

fn graphql_error_decoder() -> decode.Decoder(GraphqlError) {
  use message <- decode.optional_field("message", "unknown", decode.string)
  use code <- decode.optional_field(
    "extensions",
    option.None,
    decode.one_of(
      decode.at(["code"], decode.string) |> decode.map(option.Some),
      [
        decode.success(option.None),
      ],
    ),
  )
  decode.success(GraphqlError(message:, code:))
}

fn throttle_decoder() -> decode.Decoder(Throttle) {
  use requested <- decode.field("requestedQueryCost", whole_number())
  use available <- decode.subfield(
    ["throttleStatus", "currentlyAvailable"],
    whole_number(),
  )
  use restore_rate <- decode.subfield(
    ["throttleStatus", "restoreRate"],
    whole_number(),
  )
  decode.success(Throttle(requested:, available:, restore_rate:))
}

/// Cost figures arrive as integers or as floats such as `100.0`.
fn whole_number() -> decode.Decoder(Int) {
  decode.one_of(decode.int, [
    decode.float
    |> decode.map(fn(value) { float.truncate(float.ceiling(value)) }),
  ])
}

fn payload_decoder(
  decoder: decode.Decoder(a),
) -> decode.Decoder(Result(a, List(UserError))) {
  use user_errors <- decode.optional_field(
    "userErrors",
    [],
    graphql.user_errors_decoder(),
  )
  case user_errors {
    [] -> decode.map(decoder, Ok)
    [_, ..] -> decode.success(Error(user_errors))
  }
}

fn body_message(body: BitArray) -> String {
  case json.parse_bits(body, decode.at(["errors"], errors_decoder())) {
    Ok([first, ..]) -> first.message
    Ok([]) | Error(_) -> "no message"
  }
}

fn map_fetch_error(fetch_error: effect.FetchError) -> ShopifyError {
  case fetch_error {
    effect.NetworkError(message) -> error.ShopifyErrorNetwork(message)
    effect.UnableToReadBody -> error.ShopifyErrorNetwork("unable to read body")
    effect.NotImplemented -> error.ShopifyErrorNetwork("fetch not implemented")
  }
}
