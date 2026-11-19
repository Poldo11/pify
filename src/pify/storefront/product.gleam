//// Storefront products: one by handle, a page of the catalog, and the
//// recommendations for one product.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql.{type Connection}
import pify/money.{type Money}
import pify/storefront.{
  type Image, type Metafield, type MetafieldIdentifier, type SelectedOption,
  type Seo, type StorefrontClient,
}

pub type Product {
  Product(
    id: String,
    handle: String,
    title: String,
    description: String,
    description_html: String,
    vendor: String,
    product_type: String,
    tags: List(String),
    available_for_sale: Bool,
    updated_at: String,
    options: List(ProductOption),
    price_range: PriceRange,
    compare_at_price_range: PriceRange,
    featured_image: Option(Image),
    images: List(Image),
    variants: List(Variant),
    /// The product has more variants than the read returned:
    /// `variants_per_product` for `by_handle`, `variants_per_page` for a
    /// page of products.
    has_more_variants: Bool,
    seo: Seo,
    metafields: List(Metafield),
  )
}

pub type ProductOption {
  ProductOption(id: String, name: String, values: List(String))
}

pub type PriceRange {
  PriceRange(min_variant_price: Money, max_variant_price: Money)
}

pub type Variant {
  Variant(
    id: String,
    title: String,
    sku: Option(String),
    available_for_sale: Bool,
    price: Money,
    compare_at_price: Option(Money),
    selected_options: List(SelectedOption),
    image: Option(Image),
  )
}

pub type ProductSort {
  ProductSortTitle
  ProductSortProductType
  ProductSortVendor
  ProductSortUpdatedAt
  ProductSortCreatedAt
  ProductSortBestSelling
  ProductSortPrice
  ProductSortId
  ProductSortRelevance
}

pub fn product_sort_to_string(sort: ProductSort) -> String {
  case sort {
    ProductSortTitle -> "TITLE"
    ProductSortProductType -> "PRODUCT_TYPE"
    ProductSortVendor -> "VENDOR"
    ProductSortUpdatedAt -> "UPDATED_AT"
    ProductSortCreatedAt -> "CREATED_AT"
    ProductSortBestSelling -> "BEST_SELLING"
    ProductSortPrice -> "PRICE"
    ProductSortId -> "ID"
    ProductSortRelevance -> "RELEVANCE"
  }
}

/// One page of `list`. `search` is Shopify's product search syntax.
pub type ProductPage {
  ProductPage(
    first: Int,
    after: Option(String),
    search: Option(String),
    sort: ProductSort,
    reverse: Bool,
  )
}

/// The first page of the catalog by title.
pub fn first_page(first: Int) -> ProductPage {
  ProductPage(
    first:,
    after: option.None,
    search: option.None,
    sort: ProductSortTitle,
    reverse: False,
  )
}

pub const variants_per_product = 100

pub const variants_per_page = 10

pub const variant_fields =
  " id title sku availableForSale price {"
  <> money.fields
  <> " } compareAtPrice {"
  <> money.fields
  <> " }"
  <> storefront.selected_options_fields
  <> " image {"
  <> storefront.image_fields
  <> " }"

const price_range_fields =
  " { minVariantPrice {"
  <> money.fields
  <> " } maxVariantPrice {"
  <> money.fields
  <> " } }"

const scalar_fields =
  " id handle title description descriptionHtml vendor productType"
  <> " tags availableForSale updatedAt"
  <> " options { id name optionValues { name } }"
  <> " priceRange"
  <> price_range_fields
  <> " compareAtPriceRange"
  <> price_range_fields
  <> " featuredImage {"
  <> storefront.image_fields
  <> " }"
  <> storefront.seo_fields
  <> storefront.metafields_fields

/// The fields of one product: 20 images and `variants_per_product`
/// variants.
pub const fields =
  scalar_fields
  <> " images(first: 20) { nodes {"
  <> storefront.image_fields
  <> " } }"
  <> " variants(first: 100) { nodes {"
  <> variant_fields
  <> " } pageInfo { hasNextPage } }"

/// The fields of each product in a page: the featured image only and
/// `variants_per_page` variants, so a page stays under Shopify's query cost.
pub const page_fields =
  scalar_fields
  <> " images(first: 1) { nodes {"
  <> storefront.image_fields
  <> " } }"
  <> " variants(first: 10) { nodes {"
  <> variant_fields
  <> " } pageInfo { hasNextPage } }"

pub const by_handle_query =
  "query StorefrontProduct($handle: String!, $identifiers: [HasMetafieldsIdentifier!]!) {"
  <> " product(handle: $handle) {"
  <> fields
  <> " } }"

pub fn by_handle(
  client: StorefrontClient,
  handle: String,
  metafields: List(MetafieldIdentifier),
) -> Effect(Result(Option(Product), ShopifyError), key) {
  storefront.graphql(
    client,
    by_handle_query,
    json.object([
      #("handle", json.string(handle)),
      #("identifiers", storefront.metafield_identifiers_to_json(metafields)),
    ]),
  )
  |> execute.run(decode.field(
    "product",
    decode.optional(decoder()),
    decode.success,
  ))
}

