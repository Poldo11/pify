import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import storefront/fragments.{product_fragment}
import storefront/utils.{
  type Connection, type Edge, type Image, type PriceRange, type ProductVariant,
  type Seo, Connection, Edge, image_connection_decoder, image_decoder,
  image_to_json, price_range_decoder, price_range_to_json,
  product_variant_decoder, product_variant_to_json, remove_edges_and_nodes,
  reshape_images, seo_decoder, seo_to_json,
}

// fn get_product(
//   client: ShopifyClient,
//   handle: String,
// ) -> Result(Option(Product), ShopifyError) {
//   let query = get_product_query()
//   let variables = json.object([#("handle", json.string(handle))])
//   fetch(
//     client: client,
//     query: query,
//     variables: Some(variables),
//     decoder: shopify_product_operation_decoder(),
//   )
//   |> result.map(fn(resp) {
//     case resp.body.data.product {
//       Some(product) -> Some(reshape_product(product, True))
//       None -> None
//     }
//   })
// }

// fn get_products(
//   client: ShopifyClient,
//   query: Option(String),
//   reverse: Option(Bool),
//   sort_key: Option(String),
// ) -> Result(Option(List(Product)), ShopifyError) {
//   let main_query = get_products_query()
//   let query = option.unwrap(query, "")
//   let reverse = option.unwrap(reverse, False)
//   let sort_key = option.unwrap(sort_key, "")

//   let variables =
//     json.object([
//       #("query", json.string(query)),
//       #("reverse", json.bool(reverse)),
//       #("sortKey", json.string(sort_key)),
//     ])

//   fetch(
//     client: client,
//     query: main_query,
//     variables: Some(variables),
//     decoder: shopify_products_operation_decoder(),
//   )
//   |> result.map(fn(resp) {
//     let products = resp.body.data.products
//     case products {
//       Some(product) -> Some(reshape_products(remove_edges_and_nodes(product)))
//       None -> None
//     }
//   })
// }

// fn get_products_recommendations(
//   client: ShopifyClient,
//   product_id: String,
// ) -> Result(List(Product), ShopifyError) {
//   {
//     let query = get_product_recommendations_query()
//     let variables = json.object([#("productId", json.string(product_id))])
//     fetch(
//       client: client,
//       query: query,
//       variables: Some(variables),
//       decoder: shopify_product_recommendations_operation_decoder(),
//     )
//     |> result.map(fn(resp) {
//       reshape_products(resp.body.data.product_recommendations)
//     })
//   }
// }

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

fn shopify_product_decoder() -> decode.Decoder(ShopifyProduct) {
  use id <- decode.field("id", decode.string)
  use handle <- decode.field("handle", decode.string)
  use available_for_sale <- decode.field("available_for_sale", decode.bool)
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  use description_html <- decode.field("description_html", decode.string)
  use price_range <- decode.field("price_range", price_range_decoder())
  use variants <- decode.field("variants", product_variant_connection_decoder())
  use featured_image <- decode.field("featured_image", image_decoder())
  use images <- decode.field("images", image_connection_decoder())
  use seo <- decode.field("seo", seo_decoder())
  use tags <- decode.field("tags", decode.list(decode.string))
  use updated_at <- decode.field("updated_at", decode.string)
  decode.success(ShopifyProduct(
    id:,
    handle:,
    available_for_sale:,
    title:,
    description:,
    description_html:,
    price_range:,
    variants:,
    featured_image:,
    images:,
    seo:,
    tags:,
    updated_at:,
  ))
}

// 2. Products

fn product_variant_connection_decoder() -> decode.Decoder(
  Connection(ProductVariant),
) {
  use edges <- decode.field(
    "edges",
    decode.list(product_variant_edges_decoder()),
  )
  decode.success(Connection(edges:))
}

fn product_variant_edges_decoder() -> decode.Decoder(Edge(ProductVariant)) {
  use node <- decode.field("node", product_variant_decoder())
  decode.success(Edge(node:))
}

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

/// Query operations types and decoders
pub type ShopifyGetProductOperation {
  ShopifyProductOperation(
    data: ShopifyProductOperationData,
    variables: ShopifyProductOperationVariables,
  )
}

pub fn shopify_product_operation_decoder() -> decode.Decoder(
  ShopifyGetProductOperation,
) {
  use data <- decode.field("data", shopify_product_operation_data_decoder())
  use variables <- decode.field(
    "variables",
    shopify_product_operation_variables_decoder(),
  )
  decode.success(ShopifyProductOperation(data:, variables:))
}

