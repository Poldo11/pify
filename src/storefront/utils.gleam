import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Class of utilities that repeat itself in my places
///
/// Product Variant
///
// /// Shopify types and decoders for our examples

// /// Remove the edges from the array and return the proper type of the connection.
// ///
// /// Essential to work with GraphQL <> Shopify.
pub fn remove_edges_and_nodes(array: Connection(a)) -> List(a) {
  array.edges
  |> list.map(fn(nodes) { nodes.node })
}

pub type Maybe(a) {
  Maybe(Option(a))
}

pub type Connection(a) {
  Connection(edges: List(Edge(a)))
}

pub type Edge(a) {
  Edge(node: a)
}

pub type Image {
  Image(url: String, alt_text: String, width: String, height: String)
}

pub type Images {
  Images(images: List(Image))
}

pub fn image_to_json(image: Image) -> json.Json {
  let Image(url:, alt_text:, width:, height:) = image
  json.object([
    #("url", json.string(url)),
    #("altText", json.string(alt_text)),
    #("width", json.string(width)),
    #("height", json.string(height)),
  ])
}

pub fn image_decoder() -> decode.Decoder(Image) {
  use url <- decode.field("url", decode.string)
  use alt_text <- decode.field("altText", decode.string)
  use width <- decode.field("width", decode.string)
  use height <- decode.field("height", decode.string)
  decode.success(Image(url:, alt_text:, width:, height:))
}

pub type PriceRange {
  PriceRange(max_variant_price: Money, min_variant_price: Money)
}

pub fn price_range_to_json(price_range: PriceRange) -> json.Json {
  let PriceRange(max_variant_price:, min_variant_price:) = price_range
  json.object([
    #("maxVariantPrice", money_to_json(max_variant_price)),
    #("minVariantPrice", money_to_json(min_variant_price)),
  ])
}

pub fn price_range_decoder() -> decode.Decoder(PriceRange) {
  use max_variant_price <- decode.field("maxVariantPrice", money_decoder())
  use min_variant_price <- decode.field("minVariantPrice", money_decoder())
  decode.success(PriceRange(max_variant_price:, min_variant_price:))
}

pub type Money {
  Money(amount: String, currency_code: String)
}

pub fn money_to_json(money: Money) -> json.Json {
  let Money(amount:, currency_code:) = money
  json.object([
    #("amount", json.string(amount)),
    #("currencyCode", json.string(currency_code)),
  ])
}

pub fn money_decoder() -> decode.Decoder(Money) {
  use amount <- decode.field("amount", decode.string)
  use currency_code <- decode.field("currencyCode", decode.string)
  decode.success(Money(amount:, currency_code:))
}

pub type ProductVariant {
  ProductVariant(
    id: String,
    title: String,
    available_for_sale: Bool,
    selected_options: SelectedOption,
    price: Money,
  )
}

pub fn product_variant_to_json(product_variant: ProductVariant) -> json.Json {
  let ProductVariant(
    id:,
    title:,
    available_for_sale:,
    selected_options:,
    price:,
  ) = product_variant
  json.object([
    #("id", json.string(id)),
    #("title", json.string(title)),
    #("availableForSale", json.bool(available_for_sale)),
    #("selectedOptions", selected_option_to_json(selected_options)),
    #("price", money_to_json(price)),
  ])
}

pub fn product_variant_decoder() -> decode.Decoder(ProductVariant) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use available_for_sale <- decode.field("availableForSale", decode.bool)
  use selected_options <- decode.field(
    "selectedOptions",
    selected_option_decoder(),
  )
  use price <- decode.field("price", money_decoder())
  decode.success(ProductVariant(
    id:,
    title:,
    available_for_sale:,
    selected_options:,
    price:,
  ))
}

pub type Seo {
  Seo(title: String, description: String)
}

pub fn seo_to_json(seo: Seo) -> json.Json {
  let Seo(title:, description:) = seo
  json.object([
    #("title", json.string(title)),
    #("description", json.string(description)),
  ])
}

pub fn seo_decoder() -> decode.Decoder(Seo) {
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  decode.success(Seo(title:, description:))
}

pub fn image_connection_decoder() -> decode.Decoder(Connection(Image)) {
  use edges <- decode.field("edges", decode.list(image_edges_decoder()))
  decode.success(Connection(edges:))
}

pub fn image_edges_decoder() -> decode.Decoder(Edge(Image)) {
  use node <- decode.field("node", image_decoder())
  decode.success(Edge(node:))
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

pub type ProductOption {
  ProductOption(id: String, name: String, values: List(String))
}

pub fn product_option_decoder() -> decode.Decoder(ProductOption) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use values <- decode.field("values", decode.list(decode.string))
  decode.success(ProductOption(id:, name:, values:))
}

pub type SelectedOption {
  SelectedOption(name: String, value: String)
}

fn selected_option_to_json(selected_option: SelectedOption) -> json.Json {
  let SelectedOption(name:, value:) = selected_option
  json.object([
    #("name", json.string(name)),
    #("value", json.string(value)),
  ])
}

pub fn selected_option_decoder() -> decode.Decoder(SelectedOption) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(SelectedOption(name:, value:))
}

pub type Cost {
  Cost(total_amount: Money)
}

pub fn cost_decoder() -> decode.Decoder(Cost) {
  use total_amount <- decode.field("totalAmount", money_decoder())
  decode.success(Cost(total_amount:))
}

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

fn last_split(
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
// fn append_path(request, path) {
//   request.set_path(request, request.path <> path)
// }
