# pify

[WIP – Not ready for production]

[![Package Version](https://img.shields.io/hexpm/v/pify)](https://hex.pm/packages/pify)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pify/)

```sh
gleam add pify@1
```
```gleam
import pify

pub fn main() -> Nil {

  /// Place your keys and secrets in a .env file
  let assert Ok(key) = envoy.get("SHOPIFY_ANON_KEY")
  let assert Ok(domain) = envoy.get("SHOPIFY_URL")
  let assert Ok(api_version) = envoy.get("SHOPIFY_API_VERSION")

  /// Pass them to your Shopify Client
  let assert Ok(client) = pify.client(key: key, domain: domain, api_version: Some(api_version))

  /// Use your client to fetch products
  let assert Ok(products) = pify.fetch_products(client)

  /// Or create your own fetcher passing the arguments from fetch().

  let get_collections = pify.fetch(client: client,
    query: "
    query getCollections {
    collections(first: 100, sortKey: TITLE) {
      edges {
        node {
          ...collection
        }
      }
    }
  }" <> collection_fragment(),
  variables: None, decoder: collections_decoder())
  /// This will return a `Result(ShopifyResult(Collections), ShopifyError)` that you can decode later.
}
```

Further documentation can be found at <https://hexdocs.pm/pify>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
