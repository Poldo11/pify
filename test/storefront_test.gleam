import fixtures
import gleam/dynamic/decode
import gleam/http/request
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleeunit/should
import pify/api_version
import pify/decimal
import pify/error
import pify/storefront
import pify/storefront/cart
import pify/storefront/collection
import pify/storefront/product
import scripted

fn client(token: storefront.StorefrontToken) -> storefront.StorefrontClient {
  let assert Ok(client) =
    storefront.new(
      token:,
      shop_domain: "loja-exemplo.myshopify.com",
      version: api_version.v2026_10,
    )
  client
}

fn public_client() -> storefront.StorefrontClient {
  client(storefront.PublicToken("public-token"))
}

const author = storefront.MetafieldIdentifier(namespace: "custom", key: "author")

pub fn a_public_token_reads_the_storefront_endpoint_test() {
  let assert #(_, [sent]) =
    product.by_handle(public_client(), "o-processo", [])
    |> scripted.run([scripted.ok(fixtures.storefront_product_missing())])
  sent.host |> should.equal("loja-exemplo.myshopify.com")
  sent.path |> should.equal("/api/2026-10/graphql.json")
  request.get_header(sent, "x-shopify-storefront-access-token")
  |> should.equal(Ok("public-token"))
  request.get_header(sent, "x-shopify-access-token") |> should.equal(Error(Nil))
}

pub fn a_private_token_forwards_the_buyer_ip_test() {
  let assert Ok(buyer_ip) = storefront.parse_buyer_ip(" 203.0.113.7 ")
  let token = storefront.PrivateToken("private-token", option.Some(buyer_ip))
  let assert #(_, [sent]) =
    product.by_handle(client(token), "o-processo", [])
    |> scripted.run([scripted.ok(fixtures.storefront_product_missing())])
  request.get_header(sent, "shopify-storefront-private-token")
  |> should.equal(Ok("private-token"))
  request.get_header(sent, "shopify-storefront-buyer-ip")
  |> should.equal(Ok("203.0.113.7"))
  request.get_header(sent, "x-shopify-storefront-access-token")
  |> should.equal(Error(Nil))
}

pub fn by_handle_reads_the_product_and_its_metafields_test() {
  let assert #(Ok(option.Some(found)), [sent]) =
    product.by_handle(public_client(), "o-processo", [author])
    |> scripted.run([scripted.ok(fixtures.storefront_product())])
  scripted.variable(sent, ["handle"], decode.string)
  |> should.equal("o-processo")
  scripted.variable(
    sent,
    ["identifiers"],
    decode.list(decode.field("key", decode.string, decode.success)),
  )
  |> should.equal(["author"])
  found.title |> should.equal("O processo")
  found.options
  |> should.equal([
    product.ProductOption(
      id: "gid://shopify/ProductOption/1",
      name: "Formato",
      values: ["Brochura", "Capa dura"],
    ),
  ])
  decimal.to_string(found.price_range.min_variant_price.amount)
  |> should.equal("49.9")
  list.map(found.variants, fn(variant) { variant.sku })
  |> should.equal([option.Some("9786500000010"), option.None])
  found.has_more_variants |> should.be_false
  list.length(found.images) |> should.equal(2)
  found.metafields
  |> should.equal([
    storefront.Metafield(
      namespace: "custom",
      key: "author",
      value: "Autora Exemplo",
      value_type: "single_line_text_field",
    ),
  ])
}

pub fn a_missing_handle_reads_as_none_test() {
  product.by_handle(public_client(), "nenhum", [])
  |> scripted.run([scripted.ok(fixtures.storefront_product_missing())])
  |> fn(ran) { ran.0 }
  |> should.equal(Ok(option.None))
}

pub fn list_sends_the_page_in_variables_test() {
  let page =
    product.ProductPage(
      ..product.first_page(1000),
      after: option.Some("cursor-1"),
      search: option.Some("tag:romance"),
      sort: product.ProductSortBestSelling,
    )
  let assert #(Ok(connection), [sent]) =
    product.list(public_client(), page, [])
    |> scripted.run([scripted.ok(fixtures.storefront_products_page())])
  scripted.variable(sent, ["first"], decode.int)
  |> should.equal(storefront.max_page_size)
  scripted.variable(sent, ["after"], decode.string) |> should.equal("cursor-1")
  scripted.variable(sent, ["query"], decode.string)
  |> should.equal("tag:romance")
  scripted.variable(sent, ["sortKey"], decode.string)
  |> should.equal("BEST_SELLING")
  scripted.query(sent) |> string.contains("tag:romance") |> should.be_false
  connection.page_info.end_cursor
  |> should.equal(option.Some("eyJsYXN0IjoxfQ=="))
  let assert [found] = connection.nodes
  found.has_more_variants |> should.be_true
}

pub fn no_recommendations_read_as_an_empty_list_test() {
  product.recommendations(public_client(), "gid://shopify/Product/1", [])
  |> scripted.run([scripted.ok(fixtures.storefront_recommendations_none())])
  |> fn(ran) { ran.0 }
  |> should.equal(Ok([]))
}

pub fn collection_products_use_the_collection_sort_keys_test() {
  let page =
    collection.CollectionPage(
      ..collection.first_page(12),
      sort: collection.CollectionSortPrice,
      reverse: True,
    )
  let assert #(Ok(option.Some(connection)), [sent]) =
    collection.products(public_client(), "romances", page, [])
    |> scripted.run([scripted.ok(fixtures.storefront_collection_products())])
  scripted.query(sent)
  |> string.contains("ProductCollectionSortKeys")
  |> should.be_true
  scripted.variable(sent, ["sortKey"], decode.string) |> should.equal("PRICE")
  scripted.variable(sent, ["reverse"], decode.bool) |> should.be_true
  list.length(connection.nodes) |> should.equal(1)
}

