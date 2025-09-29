import admin/types.{
  type Edge, type Pagination, type SortKey, Edge, pagination_decoder,
  pagination_to_json, sort_key_to_json,
}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import midas/task as t
import pify.{
  type AdminApiClientConfig, type AdminClientResponse, type AdminResponseErrors,
  AdminClientResponse, admin_handler,
}
import snag

pub const get_products_query = "
query getProducts($numProducts: Int!, $cursor: String, $sortKey: ProductSortKeys, $reverse: Boolean, $query: String) {
  products(
    first: $numProducts
    after: $cursor
    sortKey: $sortKey
    reverse: $reverse
    query: $query
  ) {
    edges {
      node {
        id
        handle
        title
        totalInventory
        description
        descriptionHtml
        vendor
        options {
          id
          name
          values
        }
        priceRangeV2 {
          maxVariantPrice {
            amount
            currencyCode
          }
          minVariantPrice {
            amount
            currencyCode
          }
        }
        compareAtPriceRange {
          maxVariantCompareAtPrice {
            amount
            currencyCode
          }
          minVariantCompareAtPrice {
            amount
            currencyCode
          }
        }
        variants(first: 20) {
          edges {
            node {
              id
              title
              availableForSale
              selectedOptions {
                name
                value
              }
              price
            }
          }
        }
        featuredMedia {
          id
          mediaContentType
          alt
          preview {
            image {
              url
              id
              altText
              width
              height
              thumbhash
            }
            status
          }
        }
        media(first: 20) {
          edges {
            node {
              id
              mediaContentType
              alt
              preview {
                image {
                  url
                  id
                  altText
                  width
                  height
                  thumbhash
                }
                status
              }
            }
          }
        }
        seo {
          description
          title
        }
        tags
        updatedAt
        createdAt
        publishedAt
        variantsCount {
          count
          precision
        }
      }
    }
    pageInfo {
      hasNextPage
      hasPreviousPage
      startCursor
      endCursor
    }
  }
}
"

pub fn get_products(
  config: AdminApiClientConfig,
  query: Option(String),
  reverse: Option(Bool),
  sort_key: Option(SortKey),
  num_products: Int,
  cursor: Option(String),
) -> t.Effect(GetProductsQuery, AdminResponseErrors) {
  let validade_int = case num_products <= 0 {
    True -> 1
    _ -> num_products
  }
  let handler = admin_handler(config)
  let variables =
    json.object([
      #("query", json.nullable(query, of: json.string)),
      #("reverse", json.nullable(reverse, of: json.bool)),
      #("sortKey", json.nullable(sort_key, of: sort_key_to_json)),
      #("numProducts", json.int(validade_int)),
      #("cursor", json.nullable(cursor, of: json.string)),
    ])

  use decoded_response <- t.do(handler.fetch(
    get_products_query,
    Some(variables),
    get_products_admin_client_response_decoder(),
  ))

  let products = decoded_response.data
  case products {
    None -> t.Abort(snag.new("No product to be fetched"))
    Some(value) -> {
      t.Done(value)
    }
  }
}

pub fn get_products_admin_client_response_decoder() -> decode.Decoder(
  AdminClientResponse(GetProductsQuery),
) {
  use data <- decode.field(
    "data",
    decode.optional(get_products_query_decoder()),
  )

  decode.success(AdminClientResponse(data:))
}

pub fn get_products_admin_client_response_to_json(
  admin_client_response: AdminClientResponse(GetProductsQuery),
) -> Json {
  let AdminClientResponse(data:) = admin_client_response
  json.object([
    #("data", case data {
      None -> json.null()
      Some(value) -> get_products_query_to_json(value)
    }),
  ])
}

pub type GetProductsQuery {
  GetProductsQuery(products: ProductConnection)
}

pub fn get_products_query_to_json(get_products_query: GetProductsQuery) -> Json {
  let GetProductsQuery(products:) = get_products_query
  json.object([
    #("products", product_connection_to_json(products)),
  ])
}

fn get_products_query_decoder() -> decode.Decoder(GetProductsQuery) {
  use products <- decode.field("products", product_connection_decoder())
  decode.success(GetProductsQuery(products:))
}

