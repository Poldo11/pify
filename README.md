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
  let assert Ok(key) = envoy.get("SHOPIFY_ANON_KEY")
  let assert Ok(domain) = envoy.get("SHOPIFY_URL")
  let assert Ok(api_version) = envoy.get("SHOPIFY_API_VERSION")

  // Pass your env keys to create a Storefront client.
  let config =
    storefront.CreateStorefrontApiClient(
      // If no api_version is provided, our client uses "2023-10" api version.
      api_version: Some(api_version),
      // This is your store_domain url. You can place it with or without 'https://', but the final string of connections will have 'https://'.
      store_domain: domain,
      // To connect to Shopify, we can only provide one type of: a private OR a public.
      // If you try to place Some(key) in both, the lib will panic.
      private_access_token: Some(key),
      public_access_token: None,
      // "retries" is inactive for now.
      retries: Some(0),
      // "client_name" has no value for now.
      client_name: None,
    )

  // This will give you a StorefrontApiClientConfig type, that you have to pass to all your fetches.
  let assert Ok(client) = storefront.create_store_front_api_client(config)

  // By convention, I'm used client to extend the functions for ShopifyHandler. Below, you will see some examples.
  let client = storefront.handler(client)

  Nil
}

/// Example of a fetch that takes no variables
///
///
pub fn get_products(client: StorefrontApiClientConfig) {
  // First, we pass the client to the handler() and generate a ShopifyHandler.
  let client = storefront.handler(client)
  // The main function in ShopifyHandler is fetch(), that we can call as client.fetch(query, variables, decoder(Msg))
  // The decoder should be a direct response to the operation that you are trying to perform.
  //
  // In this case, we are passing a "get_products_operation_decoder()" that represents the expected response from Shopify.
  // You can see those responses in the official Shopify documentation or through Their GraphiQL plugin: <https://shopify-graphiql-app.shopifycloud.com/login>.
  //
  let get_products =
    client.fetch(
      // query
      get_product_query,
      // variables
      None,
      // decoder
      get_products_operation_decoder(),
    )

  // For now, the result of the fetch function is of type Promise(Result(GetProductsOperation, ShopifyError).
  // Later on, we will work in removing this Promise type and make this connection agnostic to the target.
  //
  // Now that we now that we are dealing with a Promise, let's get some results.
  //
  get_products
  |> promise.map(fn(res) {
    case res {
      Ok(products) -> {
        case products.data.products {
          Some(products) -> {
            //
            //
            // First we remove the edges and nodes from the Connection(ShopifyProduct)
            //
            let list_of_shopify_products =
              utils.remove_edges_and_nodes(products)
            //
            // Then we reshape it. From `List(ShopifyProduct)` to `List(Product)`
            //
            let list_of_shopify_products_to_list_of_products =
              reshape_products(list_of_shopify_products)
            //
            // If you need to access any individual product that inside of function, you can pass another reshaper:
            //
            let product_json = {
              list.map(list_of_shopify_products, fn(product) {
                reshape_product(product, True)
              })
              // And convert it to a json array by passing product_to_json, created from our Product type.
              |> json.array(of: products.product_to_json)
            }
            Ok(product_json)
            //
            //
            // And wrapped it around an `Ok`
            //
          }
          None -> Error(storefront.NetworkError)
          //
          // Else, we pass them as Errors. Errors mapping is a work in progress :)
          //
        }
      }
      Error(err) -> Error(err)
      //
      // Here, we just pass the ShopifyError type.
      //
    }
  })
}
// Further documentation can be found at <https://hexdocs.pm/pify>.
## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
