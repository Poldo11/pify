import gleam/dynamic/decode.{type Decoder}
import gleam/fetch
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import snag

pub type CreateStorefrontApiClient {
  CreateStorefrontApiClient(
    /// The domain of the store. It can be the Shopify myshopify.com domain or a custom store domain.
    ///
    store_domain: String,
    /// The requested Storefront API version.
    ///
    api_version: Option(String),
    /// Storefront API public access token. Either publicAccessToken or privateAccessToken must be provided at initialization.
    ///
    public_access_token: Option(String),
    /// Storefront API private access token. Either publicAccessToken or privateAccessToken must be provided at initialization.
    /// Important: Storefront API private delegate access tokens should only be used in a server-to-server implementation.
    ///
    private_access_token: Option(String),
    /// Name of the client
    ///
    client_name: Option(String),
    /// The number of HTTP request retries if the request was abandoned or the server responded
    /// with a Too Many Requests (429) or Service Unavailable (503) response.
    /// Default value is 0. Maximum value is 3.
    ///
    retries: Option(Int),
    /// A replacement fetch function that will be used in all client network requests.
    /// By default, the client uses window.fetch().
    custom_fetch_api: Option(CustomFetchApi),
    /// A logger function that accepts log content objects.
    /// This logger will be called in certain conditions with contextual information.
    logger: Option(Logger),
  )
}

pub type ShopifyError {
  BadUrl(String)
  HttpError(Response(String))
  JsonError(json.DecodeError)
  NetworkError
  UnhandledResponse(Response(String))
  RateLimitError
  ClientError(String)
}

// Base types
//
pub type StorefrontApiClientConfig {
  StorefrontApiClientConfig(
    store_domain: String,
    api_version: Option(String),
    access_token: AccessToken,
    headers: #(String, List(#(String, String))),
    api_url: String,
    client_name: Option(String),
    retries: Option(Int),
  )
}

