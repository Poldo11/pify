import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub fn remove_edges_and_nodes(array: Connection(a)) -> List(a) {
  array.edges
  |> list.map(fn(nodes) { nodes.node })
}

/// Class of utilities that repeat itself in my places
///
/// Product Variant
///
// /// Shopify types and decoders for our examples

// /// Remove the edges from the array and return the proper type of the connection.
// ///
// /// Essential to work with GraphQL <> Shopify.

pub fn image_connection_decoder() -> decode.Decoder(Connection(Image)) {
  use edges <- decode.field("edges", decode.list(image_edges_decoder()))
  decode.success(Connection(edges:))
}

pub fn image_edges_decoder() -> decode.Decoder(Edge(Image)) {
  use node <- decode.field("node", image_decoder())
  decode.success(Edge(node:))
}

pub fn image_connection_to_json(connection: Connection(Image)) -> json.Json {
  let Connection(edges:) = connection
  json.object([
    #("edges", json.array(edges, image_edge_to_json)),
  ])
}

pub fn image_edge_to_json(edge: Edge(Image)) -> json.Json {
  let Edge(node:) = edge
  json.object([
    #("node", image_to_json(node)),
  ])
}

pub fn reshape_images(
  images: Connection(Image),
  product_title: String,
) -> List(Image) {
  let flattened = remove_edges_and_nodes(images)
  flattened
  |> list.map(fn(image) {
    let new_alt_text = case image.alt_text {
      None -> {
        let filename = get_filename(image.url)
        product_title <> "-" <> filename
      }
      Some(text) -> text
    }
    Image(..image, alt_text: Some(new_alt_text))
  })
}

