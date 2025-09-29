import gleam/dynamic/decode
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import midas/task as t
import pify.{type StorefrontApiClientConfig, handler}
import snag
import storefront/fragments.{cart_fragment}
import storefront/utils.{
  type Connection, type Cost, type Edge, type Image, type Money,
  type SelectedOption, Connection, Edge, cost_decoder, image_decoder,
  money_decoder, remove_edges_and_nodes, selected_option_decoder,
}

pub const cookie_name = "cartId"

pub fn create_cart(config: StorefrontApiClientConfig) {
  let handler = handler(config)

  let fetcher =
    handler.fetch(
      create_cart_mutation,
      None,
      shopify_create_cart_mutation_decoder(),
    )
  case fetcher {
    t.Done(cart) -> {
      Ok(reshape_cart(cart.data.cart_create.cart))
    }
    err -> {
      Error(pify.ClientError(
        snag.new(string.inspect(err))
        |> snag.layer("This effect is not handled in this environment")
        |> snag.line_print,
      ))
    }
  }
}

pub fn get_cart(
  config: StorefrontApiClientConfig,
  req: request.Request(Cart),
) -> Result(Cart, pify.ShopifyError) {
  let client = handler(config)
  let try_cookies = {
    request.get_cookies(req)
    |> list.key_find("cartId")
  }

  case try_cookies {
    Error(err) ->
      Error(pify.ClientError(
        snag.new(string.inspect(err))
        |> snag.layer("This effect is not handled in this environment")
        |> snag.line_print,
      ))
    Ok(id) -> {
      let query = get_cart_query

      let variables = json.object([#("cartId", json.string(id))])

      let fetcher =
        client.fetch(query, Some(variables), shopify_cart_operation_decoder())

      case fetcher {
        t.Done(cart) -> {
          case cart.data.cart {
            Some(cart) -> Ok(reshape_cart(cart))
            None ->
              Error(pify.ClientError(
                snag.new("We were unable to get the cart.")
                |> snag.layer("This effect is not handled in this environment")
                |> snag.line_print,
              ))
          }
        }
        err -> {
          Error(pify.ClientError(
            snag.new(string.inspect(err))
            |> snag.layer("This effect is not handled in this environment")
            |> snag.line_print,
          ))
        }
      }
    }
  }
}

// pub fn add_to_cart(
//   config: StorefrontApiClientConfig,
//   lines: List(CartItem),
//   req: Request,
//   on_result: fn(Result(Cart, ShopifyError)) -> Nil,
// ) -> Nil {
//   let client = handler(config)
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Error(Nil) -> create_cart(config, on_result)
//     Ok(id) -> {
//       let query = add_to_cart_mutation
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

//       let fetch =
//         client.fetch(
//           query,
//           Some(variables),
//           shopify_add_to_cart_operation_decoder(),
//         )

//       promise.map_try(fetch, fn(res) {
//         let cart = Ok(reshape_cart(res.data.cart))
//         cart
//       })
//       |> promise.tap(on_result)
//       Nil
//     }
//   }
// }

// pub fn remove_from_cart(
//   config: StorefrontApiClientConfig,
//   lines_ids: List(String),
//   req: Request,
//   on_result: fn(Result(Cart, ShopifyError)) -> Nil,
// ) -> Nil {
//   let client = handler(config)
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Error(Nil) -> create_cart(config, on_result)
//     Ok(id) -> {
//       let query = add_to_cart_mutation

//       let variables =
//         json.object([
//           #("cartId", json.string(id)),
//           #("lineIds", json.array(lines_ids, of: json.string)),
//         ])

//       let fetch =
//         client.fetch(
//           query,
//           Some(variables),
//           shopify_remove_from_cart_operation_decoder(),
//         )

//       promise.map_try(fetch, fn(res) {
//         let cart = Ok(reshape_cart(res.data.cart_lines_remove.cart))
//         cart
//       })
//       |> promise.tap(on_result)
//       Nil
//     }
//   }
// }

// pub fn update_cart(
//   config: StorefrontApiClientConfig,
//   lines: List(CartItem),
//   req: Request,
//   on_result: fn(Result(Cart, ShopifyError)) -> Nil,
// ) {
//   let client = handler(config)
//   case wisp.get_cookie(req, cookie_name, wisp.Signed) {
//     Error(Nil) -> create_cart(config, on_result)
//     Ok(id) -> {
//       let query = edit_cart_mutation
//       let lines_json = {
//         lines
//         |> list.map(fn(line) {
//           shopify_update_cart_line_update_to_json(ShopifyUpdateCartLineUpdate(
//             id:,
//             merchandise_id: line.merchandise.id,
//             quantity: line.quantity,
//           ))
//         })
//       }
//       let variables =
//         json.object([
//           #("cartId", json.string(id)),
//           #("lines", lines_json |> json.preprocessed_array),
//         ])
//       let fetch =
//         client.fetch(
//           query,
//           Some(variables),
//           shopify_update_cart_operation_decoder(),
//         )
//       promise.map_try(fetch, fn(res) {
//         Ok(reshape_cart(res.data.cart_lines_update.cart))
//       })
//       |> promise.tap(on_result)
//       Nil
//     }
//   }
// }

pub fn reshape_cart(cart: ShopifyCart) -> Cart {
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

pub const add_to_cart_mutation = "
  mutation addToCart($cartId: ID!, $lines: [CartLineInput!]!) {
    cartLinesAdd(cartId: $cartId, lines: $lines) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

// pub opaque type CartLinesAdd {
//   CartLinesAdd(cart: ShopifyCart)
// }

// fn cart_lines_add_decoder() -> decode.Decoder(CartLinesAdd) {
//   use cart <- decode.field("cart", shopify_cart_decoder())
//   decode.success(CartLinesAdd(cart:))
// }

// type ShopifyAddToCartOperation {
//   ShopifyAddToCartMutation(
//     data: CartLinesAdd,
//     variables: List(ShopifyAddToCartOperationVariables),
//   )
// }

// fn shopify_add_to_cart_operation_decoder() -> decode.Decoder(
//   ShopifyAddToCartOperation,
// ) {
//   use data <- decode.field("data", cart_lines_add_decoder())
//   use variables <- decode.field(
//     "variables",
//     decode.list(shopify_add_to_cart_operation_variables_decoder()),
//   )
//   decode.success(ShopifyAddToCartMutation(data:, variables:))
// }

// fn shopify_add_to_cart_operation_variables_decoder() -> decode.Decoder(
//   ShopifyAddToCartOperationVariables,
// ) {
//   use cart_id <- decode.field("cart_id", decode.string)
//   use lines <- decode.field(
//     "lines",
//     shopify_add_to_cart_operation_variables_lines_decoder(),
//   )
//   decode.success(ShopifyAddToCartOperationVariables(cart_id:, lines:))
// }

// type ShopifyAddToCartOperationVariablesLines {
//   ShopifyAddToCartOperationVariablesLines(merchandise_id: String, quantity: Int)
// }

// fn shopify_add_to_cart_operation_variables_lines_to_json(
//   shopify_add_to_cart_operation_variables_lines: ShopifyAddToCartOperationVariablesLines,
// ) -> json.Json {
//   let ShopifyAddToCartOperationVariablesLines(merchandise_id:, quantity:) =
//     shopify_add_to_cart_operation_variables_lines
//   json.object([
//     #("merchandise_id", json.string(merchandise_id)),
//     #("quantity", json.int(quantity)),
//   ])
// }

// fn shopify_add_to_cart_operation_variables_lines_decoder() -> decode.Decoder(
//   ShopifyAddToCartOperationVariablesLines,
// ) {
//   use merchandise_id <- decode.field("merchandise_id", decode.string)
//   use quantity <- decode.field("quantity", decode.int)
//   decode.success(ShopifyAddToCartOperationVariablesLines(
//     merchandise_id:,
//     quantity:,
//   ))
// }

// type ShopifyAddToCartOperationVariables {
//   ShopifyAddToCartOperationVariables(
//     cart_id: String,
//     lines: ShopifyAddToCartOperationVariablesLines,
//   )
// }

pub const create_cart_mutation = "
  mutation createCart($lineItems: [CartLineInput!]) {
    cartCreate(input: { lines: $lineItems }) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

type ShopifyCreateCartMutation {
  ShopifyCreateCartMutation(data: ShopifyCreateCartData)
}

fn shopify_create_cart_mutation_decoder() -> decode.Decoder(
  ShopifyCreateCartMutation,
) {
  use data <- decode.field("data", shopify_create_cart_data_decoder())
  decode.success(ShopifyCreateCartMutation(data:))
}

type ShopifyCreateCartData {
  ShopifyCreateCartData(cart_create: CreateCart)
}

fn shopify_create_cart_data_decoder() -> decode.Decoder(ShopifyCreateCartData) {
  use cart_create <- decode.field("cartCreate", create_cart_decoder())
  decode.success(ShopifyCreateCartData(cart_create:))
}

type CreateCart {
  CreateCart(cart: ShopifyCart)
}

fn create_cart_decoder() -> decode.Decoder(CreateCart) {
  use cart <- decode.field("cart", shopify_cart_decoder())
  decode.success(CreateCart(cart:))
}

// REMOVE CART MUTATIONS AND DECODERS

pub const remove_from_cart_mutation = "
  mutation removeFromCart($cartId: ID!, $lineIds: [ID!]!) {
    cartLinesRemove(cartId: $cartId, lineIds: $lineIds) {
      cart {
        ...cart
      }
    }
  }
  "
  <> cart_fragment

// type ShopifyRemoveFromCartOperation {
//   ShopifyRemoveFromCartOperation(
//     data: RemoveOperationData,
//     variables: ShopifyRemoveFromCartVariables,
//   )
// }

// fn shopify_remove_from_cart_operation_decoder() -> decode.Decoder(
//   ShopifyRemoveFromCartOperation,
// ) {
//   use data <- decode.field("data", remove_operation_data_decoder())
//   use variables <- decode.field(
//     "variables",
//     shopify_remove_from_cart_variables_decoder(),
//   )
//   decode.success(ShopifyRemoveFromCartOperation(data:, variables:))
// }

// type ShopifyRemoveFromCartVariables {
//   ShopifyRemoveFromCartVariables(cart_id: String, line_ids: List(String))
// }

// fn shopify_remove_from_cart_variables_decoder() -> decode.Decoder(
//   ShopifyRemoveFromCartVariables,
// ) {
//   use cart_id <- decode.field("cartId", decode.string)
//   use line_ids <- decode.field("lineIds", decode.list(decode.string))
//   decode.success(ShopifyRemoveFromCartVariables(cart_id:, line_ids:))
// }

// type RemoveOperationData {
//   RemoveOperationData(cart_lines_remove: CartLinesRemove)
// }

// fn remove_operation_data_decoder() -> decode.Decoder(RemoveOperationData) {
//   use cart_lines_remove <- decode.field(
//     "cartLinesRemove",
//     cart_lines_remove_decoder(),
//   )
//   decode.success(RemoveOperationData(cart_lines_remove:))
// }

// type CartLinesRemove {
//   CartLinesRemove(cart: ShopifyCart)
// }

// fn cart_lines_remove_decoder() -> decode.Decoder(CartLinesRemove) {
//   use cart <- decode.field("cart", shopify_cart_decoder())
//   decode.success(CartLinesRemove(cart:))
// }

// pub const edit_cart_mutation = "
//   mutation editCartItems($cartId: ID!, $lines: [CartLineUpdateInput!]!) {
//     cartLinesUpdate(cartId: $cartId, lines: $lines) {
//       cart {
//         ...cart
//       }
//     }
//   }
//   "
//   <> cart_fragment

// type ShopifyUpdateCartOperation {
//   ShopifyUpdateCartOperation(
//     data: UpdateOperationData,
//     variables: ShopifyUpdateCartVariables,
//   )
// }

// fn shopify_update_cart_operation_decoder() -> decode.Decoder(
//   ShopifyUpdateCartOperation,
// ) {
//   use data <- decode.field("data", update_operation_data_decoder())
//   use variables <- decode.field(
//     "variables",
//     shopify_update_cart_variables_decoder(),
//   )
//   decode.success(ShopifyUpdateCartOperation(data:, variables:))
// }

// type UpdateOperationData {
//   UpdateOperationData(cart_lines_update: CartLinesUpdate)
// }

// fn update_operation_data_decoder() -> decode.Decoder(UpdateOperationData) {
//   use cart_lines_update <- decode.field(
//     "cartLinesUpdate",
//     cart_lines_update_decoder(),
//   )
//   decode.success(UpdateOperationData(cart_lines_update:))
// }

// type CartLinesUpdate {
//   CartLinesUpdate(cart: ShopifyCart)
// }

// fn cart_lines_update_decoder() -> decode.Decoder(CartLinesUpdate) {
//   use cart <- decode.field("cart", shopify_cart_decoder())
//   decode.success(CartLinesUpdate(cart:))
// }

// type ShopifyUpdateCartVariables {
//   ShopifyUpdateCartVariables(
//     cart_id: String,
//     lines: List(ShopifyUpdateCartLineUpdate),
//   )
// }

// fn shopify_update_cart_variables_decoder() -> decode.Decoder(
//   ShopifyUpdateCartVariables,
// ) {
//   use cart_id <- decode.field("cartId", decode.string)
//   use lines <- decode.field(
//     "lines",
//     decode.list(shopify_update_cart_line_update_decoder()),
//   )
//   decode.success(ShopifyUpdateCartVariables(cart_id:, lines:))
// }

// type ShopifyUpdateCartLineUpdate {
//   ShopifyUpdateCartLineUpdate(id: String, merchandise_id: String, quantity: Int)
// }

// fn shopify_update_cart_line_update_to_json(
//   shopify_update_cart_line_update: ShopifyUpdateCartLineUpdate,
// ) -> json.Json {
//   let ShopifyUpdateCartLineUpdate(id:, merchandise_id:, quantity:) =
//     shopify_update_cart_line_update
//   json.object([
//     #("id", json.string(id)),
//     #("merchandiseId", json.string(merchandise_id)),
//     #("quantity", json.int(quantity)),
//   ])
// }

// fn shopify_update_cart_line_update_decoder() -> decode.Decoder(
//   ShopifyUpdateCartLineUpdate,
// ) {
//   use id <- decode.field("id", decode.string)
//   use merchandise_id <- decode.field("merchandiseId", decode.string)
//   use quantity <- decode.field("quantity", decode.int)
//   decode.success(ShopifyUpdateCartLineUpdate(id:, merchandise_id:, quantity:))
// }

pub const get_cart_query = "
  query getCart($cartId: ID!) {
    cart(id: $cartId) {
      ...cart
    }
  }
  "
  <> cart_fragment

pub opaque type ShopifyCartOperation {
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

type ShopifyCartOperationData {
  ShopifyCartOperationData(cart: Option(ShopifyCart))
}

fn shopify_cart_operation_data_decoder() -> decode.Decoder(
  ShopifyCartOperationData,
) {
  use cart <- decode.field("cart", decode.optional(shopify_cart_decoder()))
  decode.success(ShopifyCartOperationData(cart:))
}

type ShopifyCartOperationVariables {
  ShopifyCartOperationVariables(cart_id: String)
}

fn shopify_cart_operation_variables_decoder() -> decode.Decoder(
  ShopifyCartOperationVariables,
) {
  use cart_id <- decode.field("cartId", decode.string)
  decode.success(ShopifyCartOperationVariables(cart_id:))
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
