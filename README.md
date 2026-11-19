# pify

Shopify's GraphQL Admin API, Storefront API and webhooks for Gleam.

[![Package Version](https://img.shields.io/hexpm/v/pify)](https://hex.pm/packages/pify)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pify/)

```sh
gleam add pify@2
```

pify does not send requests. Each function returns a
[midas](https://hex.pm/packages/midas) `Effect`. Your runner sends the
request and gives the response back. Use the same code on a server or in
a test with scripted responses.

- **Admin API**: orders, products, variants, inventory, locations,
  fulfillments, publications, webhook subscriptions, a connection check
  (`shop.probe`), access scopes (`shop.access_scopes`) and the
  client-credentials grant.
- **Storefront API**: products, collections and the cart.
- **Webhooks**: HMAC verification over the raw body, a dedupe key, and a
  check that the body fits its topic.

pify compiles for Erlang and JavaScript. The test suite runs on Erlang.
Use only the Storefront API in a browser. Keep the Admin token on a
server.

## Tokens

- **Admin API**: use the `shpat_` token of a custom app, or get a token
  with `auth.client_credentials(shop_domain:, client_id:, client_secret:)`.
  The shop domain must be `<handle>.myshopify.com`. Use
  `pify.parse_shop_domain` to check it.
- **Storefront API**: use a public or a private Storefront access token.
  The Storefront client also accepts the shop's own domain.

## The API version is a value

Shopify releases an API version each quarter and keeps it for about one
year. A request for a retired version does not fail. Shopify serves the
oldest version that it still has, and the shape of a field can change.

The client holds the version (`api_version.ApiVersion`). pify builds
each request for that version. `api_version.default()` is `2026-10`. To
use another version, parse it with `api_version.parse("2026-07")`.
`shop.probe` and `execute.run_served` return `execute.Served`, which
holds the version that served the response.

## Run an effect

pify uses only the `Fetch` effect. This runner uses `gleam_httpc` on
Erlang:

```gleam
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import midas/effect.{type Effect}
import pify
import pify/request as pify_request

pub fn run(task: Effect(a, key)) -> a {
  case task {
    effect.Done(value) -> value
    effect.Fetch(sent, resume) -> {
      let timeout_ms =
        request.get_header(sent, pify_request.timeout_header)
        |> result.try(int.parse)
        |> result.unwrap(pify.default_timeout_ms)
      let headers =
        list.filter(sent.headers, fn(header) {
          header.0 != pify_request.timeout_header
        })
      httpc.configure()
      |> httpc.timeout(timeout_ms)
      |> httpc.dispatch_bits(request.Request(..sent, headers:))
      |> result.map_error(fn(error) { effect.NetworkError(string.inspect(error)) })
      |> resume
      |> run
    }
    _ -> panic as "pify uses only the Fetch effect"
  }
}
```

Each request carries a timeout in milliseconds in the `x-pify-timeout-ms`
header (`pify_request.timeout_header`). The default is 20000. To change
it, set the field: `pify.Client(..client, timeout_ms: 5000)`, or use
`storefront.with_timeout(client, 5000)`. Remove the
header before you send the request. In a browser, Shopify refuses the
CORS preflight for an unknown header.

## Admin API

```gleam
import gleam/option
import pify
import pify/api_version
import pify/order

pub fn recent_orders() {
  let client =
    pify.new(
      access_token: "shpat_...",
      shop_domain: "your-shop.myshopify.com",
      version: api_version.default(),
    )
  order.list(
    client,
    order.ListParams(
      first: 50,
      after: option.None,
      updated_at_min: option.Some("2026-11-01T00:00:00Z"),
    ),
  )
  |> run
}
```

Errors are a `pify/error.ShopifyError`. A GraphQL error in a 200 response
makes the effect return `Error`. `THROTTLED` becomes
`ShopifyErrorThrottled`, and `ACCESS_DENIED` becomes
`ShopifyErrorForbidden`. The `userErrors` of a mutation become
`ShopifyErrorUserErrors`.

pify does not retry. On `ShopifyErrorThrottled(retry_after_ms: Some(ms))`,
wait `ms`, then run the effect again.

pify keeps money as a `decimal.Decimal`, not a `Float`.

## Storefront API

```gleam
import pify/api_version
import pify/storefront
import pify/storefront/cart
import pify/storefront/product

pub fn product_page(handle: String) {
  let assert Ok(client) =
    storefront.new(
      token: storefront.PublicToken("public-access-token"),
      shop_domain: "your-shop.myshopify.com",
      version: api_version.default(),
    )
  let author = storefront.MetafieldIdentifier(namespace: "custom", key: "author")
  product.by_handle(client, handle, [author])
  |> run
}

pub fn add_to_cart(client: storefront.StorefrontClient, variant_id: String) {
  cart.create(client, [
    cart.LineInput(merchandise_id: variant_id, quantity: 1, attributes: []),
  ])
  |> run
}
```

`storefront.new` checks the domain and returns `Error` for a text that is
not a host name. `cart.create` and the other cart writes return a
`cart.CartWrite`: the cart and the `warnings` of the write, such as a
quantity that Shopify reduced to the stock.

A `PublicToken` is safe in a browser. Use a `PrivateToken` only on a
server. Parse the buyer's IP with `storefront.parse_buyer_ip` and give it
to the token. pify sends it in `Shopify-Storefront-Buyer-IP`. Take the IP
from your trusted proxy's view of the client, not from a raw
`X-Forwarded-For` header that the buyer can write.

A product read returns up to 100 variants and 20 images. Each product on
a page returns up to 10 variants and its first image, so that a page
stays below Shopify's query cost limit. `has_more_variants` is `True`
when the product has more.

## Pagination

A list function returns one page. `product.list`, `collection.list` and
`collection.products` return a `graphql.Connection`. To read every page,
give the list function to `execute.collect_pages`:

```gleam
import pify/execute
import pify/storefront
import pify/storefront/product

pub fn whole_catalog(client: storefront.StorefrontClient) {
  execute.collect_pages(fn(cursor) {
    product.list(
      client,
      product.ProductPage(..product.first_page(20), after: cursor),
      [],
    )
  })
  |> run
}
```

`order.list` returns an `OrderPage`. Give its `next_cursor` to the next
`order.ListParams` as `after`.

## Webhooks

```gleam
import pify/webhook

pub fn receive(headers, body: BitArray, client_secret: String) {
  let assert Ok(delivery) = webhook.parse_headers(headers)
  let assert Ok(Nil) = webhook.verify(client_secret, body, delivery.hmac)
  let assert Ok(Nil) = webhook.check_topic(delivery.topic, body)
  let key = webhook.dedupe_key(delivery.topic, body)
  // store the delivery under `key`, answer 2xx, then read the resource again
  key
}
```

In a real handler, answer 401 when a check fails. Do not use
`let assert`: a forged request then stops the handler.

Verify the signature over the raw bytes before you parse them. Webhook
bodies use the REST shape. Deliveries can arrive out of order and more
than once. Read the reference with `webhook.order_ref`. Then read the
order again with `order.get(client, ref.admin_graphql_api_id)`. A `None`
result means that the order is deleted. Shopify ids are larger than
2^53, so decode webhook bodies on the Erlang target.

## Development

```sh
gleam test
python3 scripts/regenerate_fixtures.py  # after you edit test/fixtures/*.json
```

## License

Apache-2.0.
