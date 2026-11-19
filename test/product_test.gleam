import fixtures
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/string
import gleeunit/should
import pify/api_version
import pify/decimal
import pify/error
import pify/product
import pify/publication
import pify/variant
import scripted

const product_id = "gid://shopify/Product/7700000010"

fn paperback() -> variant.VariantCreate {
  variant.VariantCreate(
    option_value: "Brochura",
    sku: "9786500000010",
    barcode: option.Some("9786500000010"),
    price: decimal.from_hundredths(4990),
    compare_at_price: option.Some(decimal.from_hundredths(5990)),
    inventory_policy: variant.InventoryPolicyDeny,
    tracking: variant.InventoryTracked,
  )
}

fn hardcover() -> variant.VariantCreate {
  variant.VariantCreate(
    option_value: "Capa dura",
    sku: "9786500000011",
    barcode: option.None,
    price: decimal.from_hundredths(7990),
    compare_at_price: option.None,
    inventory_policy: variant.InventoryPolicyContinue,
    tracking: variant.InventoryUntracked,
  )
}

fn new_product() -> product.ProductSet {
  product.ProductSet(
    title: "O processo",
    description_html: "<p>Um romance.</p>",
    handle: option.Some("o-processo"),
    status: product.ProductStatusActive,
    option_name: "Formato",
    variants: [paperback(), hardcover()],
    files: ["https://cdn.example.com/capa.jpg"],
  )
}