pub const list_query =
  "query StorefrontProducts($first: Int!, $after: String, $query: String,"
  <> " $sortKey: ProductSortKeys, $reverse: Boolean,"
  <> " $identifiers: [HasMetafieldsIdentifier!]!) {"
  <> " products(first: $first, after: $after, query: $query,"
  <> " sortKey: $sortKey, reverse: $reverse) {"
  <> " nodes {"
  <> page_fields
  <> " } pageInfo { hasNextPage endCursor } } }"

pub fn list(
  client: StorefrontClient,
  page: ProductPage,
  metafields: List(MetafieldIdentifier),
) -> Effect(Result(Connection(Product), ShopifyError), key) {
  storefront.graphql(client, list_query, list_variables(page, metafields))
  |> execute.run(decode.field(
    "products",
    graphql.connection_decoder(decoder()),
    decode.success,
  ))
}

pub fn list_variables(
  page: ProductPage,
  metafields: List(MetafieldIdentifier),
) -> Json {
  storefront.page_variables(page.first, page.after, [
    #("query", json.nullable(page.search, json.string)),
    #("sortKey", json.string(product_sort_to_string(page.sort))),
    #("reverse", json.bool(page.reverse)),
    #("identifiers", storefront.metafield_identifiers_to_json(metafields)),
  ])
}

pub const recommendations_query =
  "query StorefrontRecommendations($productId: ID!, $identifiers: [HasMetafieldsIdentifier!]!) {"
  <> " productRecommendations(productId: $productId) {"
  <> page_fields
  <> " } }"

/// Shopify answers null for a product it has no recommendations for; that
/// reads as an empty list.
pub fn recommendations(
  client: StorefrontClient,
  product_id: String,
  metafields: List(MetafieldIdentifier),
) -> Effect(Result(List(Product), ShopifyError), key) {
  storefront.graphql(
    client,
    recommendations_query,
    json.object([
      #("productId", json.string(product_id)),
      #("identifiers", storefront.metafield_identifiers_to_json(metafields)),
    ]),
  )
  |> execute.run(
    decode.field(
      "productRecommendations",
      decode.optional(decode.list(decoder())),
      fn(products) { decode.success(option.unwrap(products, [])) },
    ),
  )
}

pub fn decoder() -> decode.Decoder(Product) {
  use id <- decode.field("id", decode.string)
  use handle <- decode.field("handle", decode.string)
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  use description_html <- decode.field("descriptionHtml", decode.string)
  use vendor <- decode.field("vendor", decode.string)
  use product_type <- decode.field("productType", decode.string)
  use tags <- decode.field("tags", decode.list(decode.string))
  use available_for_sale <- decode.field("availableForSale", decode.bool)
  use updated_at <- decode.field("updatedAt", decode.string)
  use options <- decode.field("options", decode.list(option_decoder()))
  use price_range <- decode.field("priceRange", price_range_decoder())
  use compare_at_price_range <- decode.field(
    "compareAtPriceRange",
    price_range_decoder(),
  )
  use featured_image <- graphql.optional(
    "featuredImage",
    storefront.image_decoder(),
  )
  use images <- decode.field(
    "images",
    graphql.nodes_decoder(storefront.image_decoder()),
  )
  use variants <- decode.field(
    "variants",
    graphql.connection_decoder(variant_decoder()),
  )
  use seo <- decode.field("seo", storefront.seo_decoder())
  use metafields <- decode.field("metafields", storefront.metafields_decoder())
  decode.success(Product(
    id:,
    handle:,
    title:,
    description:,
    description_html:,
    vendor:,
    product_type:,
    tags:,
    available_for_sale:,
    updated_at:,
    options:,
    price_range:,
    compare_at_price_range:,
    featured_image:,
    images:,
    variants: variants.nodes,
    has_more_variants: variants.page_info.has_next_page,
    seo:,
    metafields:,
  ))
}

fn option_decoder() -> decode.Decoder(ProductOption) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use values <- decode.field(
    "optionValues",
    decode.list(decode.field("name", decode.string, decode.success)),
  )
  decode.success(ProductOption(id:, name:, values:))
}

fn price_range_decoder() -> decode.Decoder(PriceRange) {
  use min_variant_price <- decode.field("minVariantPrice", money.decoder())
  use max_variant_price <- decode.field("maxVariantPrice", money.decoder())
  decode.success(PriceRange(min_variant_price:, max_variant_price:))
}

/// Reads the fields `variant_fields` selects.
pub fn variant_decoder() -> decode.Decoder(Variant) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use sku <- graphql.optional("sku", decode.string)
  use available_for_sale <- decode.field("availableForSale", decode.bool)
  use price <- decode.field("price", money.decoder())
  use compare_at_price <- graphql.optional("compareAtPrice", money.decoder())
  use selected_options <- decode.field(
    "selectedOptions",
    decode.list(storefront.selected_option_decoder()),
  )
  use image <- graphql.optional("image", storefront.image_decoder())
  decode.success(Variant(
    id:,
    title:,
    sku:,
    available_for_sale:,
    price:,
    compare_at_price:,
    selected_options:,
    image:,
  ))
}
