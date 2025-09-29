# pify

[WIP – Not ready for production]

[![Package Version](https://img.shields.io/hexpm/v/pify)](https://hex.pm/packages/pify)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pify/)

```sh
gleam add pify@1
```
```gleam
// Envoy is not a dependency of this library. I'm using it here just to illustrate a real world use.
import envoy
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import storefront.{type StorefrontApiClientConfig}
import storefront/fragments.{product_fragment}
import storefront/products.{
  get_product_query, get_products_operation_decoder, product_decoder,
  reshape_product, reshape_products,
}
import storefront/utils

/// Place your keys and secrets in a .env file
/// Pass them to your Shopify Client
/// Use your client to fetch products
/// Or create your own fetcher passing the arguments from fetch().
pub fn main() -> Nil {
  let assert Ok(key) = envoy.get("SHOPIFY_ADMIN_KEY")
  let assert Ok(domain) = envoy.get("SHOPIFY_URL")
  let assert Ok(api_version) = envoy.get("SHOPIFY_API_VERSION")

  // Pass your env keys to create a Admin client.
  let config =
    storefront.CreateAdminApiClient(
      api_version: api_version,
      // This is your store_domain url.
      store_domain: domain,
      // To connect to Admin API Shopify, we have to provide a private key..
      access_token: key,
      // "retries" is inactive for now.
      retries: Some(0),
      // "client_name" has no value for now.
    )

  // This will give you a AdminApiClientConfig type, that you have to pass to all your fetches.
  let assert Ok(client) = storefront.create_admin_api_client(config)

  // By convention, I've used client to extend the functions for ShopifyHandler. Below, you will see some examples.
  let client = storefront.admin_handler(client)

  Nil
}

/// Example of a fetch that takes no variables
///
///
fn get_product(_req: Request, ctx: Context, handle: String) -> Response  {
  // First, we pass the client to the handler() and generate a ShopifyHandler.
  let config = ctx.pify // or ``let client = storefront.handler(client)``
  // The main function in ShopifyHandler is fetch(), that we can call as client.fetch(query, variables, decoder(Msg))
  // The decoder should be a direct response to the operation that you are trying to perform.
  //
  // In this case, we are passing a "get_product_operation_decoder()" that represents the expected response from Shopify.
  // You can see those responses in the official Shopify documentation or through Their GraphiQL plugin: <https://shopify-graphiql-app.shopifycloud.com/login>.
  //
  let fetcher = {
    let handler = admin_handler(config)

    let variables =
      json.object([
        #("handle", json.object([#("handle", json.string(handle))])),
      ])

    use resp <- t.do(handler.fetch(
      get_product_query,
      Some(variables),
      get_product_admin_client_response_decoder(),
    ))

    let products = resp.data
    case products {
      None -> t.Abort(snag.new("No product to be fetched"))
      Some(value) -> {
        t.Done(value)
      }
    }

  case runner.run(fetcher) {
    t.Done(value) -> {
      json.to_string(json.object([#("data", get_product_query_to_json(value))]))
      |> wisp.json_response(200)
    }
    err -> wisp.bad_request(string.inspect(err))
  }
}

// Further documentation can be found at <https://hexdocs.pm/pify>.
## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