pub type ShopifyHandler(msg) {
  ShopifyHandler(
    /// Configuration for the client
    config: StorefrontApiClientConfig,
    /// Returns Storefront API specific headers needed to interact with the API.
    /// If additional headers are provided, the custom headers will be included in the returned headers object.
    get_headers: fn(Option(#(String, List(#(String, String))))) ->
      #(String, List(#(String, String))),
    // get_api_url: fn(Option(String)) -> String,
    // Returns the shop specific API url.
    // If an API version is provided, the returned URL will include the provided version,
    // else the URL will include the API version set at client initialization.
    /// Fetches data from Storefront API using the provided GQL operation string
    /// and ApiClientRequestOptions object and returns the network response.
    fetch: fn(String, Decoder(msg), Option(Json)) ->
      Promise(Result(msg, ShopifyError)),
  )
}

pub fn create_store_front_api_client(
  config: CreateStorefrontApiClient,
) -> Result(StorefrontApiClientConfig, ShopifyError) {
  let access_token =
    validate_required_access_token_usage(
      config.public_access_token,
      config.private_access_token,
    )
  let token = case access_token {
    Ok(PublicAccessToken(token)) -> PublicAccessToken(token)
    Ok(PrivateAccessToken(token)) -> PrivateAccessToken(token)
    Error(_) -> panic
  }

  case validate_private_access_token_usage(config.private_access_token) {
    Error(err) -> Error(err)
    Ok(Nil) -> {
      Ok(StorefrontApiClientConfig(
        store_domain: config.store_domain,
        api_version: config.api_version,
        access_token: token,
        client_name: config.client_name,
        retries: Some(0),
        api_url: generate_api_url_formatter(config),
        headers: create_headers(token),
      ))
    }
  }
}

pub fn handler(config: StorefrontApiClientConfig) -> ShopifyHandler(msg) {
  ShopifyHandler(
    config: config,
    get_headers: get_headers,
    fetch: fn(query: String, decoder: Decoder(msg), variables: Option(Json)) {
      let request = base(config)

      let graphql_body = case variables {
        Some(vars) ->
          json.object([#("query", json.string(query)), #("variables", vars)])
        None -> json.object([#("query", json.string(query))])
      }

      request
      |> request.set_body(json.to_string(graphql_body))
      |> request.set_method(http.Post)
      |> fetch.send
      |> promise.try_await(fetch.read_text_body)
      |> promise.map(fn(result) {
        case result {
          Ok(response) -> {
            case json.parse(response.body, using: decoder) {
              Ok(decoded) -> Ok(decoded)
              Error(json_error) -> Error(JsonError(json_error))
            }
          }
          Error(_) -> Error(NetworkError)
        }
      })
    },
  )
}

fn get_headers(
  headers: Option(#(String, List(#(String, String)))),
) -> #(String, List(#(String, String))) {
  case headers {
    Some(header) -> {
      header
    }
    None -> {
      #("headers", [
        #("Content-Type", "application/json"),
        #("Accept", "application/json"),
        #("X-SDK-Variant", "storefront-api-client"),
        #("X-SDK-Version", "rollup_replace_client_version"),
      ])
    }
  }
}

fn base(client: StorefrontApiClientConfig) -> Request(String) {
  let access = case client.access_token {
    PublicAccessToken(token) -> #("X-Shopify-Storefront-Access-Token", token)
    PrivateAccessToken(token) -> #("Shopify-Storefront-Private-Token", token)
  }
  request.new()
  |> request.set_host(client.api_url)
  |> request.set_method(http.Post)
  |> request.set_header("Content-Type", "application/json")
  |> request.set_header("Accept", "application/json")
  |> request.set_header("X-SDK-Variant", "storefront-api-client")
  |> request.set_header("X-SDK-Version", "rollup_replace_client_version")
  |> request.set_header(access.0, access.1)
}

pub opaque type AccessToken {
  PublicAccessToken(String)
  PrivateAccessToken(String)
}

pub opaque type CustomFetchApi {
  CustomFetchApi(
    custom_fetch: fn(Result(CustomFetchParams, ShopifyError)) ->
      Response(String),
  )
}

pub opaque type CustomFetchParams {
  CustomFetchParams(url: String, init: Option(CustomFetchInitializer))
}

pub opaque type CustomFetchInitializer {
  CustomFetchInitializer(
    method: Option(String),
    headers: #(String, List(#(String, String))),
    body: Option(String),
  )
}

pub opaque type Logger {
  Logger(log: fn(Result(LogContent, ShopifyError)) -> Nil)
}

pub opaque type LogContent {
  UnsupportedApiVersionLog
  HTTPResponseLog
  HTTPRetryLog
}

// Utils
//
//
@external(javascript, "./env.ffi.mjs", "isBrowser")
fn is_browser_environment() -> Bool

fn validate_private_access_token_usage(
  private_access_token: Option(String),
) -> Result(Nil, ShopifyError) {
  case private_access_token, is_browser_environment() {
    Some(_), True ->
      Error(ClientError(
        snag.new(
          "Storefront API Client: private access tokens and headers should only be used in a server-to-server implementation. Use the public API access token in nonserver environments.",
        )
        |> snag.line_print,
      ))
    _, _ -> Ok(Nil)
  }
}

fn validate_required_access_token_usage(
  private_access_token: Option(String),
  public_access_token: Option(String),
) -> Result(AccessToken, ShopifyError) {
  let is_valid_private_access_token = option.is_some(private_access_token)
  let is_valid_public_access_token = option.is_some(public_access_token)

  case !is_valid_private_access_token && !is_valid_public_access_token {
    True -> {
      Error(ClientError(
        snag.new("Storefront API Client: an access token must be provided.")
        |> snag.line_print,
      ))
    }
    False -> {
      case is_valid_private_access_token && is_valid_public_access_token {
        True -> {
          Error(ClientError(
            snag.new(
              "Storefront API Client: only provide either a public or private access token.",
            )
            |> snag.line_print,
          ))
        }
        False -> {
          case public_access_token {
            Some(key) -> Ok(PublicAccessToken(key))
            None ->
              case private_access_token {
                Some(key) -> Ok(PrivateAccessToken(key))
                None ->
                  Error(ClientError(
                    snag.new(
                      "Storefront API Client: an access token must be provided.",
                    )
                    |> snag.line_print,
                  ))
              }
          }
        }
      }
    }
  }
}

fn create_headers(
  access_token: AccessToken,
) -> #(String, List(#(String, String))) {
  let access = case access_token {
    PublicAccessToken(token) -> #("X-Shopify-Storefront-Access-Token", token)
    PrivateAccessToken(token) -> #("Shopify-Storefront-Private-Token", token)
  }

  #("headers", [
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("X-SDK-Variant", "storefront-api-client"),
    #("X-SDK-Version", "rollup_replace_client_version"),
    access,
  ])
}

fn generate_api_url_formatter(config: CreateStorefrontApiClient) -> String {
  let domain = validate_store_domain(config)
  case config.api_version {
    Some(api) -> domain <> "/api/" <> string.trim(api) <> "/graphql.json"
    None -> domain <> "/api/" <> string.trim("2023-10") <> "/graphql.json"
  }
}

fn validate_store_domain(config: CreateStorefrontApiClient) -> String {
  let domain = string.trim(config.store_domain)
  case string.starts_with(domain, "https://") {
    True -> domain
    False -> string.append(to: "https://", suffix: domain)
  }
}

// /// Reshape Functions
// ///
// /// Remove the edges from the array and return the proper type of the connection.
// ///
// /// Essential to work with GraphQL <> Shopify.

const hidden_product_tags = "gleam-frontend-hidden"

fn remove_edges_and_nodes(array: Connection(a)) {
  array.edges
  |> list.map(fn(nodes) { nodes.node })
}

fn reshape_images(
  images: Connection(Image),
  product_title: String,
) -> List(Image) {
  let flattened = remove_edges_and_nodes(images)
  flattened
  |> list.map(fn(image) {
    let new_alt_text = case image.alt_text {
      "" -> {
        let filename = get_filename(image.url)
        product_title <> "-" <> filename
      }
      text -> text
    }
    Image(..image, alt_text: new_alt_text)
  })
}

fn reshape_cart(cart: ShopifyCart) -> Cart {
  let result = {
    case cart.cost {
      None -> None
      Some(cost) -> {
        let lines = remove_edges_and_nodes(cart.lines)
        Some(Cart(
          checkout_url: cart.checkout_url,
          id: cart.id,
          lines: lines,
          total_quantity: cart.total_quantity,
          cost: Some(ShopifyCartCost(
            subtotal_amount: cost.subtotal_amount,
            total_tax_amount: cost.total_tax_amount,
            total_amount: cost.total_amount,
          )),
        ))
      }
    }
  }
  let lines = remove_edges_and_nodes(cart.lines)
  option.unwrap(
    result,
    Cart(
      checkout_url: cart.checkout_url,
      id: cart.id,
      lines: lines,
      total_quantity: cart.total_quantity,
      cost: cart.cost,
    ),
  )
}

fn reshape_product(
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

fn reshape_products(products: List(ShopifyProduct)) -> List(Product) {
  list.map(products, fn(product) { reshape_product(product, True) })
}

// // Let's start with some carts.
// //
// // This family of functions uses Wisp to check for cookies

const cookie_name = "cartId"

pub fn create_cart(
  config: StorefrontApiClientConfig,
  on_result: fn(Result(Cart, ShopifyError)) -> Nil,
) {
  let handler = handler(config)
  handler.fetch(
    create_cart_mutation,
    shopify_create_cart_mutation_decoder(),
    None,
  )
  |> promise.map(fn(res) {
    case res {
      Ok(x) -> Ok(reshape_cart(x.data.cart_create.cart))
      Error(err) -> Error(err)
    }
  })
  |> promise.tap(on_result)
}

// fn add_to_cart(
//   client: ShopifyClient,
//   lines: List(CartItem),
//   req: Request,
//   worker: process.Subject(FetchRequest(mutations.ShopifyAddToCartOperation)),
//   on_result: fn(Result(Cart, ShopifyError)) -> Nil,
// ) -> Nil {
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Ok(id) -> {
//       let lines_json =
//         lines
//         |> list.map(fn(line) {
//           shopify_add_to_cart_operation_variables_lines_to_json(
//             ShopifyAddToCartOperationVariablesLines(
//               merchandise_id: line.merchandise.id,
//               quantity: line.quantity,
//             ),
//           )
//         })

//       let variables =
//         json.object([
//           #("cartId", json.string(id)),
//           #("lines", lines_json |> json.preprocessed_array),
//         ])

//       let query = mutations.add_to_cart_mutation()

//       fetch(
//         worker_subject: worker,
//         client:,
//         query:,
//         decoder: shopify_add_to_cart_operation_decoder(),
//         variables: Some(variables),
//         on_result: fn(result) {
//           let final_result =
//             result
//             |> result.map(fn(response) {
//               let cart = response.body.data.cart
//               reshape_cart(cart)
//             })
//           on_result(final_result)
//         },
//       )
//     }
//     Error(Nil) -> {
//       let err = "Unable to add to cart"
//       wisp.log_error(err)
//     }
//   }
// }

// fn remove_from_cart(
//   client: ShopifyClient,
//   line_ids: List(String),
//   req: Request,
//   worker: process.Subject(
//     FetchRequest(mutations.ShopifyRemoveFromCartOperation),
//   ),
//   on_result: fn(Result(Cart, ShopifyError)) -> Nil,
// ) {
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Ok(id) -> {
//       let variables =
//         json.object([
//           #("cartId", json.string(id)),
//           #("lineIds", json.array(line_ids, of: json.string)),
//         ])

//       let query = mutations.remove_from_cart_mutation()

//       fetch(
//         client:,
//         query:,
//         decoder: shopify_remove_from_cart_operation_decoder(),
//         variables: Some(variables),
//         worker_subject: worker,
//         on_result: fn(result) {
//           let final_result =
//             result
//             |> result.map(fn(response) {
//               let cart = response.body.data.cart_lines_remove.cart
//               reshape_cart(cart)
//             })
//           on_result(final_result)
//         },
//       )
//     }
//     Error(Nil) -> {
//       let err = "Unable to remove from the cart"
//       wisp.log_error(err)
//     }
//   }
// }

// fn update_cart(
//   client: ShopifyClient,
//   lines: List(CartItem),
//   req: Request,
//   worker: process.Subject(FetchRequest(mutations.ShopifyUpdateCartOperation)),
//   on_result: fn(Result(Cart, ShopifyError)) -> Nil,
// ) {
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Ok(id) -> {
//       let lines_json =
//         lines
//         |> list.map(fn(line) {
//           shopify_update_cart_line_update_to_json(ShopifyUpdateCartLineUpdate(
//             id:,
//             merchandise_id: line.merchandise.id,
//             quantity: line.quantity,
//           ))
//         })

//       let variables =
//         json.object([
//           #("cartId", json.string(id)),
//           #("lines", lines_json |> json.preprocessed_array),
//         ])

//       let query = mutations.edit_cart_mutation()

//       fetch(
//         client:,
//         query:,
//         worker_subject: worker,
//         decoder: shopify_update_cart_operation_decoder(),
//         variables: Some(variables),
//         on_result: fn(result) {
//           let final_result =
//             result
//             |> result.map(fn(resp) {
//               let cart = resp.body.data.cart_lines_update.cart
//               reshape_cart(cart)
//             })
//           on_result(final_result)
//         },
//       )
//     }
//     Error(Nil) -> {
//       let err = "Unable to update  the cart"
//       wisp.log_error(err)
//     }
//   }
// }

// fn get_cart(
//   client: ShopifyClient,
//   req: Request,
//   worker: process.Subject(FetchRequest(queries.ShopifyCartOperation)),
//   on_result: fn(Result(Option(Cart), ShopifyError)) -> Nil,
// ) {
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Error(_) -> on_result(Ok(None))
//     Ok(id) -> {
//       let query = get_cart_query()

//       let variables = json.object([#("cartId", json.string(id))])

//       fetch(
//         worker_subject: worker,
//         client: client,
//         query: query,
//         decoder: shopify_cart_operation_decoder(),
//         variables: Some(variables),
//         on_result: fn(result) {
//           let final_result =
//             result
//             |> result.map(fn(response) {
//               case response.body.data.cart {
//                 Some(cart) -> Some(reshape_cart(cart))
//                 None -> None
//               }
//             })
//           on_result(final_result)
//         },
//       )
//     }
//   }
// }

// // The we go for the products

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

fn append_path(request, path) {
  request.set_path(request, request.path <> path)
}

// /// Shopify types and decoders for our examples
pub opaque type Maybe(a) {
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

fn image_decoder() -> decode.Decoder(Image) {
  use url <- decode.field("url", decode.string)
  use alt_text <- decode.field("alt_text", decode.string)
  use width <- decode.field("width", decode.string)
  use height <- decode.field("height", decode.string)
  decode.success(Image(url:, alt_text:, width:, height:))
}

pub type PriceRange {
  PriceRange(max_variant_price: Money, min_variant_price: Money)
}

fn price_range_decoder() -> decode.Decoder(PriceRange) {
  use max_variant_price <- decode.field("max_variant_price", money_decoder())
  use min_variant_price <- decode.field("min_variant_price", money_decoder())
  decode.success(PriceRange(max_variant_price:, min_variant_price:))
}

pub type Money {
  Money(amount: String, currency_code: String)
}

fn money_decoder() -> decode.Decoder(Money) {
  use amount <- decode.field("amount", decode.string)
  use currency_code <- decode.field("currency_code", decode.string)
  decode.success(Money(amount:, currency_code:))
}

pub type ProductOption {
  ProductOption(id: String, name: String, values: List(String))
}

fn product_option_decoder() -> decode.Decoder(ProductOption) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use values <- decode.field("values", decode.list(decode.string))
  decode.success(ProductOption(id:, name:, values:))
}

pub type SelectedOption {
  SelectedOption(name: String, value: String)
}

fn selected_option_decoder() -> decode.Decoder(SelectedOption) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(SelectedOption(name:, value:))
}

pub type Cost {
  Cost(total_amount: Money)
}

fn cost_decoder() -> decode.Decoder(Cost) {
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

fn shopify_cart_cost_decoder() -> decode.Decoder(ShopifyCartCost) {
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

fn cart_decoder() -> decode.Decoder(Cart) {
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

fn cart_item_edge_decoder() -> decode.Decoder(Edge(CartItem)) {
  use node <- decode.field("node", cart_item_decoder())
  decode.success(Edge(node:))
}

fn cart_item_connection_decoder() -> decode.Decoder(Connection(CartItem)) {
  use edges <- decode.field("edges", decode.list(cart_item_edge_decoder()))
  decode.success(Connection(edges:))
}

fn shopify_cart_decoder() -> decode.Decoder(ShopifyCart) {
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

fn products_decoder() -> decode.Decoder(Products) {
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

fn product_decoder() -> decode.Decoder(Product) {
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

fn product_variant_decoder() -> decode.Decoder(ProductVariant) {
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

fn seo_decoder() -> decode.Decoder(Seo) {
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

fn image_connection_decoder() -> decode.Decoder(Connection(Image)) {
  use edges <- decode.field("edges", decode.list(image_edges_decoder()))
  decode.success(Connection(edges:))
}

fn image_edges_decoder() -> decode.Decoder(Edge(Image)) {
  use node <- decode.field("node", image_decoder())
  decode.success(Edge(node:))
}

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

// 1. Cart Operations.

// ADD TO CART MUTATIONS AND DECODERS

const add_to_cart_mutation = "
  mutation addToCart($cartId: ID!, $lines: [CartLineInput!]!) {
    cartLinesAdd(cartId: $cartId, lines: $lines) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

pub type CartLinesAdd {
  CartLinesAdd(cart: ShopifyCart)
}

fn cart_lines_add_decoder() -> decode.Decoder(CartLinesAdd) {
  use cart <- decode.field("cart", shopify_cart_decoder())
  decode.success(CartLinesAdd(cart:))
}

pub type ShopifyAddToCartOperation {
  ShopifyAddToCartMutation(
    data: CartLinesAdd,
    variables: List(ShopifyAddToCartOperationVariables),
  )
}

fn shopify_add_to_cart_operation_decoder() -> decode.Decoder(
  ShopifyAddToCartOperation,
) {
  use data <- decode.field("data", cart_lines_add_decoder())
  use variables <- decode.field(
    "variables",
    decode.list(shopify_add_to_cart_operation_variables_decoder()),
  )
  decode.success(ShopifyAddToCartMutation(data:, variables:))
}

fn shopify_add_to_cart_operation_variables_decoder() -> decode.Decoder(
  ShopifyAddToCartOperationVariables,
) {
  use cart_id <- decode.field("cart_id", decode.string)
  use lines <- decode.field(
    "lines",
    shopify_add_to_cart_operation_variables_lines_decoder(),
  )
  decode.success(ShopifyAddToCartOperationVariables(cart_id:, lines:))
}

pub type ShopifyAddToCartOperationVariablesLines {
  ShopifyAddToCartOperationVariablesLines(merchandise_id: String, quantity: Int)
}

fn shopify_add_to_cart_operation_variables_lines_to_json(
  shopify_add_to_cart_operation_variables_lines: ShopifyAddToCartOperationVariablesLines,
) -> json.Json {
  let ShopifyAddToCartOperationVariablesLines(merchandise_id:, quantity:) =
    shopify_add_to_cart_operation_variables_lines
  json.object([
    #("merchandise_id", json.string(merchandise_id)),
    #("quantity", json.int(quantity)),
  ])
}

fn shopify_add_to_cart_operation_variables_lines_decoder() -> decode.Decoder(
  ShopifyAddToCartOperationVariablesLines,
) {
  use merchandise_id <- decode.field("merchandise_id", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  decode.success(ShopifyAddToCartOperationVariablesLines(
    merchandise_id:,
    quantity:,
  ))
}

pub type ShopifyAddToCartOperationVariables {
  ShopifyAddToCartOperationVariables(
    cart_id: String,
    lines: ShopifyAddToCartOperationVariablesLines,
  )
}

pub type ShopifyCartLinesAddOperation {
  ShopifyCartLinesAddOperation(cart: ShopifyCart)
}

// CREATE CART MUTATIONS AND DECODERS

const create_cart_mutation = "
  mutation createCart($lineItems: [CartLineInput!]) {
    cartCreate(input: { lines: $lineItems }) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

pub type ShopifyCreateCartMutation {
  ShopifyCreateCartMutation(data: ShopifyCreateCartData)
}

fn shopify_create_cart_mutation_decoder() -> decode.Decoder(
  ShopifyCreateCartMutation,
) {
  use data <- decode.field("data", shopify_create_cart_data_decoder())
  decode.success(ShopifyCreateCartMutation(data:))
}

pub type ShopifyCreateCartData {
  ShopifyCreateCartData(cart_create: CreateCart)
}

fn shopify_create_cart_data_decoder() -> decode.Decoder(ShopifyCreateCartData) {
  use cart_create <- decode.field("cartCreate", create_cart_decoder())
  decode.success(ShopifyCreateCartData(cart_create:))
}

pub type CreateCart {
  CreateCart(cart: ShopifyCart)
}

fn create_cart_decoder() -> decode.Decoder(CreateCart) {
  use cart <- decode.field("cart", shopify_cart_decoder())
  decode.success(CreateCart(cart:))
}

// REMOVE CART MUTATIONS AND DECODERS

const remove_from_cart_mutation = "
  mutation removeFromCart($cartId: ID!, $lineIds: [ID!]!) {
    cartLinesRemove(cartId: $cartId, lineIds: $lineIds) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

pub type ShopifyRemoveFromCartOperation {
  ShopifyRemoveFromCartOperation(
    data: RemoveOperationData,
    variables: ShopifyRemoveFromCartVariables,
  )
}

fn shopify_remove_from_cart_operation_decoder() -> decode.Decoder(
  ShopifyRemoveFromCartOperation,
) {
  use data <- decode.field("data", remove_operation_data_decoder())
  use variables <- decode.field(
    "variables",
    shopify_remove_from_cart_variables_decoder(),
  )
  decode.success(ShopifyRemoveFromCartOperation(data:, variables:))
}

pub type ShopifyRemoveFromCartVariables {
  ShopifyRemoveFromCartVariables(cart_id: String, line_ids: List(String))
}

fn shopify_remove_from_cart_variables_to_json(
  shopify_remove_from_cart_variables: ShopifyRemoveFromCartVariables,
) -> json.Json {
  let ShopifyRemoveFromCartVariables(cart_id:, line_ids:) =
    shopify_remove_from_cart_variables
  json.object([
    #("cart_id", json.string(cart_id)),
    #("line_ids", json.array(line_ids, json.string)),
  ])
}

fn shopify_remove_from_cart_variables_decoder() -> decode.Decoder(
  ShopifyRemoveFromCartVariables,
) {
  use cart_id <- decode.field("cart_id", decode.string)
  use line_ids <- decode.field("line_ids", decode.list(decode.string))
  decode.success(ShopifyRemoveFromCartVariables(cart_id:, line_ids:))
}

pub type RemoveOperationData {
  RemoveOperationData(cart_lines_remove: CartLinesRemove)
}

fn remove_operation_data_decoder() -> decode.Decoder(RemoveOperationData) {
  use cart_lines_remove <- decode.field(
    "cartLinesRemove",
    cart_lines_remove_decoder(),
  )
  decode.success(RemoveOperationData(cart_lines_remove:))
}

pub type CartLinesRemove {
  CartLinesRemove(cart: ShopifyCart)
}

fn cart_lines_remove_decoder() -> decode.Decoder(CartLinesRemove) {
  use cart <- decode.field("cart", shopify_cart_decoder())
  decode.success(CartLinesRemove(cart:))
}

// EDIT CART MUTATIONS AND DECODERS

const edit_cart_mutation = "
  mutation editCartItems($cartId: ID!, $lines: [CartLineUpdateInput!]!) {
    cartLinesUpdate(cartId: $cartId, lines: $lines) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

pub type ShopifyUpdateCartOperation {
  ShopifyUpdateCartOperation(
    data: UpdateOperationData,
    variables: ShopifyUpdateCartVariables,
  )
}

fn shopify_update_cart_operation_decoder() -> decode.Decoder(
  ShopifyUpdateCartOperation,
) {
  use data <- decode.field("data", update_operation_data_decoder())
  use variables <- decode.field(
    "variables",
    shopify_update_cart_variables_decoder(),
  )
  decode.success(ShopifyUpdateCartOperation(data:, variables:))
}

pub type UpdateOperationData {
  UpdateOperationData(cart_lines_update: CartLinesUpdate)
}

fn update_operation_data_decoder() -> decode.Decoder(UpdateOperationData) {
  use cart_lines_update <- decode.field(
    "cartLinesUpdate",
    cart_lines_update_decoder(),
  )
  decode.success(UpdateOperationData(cart_lines_update:))
}

pub type CartLinesUpdate {
  CartLinesUpdate(cart: ShopifyCart)
}

fn cart_lines_update_decoder() -> decode.Decoder(CartLinesUpdate) {
  use cart <- decode.field("cart", shopify_cart_decoder())
  decode.success(CartLinesUpdate(cart:))
}

pub type ShopifyUpdateCartVariables {
  ShopifyUpdateCartVariables(
    cart_id: String,
    lines: List(ShopifyUpdateCartLineUpdate),
  )
}

fn shopify_update_cart_variables_decoder() -> decode.Decoder(
  ShopifyUpdateCartVariables,
) {
  use cart_id <- decode.field("cartId", decode.string)
  use lines <- decode.field(
    "lines",
    decode.list(shopify_update_cart_line_update_decoder()),
  )
  decode.success(ShopifyUpdateCartVariables(cart_id:, lines:))
}

pub type ShopifyUpdateCartLineUpdate {
  ShopifyUpdateCartLineUpdate(id: String, merchandise_id: String, quantity: Int)
}

fn shopify_update_cart_line_update_to_json(
  shopify_update_cart_line_update: ShopifyUpdateCartLineUpdate,
) -> json.Json {
  let ShopifyUpdateCartLineUpdate(id:, merchandise_id:, quantity:) =
    shopify_update_cart_line_update
  json.object([
    #("id", json.string(id)),
    #("merchandiseId", json.string(merchandise_id)),
    #("quantity", json.int(quantity)),
  ])
}

fn shopify_update_cart_line_update_decoder() -> decode.Decoder(
  ShopifyUpdateCartLineUpdate,
) {
  use id <- decode.field("id", decode.string)
  use merchandise_id <- decode.field("merchandiseId", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  decode.success(ShopifyUpdateCartLineUpdate(id:, merchandise_id:, quantity:))
}

// 1. Cart

const get_cart_query = "
  query getCart($cartId: ID!) {
    cart(id: $cartId) {
      ...cart
    }
  }
  "
  <> cart_fragment

pub type ShopifyCartOperation {
  ShopifyCartOperation(
    data: ShopifyCartOperationData,
    variables: ShopifyCartOperationVariables,
  )
}

fn shopify_cart_operation_decoder() -> decode.Decoder(ShopifyCartOperation) {
  use data <- decode.field("data", shopify_cart_operation_data_decoder())
  use variables <- decode.field(
    "variables",
    shopify_cart_operation_variables_decoder(),
  )
  decode.success(ShopifyCartOperation(data:, variables:))
}

pub type ShopifyCartOperationData {
  ShopifyCartOperationData(cart: Option(ShopifyCart))
}

fn shopify_cart_operation_data_decoder() -> decode.Decoder(
  ShopifyCartOperationData,
) {
  use cart <- decode.field("cart", decode.optional(shopify_cart_decoder()))
  decode.success(ShopifyCartOperationData(cart:))
}

pub type ShopifyCartOperationVariables {
  ShopifyCartOperationVariables(cart_id: String)
}

fn shopify_cart_operation_variables_decoder() -> decode.Decoder(
  ShopifyCartOperationVariables,
) {
  use cart_id <- decode.field("cartId", decode.string)
  decode.success(ShopifyCartOperationVariables(cart_id:))
}

// 2. Products

const get_product_query = "
  query getProduct($handle: String!) {
    product(handle: $handle) {
      ...product
    }
  }
  "
  <> product_fragment

pub type ShopifyProductOperation {
  ShopifyProductOperation(
    data: ShopifyProductOperationData,
    variables: ShopifyProductOperationVariables,
  )
}

fn shopify_product_operation_decoder() -> decode.Decoder(
  ShopifyProductOperation,
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

const get_products_query = "
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

pub type ShopifyProductsOperation {
  ShopifyProductsOperation(
    data: ShopifyProductsOperationData,
    variables: ShopifyProductsOperationVariables,
  )
}

fn shopify_products_operation_decoder() -> decode.Decoder(
  ShopifyProductsOperation,
) {
  use data <- decode.field("data", shopify_products_operation_data_decoder())
  use variables <- decode.field(
    "variables",
    shopify_products_operation_variables_decoder(),
  )
  decode.success(ShopifyProductsOperation(data:, variables:))
}

pub opaque type ShopifyProductsOperationData {
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

pub opaque type ShopifyProductsOperationVariables {
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

const get_product_recommendations_query = "
  query getProductRecommendations($productId: ID!) {
    productRecommendations(productId: $productId) {
      ...product
    }
  }
  "
  <> product_fragment

pub opaque type ShopifyProductRecommendationsOperation {
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

const cart_fragment = "
  	fragment cart on Cart {
  		id
  		checkoutUrl
  		cost {
  			subtotalAmount {
  				amount
  				currencyCode
  			}
  			totalAmount {
  				amount
  				currencyCode
  			}
  			totalTaxAmount {
  				amount
  				currencyCode
  			}
  		}
  		lines(first: 100) {
  			edges {
  				node {
  					id
  					quantity
  					attributes {
  						key
  						value
  					}
  					cost {
  						totalAmount {
  							amount
  							currencyCode
  						}
  					}
  					merchandise {
  						... on ProductVariant {
  							id
  							title
  							compareAtPrice {
  								amount
  								currencyCode
  							}
  							selectedOptions {
  								name
  								value
  							}
  							product {
  								...product
  							}
  						}
  					}
  				}
  			}
  		}
  		totalQuantity
  	}
  "
  <> product_fragment

const image_fragment = // GraphQL
"
	fragment image on Image {
		url
		altText
		width
		height
	}
  "

const metafield_fragment = // GraphQL
"
  fragment metafield on Metafield {
  key
  value
  type
  }
  "

const metaobject_fragment = // GraphQL
"
  	fragment metaobject on Metaobject {
  		id
  		type
  		fields {
  			key
  			value
  			type
  			reference {
  				... on Metaobject {
  					id
  					type
  					fields {
  						key
  						value
  					}
  				}
  			}
  		}
  	}
  "

const money_fields_fragment = "
  fragment MoneyFields on MoneyV2 {
      amount
      currencyCode
    }
  "

const money_bag_fields_fragment = "
    fragment MoneyBagFields on MoneyBag {
      shopMoney {
        ...MoneyFields
      }
      presentmentMoney {
        ...MoneyFields
      }
    }
  "

const line_items_fields_fragment = "
  fragment LineItemFields on LineItem {
    id
    name
    title
    quantity
  	discountAllocations {
    allocatedAmountSet {
      presentmentMoney {
        amount
        currencyCode
      }
    }
    discountApplication {
      allocationMethod
      value {
        ...MoneyFields
      }
    }
      discountApplication {
        ...DiscountApplicationFields
      }
  }
    requiresShipping
    sku
    taxable
    product {
    	id
      handle
    }
    variant {
      id
      price
      product {
        id
        handle
      }
      title
    }
    originalTotalSet {
      ...MoneyBagFields
    }
    discountedTotalSet {
      ...MoneyBagFields
    }
    customAttributes {
      key
      value
      }
    }
  "

const discount_application_fields_fragment = "
    fragment DiscountApplicationFields on DiscountApplication {
      allocationMethod
      targetSelection
    targetType
      value {
        ... on MoneyV2 {
          ...MoneyFields
        }
        ... on PricingPercentageValue {
          percentage
        }
      }
    ... on DiscountCodeApplication {
      code
    }
    ... on AutomaticDiscountApplication {
      title
      }
    }
  "

const address_fields_fragment = "
    fragment AddressFields on MailingAddressConnection {
      pageInfo {
        hasNextPage
        endCursor
      }
      edges {
        cursor
        node {
          ... on MailingAddress{
            name
          }
        }
      }
      nodes{
        id
        address1
        address2
        name
        firstName
        lastName
      city
      province
      country
      countryCodeV2
      formatted
      formattedArea
      timeZone
        zip
      }
    }
  "

const customer_fields_fragments = "
    fragment CustomerFields on Customer {
    id
    displayName
    firstName
    lastName
    numberOfOrders
    note
    tags
    updatedAt
    verifiedEmail
    defaultAddress{
      name
      phone
      timeZone
      id
      address1
      address2
      zip
      city
      company
      country
      countryCodeV2
      formatted
      formattedArea
    }
    defaultEmailAddress {
      emailAddress
      marketingOptInLevel
      marketingState
      validFormat
    }
    defaultPhoneNumber {
      phoneNumber
      marketingOptInLevel
      marketingState
    }
  }
  "

const order_node_fields = "
    fragment OrderNodeFields on Order {
      id
      name
      note
      createdAt
      updatedAt
    processedAt
    cancelledAt
    cancelReason
    closed
    closedAt
    confirmed
    test
    currentSubtotalLineItemsQuantity
    currentTotalWeight
    displayFinancialStatus
    displayFulfillmentStatus
    edited
    requiresShipping
    currentSubtotalPriceSet {
      ...MoneyBagFields
    }
    currentTotalPriceSet {
      ...MoneyBagFields
    }
    currentTotalDiscountsSet {
      ...MoneyBagFields
    }
    currentTotalTaxSet {
      ...MoneyBagFields
    }
    originalTotalPriceSet {
      ...MoneyBagFields
    }
    app {
      id
      name
    }
    customer {
      ...CustomerFields
    }
    discountApplications(first: 10) {
      edges {
        node {
          ...DiscountApplicationFields
        }
      }
    }
    tags
    taxExempt
    taxesIncluded
    lineItems(first: 25) {
      edges {
        node {
          ...LineItemFields
        }
      }
    }
    fulfillments {
      id
      createdAt
      displayStatus
      estimatedDeliveryAt
      status
      trackingInfo {
        company
        number
        url
      }
    }
    refunds {
      id
      createdAt
      note
    }
    transactions {
      id
      createdAt
      errorCode
      gateway
      kind
      processedAt
      status
      test
    }
  }
  "

const product_fragment = "
	fragment product on Product {
		id
		handle
		availableForSale
		title
		description
		descriptionHtml
		vendor
		options {
			id
			name
			values
		}
		priceRange {
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
			maxVariantPrice {
				amount
				currencyCode
			}
			minVariantPrice {
				amount
				currencyCode
			}
		}
		variants(first: 250) {
			edges {
				node {
					id
					title
					availableForSale
					selectedOptions {
						name
						value
					}
					price {
						amount
						currencyCode
					}
				}
			}
		}
		featuredImage {
			...image
		}
		images(first: 20) {
			edges {
				node {
					...image
				}
			}
		}
		seo {
			...seo
		}
		metafields(
		{ namespace: \"metafield\", key: \"width\" }
						{ namespace: \"metafield\", key: \"height\" }
						{ namespace: \"metafield\", key: \"thickness\" }
						{ namespace: \"metafield\", key: \"pages\" }
						{ namespace: \"metafield\", key: \"categories\" }
						{ namespace: \"metafield\", key: \"language\" }
						{ namespace: \"metafield\", key: \"format\" }
						{ namespace: \"custom\", key: \"author\" }
						{ namespace: \"custom\", key: \"publisher\" }
						{ namespace: \"custom\", key: \"related-authors\" }
						{ namespace: \"custom\", key: \"people-who-worked\" }
						{ namespace: \"custom\", key: \"translator\" }
						{ namespace: \"custom\", key: \"related-books\" }
						{ namespace: \"shopify\", key: \"genre\" }
						{ namespace: \"shopify\", key: \"book-cover-type\" }
						{ namespace: \"shopify\", key: \"target-audience\" }
					]
		) {
			key
			namespace
			value
			type
			references(first: 5) {
				nodes {
					... on Metaobject {
						id
						type
						fields {
							key
							value
						}
					}
				}
			}
		}
		tags
		updatedAt
	}
"
  <> image_fragment
  <> seo_fragment

const seo_fragment = "
  fragment seo on SEO {
  description
  title
  }
  "