pub type ProductConnection {
  ProductConnection(edges: List(Edge(Product)), pagination: Pagination)
}

fn product_connection_to_json(product_connection: ProductConnection) -> Json {
  let ProductConnection(edges:, pagination:) = product_connection
  json.object([
    #("edges", json.array(edges, product_edge_to_json)),
    #("pageInfo", pagination_to_json(pagination)),
  ])
}

fn product_connection_decoder() -> Decoder(ProductConnection) {
  use edges <- decode.field("edges", decode.list(product_edge_decoder()))
  use pagination <- decode.field("pageInfo", pagination_decoder())
  decode.success(ProductConnection(edges:, pagination:))
}

pub fn product_edge_decoder() -> Decoder(Edge(Product)) {
  use node <- decode.field("node", product_decoder())
  decode.success(Edge(node:))
}

pub fn product_edge_to_json(edge: Edge(Product)) -> Json {
  let Edge(node:) = edge
  json.object([
    #("node", product_to_json(node)),
  ])
}

pub type Product {
  Product(
    id: String,
    handle: String,
    title: String,
    total_inventory: Option(Int),
    description: Option(String),
    description_html: Option(String),
    vendor: String,
    options: List(ProductOption),
    price_range_v2: ProductPriceRange,
    compare_at_price_range: Option(ProductCompareAtPriceRange),
    variants: ProductVariantConnection,
    featured_media: Option(Media),
    media: MediaConnection,
    seo: Option(Seo),
    tags: List(String),
    updated_at: String,
    created_at: String,
    published_at: Option(String),
    variants_count: VariantsCount,
  )
}

pub fn product_to_json(product: Product) -> json.Json {
  let Product(
    id:,
    handle:,
    title:,
    total_inventory:,
    description:,
    description_html:,
    vendor:,
    options:,
    price_range_v2:,
    compare_at_price_range:,
    variants:,
    featured_media:,
    media:,
    seo:,
    tags:,
    updated_at:,
    created_at:,
    published_at:,
    variants_count:,
  ) = product
  json.object([
    #("id", json.string(id)),
    #("handle", json.string(handle)),
    #("title", json.string(title)),
    #("totalInventory", case total_inventory {
      None -> json.null()
      Some(value) -> json.int(value)
    }),
    #("description", case description {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("descriptionHtml", case description_html {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("vendor", json.string(vendor)),
    #("options", json.array(options, product_option_to_json)),
    #("priceRangeV2", product_price_range_to_json(price_range_v2)),
    #("compareAtPriceRange", case compare_at_price_range {
      None -> json.null()
      Some(value) -> product_compare_at_price_range_to_json(value)
    }),
    #("variants", product_variant_connection_to_json(variants)),
    #("featuredMedia", case featured_media {
      None -> json.null()
      Some(value) -> media_to_json(value)
    }),
    #("media", media_connection_to_json(media)),
    #("seo", case seo {
      None -> json.null()
      Some(value) -> seo_to_json(value)
    }),
    #("tags", json.array(tags, json.string)),
    #("updatedAt", json.string(updated_at)),
    #("createdAt", json.string(created_at)),
    #("publishedAt", case published_at {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("variantsCount", variants_count_to_json(variants_count)),
  ])
}

