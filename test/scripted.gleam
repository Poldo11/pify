//// Runs an effect against scripted replies and records every request.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/json
import gleam/list
import midas/effect.{type Effect}
import pify
import pify/api_version.{type ApiVersion}

pub type Reply {
  Reply(status: Int, headers: List(#(String, String)), body: String)
}

pub fn ok(body: String) -> Reply {
  Reply(status: 200, headers: [], body:)
}

pub fn client(version: ApiVersion) -> pify.Client {
  pify.new(
    access_token: "shpat_test",
    shop_domain: "loja-exemplo.myshopify.com",
    version:,
  )
}

/// Answer each `Fetch` with the next reply, in order.
pub fn run(
  task: Effect(a, key),
  replies: List(Reply),
) -> #(a, List(Request(BitArray))) {
  loop(task, replies, [])
}

fn loop(
  task: Effect(a, key),
  replies: List(Reply),
  sent: List(Request(BitArray)),
) -> #(a, List(Request(BitArray))) {
  case task, replies {
    effect.Done(value), _ -> #(value, list.reverse(sent))
    effect.Fetch(sent_request, resume), [reply, ..rest] -> {
      let answer =
        response.new(reply.status)
        |> response.set_body(bit_array.from_string(reply.body))
      let answer = response.Response(..answer, headers: reply.headers)
      loop(resume(Ok(answer)), rest, [sent_request, ..sent])
    }
    effect.Fetch(..), [] -> panic as "no scripted reply left"
    _, _ -> panic as "unexpected effect"
  }
}

pub fn body(sent_request: Request(BitArray)) -> String {
  let assert Ok(text) = bit_array.to_string(sent_request.body)
  text
}

/// Read one value from the request's GraphQL `variables`.
pub fn variable(
  sent_request: Request(BitArray),
  path: List(String),
  decoder: decode.Decoder(a),
) -> a {
  let assert Ok(value) =
    json.parse(body(sent_request), decode.at(["variables", ..path], decoder))
  value
}

pub fn query(sent_request: Request(BitArray)) -> String {
  let assert Ok(text) =
    json.parse(body(sent_request), decode.at(["query"], decode.string))
  text
}

/// True when the variables hold `path`, whatever its value.
pub fn has_variable(
  sent_request: Request(BitArray),
  path: List(String),
) -> Bool {
  let parsed =
    json.parse(
      body(sent_request),
      decode.at(["variables", ..path], decode.dynamic),
    )
  case parsed {
    Ok(_) -> True
    Error(_) -> False
  }
}