pub fn create_sends_the_lines_and_reads_the_cart_test() {
  let line =
    cart.LineInput(
      merchandise_id: "gid://shopify/ProductVariant/4400000010",
      quantity: 2,
      attributes: [cart.Attribute(key: "dedicatória", value: option.None)],
    )
  let assert #(Ok(cart.CartWrite(cart: created, warnings:)), [sent]) =
    cart.create(public_client(), [line])
    |> scripted.run([scripted.ok(fixtures.storefront_cart_create())])
  scripted.variable(
    sent,
    ["input", "lines"],
    decode.list(decode.field("quantity", decode.int, decode.success)),
  )
  |> should.equal([2])
  created.total_quantity |> should.equal(2)
  decimal.to_string(created.total.amount) |> should.equal("99.8")
  let assert [cart.CartLine(merchandise:, attributes:, ..)] = created.lines
  merchandise.product_handle |> should.equal("o-processo")
  merchandise.variant.sku |> should.equal(option.Some("9786500000010"))
  warnings
  |> should.equal([
    cart.CartWarning(
      code: "MERCHANDISE_NOT_ENOUGH_STOCK",
      message: "Only 2 left in stock.",
      target: "gid://shopify/CartLine/l1",
    ),
  ])
  attributes
  |> should.equal([cart.Attribute(key: "dedicatória", value: option.None)])
}

pub fn a_refused_line_fails_with_its_user_errors_test() {
  let line =
    cart.LineInput(
      merchandise_id: "gid://shopify/ProductVariant/1",
      quantity: 1,
      attributes: [],
    )
  let assert #(Error(error.ShopifyErrorUserErrors([refused])), _) =
    cart.add_lines(public_client(), "gid://shopify/Cart/c1", [line])
    |> scripted.run([
      scripted.ok(fixtures.storefront_cart_lines_add_user_errors()),
    ])
  refused.code |> should.equal(option.Some("INVALID_MERCHANDISE_LINE"))
}

pub fn update_and_remove_name_their_lines_test() {
  let assert #(_, [updated]) =
    cart.update_lines(public_client(), "gid://shopify/Cart/c1", [
      cart.LineUpdate(line_id: "gid://shopify/CartLine/l1", quantity: 0),
    ])
    |> scripted.run([scripted.ok(fixtures.storefront_cart_create())])
  scripted.variable(
    updated,
    ["lines"],
    decode.list(decode.field("id", decode.string, decode.success)),
  )
  |> should.equal(["gid://shopify/CartLine/l1"])
  let assert #(_, [removed]) =
    cart.remove_lines(public_client(), "gid://shopify/Cart/c1", [
      "gid://shopify/CartLine/l1",
    ])
    |> scripted.run([scripted.ok(fixtures.storefront_cart_create())])
  scripted.variable(removed, ["lineIds"], decode.list(decode.string))
  |> should.equal(["gid://shopify/CartLine/l1"])
}

pub fn get_reads_the_cart_test() {
  let assert #(Ok(option.Some(found)), [sent]) =
    cart.get(public_client(), "gid://shopify/Cart/c1-exemplo?key=k")
    |> scripted.run([scripted.ok(fixtures.storefront_cart())])
  scripted.variable(sent, ["cartId"], decode.string)
  |> should.equal("gid://shopify/Cart/c1-exemplo?key=k")
  found.checkout_url
  |> string.starts_with("https://loja-exemplo.myshopify.com/cart/c/")
  |> should.be_true
  found.has_more_lines |> should.be_false
}

pub fn new_refuses_a_domain_that_moves_the_host_test() {
  [
    "evil.example#", "x@evil.example", "evil.example/x?", "shop.example:443",
    "localhost", "-shop.example", "shop..example", "",
  ]
  |> list.each(fn(text) {
    storefront.new(
      token: storefront.PublicToken("public-token"),
      shop_domain: text,
      version: api_version.v2026_10,
    )
    |> result.is_error
    |> should.be_true
  })
  storefront.parse_domain(" HTTPS://Livraria.Example.com.br/ ")
  |> should.equal(Ok("livraria.example.com.br"))
}

pub fn a_buyer_ip_holds_an_address_only_test() {
  storefront.parse_buyer_ip("2001:db8::1")
  |> result.map(storefront.buyer_ip_to_string)
  |> should.equal(Ok("2001:db8::1"))
  ["203.0.113.7\r\nx-evil: 1", "203.0.113.7, 198.51.100.2", "localhost", ""]
  |> list.each(fn(text) {
    storefront.parse_buyer_ip(text) |> result.is_error |> should.be_true
  })
}

pub fn a_page_reads_fewer_variants_than_one_product_test() {
  let assert #(_, [listed]) =
    product.list(public_client(), product.first_page(20), [])
    |> scripted.run([scripted.ok(fixtures.storefront_products_page())])
  scripted.query(listed)
  |> string.contains("variants(first: 10)")
  |> should.be_true
  let assert #(_, [one]) =
    product.by_handle(public_client(), "o-processo", [])
    |> scripted.run([scripted.ok(fixtures.storefront_product_missing())])
  scripted.query(one)
  |> string.contains("variants(first: 100)")
  |> should.be_true
}
