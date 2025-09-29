import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import storefront/fragments.{product_fragment}
import storefront/utils.{
  type Connection, type Image, type PriceRange, type ProductVariant, type Seo,
  image_decoder, image_to_json, price_range_decoder, price_range_to_json,
  product_variant_decoder, product_variant_to_json, remove_edges_and_nodes,
  reshape_images, seo_decoder, seo_to_json,
}

pub type ProductOption {
  ProductOption(id: String, name: String, values: List(String))
}

const hidden_product_tags = "gleam-frontend-hidden"

pub fn product_option_decoder() -> decode.Decoder(ProductOption) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use values <- decode.field("values", decode.list(decode.string))
  decode.success(ProductOption(id:, name:, values:))
}

pub type Products {
  Products(products: List(Product))
}

pub fn products_decoder() -> decode.Decoder(Products) {
  use products <- decode.field("products", decode.list(product_decoder()))
  decode.success(Products(products:))
}

pub type Product {
  Product(
    id: String,
    handle: String,
    available_for_sale: Bool,
    title: String,
    description: String,
    description_html: String,
    price_range: PriceRange,
    featured_image: Image,
    seo: Seo,
    tags: List(String),
    updated_at: String,
    variants: List(ProductVariant),
    images: List(Image),
  )
}

pub fn product_to_json(product: Product) -> json.Json {
  let Product(
    id:,
    handle:,
    available_for_sale:,
    title:,
    description:,
    description_html:,
    price_range:,
    featured_image:,
    seo:,
    tags:,
    updated_at:,
    variants:,
    images:,
  ) = product
  json.object([
    #("id", json.string(id)),
    #("handle", json.string(handle)),
    #("availableForSale", json.bool(available_for_sale)),
    #("title", json.string(title)),
    #("description", json.string(description)),
    #("descriptionHtml", json.string(description_html)),
    #("priceRange", price_range_to_json(price_range)),
    #("featuredImage", image_to_json(featured_image)),
    #("seo", seo_to_json(seo)),
    #("tags", json.array(tags, json.string)),
    #("updatedAt", json.string(updated_at)),
    #("variants", json.array(variants, product_variant_to_json)),
    #("images", json.array(images, image_to_json)),
  ])
}

pub fn product_decoder() -> decode.Decoder(Product) {
  use id <- decode.field("id", decode.string)
  use handle <- decode.field("handle", decode.string)
  use available_for_sale <- decode.field("available_for_sale", decode.bool)
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  use description_html <- decode.field("description_html", decode.string)
  use price_range <- decode.field("price_range", price_range_decoder())
  use featured_image <- decode.field("featured_image", image_decoder())
  use seo <- decode.field("seo", seo_decoder())
  use tags <- decode.field("tags", decode.list(decode.string))
  use updated_at <- decode.field("updated_at", decode.string)
  use variants <- decode.field(
    "variants",
    decode.list(product_variant_decoder()),
  )
  use images <- decode.field("images", decode.list(image_decoder()))
  decode.success(Product(
    id:,
    handle:,
    available_for_sale:,
    title:,
    description:,
    description_html:,
    price_range:,
    featured_image:,
    seo:,
    tags:,
    updated_at:,
    variants:,
    images:,
  ))
}

pub type ShopifyProduct {
  ShopifyProduct(
    id: String,
    handle: String,
    available_for_sale: Bool,
    title: String,
    description: String,
    description_html: String,
    price_range: PriceRange,
    variants: Connection(ProductVariant),
    featured_image: Image,
    images: Connection(Image),
    seo: Seo,
    tags: List(String),
    updated_at: String,
  )
}

// 2. Products

pub type ShopifyCollection {
  ShopifyCollection(
    handle: String,
    title: String,
    description: String,
    seo: Seo,
    updated_at: String,
  )
}

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

/// Queries
///
pub const get_product_query = "
  query getProduct($handle: String!) {
    product(handle: $handle) {
      ...product
    }
  }
  "
  <> product_fragment

pub const get_products_query = "
    query getProducts($sortKey: ProductSortKeys, $reverse: Boolean, $query: String) {
      products(sortKey: $sortKey, reverse: $reverse, query: $query, first: 100) {
        edges {
          node {
            ...product
          }
        }
      }
    }
    "
  <> product_fragment

pub const get_product_recommendations_query = "
      query getProductRecommendations($productId: ID!) {
        productRecommendations(productId: $productId) {
          ...product
        }
      }
      "
  <> product_fragment
