import gleam/dynamic/decode
import gleam/option.{type Option}

pub type ShopifyClient {
  ShopifyClient(key: String, domain: String, api_version: Option(String))
}

pub fn shopify_client_decoder() -> decode.Decoder(ShopifyClient) {
  use key <- decode.field("key", decode.string)
  use domain <- decode.field("domain", decode.string)
  use api_version <- decode.field("api_version", decode.optional(decode.string))
  decode.success(ShopifyClient(key:, domain:, api_version:))
}

pub type ShopifyError {
  ShopifyError(status: Int, body: String)
}

pub fn shopify_error_decoder() -> decode.Decoder(ShopifyError) {
  use status <- decode.field("status", decode.int)
  use body <- decode.field("body", decode.string)
  decode.success(ShopifyError(status:, body:))
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

pub fn image_decoder() -> decode.Decoder(Image) {
  use url <- decode.field("url", decode.string)
  use alt_text <- decode.field("alt_text", decode.string)
  use width <- decode.field("width", decode.string)
  use height <- decode.field("height", decode.string)
  decode.success(Image(url:, alt_text:, width:, height:))
}

pub type PriceRange {
  PriceRange(max_variant_price: Money, min_variant_price: Money)
}

pub fn price_range_decoder() -> decode.Decoder(PriceRange) {
  use max_variant_price <- decode.field("max_variant_price", money_decoder())
  use min_variant_price <- decode.field("min_variant_price", money_decoder())
  decode.success(PriceRange(max_variant_price:, min_variant_price:))
}

pub type Money {
  Money(amount: String, currency_code: String)
}

pub fn money_decoder() -> decode.Decoder(Money) {
  use amount <- decode.field("amount", decode.string)
  use currency_code <- decode.field("currency_code", decode.string)
  decode.success(Money(amount:, currency_code:))
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

pub fn selected_option_decoder() -> decode.Decoder(SelectedOption) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(SelectedOption(name:, value:))
}

pub type Cost {
  Cost(total_amount: Money)
}

pub fn cost_decoder() -> decode.Decoder(Cost) {
  use total_amount <- decode.field("total_amount", money_decoder())
  decode.success(Cost(total_amount:))
}

pub type ShopifyCartCost {
  ShopifyCartCost(
    total_amount: Money,
    subtotal_amount: Money,
    total_tax_amount: Money,
  )
}

pub fn shopify_cart_cost_decoder() -> decode.Decoder(ShopifyCartCost) {
  use total_amount <- decode.field("total_amount", money_decoder())
  use subtotal_amount <- decode.field("subtotal_amount", money_decoder())
  use total_tax_amount <- decode.field("total_tax_amount", money_decoder())
  decode.success(ShopifyCartCost(
    total_amount:,
    subtotal_amount:,
    total_tax_amount:,
  ))
}

pub type Cart {
  Cart(
    id: Option(String),
    checkout_url: String,
    cost: Option(ShopifyCartCost),
    total_quantity: Int,
    lines: List(CartItem),
  )
}

pub fn cart_decoder() -> decode.Decoder(Cart) {
  use id <- decode.field("id", decode.optional(decode.string))
  use checkout_url <- decode.field("checkout_url", decode.string)
  use cost <- decode.field("cost", decode.optional(shopify_cart_cost_decoder()))
  use total_quantity <- decode.field("total_quantity", decode.int)
  use lines <- decode.field("lines", decode.list(cart_item_decoder()))
  decode.success(Cart(id:, checkout_url:, cost:, total_quantity:, lines:))
}

pub type ShopifyCart {
  ShopifyCart(
    id: Option(String),
    checkout_url: String,
    cost: Option(ShopifyCartCost),
    lines: Connection(CartItem),
    total_quantity: Int,
  )
}

pub fn cart_item_edge_decoder() -> decode.Decoder(Edge(CartItem)) {
  use node <- decode.field("node", cart_item_decoder())
  decode.success(Edge(node:))
}

pub fn cart_item_connection_decoder() -> decode.Decoder(Connection(CartItem)) {
  use edges <- decode.field("edges", decode.list(cart_item_edge_decoder()))
  decode.success(Connection(edges:))
}

pub fn shopify_cart_decoder() -> decode.Decoder(ShopifyCart) {
  use id <- decode.field("id", decode.optional(decode.string))
  use checkout_url <- decode.field("checkout_url", decode.string)
  use cost <- decode.field("cost", decode.optional(shopify_cart_cost_decoder()))
  use lines <- decode.field("lines", cart_item_connection_decoder())
  use total_quantity <- decode.field("total_quantity", decode.int)
  decode.success(ShopifyCart(id:, checkout_url:, cost:, lines:, total_quantity:))
}

pub type Merchandise {
  Merchandise(
    id: String,
    title: String,
    selected_options: List(SelectedOption),
    product: CartProduct,
  )
}

fn merchandise_decoder() -> decode.Decoder(Merchandise) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use selected_options <- decode.field(
    "selected_options",
    decode.list(selected_option_decoder()),
  )
  use product <- decode.field("product", cart_product_decoder())
  decode.success(Merchandise(id:, title:, selected_options:, product:))
}

pub type CartProduct {
  CartProduct(id: String, handle: String, title: String, featured_image: Image)
}

fn cart_product_decoder() -> decode.Decoder(CartProduct) {
  use id <- decode.field("id", decode.string)
  use handle <- decode.field("handle", decode.string)
  use title <- decode.field("title", decode.string)
  use featured_image <- decode.field("featured_image", image_decoder())
  decode.success(CartProduct(id:, handle:, title:, featured_image:))
}

pub type CartItem {
  CartItem(
    id: Option(String),
    quantity: Int,
    cost: Cost,
    merchandise: Merchandise,
  )
}

fn cart_item_decoder() -> decode.Decoder(CartItem) {
  use id <- decode.field("id", decode.optional(decode.string))
  use quantity <- decode.field("quantity", decode.int)
  use cost <- decode.field("cost", cost_decoder())
  use merchandise <- decode.field("merchandise", merchandise_decoder())
  decode.success(CartItem(id:, quantity:, cost:, merchandise:))
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

pub type ProductVariant {
  ProductVariant(
    id: String,
    title: String,
    available_for_sale: Bool,
    selected_options: SelectedOption,
    price: Money,
  )
}

pub fn product_variant_decoder() -> decode.Decoder(ProductVariant) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use available_for_sale <- decode.field("available_for_sale", decode.bool)
  use selected_options <- decode.field(
    "selected_options",
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

pub fn seo_decoder() -> decode.Decoder(Seo) {
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  decode.success(Seo(title:, description:))
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

pub fn shopify_product_decoder() -> decode.Decoder(ShopifyProduct) {
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

fn image_connection_decoder() -> decode.Decoder(Connection(Image)) {
  use edges <- decode.field("edges", decode.list(image_edges_decoder()))
  decode.success(Connection(edges:))
}

fn image_edges_decoder() -> decode.Decoder(Edge(Image)) {
  use node <- decode.field("node", image_decoder())
  decode.success(Edge(node:))
}

pub fn product_variant_connection_decoder() -> decode.Decoder(
  Connection(ProductVariant),
) {
  use edges <- decode.field(
    "edges",
    decode.list(product_variant_edges_decoder()),
  )
  decode.success(Connection(edges:))
}

pub fn product_variant_edges_decoder() -> decode.Decoder(Edge(ProductVariant)) {
  use node <- decode.field("node", product_variant_decoder())
  decode.success(Edge(node:))
}
