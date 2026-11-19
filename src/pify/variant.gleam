//// Product variants: find by SKU, create, write price, compare-at price,
//// barcode, SKU, option value and the inventory policy.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/set
import gleam/string
import midas/effect.{type Effect}
import pify.{type Client}
import pify/decimal.{type Decimal}
import pify/error.{type ShopifyError}
import pify/execute
import pify/graphql
import pify/request

pub type Variant {
  Variant(
    id: String,
    sku: Option(String),
    barcode: Option(String),
    price: Decimal,
    compare_at_price: Option(Decimal),
    product_id: String,
    inventory_item_id: String,
    /// Shopify counts stock for the item. An untracked item has no
    /// quantity to write.
    tracked: Bool,
    /// `None` when the response did not carry it.
    inventory_policy: Option(InventoryPolicy),
  )
}

/// Whether customers can buy the variant when it is out of stock
/// (`ProductVariantInventoryPolicy`).
pub type InventoryPolicy {
  /// `DENY`: no sale at zero available.
  InventoryPolicyDeny
  /// `CONTINUE`: sales go on below zero.
  InventoryPolicyContinue
}

pub fn inventory_policy_to_string(policy: InventoryPolicy) -> String {
  case policy {
    InventoryPolicyDeny -> "DENY"
    InventoryPolicyContinue -> "CONTINUE"
  }
}

fn tracked(tracking: InventoryTracking) -> Bool {
  case tracking {
    InventoryTracked -> True
    InventoryUntracked -> False
  }
}

pub fn inventory_policy_decoder() -> decode.Decoder(InventoryPolicy) {
  use raw <- decode.then(decode.string)
  case raw {
    "DENY" -> decode.success(InventoryPolicyDeny)
    "CONTINUE" -> decode.success(InventoryPolicyContinue)
    _ -> decode.failure(InventoryPolicyDeny, "ProductVariantInventoryPolicy")
  }
}

/// Whether Shopify counts stock for the variant's inventory item
/// (`InventoryItemInput.tracked`).
pub type InventoryTracking {
  InventoryTracked
  InventoryUntracked
}

/// One value of one product option, as `VariantOptionValueInput` and
/// `selectedOptions` carry it: `option_name` is the option, such as
/// "Formato", and `name` is the value, such as "Capa dura".
pub type OptionValue {
  OptionValue(option_name: String, name: String)
}

pub type VariantUpdate {
  VariantUpdate(
    id: String,
    price: Decimal,
    /// `None` clears the compare-at price.
    compare_at_price: Option(Decimal),
    /// `None` leaves the barcode as it is.
    barcode: Option(String),
    /// Written to `inventoryItem.sku`. `None` leaves the SKU as it is.
    sku: Option(String),
    /// The variant's value of an option the product has. `None` leaves it
    /// as it is.
    option: Option(OptionValue),
  )
}

/// A variant to create, under the product's one option. `productSet` and
/// `bulk_create` take the same input.
pub type VariantCreate {
  VariantCreate(
    option_value: String,
    sku: String,
    barcode: Option(String),
    price: Decimal,
    /// `None` sends no compare-at price.
    compare_at_price: Option(Decimal),
    inventory_policy: InventoryPolicy,
    tracking: InventoryTracking,
  )
}

/// A variant as a product read or write answers it.
pub type VariantSummary {
  VariantSummary(
    id: String,
    sku: Option(String),
    inventory_item_id: String,
    tracking: InventoryTracking,
    selected_options: List(OptionValue),
  )
}

/// The variant as Shopify stored it after `bulk_update`.
pub type UpdatedVariant {
  UpdatedVariant(
    id: String,
    price: Decimal,
    compare_at_price: Option(Decimal),
    barcode: Option(String),
  )
}

/// SKUs per search. Fifty `sku:` terms keep the search string short.
pub const skus_per_search = 50

/// Variants per `productVariantsBulkUpdate` call, Shopify's array limit.
pub const variants_per_update = 250

/// Search by SKU, `skus_per_search` at a time. Shopify's search tokenizes
/// and can match near SKUs, so only variants whose SKU equals a SKU of the
/// same search come back. The search ignores case, so the match ignores case
/// and surrounding spaces too. A blank SKU is never searched.
pub fn find_by_skus(
  client: Client,
  skus: List(String),
) -> Effect(Result(List(Variant), ShopifyError), key) {
  skus
  |> list.filter(fn(sku) { string.trim(sku) != "" })
  |> list.unique
  |> list.sized_chunk(skus_per_search)
  |> execute.try_each(fn(chunk) {
    execute.collect_pages(fn(cursor) {
      request.graphql(client, search_query, search_variables(chunk, cursor))
      |> execute.run(search_decoder())
    })
    |> execute.map(fn(found) {
      let keys = set.from_list(list.map(chunk, sku_key))
      list.filter(found, fn(found_variant) {
        case found_variant.sku {
          option.Some(sku) -> set.contains(keys, sku_key(sku))
          option.None -> False
        }
      })
    })
  })
  |> execute.map(list.flatten)
}

