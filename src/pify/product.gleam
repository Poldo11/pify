//// Products: create one with its option, variants and files in one call,
//// read it back, update its fields and status, and replace its media.
////
//// `productSet` replaces the whole variant list it is given and deletes the
//// variants left out, so `set` only creates. An existing product changes
//// through `update`, `set_status`, `replace_media` and the `variant`
//// writes.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import midas/effect.{type Effect}
import pify.{type Client}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request
import pify/variant.{type VariantCreate, type VariantSummary}

/// The status a write sets (`ProductStatus`). A draft is hidden from every
/// sales channel.
pub type ProductStatus {
  ProductStatusActive
  ProductStatusDraft
}

pub fn product_status_to_string(status: ProductStatus) -> String {
  case status {
    ProductStatusActive -> "ACTIVE"
    ProductStatusDraft -> "DRAFT"
  }
}

/// A new product with one option. Each variant holds a value of that
/// option, and the values must differ.
pub type ProductSet {
  ProductSet(
    title: String,
    description_html: String,
    /// `None` lets Shopify build the handle from the title.
    handle: Option(String),
    status: ProductStatus,
    option_name: String,
    variants: List(VariantCreate),
    /// Image URLs Shopify downloads, in gallery order.
    files: List(String),
  )
}

/// A product as `get` and `set` read it: the first 250 variants, Shopify's
/// page limit, and the first 50 media. `description_html` is `""` when the
/// product has no description.
pub type Product {
  Product(
    id: String,
    description_html: String,
    options: List(ProductOption),
    variants: List(VariantSummary),
    media_ids: List(String),
  )
}

/// One option and the values its variants use. A linked option takes its
/// values from a metafield, and Shopify refuses a value name written to it.
pub type ProductOption {
  ProductOption(
    name: String,
    values: List(String),
    linked_metafield: Option(LinkedMetafield),
  )
}

/// The metafield a linked option reads its values from. The schema leaves
/// both fields nullable.
pub type LinkedMetafield {
  LinkedMetafield(namespace: Option(String), key: Option(String))
}

const product_fields =
  " id descriptionHtml options { name values linkedMetafield { namespace key } }"
  <> " variants(first: 250) { nodes {"
  <> variant.summary_fields
  <> " } }"
  <> " media(first: 50) { nodes { id } }"

/// Create the product with its option, variants and files in one
/// synchronous `productSet`. A crash after the call leaves a whole product,
/// never half of one. The product is on no sales channel yet: see
/// `publication.publish`.
pub fn set(
  client: Client,
  product: ProductSet,
) -> Effect(Result(Product, ShopifyError), key) {
  request.graphql(client, set_mutation, set_variables(product))
  |> execute.run_mutation(
    "productSet",
    decode.field("product", product_decoder(), decode.success),
  )
}

pub const set_mutation =
  "mutation ProductSet($input: ProductSetInput!, $synchronous: Boolean!) {"
  <> " productSet(input: $input, synchronous: $synchronous) {"
  <> " product {"
  <> product_fields
  <> " }"
  <> " userErrors { field message code } } }"

pub fn set_variables(product: ProductSet) -> Json {
  let handle = case product.handle {
    option.Some(handle) -> [#("handle", json.string(handle))]
    option.None -> []
  }
  let values =
    product.variants
    |> list.map(fn(new_variant) { new_variant.option_value })
    |> list.unique
  let input = [
    #("title", json.string(product.title)),
    #("descriptionHtml", json.string(product.description_html)),
    #("status", json.string(product_status_to_string(product.status))),
    #(
      "productOptions",
      json.preprocessed_array([
        json.object([
          #("name", json.string(product.option_name)),
          #("position", json.int(1)),
          #(
            "values",
            json.array(values, fn(value) {
              json.object([#("name", json.string(value))])
            }),
          ),
        ]),
      ]),
    ),
    #(
      "variants",
      json.array(product.variants, variant.create_input(product.option_name, _)),
    ),
    #("files", json.array(product.files, file_input)),
    ..handle
  ]
  json.object([
    #("input", json.object(input)),
    #("synchronous", json.bool(True)),
  ])
}

