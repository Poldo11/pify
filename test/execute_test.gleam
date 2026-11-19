import fixtures
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option
import gleeunit/should
import midas/effect
import pify/api_version
import pify/error
import pify/execute
import pify/order
import pify/request
import scripted

fn reply(status: Int, body: String) -> response.Response(BitArray) {
  response.new(status) |> response.set_body(bit_array.from_string(body))
}

pub fn graphql_request_shape_test() {
  let client = scripted.client(api_version.v2026_07)
  let assert Ok(http_request) =
    request.graphql(client, "query { shop { name } }", json.object([]))
    |> request.to_http_request
  http_request.method |> should.equal(http.Post)
  http_request.host |> should.equal("loja-exemplo.myshopify.com")
  http_request.path |> should.equal("/admin/api/2026-07/graphql.json")
  let header = fn(name) {
    list.key_find(http_request.headers, name) |> option.from_result
  }
  header("x-shopify-access-token") |> should.equal(option.Some("shpat_test"))
  header("content-type") |> should.equal(option.Some("application/json"))
  header("accept") |> should.equal(option.Some("application/json"))
  header(request.timeout_header) |> should.equal(option.Some("20000"))
  scripted.query(http_request) |> should.equal("query { shop { name } }")
}

pub fn status_mapping_test() {
  let status_error = fn(status) {
    execute.handle_response(reply(status, "{}"), decode.success(Nil))
  }
  status_error(401) |> should.equal(Error(error.ShopifyErrorAuthentication))
  status_error(402)
  |> should.equal(Error(error.ShopifyErrorShopUnavailable(402)))
  status_error(404) |> should.equal(Error(error.ShopifyErrorNotFound))
  status_error(423)
  |> should.equal(Error(error.ShopifyErrorShopUnavailable(423)))
  status_error(503) |> should.equal(Error(error.ShopifyErrorServer(503)))
  status_error(400)
  |> should.equal(
    Error(error.ShopifyErrorApi(
      message: "HTTP 400: no message",
      code: option.None,
    )),
  )
}

pub fn forbidden_keeps_the_message_test() {
  execute.handle_response(
    reply(403, "{\"errors\":\"[API] This action requires merchant approval\"}"),
    decode.success(Nil),
  )
  |> should.equal(
    Error(error.ShopifyErrorForbidden(
      "[API] This action requires merchant approval",
    )),
  )
}

pub fn http_429_reads_retry_after_seconds_test() {
  let throttled =
    response.Response(..reply(429, ""), headers: [#("Retry-After", "2.0")])
  execute.handle_response(throttled, decode.success(Nil))
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(2000))))
  execute.handle_response(reply(429, ""), decode.success(Nil))
  |> should.equal(Error(error.ShopifyErrorThrottled(option.None)))
}

pub fn http_429_waits_at_least_one_second_test() {
  let retry_after = fn(value) {
    response.Response(..reply(429, ""), headers: [#("Retry-After", value)])
    |> execute.handle_response(decode.success(Nil))
  }
  retry_after("0")
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(1000))))
  retry_after("-1")
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(1000))))
}

pub fn throttled_in_a_200_computes_the_wait_test() {
  execute.handle_response(reply(200, fixtures.throttled()), decode.success(Nil))
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(7000))))
}

fn throttled(cost: String) {
  execute.handle_response(
    reply(
      200,
      "{\"errors\":[{\"message\":\"T\",\"extensions\":{\"code\":\"THROTTLED\"}}],\"extensions\":{\"cost\":"
        <> cost
        <> "}}",
    ),
    decode.success(Nil),
  )
}

pub fn throttled_wait_rounds_up_test() {
  throttled(
    "{\"requestedQueryCost\":101,\"throttleStatus\":{\"currentlyAvailable\":0,\"restoreRate\":100}}",
  )
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(2000))))
  throttled(
    "{\"requestedQueryCost\":101,\"throttleStatus\":{\"currentlyAvailable\":0,\"restoreRate\":0}}",
  )
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(1000))))
  throttled("{\"requestedQueryCost\":101}")
  |> should.equal(Error(error.ShopifyErrorThrottled(option.None)))
}