pub type ShopifyProductOperationData {
  ShopifyProductOperationData(product: Option(ShopifyProduct))
}

fn shopify_product_operation_data_decoder() -> decode.Decoder(
  ShopifyProductOperationData,
) {
  use product <- decode.field(
    "product",
    decode.optional(shopify_product_decoder()),
  )
  decode.success(ShopifyProductOperationData(product:))
}

pub type ShopifyProductOperationVariables {
  ShopifyProductOperationVariables(handle: String)
}

fn shopify_product_operation_variables_decoder() -> decode.Decoder(
  ShopifyProductOperationVariables,
) {
  use handle <- decode.field("handle", decode.string)
  decode.success(ShopifyProductOperationVariables(handle:))
}

pub type GetProductsOperation {
  GetProductsOperation(
    data: ShopifyProductsOperationData,
    variables: ShopifyProductsOperationVariables,
  )
}

pub fn get_products_operation_decoder() -> decode.Decoder(GetProductsOperation) {
  use data <- decode.field("data", shopify_products_operation_data_decoder())
  use variables <- decode.field(
    "variables",
    shopify_products_operation_variables_decoder(),
  )
  decode.success(GetProductsOperation(data:, variables:))
}

pub type ShopifyProductsOperationData {
  ShopifyProductsOperationData(products: Option(Connection(ShopifyProduct)))
}

fn shopify_products_operation_data_decoder() -> decode.Decoder(
  ShopifyProductsOperationData,
) {
  use products <- decode.field(
    "products",
    decode.optional(shopify_product_connection_decoder()),
  )
  decode.success(ShopifyProductsOperationData(products:))
}

pub type ShopifyProductsOperationVariables {
  ShopifyProductsOperationVariables(
    query: String,
    reverse: Bool,
    sort_key: String,
  )
}

fn shopify_products_operation_variables_decoder() -> decode.Decoder(
  ShopifyProductsOperationVariables,
) {
  use query <- decode.field("query", decode.string)
  use reverse <- decode.field("reverse", decode.bool)
  use sort_key <- decode.field("sortKey", decode.string)
  decode.success(ShopifyProductsOperationVariables(query:, reverse:, sort_key:))
}

fn shopify_product_connection_decoder() -> decode.Decoder(
  Connection(ShopifyProduct),
) {
  use edges <- decode.field(
    "edges",
    decode.list(shopify_product_edges_decoder()),
  )
  decode.success(Connection(edges:))
}

fn shopify_product_edges_decoder() -> decode.Decoder(Edge(ShopifyProduct)) {
  use node <- decode.field("node", shopify_product_decoder())
  decode.success(Edge(node:))
}

pub type ShopifyProductRecommendationsOperation {
  ShopifyProductRecommendationsOperation(
    data: ShopifyProductRecommendationsOperationData,
    variables: ShopifyProductRecommendationsOperationVariables,
  )
}

fn shopify_product_recommendations_operation_decoder() -> decode.Decoder(
  ShopifyProductRecommendationsOperation,
) {
  use data <- decode.field(
    "data",
    shopify_product_recommendations_operation_data_decoder(),
  )
  use variables <- decode.field(
    "variables",
    shopify_product_recommendations_operation_variables_decoder(),
  )
  decode.success(ShopifyProductRecommendationsOperation(data:, variables:))
}

pub opaque type ShopifyProductRecommendationsOperationData {
  ShopifyProductRecommendationsOperationData(
    product_recommendations: List(ShopifyProduct),
  )
}

fn shopify_product_recommendations_operation_data_decoder() -> decode.Decoder(
  ShopifyProductRecommendationsOperationData,
) {
  use product_recommendations <- decode.field(
    "productRecommendations",
    decode.list(shopify_product_decoder()),
  )
  decode.success(ShopifyProductRecommendationsOperationData(
    product_recommendations:,
  ))
}

pub opaque type ShopifyProductRecommendationsOperationVariables {
  ShopifyProductRecommendationsOperationVariables(product_id: String)
}

fn shopify_product_recommendations_operation_variables_decoder() -> decode.Decoder(
  ShopifyProductRecommendationsOperationVariables,
) {
  use product_id <- decode.field("productId", decode.string)
  decode.success(ShopifyProductRecommendationsOperationVariables(product_id:))
}