fn file_input(url: String) -> Json {
  json.object([
    #("originalSource", json.string(url)),
    #("contentType", json.string("IMAGE")),
  ])
}

/// Read one product. `None` when Shopify holds no product with that id,
/// such as one a merchant deleted.
pub fn get(
  client: Client,
  product_id: String,
) -> Effect(Result(Option(Product), ShopifyError), key) {
  request.graphql(client, get_query, id_variables(product_id))
  |> execute.run(decode.field(
    "product",
    decode.optional(product_decoder()),
    decode.success,
  ))
}

pub const get_query =
  "query ProductGet($id: ID!) { product(id: $id) {" <> product_fields <> " } }"

fn id_variables(product_id: String) -> Json {
  json.object([#("id", json.string(product_id))])
}

/// The most products one `variant_counts` call reads.
pub const products_per_count = 250

/// Each product's count of variants, by id. A product Shopify does not hold
/// is left out.
pub fn variant_counts(
  client: Client,
  product_ids: List(String),
) -> Effect(Result(List(#(String, Int)), ShopifyError), key) {
  product_ids
  |> list.unique
  |> list.sized_chunk(products_per_count)
  |> execute.try_each(fn(chunk) {
    request.graphql(
      client,
      variant_counts_query,
      variant_counts_variables(chunk),
    )
    |> execute.run(variant_counts_decoder())
  })
  |> execute.map(list.flatten)
}

pub const variant_counts_query =
  "query ProductVariantCounts($ids: [ID!]!) { nodes(ids: $ids) {"
  <> " ... on Product { id variantsCount { count } } } }"

pub fn variant_counts_variables(product_ids: List(String)) -> Json {
  json.object([#("ids", json.array(product_ids, json.string))])
}

/// A deleted product reads `null`, and a node of another type reads `{}`:
/// both are left out. A node with an `id` is a product, so it must carry its
/// count.
pub fn variant_counts_decoder() -> decode.Decoder(List(#(String, Int))) {
  let node = {
    use id <- decode.optional_field(
      "id",
      option.None,
      decode.optional(decode.string),
    )
    case id {
      option.None -> decode.success(option.None)
      option.Some(id) -> {
        use count <- decode.subfield(["variantsCount", "count"], decode.int)
        decode.success(option.Some(#(id, count)))
      }
    }
  }
  decode.field(
    "nodes",
    decode.list(decode.optional(node) |> decode.map(option.flatten)),
    fn(nodes) { decode.success(option.values(nodes)) },
  )
}

/// Write the status, and the title and the description each when it is
/// `Some`. `None` leaves the product's own. The handle stays, so the
/// product's address does not change.
pub fn update(
  client: Client,
  product_id: String,
  title title: Option(String),
  description_html description_html: Option(String),
  status status: ProductStatus,
) -> Effect(Result(Nil, ShopifyError), key) {
  run_update(
    client,
    update_variables(
      product_id,
      list.flatten([
        optional_text("title", title),
        optional_text("descriptionHtml", description_html),
        [#("status", json.string(product_status_to_string(status)))],
      ]),
    ),
  )
}

fn optional_text(key: String, value: Option(String)) -> List(#(String, Json)) {
  case value {
    option.None -> []
    option.Some(text) -> [#(key, json.string(text))]
  }
}

/// Write the status alone, such as `ProductStatusDraft` to hide the product.
pub fn set_status(
  client: Client,
  product_id: String,
  status: ProductStatus,
) -> Effect(Result(Nil, ShopifyError), key) {
  run_update(
    client,
    update_variables(product_id, [
      #("status", json.string(product_status_to_string(status))),
    ]),
  )
}

/// Add the images at `add`, then delete the media `remove` names. Adding
/// first keeps the gallery from going empty when the second call fails.
/// Either list may be empty, and an empty list sends no call.
pub fn replace_media(
  client: Client,
  product_id: String,
  remove remove: List(String),
  add add: List(String),
) -> Effect(Result(Nil, ShopifyError), key) {
  use added <- effect.do(add_media(client, product_id, add))
  case added {
    Error(shopify_error) -> effect.Done(Error(shopify_error))
    Ok(Nil) -> delete_media(client, product_id, remove)
  }
}

fn add_media(
  client: Client,
  product_id: String,
  urls: List(String),
) -> Effect(Result(Nil, ShopifyError), key) {
  case urls {
    [] -> effect.Done(Ok(Nil))
    [_, ..] -> run_update(client, add_media_variables(product_id, urls))
  }
}

fn delete_media(
  client: Client,
  product_id: String,
  media_ids: List(String),
) -> Effect(Result(Nil, ShopifyError), key) {
  case media_ids {
    [] -> effect.Done(Ok(Nil))
    [_, ..] ->
      request.graphql(
        client,
        delete_media_mutation,
        delete_media_variables(product_id, media_ids),
      )
      |> execute.run_mutation("productDeleteMedia", decode.success(Nil))
  }
}

fn run_update(
  client: Client,
  variables: Json,
) -> Effect(Result(Nil, ShopifyError), key) {
  request.graphql(client, update_mutation, variables)
  |> execute.run_mutation("productUpdate", decode.success(Nil))
}

/// `productUpdate` takes `product: ProductUpdateInput`; its `input`
/// argument is deprecated. Its `UserError` has no `code`.
pub const update_mutation =
  "mutation ProductUpdate($product: ProductUpdateInput!, $media: [CreateMediaInput!]) {"
  <> " productUpdate(product: $product, media: $media) {"
  <> " product { id }"
  <> " userErrors { field message } } }"

pub fn update_variables(
  product_id: String,
  fields: List(#(String, Json)),
) -> Json {
  json.object([
    #("product", json.object([#("id", json.string(product_id)), ..fields])),
    #("media", json.null()),
  ])
}

pub fn add_media_variables(product_id: String, urls: List(String)) -> Json {
  json.object([
    #("product", id_variables(product_id)),
    #(
      "media",
      json.array(urls, fn(url) {
        json.object([
          #("originalSource", json.string(url)),
          #("mediaContentType", json.string("IMAGE")),
        ])
      }),
    ),
  ])
}

/// `productDeleteMedia` needs only `write_products`. 2026-07 marks it
/// deprecated for `fileUpdate(referencesToRemove:)`, which needs
/// `write_files` as well. Its errors are `mediaUserErrors`; the alias lets
/// `execute.run_mutation` read them as `userErrors`.
pub const delete_media_mutation =
  "mutation ProductDeleteMedia($productId: ID!, $mediaIds: [ID!]!) {"
  <> " productDeleteMedia(productId: $productId, mediaIds: $mediaIds) {"
  <> " deletedMediaIds"
  <> " userErrors: mediaUserErrors { field message code } } }"

pub fn delete_media_variables(
  product_id: String,
  media_ids: List(String),
) -> Json {
  json.object([
    #("productId", json.string(product_id)),
    #("mediaIds", json.array(media_ids, json.string)),
  ])
}

fn linked_metafield_decoder() -> decode.Decoder(LinkedMetafield) {
  use namespace <- graphql.optional("namespace", decode.string)
  use key <- graphql.optional("key", decode.string)
  decode.success(LinkedMetafield(namespace:, key:))
}

fn product_decoder() -> decode.Decoder(Product) {
  use id <- decode.field("id", decode.string)
  use description_html <- decode.field("descriptionHtml", decode.string)
  use options <- decode.field(
    "options",
    decode.list({
      use name <- decode.field("name", decode.string)
      use values <- decode.field("values", decode.list(decode.string))
      use linked_metafield <- graphql.optional(
        "linkedMetafield",
        linked_metafield_decoder(),
      )
      decode.success(ProductOption(name:, values:, linked_metafield:))
    }),
  )
  use variants <- decode.subfield(
    ["variants", "nodes"],
    decode.list(variant.summary_decoder()),
  )
  use media_ids <- decode.subfield(
    ["media", "nodes"],
    decode.list(decode.field("id", decode.string, decode.success)),
  )
  decode.success(Product(
    id:,
    description_html:,
    options:,
    variants:,
    media_ids:,
  ))
}
