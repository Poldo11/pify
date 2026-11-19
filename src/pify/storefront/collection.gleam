//// Storefront collections: one by handle, a page of them, and a page of
//// the products in one.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql.{type Connection}
import pify/storefront.{
  type Image, type MetafieldIdentifier, type Page, type Seo,
  type StorefrontClient,
}
import pify/storefront/product.{type Product}

pub type Collection {
  Collection(
    id: String,
    handle: String,
    title: String,
    description: String,
    description_html: String,
    updated_at: String,
    image: Option(Image),
    seo: Seo,
  )
}

/// The sort keys of the products in a collection, which differ from the
/// sort keys of the catalog.
pub type CollectionSort {
  CollectionSortCollectionDefault
  CollectionSortManual
  CollectionSortTitle
  CollectionSortPrice
  CollectionSortBestSelling
  CollectionSortCreated
  CollectionSortId
  CollectionSortRelevance
}

pub fn collection_sort_to_string(sort: CollectionSort) -> String {
  case sort {
    CollectionSortCollectionDefault -> "COLLECTION_DEFAULT"
    CollectionSortManual -> "MANUAL"
    CollectionSortTitle -> "TITLE"
    CollectionSortPrice -> "PRICE"
    CollectionSortBestSelling -> "BEST_SELLING"
    CollectionSortCreated -> "CREATED"
    CollectionSortId -> "ID"
    CollectionSortRelevance -> "RELEVANCE"
  }
}

pub type CollectionPage {
  CollectionPage(
    first: Int,
    after: Option(String),
    sort: CollectionSort,
    reverse: Bool,
  )
}

/// The first page of a collection in the order the shop set.
pub fn first_page(first: Int) -> CollectionPage {
  CollectionPage(
    first:,
    after: option.None,
    sort: CollectionSortCollectionDefault,
    reverse: False,
  )
}

pub const fields =
  " id handle title description descriptionHtml updatedAt"
  <> " image {"
  <> storefront.image_fields
  <> " }"
  <> storefront.seo_fields

pub const by_handle_query =
  "query StorefrontCollection($handle: String!) {"
  <> " collection(handle: $handle) {"
  <> fields
  <> " } }"

pub fn by_handle(
  client: StorefrontClient,
  handle: String,
) -> Effect(Result(Option(Collection), ShopifyError), key) {
  storefront.graphql(
    client,
    by_handle_query,
    json.object([#("handle", json.string(handle))]),
  )
  |> execute.run(decode.field(
    "collection",
    decode.optional(decoder()),
    decode.success,
  ))
}

pub const list_query =
  "query StorefrontCollections($first: Int!, $after: String) {"
  <> " collections(first: $first, after: $after) { nodes {"
  <> fields
  <> " } pageInfo { hasNextPage endCursor } } }"

pub fn list(
  client: StorefrontClient,
  page: Page,
) -> Effect(Result(Connection(Collection), ShopifyError), key) {
  storefront.graphql(
    client,
    list_query,
    storefront.page_variables(page.first, page.after, []),
  )
  |> execute.run(decode.field(
    "collections",
    graphql.connection_decoder(decoder()),
    decode.success,
  ))
}

pub const products_query =
  "query StorefrontCollectionProducts($handle: String!, $first: Int!,"
  <> " $after: String, $sortKey: ProductCollectionSortKeys, $reverse: Boolean,"
  <> " $identifiers: [HasMetafieldsIdentifier!]!) {"
  <> " collection(handle: $handle) {"
  <> " products(first: $first, after: $after, sortKey: $sortKey, reverse: $reverse) {"
  <> " nodes {"
  <> product.page_fields
  <> " } pageInfo { hasNextPage endCursor } } } }"

/// `Ok(None)` when no collection has the handle.
pub fn products(
  client: StorefrontClient,
  handle: String,
  page: CollectionPage,
  metafields: List(MetafieldIdentifier),
) -> Effect(Result(Option(Connection(Product)), ShopifyError), key) {
  storefront.graphql(
    client,
    products_query,
    products_variables(handle, page, metafields),
  )
  |> execute.run(decode.field(
    "collection",
    decode.optional(decode.field(
      "products",
      graphql.connection_decoder(product.decoder()),
      decode.success,
    )),
    decode.success,
  ))
}

pub fn products_variables(
  handle: String,
  page: CollectionPage,
  metafields: List(MetafieldIdentifier),
) -> Json {
  storefront.page_variables(page.first, page.after, [
    #("handle", json.string(handle)),
    #("sortKey", json.string(collection_sort_to_string(page.sort))),
    #("reverse", json.bool(page.reverse)),
    #("identifiers", storefront.metafield_identifiers_to_json(metafields)),
  ])
}

pub fn decoder() -> decode.Decoder(Collection) {
  use id <- decode.field("id", decode.string)
  use handle <- decode.field("handle", decode.string)
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  use description_html <- decode.field("descriptionHtml", decode.string)
  use updated_at <- decode.field("updatedAt", decode.string)
  use image <- graphql.optional("image", storefront.image_decoder())
  use seo <- decode.field("seo", storefront.seo_decoder())
  decode.success(Collection(
    id:,
    handle:,
    title:,
    description:,
    description_html:,
    updated_at:,
    image:,
    seo:,
  ))
}