pub fn throttled_without_cost_has_no_wait_test() {
  execute.handle_response(
    reply(
      200,
      "{\"errors\":[{\"message\":\"Throttled\",\"extensions\":{\"code\":\"THROTTLED\"}}]}",
    ),
    decode.success(Nil),
  )
  |> should.equal(Error(error.ShopifyErrorThrottled(option.None)))
}

pub fn throttled_wait_is_at_least_one_second_test() {
  execute.handle_response(
    reply(
      200,
      "{\"errors\":[{\"message\":\"Throttled\",\"extensions\":{\"code\":\"THROTTLED\"}}],"
        <> "\"extensions\":{\"cost\":{\"requestedQueryCost\":50,\"actualQueryCost\":null,"
        <> "\"throttleStatus\":{\"maximumAvailable\":1000.0,\"currentlyAvailable\":49.5,\"restoreRate\":50.0}}}}",
    ),
    decode.success(Nil),
  )
  |> should.equal(Error(error.ShopifyErrorThrottled(option.Some(1000))))
}

pub fn access_denied_in_a_200_is_forbidden_test() {
  let assert Error(error.ShopifyErrorForbidden(message)) =
    execute.handle_response(
      reply(200, fixtures.access_denied()),
      order.get_decoder(),
    )
  message
  |> should.equal(
    "Access denied for customer field. Required access: `read_customers` access scope.",
  )
}

pub fn other_graphql_error_is_api_test() {
  execute.handle_response(
    reply(
      200,
      "{\"errors\":[{\"message\":\"Field 'x' doesn't exist on type 'Order'\",\"extensions\":{\"code\":\"undefinedField\"}}]}",
    ),
    decode.success(Nil),
  )
  |> should.equal(
    Error(error.ShopifyErrorApi(
      message: "Field 'x' doesn't exist on type 'Order'",
      code: option.Some("undefinedField"),
    )),
  )
}

pub fn served_version_comes_from_the_header_test() {
  let served =
    response.Response(..reply(200, fixtures.shop()), headers: [
      #("X-Shopify-API-Version", "2025-10"),
    ])
  let assert Ok(execute.Served(value: _, served_version:)) =
    execute.handle_response(served, decode.success(Nil))
  served_version |> should.equal(option.Some("2025-10"))
}

pub fn non_json_body_is_malformed_test() {
  let assert Error(error.ShopifyErrorMalformedJson(_)) =
    execute.handle_response(reply(200, "<html>"), decode.success(Nil))
}

pub fn wrong_shape_is_decode_test() {
  let assert Error(error.ShopifyErrorDecode(_)) =
    execute.handle_response(
      reply(200, "{\"data\":{}}"),
      decode.at(["shop"], decode.string),
    )
}

pub fn network_failure_is_network_error_test() {
  let task =
    request.graphql(
      scripted.client(api_version.v2026_07),
      "query { shop { name } }",
      json.object([]),
    )
    |> execute.run(decode.success(Nil))
  let assert effect.Fetch(_, resume) = task
  resume(Error(effect.NetworkError("connection refused")))
  |> should.equal(
    effect.Done(Error(error.ShopifyErrorNetwork("connection refused"))),
  )
}

pub fn runner_timeout_is_network_error_test() {
  let task =
    request.graphql(
      scripted.client(api_version.v2026_07),
      "query { shop { name } }",
      json.object([]),
    )
    |> execute.run(decode.success(Nil))
  let assert effect.Fetch(_, resume) = task
  resume(Error(effect.NetworkError("timed out after 20000ms")))
  |> should.equal(
    effect.Done(Error(error.ShopifyErrorNetwork("timed out after 20000ms"))),
  )
}