fn sku_key(sku: String) -> String {
  string.lowercase(string.trim(sku))
}

pub const search_query =
  "query VariantsBySku($query: String!, $after: String) {"
  <> " productVariants(first: 250, query: $query, after: $after) {"
  <> " nodes { id sku barcode price compareAtPrice inventoryPolicy"
  <> " product { id } inventoryItem { id tracked } }"
  <> " pageInfo { hasNextPage endCursor } } }"

pub fn search_variables(skus: List(String), after: Option(String)) -> Json {
  json.object([
    #("query", json.string(graphql.search_any("sku", skus))),
    #("after", json.nullable(after, json.string)),
  ])
}

pub fn search_decoder() -> decode.Decoder(graphql.Connection(Variant)) {
  decode.field(
    "productVariants",
    graphql.connection_decoder(variant_decoder()),
    decode.success,
  )
}

/// Write price, compare-at price and barcode for variants of one product,
/// `variants_per_update` per call. A call is all or nothing: any
/// `userErrors` fail it and nothing in it is written.
pub fn bulk_update(
  client: Client,
  product_id: String,
  updates: List(VariantUpdate),
) -> Effect(Result(List(UpdatedVariant), ShopifyError), key) {
  updates
  |> list.sized_chunk(variants_per_update)
  |> execute.try_each(fn(chunk) {
    request.graphql(
      client,
      bulk_update_mutation,
      bulk_update_variables(product_id, chunk),
    )
    |> execute.run_mutation(
      "productVariantsBulkUpdate",
      decode.field(
        "productVariants",
        decode.list(updated_variant_decoder()),
        decode.success,
      ),
    )
  })
  |> execute.map(list.flatten)
}

/// Write the inventory policy of variants of one product,
/// `variants_per_update` per call. A call is all or nothing.
pub fn set_inventory_policies(
  client: Client,
  product_id: String,
  policies: List(#(String, InventoryPolicy)),
) -> Effect(Result(List(String), ShopifyError), key) {
  policies
  |> list.sized_chunk(variants_per_update)
  |> execute.try_each(fn(chunk) {
    request.graphql(
      client,
      set_inventory_policies_mutation,
      set_inventory_policies_variables(product_id, chunk),
    )
    |> execute.run_mutation(
      "productVariantsBulkUpdate",
      decode.field(
        "productVariants",
        decode.list(decode.field("id", decode.string, decode.success)),
        decode.success,
      ),
    )
  })
  |> execute.map(list.flatten)
}

pub const set_inventory_policies_mutation =
  "mutation VariantsInventoryPolicy($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {"
  <> " productVariantsBulkUpdate(productId: $productId, variants: $variants) {"
  <> " productVariants { id inventoryPolicy }"
  <> " userErrors { field message code } } }"

pub fn set_inventory_policies_variables(
  product_id: String,
  policies: List(#(String, InventoryPolicy)),
) -> Json {
  json.object([
    #("productId", json.string(product_id)),
    #(
      "variants",
      json.array(policies, fn(entry) {
        let #(variant_id, policy) = entry
        json.object([
          #("id", json.string(variant_id)),
          #("inventoryPolicy", json.string(inventory_policy_to_string(policy))),
        ])
      }),
    ),
  ])
}

pub const bulk_update_mutation =
  "mutation VariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {"
  <> " productVariantsBulkUpdate(productId: $productId, variants: $variants) {"
  <> " productVariants { id price compareAtPrice barcode }"
  <> " userErrors { field message code } } }"

pub fn bulk_update_variables(
  product_id: String,
  updates: List(VariantUpdate),
) -> Json {
  json.object([
    #("productId", json.string(product_id)),
    #("variants", json.array(updates, update_input)),
  ])
}

fn update_input(update: VariantUpdate) -> Json {
  let barcode = case update.barcode {
    option.Some(barcode) -> [#("barcode", json.string(barcode))]
    option.None -> []
  }
  let sku = case update.sku {
    option.Some(sku) -> [
      #("inventoryItem", json.object([#("sku", json.string(sku))])),
    ]
    option.None -> []
  }
  let option_values = case update.option {
    option.Some(value) -> [
      #("optionValues", json.preprocessed_array([option_value_input(value)])),
    ]
    option.None -> []
  }
  json.object(
    list.flatten([
      [
        #("id", json.string(update.id)),
        #("price", json.string(decimal.to_string(update.price))),
        #(
          "compareAtPrice",
          json.nullable(update.compare_at_price, fn(amount) {
            json.string(decimal.to_string(amount))
          }),
        ),
      ],
      barcode,
      sku,
      option_values,
    ]),
  )
}

/// Create variants on one product, `variants_per_update` per call, under
/// the product's option `option_name`. The strategy is `DEFAULT`: Shopify
/// deletes the standalone "Default Title" variant when it is the only one
/// and keeps a standalone variant with a custom value. A call is all or
/// nothing.
pub fn bulk_create(
  client: Client,
  product_id: String,
  option_name: String,
  variants: List(VariantCreate),
) -> Effect(Result(List(VariantSummary), ShopifyError), key) {
  variants
  |> list.sized_chunk(variants_per_update)
  |> execute.try_each(fn(chunk) {
    request.graphql(
      client,
      bulk_create_mutation,
      bulk_create_variables(product_id, option_name, chunk),
    )
    |> execute.run_mutation(
      "productVariantsBulkCreate",
      decode.field(
        "productVariants",
        decode.list(summary_decoder()),
        decode.success,
      ),
    )
  })
  |> execute.map(list.flatten)
}

pub const bulk_create_mutation =
  "mutation VariantsBulkCreate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {"
  <> " productVariantsBulkCreate(productId: $productId, variants: $variants, strategy: DEFAULT) {"
  <> " productVariants {"
  <> summary_fields
  <> " }"
  <> " userErrors { field message code } } }"

pub fn bulk_create_variables(
  product_id: String,
  option_name: String,
  variants: List(VariantCreate),
) -> Json {
  json.object([
    #("productId", json.string(product_id)),
    #("variants", json.array(variants, create_input(option_name, _))),
  ])
}

/// One new variant as `ProductVariantsBulkInput` and
/// `ProductVariantSetInput` both read it. The SKU rides `inventoryItem`,
/// which both inputs take.
pub fn create_input(option_name: String, variant: VariantCreate) -> Json {
  let barcode = case variant.barcode {
    option.Some(barcode) -> [#("barcode", json.string(barcode))]
    option.None -> []
  }
  let compare_at_price = case variant.compare_at_price {
    option.Some(amount) -> [
      #("compareAtPrice", json.string(decimal.to_string(amount))),
    ]
    option.None -> []
  }
  json.object(
    list.flatten([
      [
        #(
          "optionValues",
          json.preprocessed_array([
            option_value_input(OptionValue(
              option_name:,
              name: variant.option_value,
            )),
          ]),
        ),
        #("price", json.string(decimal.to_string(variant.price))),
        #(
          "inventoryPolicy",
          json.string(inventory_policy_to_string(variant.inventory_policy)),
        ),
        #(
          "inventoryItem",
          json.object([
            #("sku", json.string(variant.sku)),
            #("tracked", json.bool(tracked(variant.tracking))),
          ]),
        ),
      ],
      barcode,
      compare_at_price,
    ]),
  )
}