pub fn product_decoder() -> decode.Decoder(Product) {
  use id <- decode.field("id", decode.string)
  use handle <- decode.field("handle", decode.string)
  use title <- decode.field("title", decode.string)
  use total_inventory <- decode.field(
    "totalInventory",
    decode.optional(decode.int),
  )
  use description <- decode.field("description", decode.optional(decode.string))
  use description_html <- decode.field(
    "descriptionHtml",
    decode.optional(decode.string),
  )
  use vendor <- decode.field("vendor", decode.string)
  use options <- decode.field("options", decode.list(product_option_decoder()))
  use price_range_v2 <- decode.field(
    "priceRangeV2",
    product_price_range_decoder(),
  )
  use compare_at_price_range <- decode.field(
    "compareAtPriceRange",
    decode.optional(product_compare_at_price_range_decoder()),
  )
  use variants <- decode.field("variants", product_variant_connection_decoder())
  use featured_media <- decode.field(
    "featuredMedia",
    decode.optional(media_decoder()),
  )
  use media <- decode.field("media", media_connection_decoder())
  use seo <- decode.field("seo", decode.optional(seo_decoder()))
  use tags <- decode.field("tags", decode.list(decode.string))
  use updated_at <- decode.field("updatedAt", decode.string)
  use created_at <- decode.field("createdAt", decode.string)
  use published_at <- decode.field(
    "publishedAt",
    decode.optional(decode.string),
  )
  use variants_count <- decode.field("variantsCount", variants_count_decoder())
  decode.success(Product(
    id:,
    handle:,
    title:,
    total_inventory:,
    description:,
    description_html:,
    vendor:,
    options:,
    price_range_v2:,
    compare_at_price_range:,
    variants:,
    featured_media:,
    media:,
    seo:,
    tags:,
    updated_at:,
    created_at:,
    published_at:,
    variants_count:,
  ))
}

pub type ProductOption {
  ProductOption(id: String, name: String, values: List(String))
}

fn product_option_to_json(product_option: ProductOption) -> json.Json {
  let ProductOption(id:, name:, values:) = product_option
  json.object([
    #("id", json.string(id)),
    #("name", json.string(name)),
    #("values", json.array(values, json.string)),
  ])
}

fn product_option_decoder() -> decode.Decoder(ProductOption) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use values <- decode.field("values", decode.list(decode.string))
  decode.success(ProductOption(id:, name:, values:))
}

pub type Money {
  Money(amount: String, currency_code: String)
}

fn money_to_json(money: Money) -> json.Json {
  let Money(amount:, currency_code:) = money
  json.object([
    #("amount", json.string(amount)),
    #("currencyCode", json.string(currency_code)),
  ])
}

fn money_decoder() -> decode.Decoder(Money) {
  use amount <- decode.field("amount", decode.string)
  use currency_code <- decode.field("currencyCode", decode.string)
  decode.success(Money(amount:, currency_code:))
}

pub type ProductPriceRange {
  ProductPriceRange(max_variant_price: Money, min_variant_price: Money)
}

fn product_price_range_to_json(
  product_price_range: ProductPriceRange,
) -> json.Json {
  let ProductPriceRange(max_variant_price:, min_variant_price:) =
    product_price_range
  json.object([
    #("maxVariantPrice", money_to_json(max_variant_price)),
    #("minVariantPrice", money_to_json(min_variant_price)),
  ])
}

fn product_price_range_decoder() -> decode.Decoder(ProductPriceRange) {
  use max_variant_price <- decode.field("maxVariantPrice", money_decoder())
  use min_variant_price <- decode.field("minVariantPrice", money_decoder())
  decode.success(ProductPriceRange(max_variant_price:, min_variant_price:))
}

pub type ProductCompareAtPriceRange {
  ProductCompareAtPriceRange(
    max_variant_compare_at_price: Option(Money),
    min_variant_compare_at_price: Option(Money),
  )
}

fn product_compare_at_price_range_to_json(
  product_compare_at_price_range: ProductCompareAtPriceRange,
) -> json.Json {
  let ProductCompareAtPriceRange(
    max_variant_compare_at_price:,
    min_variant_compare_at_price:,
  ) = product_compare_at_price_range
  json.object([
    #("maxVariantCompareAtPrice", case max_variant_compare_at_price {
      None -> json.null()
      Some(value) -> money_to_json(value)
    }),
    #("minVariantCompareAtPrice", case min_variant_compare_at_price {
      None -> json.null()
      Some(value) -> money_to_json(value)
    }),
  ])
}

fn product_compare_at_price_range_decoder() -> decode.Decoder(
  ProductCompareAtPriceRange,
) {
  use max_variant_compare_at_price <- decode.field(
    "maxVariantCompareAtPrice",
    decode.optional(money_decoder()),
  )
  use min_variant_compare_at_price <- decode.field(
    "minVariantCompareAtPrice",
    decode.optional(money_decoder()),
  )
  decode.success(ProductCompareAtPriceRange(
    max_variant_compare_at_price:,
    min_variant_compare_at_price:,
  ))
}

