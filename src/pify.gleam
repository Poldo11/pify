import fragments.{product_fragment}
import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Post}
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import snag
import types.{
  type Cart, type Connection, type Image, type Product, type Products,
  type ShopifyCart, type ShopifyClient, type ShopifyError, type ShopifyProduct,
  Cart, Image, Product, ShopifyCartCost, ShopifyClient, ShopifyError,
  product_decoder, products_decoder,
}

pub fn client(key: String, domain: String, api_version: Option(String)) {
  Ok(ShopifyClient(key:, domain:, api_version:))
}

fn base(client: ShopifyClient) {
  let request = {
    request.new()
    |> request.set_host(client.domain)
    |> append_path(
      "/api/" <> option.unwrap(client.api_version, "2023-10") <> "/graphql.json",
    )
    |> request.set_method(Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("X-Shopify-Storefront-Access-Token", client.key)
  }
  request
}

pub type ShopifyResult(a) {
  ShopifyResult(status: Int, body: a)
}

pub fn fetch(
  client client: ShopifyClient,
  query query: String,
  variables variables: Option(String),
  decoder decoder: Decoder(a),
) -> Result(ShopifyResult(a), ShopifyError) {
  let request = {
    base(client)
    |> request.set_body(
      json.to_string(
        json.object([
          #("query", json.string(query)),
          #("variables", case variables {
            option.None -> json.null()
            option.Some(value) -> json.string(value)
          }),
        ]),
      ),
    )
  }
  use resp <- result.try(
    httpc.send(request)
    |> result.map_error(fn(_) {
      ShopifyError(
        status: 500,
        body: snag.new("HTTP request failed") |> snag.line_print,
      )
    }),
  )
  use decoded_body <- result.try(
    resp.body
    |> json.parse(using: decoder)
    |> result.map_error(fn(_) {
      ShopifyError(status: 500, body: "JSON decoding failed.")
    }),
  )

  Ok(ShopifyResult(status: resp.status, body: decoded_body))
}

pub fn fetch_products(
  client: ShopifyClient,
) -> Result(ShopifyResult(Products), ShopifyError) {
  let query = product_fragment()
  fetch(
    client: client,
    query: query,
    variables: option.None,
    decoder: products_decoder(),
  )
}

pub fn fetch_product(
  client: ShopifyClient,
  handle: String,
) -> Result(ShopifyResult(Product), ShopifyError) {
  let query = product_fragment()
  fetch(
    client: client,
    query: query,
    variables: option.Some(handle),
    decoder: product_decoder(),
  )
}

pub fn append_path(request, path) {
  request.set_path(request, request.path <> path)
}

// Reshape Functions

/// Remove the edges from the array and return the proper type of the connection.
///
/// Essential to work with GraphQL.
///
pub fn remove_edges_and_nodes(array: Connection(a)) {
  array.edges
  |> list.map(fn(nodes) { nodes.node })
}

pub fn reshape_images(
  images: Connection(Image),
  product_title: String,
) -> List(Image) {
  let flattened = remove_edges_and_nodes(images)
  flattened
  |> list.map(fn(image) {
    let new_alt_text = case image.alt_text {
      "" -> {
        let filename = get_filename(image.url)
        product_title <> "-" <> filename
      }
      text -> text
    }
    Image(..image, alt_text: new_alt_text)
  })
}

pub fn reshape_cart(cart: ShopifyCart) -> Cart {
  let result = {
    case cart.cost {
      None -> None
      Some(cost) -> {
        let lines = remove_edges_and_nodes(cart.lines)
        Some(Cart(
          checkout_url: cart.checkout_url,
          id: cart.id,
          lines: lines,
          total_quantity: cart.total_quantity,
          cost: Some(ShopifyCartCost(
            subtotal_amount: cost.subtotal_amount,
            total_tax_amount: cost.total_tax_amount,
            total_amount: cost.total_tax_amount,
          )),
        ))
      }
    }
  }
  let lines = remove_edges_and_nodes(cart.lines)
  option.unwrap(
    result,
    Cart(
      checkout_url: cart.checkout_url,
      id: cart.id,
      lines: lines,
      total_quantity: cart.total_quantity,
      cost: cart.cost,
    ),
  )
}

const hidden_product_tags = "gleam-frontend-hidden"

pub fn reshape_product(
  product: ShopifyProduct,
  filter_hidden_products: Bool,
) -> Product {
  let result = {
    let is_hidden = list.contains(product.tags, hidden_product_tags)
    case filter_hidden_products && is_hidden {
      True -> None
      False -> {
        let reshaped_image = reshape_images(product.images, product.title)
        let reshaped_variants = remove_edges_and_nodes(product.variants)
        Some(Product(
          id: product.id,
          handle: product.handle,
          available_for_sale: product.available_for_sale,
          title: product.title,
          description: product.description,
          description_html: product.description_html,
          price_range: product.price_range,
          featured_image: product.featured_image,
          seo: product.seo,
          tags: product.tags,
          updated_at: product.updated_at,
          images: reshaped_image,
          variants: reshaped_variants,
        ))
      }
    }
  }
  let reshaped_image = reshape_images(product.images, product.title)
  let reshaped_variants = remove_edges_and_nodes(product.variants)
  option.unwrap(
    result,
    Product(
      id: product.id,
      handle: product.handle,
      available_for_sale: product.available_for_sale,
      title: product.title,
      description: product.description,
      description_html: product.description_html,
      price_range: product.price_range,
      featured_image: product.featured_image,
      seo: product.seo,
      tags: product.tags,
      updated_at: product.updated_at,
      images: reshaped_image,
      variants: reshaped_variants,
    ),
  )
}

pub fn reshape_products(products: List(ShopifyProduct)) -> List(Product) {
  list.map(products, fn(product) { reshape_product(product, True) })
}

// pub fn create_cart(client: ShopifyClient) -> Result(Cart, ShopifyError) {
//   let query = cart.create_cart_mutation()
//   todo
// }

/// AI constructed. Need to verify logic.
///
fn get_filename(url: String) -> String {
  let path_segment = case last_split(url, "/") {
    Ok(#(_, after)) -> after
    Error(_) -> url
  }

  case last_split(path_segment, ".") {
    Ok(#(before, _)) -> before
    Error(_) -> path_segment
  }
}

/// AI constructed. Need to verify logic.
///
pub fn last_split(
  str: String,
  on separator: String,
) -> Result(#(String, String), Nil) {
  let reversed_str = string.reverse(str)
  let reversed_separator = string.reverse(separator)

  case string.split_once(reversed_str, on: reversed_separator) {
    Ok(#(after_reversed, before_reversed)) -> {
      let before = string.reverse(before_reversed)
      let after = string.reverse(after_reversed)
      Ok(#(before, after))
    }
    Error(_) -> Error(Nil)
  }
}