fn option_value_input(value: OptionValue) -> Json {
  json.object([
    #("optionName", json.string(value.option_name)),
    #("name", json.string(value.name)),
  ])
}

/// The fields `summary_decoder` reads.
pub const summary_fields =
  " id sku inventoryItem { id tracked } selectedOptions { name value }"

pub fn summary_decoder() -> decode.Decoder(VariantSummary) {
  use id <- decode.field("id", decode.string)
  use sku <- graphql.optional("sku", decode.string)
  use inventory_item_id <- decode.subfield(
    ["inventoryItem", "id"],
    decode.string,
  )
  use tracked <- decode.subfield(["inventoryItem", "tracked"], decode.bool)
  use selected_options <- decode.field(
    "selectedOptions",
    decode.list({
      use option_name <- decode.field("name", decode.string)
      use name <- decode.field("value", decode.string)
      decode.success(OptionValue(option_name:, name:))
    }),
  )
  decode.success(VariantSummary(
    id:,
    sku:,
    inventory_item_id:,
    tracking: case tracked {
      True -> InventoryTracked
      False -> InventoryUntracked
    },
    selected_options:,
  ))
}

fn variant_decoder() -> decode.Decoder(Variant) {
  use id <- decode.field("id", decode.string)
  use sku <- graphql.optional("sku", decode.string)
  use barcode <- graphql.optional("barcode", decode.string)
  use price <- decode.field("price", decimal.decoder())
  use compare_at_price <- graphql.optional("compareAtPrice", decimal.decoder())
  use product_id <- decode.subfield(["product", "id"], decode.string)
  use inventory_item_id <- decode.subfield(
    ["inventoryItem", "id"],
    decode.string,
  )
  use tracked <- decode.subfield(["inventoryItem", "tracked"], decode.bool)
  use inventory_policy <- graphql.optional(
    "inventoryPolicy",
    inventory_policy_decoder(),
  )
  decode.success(Variant(
    id:,
    sku:,
    barcode:,
    price:,
    compare_at_price:,
    product_id:,
    inventory_item_id:,
    tracked:,
    inventory_policy:,
  ))
}

fn updated_variant_decoder() -> decode.Decoder(UpdatedVariant) {
  use id <- decode.field("id", decode.string)
  use price <- decode.field("price", decimal.decoder())
  use compare_at_price <- graphql.optional("compareAtPrice", decimal.decoder())
  use barcode <- graphql.optional("barcode", decode.string)
  decode.success(UpdatedVariant(id:, price:, compare_at_price:, barcode:))
}