pub type ProductVariantConnection {
  ProductVariantConnection(edges: List(ProductVariantEdge))
}

fn product_variant_connection_to_json(
  product_variant_connection: ProductVariantConnection,
) -> json.Json {
  let ProductVariantConnection(edges:) = product_variant_connection
  json.object([
    #("edges", json.array(edges, product_variant_edge_to_json)),
  ])
}

fn product_variant_connection_decoder() -> decode.Decoder(
  ProductVariantConnection,
) {
  use edges <- decode.field(
    "edges",
    decode.list(product_variant_edge_decoder()),
  )
  decode.success(ProductVariantConnection(edges:))
}

pub type ProductVariantEdge {
  ProductVariantEdge(node: ProductVariant)
}

fn product_variant_edge_to_json(
  product_variant_edge: ProductVariantEdge,
) -> json.Json {
  let ProductVariantEdge(node:) = product_variant_edge
  json.object([
    #("node", product_variant_to_json(node)),
  ])
}

fn product_variant_edge_decoder() -> decode.Decoder(ProductVariantEdge) {
  use node <- decode.field("node", product_variant_decoder())
  decode.success(ProductVariantEdge(node:))
}

pub type ProductVariant {
  ProductVariant(
    id: String,
    title: String,
    available_for_sale: Bool,
    selected_options: List(SelectedOption),
    price: String,
  )
}

fn product_variant_to_json(product_variant: ProductVariant) -> json.Json {
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
    #("selectedOptions", json.array(selected_options, selected_option_to_json)),
    #("price", json.string(price)),
  ])
}

fn product_variant_decoder() -> decode.Decoder(ProductVariant) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use available_for_sale <- decode.field("availableForSale", decode.bool)
  use selected_options <- decode.field(
    "selectedOptions",
    decode.list(selected_option_decoder()),
  )
  use price <- decode.field("price", decode.string)
  decode.success(ProductVariant(
    id:,
    title:,
    available_for_sale:,
    selected_options:,
    price:,
  ))
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

fn selected_option_decoder() -> decode.Decoder(SelectedOption) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(SelectedOption(name:, value:))
}

pub type MediaConnection {
  MediaConnection(edges: List(MediaEdge))
}

fn media_connection_to_json(media_connection: MediaConnection) -> json.Json {
  let MediaConnection(edges:) = media_connection
  json.object([
    #("edges", json.array(edges, media_edge_to_json)),
  ])
}

fn media_connection_decoder() -> decode.Decoder(MediaConnection) {
  use edges <- decode.field("edges", decode.list(media_edge_decoder()))
  decode.success(MediaConnection(edges:))
}

pub type MediaEdge {
  MediaEdge(node: Media)
}

fn media_edge_to_json(media_edge: MediaEdge) -> json.Json {
  let MediaEdge(node:) = media_edge
  json.object([
    #("node", media_to_json(node)),
  ])
}

fn media_edge_decoder() -> decode.Decoder(MediaEdge) {
  use node <- decode.field("node", media_decoder())
  decode.success(MediaEdge(node:))
}

pub type Media {
  Media(
    id: String,
    media_content_type: String,
    alt: Option(String),
    preview: Option(Preview),
  )
}

fn media_to_json(media: Media) -> json.Json {
  let Media(id:, media_content_type:, alt:, preview:) = media
  json.object([
    #("id", json.string(id)),
    #("mediaContentType", json.string(media_content_type)),
    #("alt", case alt {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("preview", case preview {
      None -> json.null()
      Some(value) -> preview_to_json(value)
    }),
  ])
}

fn media_decoder() -> decode.Decoder(Media) {
  use id <- decode.field("id", decode.string)
  use media_content_type <- decode.field("mediaContentType", decode.string)
  use alt <- decode.field("alt", decode.optional(decode.string))
  use preview <- decode.field("preview", decode.optional(preview_decoder()))
  decode.success(Media(id:, media_content_type:, alt:, preview:))
}

pub type Preview {
  Preview(image: Option(Image), status: String)
}

fn preview_to_json(preview: Preview) -> json.Json {
  let Preview(image:, status:) = preview
  json.object([
    #("image", case image {
      None -> json.null()
      Some(value) -> image_to_json(value)
    }),
    #("status", json.string(status)),
  ])
}