fn get_filename(url: String) -> String {
  let path_segment = case last_split(url, "/") {
    Ok(#(_, after)) -> after
    Error(_) -> url
  }

  case last_split(path_segment, ".") {
    Ok(#(before, _)) -> before
    Error(_) -> path_segment
  }
}

fn last_split(
  str: String,
  on separator: String,
) -> Result(#(String, String), Nil) {
  let reversed_str = string.reverse(str)
  let reversed_separator = string.reverse(separator)

  case string.split_once(reversed_str, on: reversed_separator) {
    Ok(#(after_reversed, before_reversed)) -> {
      let before = string.reverse(before_reversed)
      let after = string.reverse(after_reversed)
      Ok(#(before, after))
    }
    Error(_) -> Error(Nil)
  }
}

pub type GetProductsQuery {
  GetProductsQuery(products: Connection(Product))
}

pub fn get_products_query_decoder() -> decode.Decoder(GetProductsQuery) {
  use products <- decode.field("products", product_connection_decoder())
  decode.success(GetProductsQuery(products:))
}

pub type ProductConnection {
  ProductConnection(edges: Connection(Product))
}

pub type ProductEdge {
  ProductEdge(node: Edge(Product))
}

pub fn product_connection_decoder() -> decode.Decoder(Connection(Product)) {
  use edges <- decode.field("edges", decode.list(product_edges_decoder()))
  decode.success(Connection(edges:))
}

pub fn product_edges_decoder() -> decode.Decoder(Edge(Product)) {
  use node <- decode.field("node", product_decoder())
  decode.success(Edge(node:))
}

pub fn product_connection_to_json(connection: Connection(Product)) -> json.Json {
  let Connection(edges:) = connection
  json.object([
    #("edges", json.array(edges, product_edge_to_json)),
  ])
}

pub fn product_edge_to_json(edge: Edge(Product)) -> json.Json {
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

pub type MediaPreviewImage {
  MediaPreviewImage(image: Option(Image), status: MediaPreviewImageStatus)
}

pub fn media_preview_image_to_json(
  media_preview_image: MediaPreviewImage,
) -> json.Json {
  let MediaPreviewImage(image:, status:) = media_preview_image
  json.object([
    #("image", case image {
      None -> json.null()
      Some(value) -> image_to_json(value)
    }),
    #("status", media_preview_image_status_to_json(status)),
  ])
}

pub fn media_preview_image_decoder() -> decode.Decoder(MediaPreviewImage) {
  use image <- decode.field("image", decode.optional(image_decoder()))
  use status <- decode.field("status", media_preview_image_status_decoder())
  decode.success(MediaPreviewImage(image:, status:))
}

pub type MediaPreviewImageStatus {
  Failed
  Processing
  Ready
  Uploaded
}

pub fn media_preview_image_status_to_json(
  media_preview_image_status: MediaPreviewImageStatus,
) -> json.Json {
  case media_preview_image_status {
    Failed -> json.string("FAILED")
    Processing -> json.string("PROCESSING")
    Ready -> json.string("READY")
    Uploaded -> json.string("UPLOADED")
  }
}

pub fn media_preview_image_status_decoder() -> decode.Decoder(
  MediaPreviewImageStatus,
) {
  use variant <- decode.then(decode.string)
  case variant {
    "FAILED" -> decode.success(Failed)
    "PROCESSING" -> decode.success(Processing)
    "READY" -> decode.success(Ready)
    "UPLOADED" -> decode.success(Uploaded)
    _ -> decode.failure(Failed, "MediaPreviewImageStatus")
  }
}

pub type MediaContentType {
  ExternalVideo
  ImageContent
  Model3D
  Video
}

pub fn media_content_type_to_json(
  media_content_type: MediaContentType,
) -> json.Json {
  case media_content_type {
    ExternalVideo -> json.string(string.uppercase("EXTERNAL_VIDEO"))
    ImageContent -> json.string(string.uppercase("IMAGE"))
    Model3D -> json.string(string.uppercase("MODEL_3D"))
    Video -> json.string(string.uppercase("VIDEO"))
  }
}

pub fn media_content_type_decoder() -> decode.Decoder(MediaContentType) {
  use variant <- decode.then(decode.string)
  case variant {
    "EXTERNAL_VIDEO" -> decode.success(ExternalVideo)
    "IMAGE" -> decode.success(ImageContent)
    "MODEL_3D" -> decode.success(Model3D)
    "VIDEO" -> decode.success(Video)
    _ -> decode.failure(ImageContent, "MediaContentType")
  }
}

pub type FeaturedMedia {
  FeaturedMedia(
    id: String,
    media_content_type: MediaContentType,
    alt: Option(String),
    preview: Option(MediaPreviewImage),
  )
}

pub type Count {
  Count(count: Int, precision: CountPrecision)
}

pub fn count_to_json(count: Count) -> json.Json {
  let Count(count:, precision:) = count
  json.object([
    #("count", json.int(count)),
    #("precision", count_precision_to_json(precision)),
  ])
}

pub fn count_decoder() -> decode.Decoder(Count) {
  use count <- decode.field("count", decode.int)
  use precision <- decode.field("precision", count_precision_decoder())
  decode.success(Count(count:, precision:))
}

pub type CountPrecision {
  AtLeast
  Exact
}

pub fn count_precision_to_json(count_precision: CountPrecision) -> json.Json {
  case count_precision {
    AtLeast -> json.string("AT_LEAST")
    Exact -> json.string("EXACT")
  }
}

pub fn count_precision_decoder() -> decode.Decoder(CountPrecision) {
  use variant <- decode.then(decode.string)
  case variant {
    "AT_LEAST" -> decode.success(AtLeast)
    "EXACT" -> decode.success(Exact)
    _ -> decode.failure(AtLeast, "CountPrecision")
  }
}

/// Class of utilities that repeat itself in my places
///
/// Product Variant
///
// /// Shopify types and decoders for our examples

// /// Remove the edges from the array and return the proper type of the connection.
// ///
// /// Essential to work with GraphQL <> Shopify.

pub type Maybe(a) {
  Maybe(Option(a))
}

pub type Connection(a) {
  Connection(edges: List(Edge(a)))
}

pub type Edge(a) {
  Edge(node: a)
}

pub type PriceRange {
  PriceRange(max_variant_price: Money, min_variant_price: Money)
}

pub fn price_range_to_json(price_range: PriceRange) -> json.Json {
  let PriceRange(max_variant_price:, min_variant_price:) = price_range
  json.object([
    #("maxVariantPrice", money_to_json(max_variant_price)),
    #("minVariantPrice", money_to_json(min_variant_price)),
  ])
}

pub fn price_range_decoder() -> decode.Decoder(PriceRange) {
  use max_variant_price <- decode.field("maxVariantPrice", money_decoder())
  use min_variant_price <- decode.field("minVariantPrice", money_decoder())
  decode.success(PriceRange(max_variant_price:, min_variant_price:))
}

pub type Cost {
  Cost(total_amount: Money)
}

pub fn cost_decoder() -> decode.Decoder(Cost) {
  use total_amount <- decode.field("totalAmount", money_decoder())
  decode.success(Cost(total_amount:))
}

pub type Products {
  Products(products: List(Product))
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

pub type SortKey {
  InventoryTotal
  Title
  ProductType
  Vendor
  UpdatedAt
  CreatedAt
  PublishedAt
  Price
  Id
  Relevance
}

pub fn sort_key_decoder() -> Decoder(SortKey) {
  use variant <- decode.then(decode.string)
  case variant {
    "INVENTORY_TOTAL" -> decode.success(InventoryTotal)
    "TITLE" -> decode.success(Title)
    "PRODUCT_TYPE" -> decode.success(ProductType)
    "VENDOR" -> decode.success(Vendor)
    "UPDATED_AT" -> decode.success(UpdatedAt)
    "CREATED_AT" -> decode.success(CreatedAt)
    "PUBLISHED_AT" -> decode.success(PublishedAt)
    "PRICE" -> decode.success(Price)
    "ID" -> decode.success(Id)
    "RELEVANCE" -> decode.success(Relevance)
    _ -> decode.failure(CreatedAt, "SortKey")
  }
}

pub fn sort_key_from_string(value: String) -> Option(SortKey) {
  case value {
    "title" -> Some(Title)
    "product_type" -> Some(ProductType)
    "vendor" -> Some(Vendor)
    "updated_at" -> Some(UpdatedAt)
    "created_at" -> Some(CreatedAt)
    "published_at" -> Some(PublishedAt)
    "inventory_total" -> Some(InventoryTotal)
    "price" -> Some(Price)
    "id" -> Some(Id)
    "relevance" -> Some(Relevance)
    _ -> None
  }
}

pub fn sort_key_to_json(sort_key: SortKey) -> json.Json {
  case sort_key {
    Title -> json.string(string.uppercase("title"))
    ProductType -> json.string(string.uppercase("product_type"))
    Vendor -> json.string(string.uppercase("vendor"))
    UpdatedAt -> json.string(string.uppercase("updated_at"))
    CreatedAt -> json.string(string.uppercase("created_at"))
    PublishedAt -> json.string(string.uppercase("published_at"))
    InventoryTotal -> json.string(string.uppercase("inventory_total"))
    Price -> json.string(string.uppercase("price"))
    Id -> json.string(string.uppercase("id"))
    Relevance -> json.string(string.uppercase("relevance"))
  }
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
  use checkout_url <- decode.field("checkoutUrl", decode.string)
  use cost <- decode.field("cost", decode.optional(shopify_cart_cost_decoder()))
  use total_quantity <- decode.field("totalQuantity", decode.int)
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
  use checkout_url <- decode.field("checkoutUrl", decode.string)
  use cost <- decode.field("cost", decode.optional(shopify_cart_cost_decoder()))
  use lines <- decode.field("lines", cart_item_connection_decoder())
  use total_quantity <- decode.field("totalQuantity", decode.int)
  decode.success(ShopifyCart(id:, checkout_url:, cost:, lines:, total_quantity:))
}

pub type ShopifyCartCost {
  ShopifyCartCost(
    total_amount: Money,
    subtotal_amount: Money,
    total_tax_amount: Money,
  )
}

fn shopify_cart_cost_decoder() -> decode.Decoder(ShopifyCartCost) {
  use total_amount <- decode.field("totalAmount", money_decoder())
  use subtotal_amount <- decode.field("subtotalAmount", money_decoder())
  use total_tax_amount <- decode.field("totalTaxAmount", money_decoder())
  decode.success(ShopifyCartCost(
    total_amount:,
    subtotal_amount:,
    total_tax_amount:,
  ))
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

pub type Merchandise {
  Merchandise(
    id: String,
    title: String,
    selected_options: List(SelectedOption),
    product: CartProduct,
  )
}

pub fn merchandise_decoder() -> decode.Decoder(Merchandise) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use selected_options <- decode.field(
    "selectedOptions",
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
  use featured_image <- decode.field("featuredImage", image_decoder())
  decode.success(CartProduct(id:, handle:, title:, featured_image:))
}

pub type Pagination {
  Pagination(
    has_next_page: Bool,
    has_previous_page: Bool,
    start_cursor: String,
    end_cursor: String,
  )
}

pub fn pagination_to_json(pagination: Pagination) -> json.Json {
  let Pagination(has_next_page:, has_previous_page:, start_cursor:, end_cursor:) =
    pagination
  json.object([
    #("hasNextPage", json.bool(has_next_page)),
    #("hasPreviousPage", json.bool(has_previous_page)),
    #("startCursor", json.string(start_cursor)),
    #("endCursor", json.string(end_cursor)),
  ])
}

pub fn pagination_decoder() -> decode.Decoder(Pagination) {
  use has_next_page <- decode.field("hasNextPage", decode.bool)
  use has_previous_page <- decode.field("hasPreviousPage", decode.bool)
  use start_cursor <- decode.field("startCursor", decode.string)
  use end_cursor <- decode.field("endCursor", decode.string)
  decode.success(Pagination(
    has_next_page:,
    has_previous_page:,
    start_cursor:,
    end_cursor:,
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