pub fn set_sends_one_synchronous_product_set_test() {
  let assert #(result, [sent]) =
    product.set(scripted.client(api_version.v2026_07), new_product())
    |> scripted.run([scripted.ok(fixtures.product_set())])
  scripted.query(sent) |> string.contains("productSet(") |> should.be_true
  scripted.variable(sent, ["synchronous"], decode.bool) |> should.be_true
  scripted.variable(sent, ["input", "handle"], decode.string)
  |> should.equal("o-processo")
  scripted.variable(sent, ["input", "status"], decode.string)
  |> should.equal("ACTIVE")
  scripted.variable(sent, ["input", "descriptionHtml"], decode.string)
  |> should.equal("<p>Um romance.</p>")
  scripted.variable(
    sent,
    ["input", "productOptions"],
    decode.list({
      use name <- decode.field("name", decode.string)
      use values <- decode.field(
        "values",
        decode.list(decode.field("name", decode.string, decode.success)),
      )
      decode.success(#(name, values))
    }),
  )
  |> should.equal([#("Formato", ["Brochura", "Capa dura"])])
  scripted.variable(
    sent,
    ["input", "files"],
    decode.list({
      use source <- decode.field("originalSource", decode.string)
      use content_type <- decode.field("contentType", decode.string)
      decode.success(#(source, content_type))
    }),
  )
  |> should.equal([#("https://cdn.example.com/capa.jpg", "IMAGE")])
  let assert Ok(created) = result
  created.id |> should.equal(product_id)
  created.media_ids |> should.equal(["gid://shopify/MediaImage/3300000010"])
  created.variants
  |> should.equal([
    variant.VariantSummary(
      id: "gid://shopify/ProductVariant/4400000010",
      sku: option.Some("9786500000010"),
      inventory_item_id: "gid://shopify/InventoryItem/5500000010",
      tracking: variant.InventoryTracked,
      selected_options: [
        variant.OptionValue(option_name: "Formato", name: "Brochura"),
      ],
    ),
    variant.VariantSummary(
      id: "gid://shopify/ProductVariant/4400000011",
      sku: option.Some("9786500000011"),
      inventory_item_id: "gid://shopify/InventoryItem/5500000011",
      tracking: variant.InventoryTracked,
      selected_options: [
        variant.OptionValue(option_name: "Formato", name: "Capa dura"),
      ],
    ),
  ])
}

pub fn set_variant_input_shape_test() {
  product.set_variables(new_product())
  |> json.to_string
  |> string.contains(
    "\"variants\":[{\"optionValues\":[{\"optionName\":\"Formato\",\"name\":\"Brochura\"}],"
    <> "\"price\":\"49.90\",\"inventoryPolicy\":\"DENY\","
    <> "\"inventoryItem\":{\"sku\":\"9786500000010\",\"tracked\":true},"
    <> "\"barcode\":\"9786500000010\",\"compareAtPrice\":\"59.90\"},"
    <> "{\"optionValues\":[{\"optionName\":\"Formato\",\"name\":\"Capa dura\"}],"
    <> "\"price\":\"79.90\",\"inventoryPolicy\":\"CONTINUE\","
    <> "\"inventoryItem\":{\"sku\":\"9786500000011\",\"tracked\":false}}]",
  )
  |> should.be_true
}

pub fn set_without_handle_leaves_it_to_shopify_test() {
  product.set_variables(
    product.ProductSet(..new_product(), handle: option.None, files: []),
  )
  |> json.to_string
  |> string.contains("\"handle\"")
  |> should.be_false
}

pub fn set_surfaces_user_errors_test() {
  let #(result, _) =
    product.set(scripted.client(api_version.v2026_07), new_product())
    |> scripted.run([scripted.ok(fixtures.product_set_user_errors())])
  result
  |> should.equal(
    Error(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: ["input", "handle"],
          message: "Handle 'o-processo' already in use. Please provide a new handle.",
          code: option.Some("HANDLE_NOT_UNIQUE"),
        ),
      ]),
    ),
  )
}

pub fn get_reads_options_variants_and_media_test() {
  let assert #(result, [sent]) =
    product.get(scripted.client(api_version.v2026_07), product_id)
    |> scripted.run([scripted.ok(fixtures.product())])
  scripted.variable(sent, ["id"], decode.string) |> should.equal(product_id)
  result
  |> should.equal(
    Ok(
      option.Some(
        product.Product(
          id: product_id,
          description_html: "<p>Um romance.</p>",
          options: [
            product.ProductOption(
              name: "Title",
              values: ["Default Title"],
              linked_metafield: option.None,
            ),
            product.ProductOption(
              name: "Formato",
              values: ["Brochura"],
              linked_metafield: option.Some(product.LinkedMetafield(
                namespace: option.Some("shopify"),
                key: option.Some("book-cover-type"),
              )),
            ),
          ],
          variants: [
            variant.VariantSummary(
              id: "gid://shopify/ProductVariant/4400000010",
              sku: option.None,
              inventory_item_id: "gid://shopify/InventoryItem/5500000010",
              tracking: variant.InventoryTracked,
              selected_options: [
                variant.OptionValue(option_name: "Title", name: "Default Title"),
              ],
            ),
          ],
          media_ids: [
            "gid://shopify/MediaImage/3300000010",
            "gid://shopify/MediaImage/3300000011",
          ],
        ),
      ),
    ),
  )
}

pub fn get_answers_none_for_a_missing_product_test() {
  let #(result, _) =
    product.get(scripted.client(api_version.v2026_07), product_id)
    |> scripted.run([scripted.ok(fixtures.product_missing())])
  result |> should.equal(Ok(option.None))
}

/// A deleted product reads `null` and another node type `{}`: both are left
/// out. A repeated id is asked once.
pub fn variant_counts_reads_each_product_test() {
  let assert #(result, [sent]) =
    product.variant_counts(scripted.client(api_version.v2026_07), [
      product_id,
      "gid://shopify/Product/7700000011",
      product_id,
      "gid://shopify/Product/7700000012",
    ])
    |> scripted.run([scripted.ok(fixtures.product_variant_counts())])
  scripted.query(sent) |> string.contains("variantsCount") |> should.be_true
  scripted.variable(sent, ["ids"], decode.list(decode.string))
  |> should.equal([
    product_id,
    "gid://shopify/Product/7700000011",
    "gid://shopify/Product/7700000012",
  ])
  result
  |> should.equal(
    Ok([#(product_id, 2), #("gid://shopify/Product/7700000012", 1)]),
  )
}

/// A product node that reads no count is a decode failure, not a node of
/// another type.
pub fn variant_counts_refuses_a_product_with_no_count_test() {
  let assert #(Error(error.ShopifyErrorDecode(_)), [_sent]) =
    product.variant_counts(scripted.client(api_version.v2026_07), [product_id])
    |> scripted.run([scripted.ok(fixtures.product_variant_counts_uncounted())])
}

pub fn variant_counts_sends_no_call_for_no_product_test() {
  let #(result, sent) =
    product.variant_counts(scripted.client(api_version.v2026_07), [])
    |> scripted.run([])
  result |> should.equal(Ok([]))
  sent |> should.equal([])
}

pub fn update_writes_title_description_and_status_test() {
  let assert #(result, [sent]) =
    product.update(
      scripted.client(api_version.v2026_07),
      product_id,
      title: option.Some("O processo"),
      description_html: option.Some("<p>Nova edição.</p>"),
      status: product.ProductStatusDraft,
    )
    |> scripted.run([scripted.ok(fixtures.product_update())])
  result |> should.equal(Ok(Nil))
  scripted.query(sent)
  |> string.contains("productUpdate(product:")
  |> should.be_true
  scripted.variable(
    sent,
    ["product"],
    decode.dict(decode.string, decode.string),
  )
  |> should.equal(
    [
      #("id", product_id),
      #("title", "O processo"),
      #("descriptionHtml", "<p>Nova edição.</p>"),
      #("status", "DRAFT"),
    ]
    |> dict.from_list,
  )
  scripted.body(sent) |> string.contains("\"handle\"") |> should.be_false
}

pub fn update_keeps_the_title_and_description_given_none_test() {
  let assert #(result, [sent]) =
    product.update(
      scripted.client(api_version.v2026_07),
      product_id,
      title: option.None,
      description_html: option.None,
      status: product.ProductStatusActive,
    )
    |> scripted.run([scripted.ok(fixtures.product_update())])
  result |> should.equal(Ok(Nil))
  scripted.variable(
    sent,
    ["product"],
    decode.dict(decode.string, decode.string),
  )
  |> should.equal(
    [#("id", product_id), #("status", "ACTIVE")] |> dict.from_list,
  )
}

pub fn set_status_writes_the_status_alone_test() {
  let assert #(_, [sent]) =
    product.set_status(
      scripted.client(api_version.v2026_07),
      product_id,
      product.ProductStatusDraft,
    )
    |> scripted.run([scripted.ok(fixtures.product_update())])
  scripted.variable(
    sent,
    ["product"],
    decode.dict(decode.string, decode.string),
  )
  |> should.equal(dict.from_list([#("id", product_id), #("status", "DRAFT")]))
}

pub fn update_surfaces_a_missing_product_test() {
  let #(result, _) =
    product.set_status(
      scripted.client(api_version.v2026_07),
      product_id,
      product.ProductStatusDraft,
    )
    |> scripted.run([scripted.ok(fixtures.product_update_user_errors())])
  result
  |> should.equal(
    Error(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: ["id"],
          message: "Product does not exist",
          code: option.None,
        ),
      ]),
    ),
  )
}

pub fn replace_media_adds_then_deletes_test() {
  let assert #(result, [added, deleted]) =
    product.replace_media(
      scripted.client(api_version.v2026_07),
      product_id,
      remove: ["gid://shopify/MediaImage/3300000010"],
      add: ["https://cdn.example.com/capa-nova.jpg"],
    )
    |> scripted.run([
      scripted.ok(fixtures.product_update()),
      scripted.ok(fixtures.product_delete_media()),
    ])
  result |> should.equal(Ok(Nil))
  scripted.variable(
    added,
    ["media"],
    decode.list({
      use source <- decode.field("originalSource", decode.string)
      use content_type <- decode.field("mediaContentType", decode.string)
      decode.success(#(source, content_type))
    }),
  )
  |> should.equal([#("https://cdn.example.com/capa-nova.jpg", "IMAGE")])
  scripted.query(deleted)
  |> string.contains("userErrors: mediaUserErrors")
  |> should.be_true
  scripted.variable(deleted, ["mediaIds"], decode.list(decode.string))
  |> should.equal(["gid://shopify/MediaImage/3300000010"])
  scripted.variable(deleted, ["productId"], decode.string)
  |> should.equal(product_id)
}

pub fn replace_media_skips_empty_lists_test() {
  let client = scripted.client(api_version.v2026_07)
  let #(result, sent) =
    product.replace_media(client, product_id, remove: [], add: [])
    |> scripted.run([])
  result |> should.equal(Ok(Nil))
  sent |> should.equal([])
  let assert #(_, [only]) =
    product.replace_media(
      client,
      product_id,
      remove: ["gid://shopify/MediaImage/3300000010"],
      add: [],
    )
    |> scripted.run([scripted.ok(fixtures.product_delete_media())])
  scripted.query(only)
  |> string.contains("productDeleteMedia")
  |> should.be_true
}

pub fn replace_media_stops_after_a_failed_add_test() {
  let #(result, sent) =
    product.replace_media(
      scripted.client(api_version.v2026_07),
      product_id,
      remove: ["gid://shopify/MediaImage/3300000010"],
      add: ["https://cdn.example.com/capa-nova.jpg"],
    )
    |> scripted.run([scripted.Reply(status: 503, headers: [], body: "")])
  result |> should.equal(Error(error.ShopifyErrorServer(503)))
  let assert [_] = sent
}

pub fn delete_media_reads_media_user_errors_test() {
  let #(result, _) =
    product.replace_media(
      scripted.client(api_version.v2026_07),
      product_id,
      remove: ["gid://shopify/MediaImage/1"],
      add: [],
    )
    |> scripted.run([scripted.ok(fixtures.product_delete_media_user_errors())])
  result
  |> should.equal(
    Error(
      error.ShopifyErrorUserErrors([
        error.UserError(
          field: ["mediaIds"],
          message: "Media id gid://shopify/MediaImage/1 does not exist",
          code: option.Some("MEDIA_DOES_NOT_EXIST"),
        ),
      ]),
    ),
  )
}

pub fn online_store_finds_the_publication_by_name_test() {
  let assert #(result, [sent]) =
    publication.online_store(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(fixtures.publications())])
  result
  |> should.equal(Ok(option.Some("gid://shopify/Publication/9900000002")))
  scripted.variable(sent, ["after"], decode.optional(decode.string))
  |> should.equal(option.None)
}

pub fn online_store_follows_the_cursor_test() {
  let first_page =
    "{\"data\":{\"publications\":{\"nodes\":[{\"id\":\"gid://shopify/Publication/1\",\"name\":\"Point of Sale\"}],"
    <> "\"pageInfo\":{\"hasNextPage\":true,\"endCursor\":\"page-2\"}}}}"
  let assert #(result, [_, second]) =
    publication.online_store(scripted.client(api_version.v2026_07))
    |> scripted.run([
      scripted.ok(first_page),
      scripted.ok(fixtures.publications()),
    ])
  result
  |> should.equal(Ok(option.Some("gid://shopify/Publication/9900000002")))
  scripted.variable(second, ["after"], decode.string) |> should.equal("page-2")
}

pub fn online_store_answers_none_without_the_channel_test() {
  let #(result, _) =
    publication.online_store(scripted.client(api_version.v2026_07))
    |> scripted.run([
      scripted.ok(
        "{\"data\":{\"publications\":{\"nodes\":[{\"id\":\"gid://shopify/Publication/1\",\"name\":\"Point of Sale\"}],"
        <> "\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null}}}}",
      ),
    ])
  result |> should.equal(Ok(option.None))
}

pub fn publish_request_shape_test() {
  let assert #(result, [sent]) =
    publication.publish(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Product/7700000010",
      "gid://shopify/Publication/9900000002",
    )
    |> scripted.run([scripted.ok(fixtures.publishable_publish())])
  result |> should.equal(Ok(Nil))
  scripted.query(sent)
  |> string.contains("publishablePublish(")
  |> should.be_true
  publication.publish_variables(
    "gid://shopify/Product/7700000010",
    "gid://shopify/Publication/9900000002",
  )
  |> json.to_string
  |> should.equal(
    "{\"id\":\"gid://shopify/Product/7700000010\","
    <> "\"input\":[{\"publicationId\":\"gid://shopify/Publication/9900000002\"}]}",
  )
}

pub fn publish_without_the_scope_is_forbidden_test() {
  let #(result, _) =
    publication.publish(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Product/7700000010",
      "gid://shopify/Publication/9900000002",
    )
    |> scripted.run([scripted.ok(fixtures.publishable_publish_access_denied())])
  let assert Error(error.ShopifyErrorForbidden(message)) = result
  message |> string.contains(publication.write_scope) |> should.be_true
}
