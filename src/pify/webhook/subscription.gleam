//// Webhook subscriptions the app owns on one shop.
////
//// Shopify deletes a subscription made through the Admin API after eight
//// failed deliveries in a row, so a consumer lists them and creates what is
//// missing. A subscription reports the version it serializes bodies with;
//// compare it with the `X-Shopify-API-Version` of each delivery.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify.{type Client}
import pify/api_version.{type ApiVersion}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request
import pify/webhook.{type Topic}

pub type Subscription {
  Subscription(
    id: String,
    /// The `WebhookSubscriptionTopic` enum value, such as `ORDERS_CREATE`.
    topic: String,
    uri: String,
    /// The version handle bodies are serialized with, such as `2026-07`.
    api_version: Option(String),
  )
}

/// From this version a subscription takes a `name`, which Shopify sends
/// back in `X-Shopify-Name`.
pub const name_since = api_version.v2026_04

pub fn list(
  client: Client,
) -> Effect(Result(List(Subscription), ShopifyError), key) {
  execute.collect_pages(fn(cursor) {
    request.graphql(client, list_query, list_variables(cursor))
    |> execute.run(list_decoder())
  })
}

pub const list_query =
  "query WebhookSubscriptionList($after: String) {"
  <> " webhookSubscriptions(first: 100, after: $after) {"
  <> " nodes { id topic uri apiVersion { handle } }"
  <> " pageInfo { hasNextPage endCursor } } }"

pub fn list_variables(after: Option(String)) -> Json {
  json.object([#("after", json.nullable(after, json.string))])
}

pub fn list_decoder() -> decode.Decoder(graphql.Connection(Subscription)) {
  decode.field(
    "webhookSubscriptions",
    graphql.connection_decoder(subscription_decoder()),
    decode.success,
  )
}

/// Subscribe `uri` to `topic`. `name` is sent only to versions that take
/// it and is dropped for older ones.
pub fn create(
  client: Client,
  topic topic: Topic,
  uri uri: String,
  name name: Option(String),
) -> Effect(Result(Subscription, ShopifyError), key) {
  case webhook.topic_to_graphql_enum(topic) {
    Error(unsupported) -> effect.Done(Error(unsupported))
    Ok(topic_enum) ->
      request.graphql(
        client,
        create_mutation,
        create_variables(client.version, topic_enum, uri, name),
      )
      |> execute.run_mutation(
        "webhookSubscriptionCreate",
        decode.field(
          "webhookSubscription",
          subscription_decoder(),
          decode.success,
        ),
      )
  }
}

pub const create_mutation =
  "mutation WebhookSubscriptionCreate($topic: WebhookSubscriptionTopic!, $webhookSubscription: WebhookSubscriptionInput!) {"
  <> " webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {"
  <> " webhookSubscription { id topic uri apiVersion { handle } }"
  <> " userErrors { field message } } }"

pub fn create_variables(
  version: ApiVersion,
  topic_enum: String,
  uri: String,
  name: Option(String),
) -> Json {
  let named = case name, api_version.at_least(version, name_since) {
    option.Some(name), True -> [#("name", json.string(name))]
    option.Some(_), False | option.None, _ -> []
  }
  json.object([
    #("topic", json.string(topic_enum)),
    #(
      "webhookSubscription",
      json.object([
        #("uri", json.string(uri)),
        #("format", json.string("JSON")),
        ..named
      ]),
    ),
  ])
}

fn subscription_decoder() -> decode.Decoder(Subscription) {
  use id <- decode.field("id", decode.string)
  use topic <- decode.field("topic", decode.string)
  use uri <- decode.field("uri", decode.string)
  use api_version <- graphql.optional("apiVersion", {
    use handle <- graphql.optional("handle", decode.string)
    decode.success(handle)
  })
  decode.success(Subscription(
    id:,
    topic:,
    uri:,
    api_version: option.flatten(api_version),
  ))
}
