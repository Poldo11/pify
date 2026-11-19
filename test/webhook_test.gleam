import fixtures
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import pify/api_version
import pify/error
import pify/webhook
import pify/webhook/subscription as webhook_subscription
import scripted

const secret = "client-secret-for-tests"

const delivery_headers = [
  #("Content-Type", "application/json"),
  #("X-Shopify-Topic", "orders/create"),
  #("X-Shopify-Hmac-Sha256", "n2CtZWL37AkCdW37bQaCUbu0JD4nMvy+i1OlyqAkCmc="),
  #("X-Shopify-Shop-Domain", "loja-exemplo.myshopify.com"),
  #("X-Shopify-API-Version", "2026-07"),
  #("X-Shopify-Webhook-Id", "b54557e4-bdd9-4b37-8a5f-bf7d70bcd043"),
  #("X-Shopify-Event-Id", "98880550-7158-44d4-b7cd-2c97c8a091b5"),
  #("X-Shopify-Triggered-At", "2026-09-20T13:07:40.000000Z"),
]

/// A signed `products/update` body: its own id and a Product GraphQL id.
const product_body =
  "{\"id\":632910392,\"admin_graphql_api_id\":\"gid://shopify/Product/632910392\",\"title\":\"Livro\",\"variants\":[]}"

/// A signed `app/uninstalled` body: the shop.
const shop_body =
  "{\"id\":548380009,\"name\":\"Loja Exemplo\",\"myshopify_domain\":\"loja-exemplo.myshopify.com\"}"

fn body(text: String) -> BitArray {
  bit_array.from_string(text)
}

pub fn parse_headers_is_case_insensitive_test() {
  webhook.parse_headers(delivery_headers)
  |> should.equal(
    Ok(webhook.Delivery(
      topic: webhook.TopicOrdersCreate,
      hmac: "n2CtZWL37AkCdW37bQaCUbu0JD4nMvy+i1OlyqAkCmc=",
      shop_domain: "loja-exemplo.myshopify.com",
      api_version: "2026-07",
      webhook_id: "b54557e4-bdd9-4b37-8a5f-bf7d70bcd043",
      event_id: option.Some("98880550-7158-44d4-b7cd-2c97c8a091b5"),
      triggered_at: option.Some("2026-09-20T13:07:40.000000Z"),
      name: option.None,
    )),
  )
}

pub fn parse_headers_reads_the_optional_name_test() {
  let assert Ok(delivery) =
    webhook.parse_headers([
      #("x-shopify-name", "loja-orders"),
      ..delivery_headers
    ])
  delivery.name |> should.equal(option.Some("loja-orders"))
}