fn preview_decoder() -> decode.Decoder(Preview) {
  use image <- decode.field("image", decode.optional(image_decoder()))
  use status <- decode.field("status", decode.string)
  decode.success(Preview(image:, status:))
}

pub type Image {
  Image(
    url: String,
    id: String,
    alt_text: Option(String),
    width: Option(Int),
    height: Option(Int),
    thumbhash: Option(String),
  )
}

fn image_to_json(image: Image) -> json.Json {
  let Image(url:, id:, alt_text:, width:, height:, thumbhash:) = image
  json.object([
    #("url", json.string(url)),
    #("id", json.string(id)),
    #("altText", case alt_text {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("width", case width {
      None -> json.null()
      Some(value) -> json.int(value)
    }),
    #("height", case height {
      None -> json.null()
      Some(value) -> json.int(value)
    }),
    #("thumbhash", case thumbhash {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
  ])
}

fn image_decoder() -> decode.Decoder(Image) {
  use url <- decode.field("url", decode.string)
  use id <- decode.field("id", decode.string)
  use alt_text <- decode.field("altText", decode.optional(decode.string))
  use width <- decode.field("width", decode.optional(decode.int))
  use height <- decode.field("height", decode.optional(decode.int))
  use thumbhash <- decode.field("thumbhash", decode.optional(decode.string))
  decode.success(Image(url:, id:, alt_text:, width:, height:, thumbhash:))
}

pub type Seo {
  Seo(description: Option(String), title: Option(String))
}

fn seo_to_json(seo: Seo) -> json.Json {
  let Seo(description:, title:) = seo
  json.object([
    #("description", case description {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("title", case title {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
  ])
}

fn seo_decoder() -> decode.Decoder(Seo) {
  use description <- decode.field("description", decode.optional(decode.string))
  use title <- decode.field("title", decode.optional(decode.string))
  decode.success(Seo(description:, title:))
}

pub type VariantsCount {
  VariantsCount(count: Int, precision: String)
}

fn variants_count_to_json(variants_count: VariantsCount) -> json.Json {
  let VariantsCount(count:, precision:) = variants_count
  json.object([
    #("count", json.int(count)),
    #("precision", json.string(precision)),
  ])
}

fn variants_count_decoder() -> decode.Decoder(VariantsCount) {
  use count <- decode.field("count", decode.int)
  use precision <- decode.field("precision", decode.string)
  decode.success(VariantsCount(count:, precision:))
}

/// Queries
///
pub const get_product_recommendations_query = "
      query getProductRecommendations($productId: ID!) {
        productRecommendations(productId: $productId) {
          ...product
        }
      }
      "
  <> product_fragment

pub const get_product_query = "
      query getProduct($handle: ProductIdentifierInput!){
        productByIdentifier(identifier:$handle){
          ...product
        }
      }
    "
  <> product_fragment

pub const product_fragment = "
      fragment product on Product {
        id
        handle
        title
        totalInventory
        description
        descriptionHtml
        vendor
        options {
          id
          name
          values
        }
        priceRangeV2 {
          maxVariantPrice {
            amount
            currencyCode
          }
          minVariantPrice {
            amount
            currencyCode
          }
        }
        compareAtPriceRange {
          maxVariantCompareAtPrice {
            amount
            currencyCode
          }
          minVariantCompareAtPrice {
            amount
            currencyCode
          }
        }
        variants(first: 20) {
          edges {
            node {
              id
              title
              availableForSale
              selectedOptions {
                name
                value
              }
              price
            }
          }
        }
        featuredMedia {
          id
          mediaContentType
          alt
          preview {
            image {
              url
              id
              altText
              width
              height
              thumbhash
            }
            status
          }
        }
        media(first: 20) {
          edges {
            node {
              id
              mediaContentType
              alt
              preview {
                image {
                  url
                  id
                  altText
                  width
                  height
                  thumbhash
                }
                status
              }
            }
          }
        }
        seo {
          description
          title
        }
        tags
        updatedAt
        createdAt
        publishedAt
        variantsCount {
          count
          precision
        }
      }
      "