pub fn parse_headers_names_the_missing_header_test() {
  delivery_headers
  |> list.filter(fn(header) { header.0 != "X-Shopify-Webhook-Id" })
  |> webhook.parse_headers
  |> should.equal(Error(webhook.HeaderErrorMissing(webhook.header_webhook_id)))
  webhook.parse_headers([#("x-shopify-topic", "orders/create")])
  |> should.equal(Error(webhook.HeaderErrorMissing(webhook.header_hmac)))
}

pub fn sign_and_verify_over_raw_bytes_test() {
  let raw = body(fixtures.webhook_orders_create())
  let signature = sign(secret, raw)
  webhook.verify(secret, raw, signature) |> should.equal(Ok(Nil))
  webhook.verify("other-secret", raw, signature)
  |> should.equal(Error(error.ShopifyErrorSignatureInvalid))
  webhook.verify(secret, <<raw:bits, " ":utf8>>, signature)
  |> should.equal(Error(error.ShopifyErrorSignatureInvalid))
  webhook.verify(secret, raw, "not base64!")
  |> should.equal(Error(error.ShopifyErrorSignatureInvalid))
}

pub fn verify_matches_an_independent_hmac_test() {
  let raw = body(fixtures.webhook_orders_create())
  let expected = "n2CtZWL37AkCdW37bQaCUbu0JD4nMvy+i1OlyqAkCmc="
  sign(secret, raw) |> should.equal(expected)
  let assert Ok(delivery) = webhook.parse_headers(delivery_headers)
  webhook.verify(secret, raw, delivery.hmac) |> should.equal(Ok(Nil))
  sign("hush", body("hello"))
  |> should.equal("zvT9tMFR8adPsBeM6dkn8QqflvWemcuCShl3MgGBDKI=")
  webhook.verify(secret, raw, "n2CtZWL37AkCdW37bQaCUbu0JD4nMvy+i1OlyqAkCg==")
  |> should.equal(Error(error.ShopifyErrorSignatureInvalid))
  webhook.verify(
    secret,
    raw,
    "9f60ad6562f7ec0902756dfb6d068251bbb4243e2732fcbe8b53a5caa0240a67",
  )
  |> should.equal(Error(error.ShopifyErrorSignatureInvalid))
}

pub fn verify_accepts_bytes_that_are_not_utf8_test() {
  let raw = <<0xff, 0xfe, 0x00>>
  webhook.verify(secret, raw, sign(secret, raw))
  |> should.equal(Ok(Nil))
}

pub fn verify_refuses_empty_signature_and_secret_test() {
  let raw = body("{}")
  webhook.verify(secret, raw, "  ")
  |> should.equal(Error(error.ShopifyErrorSignatureMissing))
  webhook.verify("", raw, sign("", raw))
  |> should.equal(Error(error.ShopifyErrorSignatureInvalid))
}

pub fn dedupe_key_hashes_topic_and_body_test() {
  webhook.dedupe_key(webhook.TopicOrdersCreate, body("{\"id\":1}"))
  |> should.equal(
    "69b26a246fbaca998549289dfe5f7a48cb1abe980205f749444048811e6bd993",
  )
}

pub fn dedupe_key_keeps_two_topics_with_one_body_apart_test() {
  webhook.dedupe_key(webhook.TopicOrdersUpdated, body("{\"id\":1}"))
  |> should.equal(
    "9eb3ac98c81c732099fc7bf1dd8beaa2ff11ed40761ddc46c10dbddc3c7ca92a",
  )
}

pub fn dedupe_key_takes_an_unknown_topic_and_raw_bytes_test() {
  webhook.dedupe_key(webhook.TopicUnknown("custom/topic"), <<0xff, 0xfe>>)
  |> should.equal(
    "ce812e24fb810177577fac4bbf3e8477ccfa0b168f366c78dcc283684a7f57d3",
  )
}

pub fn check_topic_holds_orders_to_their_shape_test() {
  let create = body(fixtures.webhook_orders_create())
  let delete = body(fixtures.webhook_orders_delete())
  let edited = body(fixtures.webhook_orders_edited())
  webhook.check_topic(webhook.TopicOrdersCreate, create)
  |> should.equal(Ok(Nil))
  webhook.check_topic(webhook.TopicOrdersPaid, create) |> should.equal(Ok(Nil))
  webhook.check_topic(webhook.TopicOrdersDelete, delete)
  |> should.equal(Ok(Nil))
  webhook.check_topic(webhook.TopicOrdersEdited, edited)
  |> should.equal(Ok(Nil))
  webhook.check_topic(webhook.TopicOrdersDelete, create)
  |> should.equal(Error(error.ShopifyErrorTopicBodyMismatch("orders/delete")))
  webhook.check_topic(webhook.TopicOrdersUpdated, delete)
  |> should.equal(Error(error.ShopifyErrorTopicBodyMismatch("orders/updated")))
  webhook.check_topic(webhook.TopicProductsUpdate, create)
  |> should.equal(Error(error.ShopifyErrorTopicBodyMismatch("products/update")))
  webhook.check_topic(webhook.TopicOrdersCreate, body("not json"))
  |> should.equal(Error(error.ShopifyErrorTopicBodyMismatch("orders/create")))
  webhook.check_topic(webhook.TopicUnknown("carts/update"), body("{}"))
  |> should.equal(Ok(Nil))
}

pub fn check_topic_holds_a_delete_to_a_bare_id_test() {
  assert_mismatch(webhook.TopicOrdersDelete, product_body)
  assert_mismatch(webhook.TopicOrdersDelete, shop_body)
  assert_mismatch(webhook.TopicProductsDelete, fixtures.webhook_orders_create())
  assert_mismatch(webhook.TopicOrdersDelete, "{\"id\":\"x\"}")
  assert_mismatch(webhook.TopicProductsDelete, "{\"id\":\"x\"}")
  webhook.check_topic(
    webhook.TopicProductsDelete,
    body(fixtures.webhook_orders_delete()),
  )
  |> should.equal(Ok(Nil))
}

pub fn order_ref_from_a_full_body_test() {
  webhook.order_ref(body(fixtures.webhook_orders_create()))
  |> should.equal(
    Ok(webhook.OrderRef(
      id: 820_982_911_946_154_508,
      admin_graphql_api_id: "gid://shopify/Order/820982911946154508",
      name: option.Some("#1001"),
      updated_at: option.Some("2026-09-20T10:07:40-03:00"),
    )),
  )
}

pub fn order_ref_builds_the_gid_for_a_delete_body_test() {
  webhook.order_ref(body(fixtures.webhook_orders_delete()))
  |> should.equal(
    Ok(webhook.OrderRef(
      id: 820_982_911_946_154_508,
      admin_graphql_api_id: "gid://shopify/Order/820982911946154508",
      name: option.None,
      updated_at: option.None,
    )),
  )
}

pub fn order_ref_reads_an_order_edit_test() {
  let assert Ok(ref) = webhook.order_ref(body(fixtures.webhook_orders_edited()))
  ref.admin_graphql_api_id
  |> should.equal("gid://shopify/Order/820982911946154508")
}

pub fn order_ref_rejects_a_body_without_an_id_test() {
  let assert Error(error.ShopifyErrorDecode(_)) =
    webhook.order_ref(body("{\"name\":\"#1001\"}"))
}

pub fn order_ref_rejects_another_resource_gid_test() {
  let assert Error(error.ShopifyErrorDecode(_)) =
    webhook.order_ref(body(product_body))
}

pub fn order_ref_and_check_topic_refuse_a_null_gid_test() {
  let null_gid = "{\"id\":450789469,\"admin_graphql_api_id\":null}"
  let assert Error(error.ShopifyErrorDecode(_)) =
    webhook.order_ref(body(null_gid))
  assert_mismatch(webhook.TopicOrdersUpdated, null_gid)
}

pub fn topic_round_trip_test() {
  webhook.parse_topic("orders/partially_fulfilled")
  |> should.equal(webhook.TopicOrdersPartiallyFulfilled)
  webhook.parse_topic("carts/update")
  |> should.equal(webhook.TopicUnknown("carts/update"))
  webhook.topic_to_string(webhook.TopicInventoryLevelsUpdate)
  |> should.equal("inventory_levels/update")
  webhook.topic_to_graphql_enum(webhook.TopicOrdersDelete)
  |> should.equal(Ok("ORDERS_DELETE"))
  webhook.topic_to_graphql_enum(webhook.TopicUnknown("carts/update"))
  |> should.equal(Error(error.ShopifyErrorTopicUnsupported("carts/update")))
}

const inventory_level_body =
  "{\"inventory_item_id\":271878346596884015,\"location_id\":24826418,\"available\":1,\"updated_at\":\"2026-09-20T10:07:40-03:00\",\"admin_graphql_api_id\":\"gid://shopify/InventoryLevel/24826418?inventory_item_id=271878346596884015\"}"

pub fn check_topic_accepts_every_known_shape_test() {
  let fits = fn(topic, text) { webhook.check_topic(topic, body(text)) }
  fits(webhook.TopicProductsCreate, product_body) |> should.equal(Ok(Nil))
  fits(webhook.TopicProductsUpdate, product_body) |> should.equal(Ok(Nil))
  fits(webhook.TopicAppUninstalled, shop_body) |> should.equal(Ok(Nil))
  fits(webhook.TopicInventoryLevelsUpdate, inventory_level_body)
  |> should.equal(Ok(Nil))
  fits(webhook.TopicOrdersEdited, fixtures.webhook_orders_create())
  |> should.equal(Ok(Nil))
}

pub fn check_topic_refuses_another_resource_body_test() {
  [
    webhook.TopicProductsCreate,
    webhook.TopicProductsUpdate,
    webhook.TopicAppUninstalled,
    webhook.TopicInventoryLevelsUpdate,
  ]
  |> list.each(fn(topic) {
    assert_mismatch(topic, fixtures.webhook_orders_create())
    assert_mismatch(topic, fixtures.webhook_orders_delete())
  })
  assert_mismatch(webhook.TopicOrdersEdited, product_body)
  assert_mismatch(
    webhook.TopicInventoryLevelsUpdate,
    "{\"inventory_item_id\":1}",
  )
}

pub fn every_topic_round_trips_test() {
  [
    webhook.TopicOrdersCreate,
    webhook.TopicOrdersUpdated,
    webhook.TopicOrdersCancelled,
    webhook.TopicOrdersDelete,
    webhook.TopicOrdersFulfilled,
    webhook.TopicOrdersPaid,
    webhook.TopicOrdersPartiallyFulfilled,
    webhook.TopicOrdersEdited,
    webhook.TopicProductsCreate,
    webhook.TopicProductsUpdate,
    webhook.TopicProductsDelete,
    webhook.TopicInventoryLevelsUpdate,
    webhook.TopicAppUninstalled,
  ]
  |> list.each(fn(topic) {
    webhook.parse_topic(webhook.topic_to_string(topic)) |> should.equal(topic)
  })
}

/// The signature Shopify sends for `body`: base64(HMAC-SHA256(secret, body)).
fn sign(secret: String, body: BitArray) -> String {
  crypto.hmac(body, crypto.Sha256, bit_array.from_string(secret))
  |> bit_array.base64_encode(True)
}

const uri = "https://erp.example.com/api/webhooks/shopify"

fn create(version: api_version.ApiVersion, topic: webhook.Topic) {
  webhook_subscription.create(
    scripted.client(version),
    topic:,
    uri:,
    name: option.Some("loja-orders"),
  )
  |> scripted.run([scripted.ok(fixtures.webhook_subscription_create())])
}

pub fn list_decodes_subscriptions_test() {
  let #(result, _) =
    webhook_subscription.list(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(fixtures.webhook_subscriptions())])
  result
  |> should.equal(
    Ok([
      webhook_subscription.Subscription(
        id: "gid://shopify/WebhookSubscription/8800000001",
        topic: "ORDERS_CREATE",
        uri:,
        api_version: option.Some("2026-07"),
      ),
      webhook_subscription.Subscription(
        id: "gid://shopify/WebhookSubscription/8800000002",
        topic: "ORDERS_DELETE",
        uri:,
        api_version: option.Some("2026-04"),
      ),
    ]),
  )
}

pub fn create_sends_uri_and_name_from_2026_04_test() {
  let assert #(result, [sent]) =
    create(api_version.v2026_07, webhook.TopicOrdersUpdated)
  let assert Ok(created) = result
  created.topic |> should.equal("ORDERS_UPDATED")
  scripted.variable(sent, ["topic"], decode.string)
  |> should.equal("ORDERS_UPDATED")
  scripted.variable(sent, ["webhookSubscription", "uri"], decode.string)
  |> should.equal(uri)
  scripted.variable(sent, ["webhookSubscription", "name"], decode.string)
  |> should.equal("loja-orders")
  scripted.body(sent) |> string.contains("callbackUrl") |> should.be_false
}

pub fn create_sends_name_from_exactly_2026_04_test() {
  let assert #(_, [sent]) =
    create(api_version.v2026_04, webhook.TopicOrdersCreate)
  scripted.variable(sent, ["webhookSubscription", "name"], decode.string)
  |> should.equal("loja-orders")
  scripted.variable(sent, ["webhookSubscription", "format"], decode.string)
  |> should.equal("JSON")
  let assert #(_, [unnamed]) =
    webhook_subscription.create(
      scripted.client(api_version.v2026_07),
      topic: webhook.TopicOrdersCreate,
      uri:,
      name: option.None,
    )
    |> scripted.run([scripted.ok(fixtures.webhook_subscription_create())])
  scripted.has_variable(unnamed, ["webhookSubscription", "name"])
  |> should.be_false
}

pub fn create_drops_name_before_2026_04_test() {
  let assert #(_, [sent]) =
    create(api_version.v2026_01, webhook.TopicOrdersUpdated)
  scripted.has_variable(sent, ["webhookSubscription", "name"])
  |> should.be_false
  scripted.variable(sent, ["webhookSubscription", "uri"], decode.string)
  |> should.equal(uri)
}

pub fn create_refuses_an_unknown_topic_test() {
  let #(result, sent) =
    create(api_version.v2026_07, webhook.TopicUnknown("carts/update"))
  result
  |> should.equal(Error(error.ShopifyErrorTopicUnsupported("carts/update")))
  sent |> should.equal([])
}

pub fn create_surfaces_user_errors_test() {
  let #(result, _) =
    webhook_subscription.create(
      scripted.client(api_version.v2026_07),
      topic: webhook.TopicOrdersCreate,
      uri: "http://not-https",
      name: option.None,
    )
    |> scripted.run([
      scripted.ok(
        "{\"data\":{\"webhookSubscriptionCreate\":{\"webhookSubscription\":null,"
        <> "\"userErrors\":[{\"field\":[\"webhookSubscription\",\"callbackUrl\"],"
        <> "\"message\":\"Address protocol http:// is not supported\"}]}}}",
      ),
    ])
  result
  |> should.equal(
    Error(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: ["webhookSubscription", "callbackUrl"],
          message: "Address protocol http:// is not supported",
          code: option.None,
        ),
      ]),
    ),
  )
}

fn assert_mismatch(topic: webhook.Topic, text: String) -> Nil {
  webhook.check_topic(topic, body(text))
  |> should.equal(
    Error(error.ShopifyErrorTopicBodyMismatch(webhook.topic_to_string(topic))),
  )
}
