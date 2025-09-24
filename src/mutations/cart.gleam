import fragments/cart.{cart_fragment}
import gleam/dynamic/decode
import types.{type ShopifyCart, shopify_cart_decoder}

pub fn add_to_cart_mutation() {
  "
  mutation addToCart($cartId: ID!, $lines: [CartLineInput!]!) {
    cartLinesAdd(cartId: $cartId, lines: $lines) {
      cart {
        ...cart
      }
    }
  }
  " <> cart_fragment()
}

pub fn create_cart_mutation() {
  "
  mutation createCart($lineItems: [CartLineInput!]) {
    cartCreate(input: { lines: $lineItems }) {
      cart {
        ...cart
      }
    }
  }
  " <> cart_fragment()
}

pub type ShopifyCreateCartMutation {
  ShopifyCreateCartMutation(data: CreateCart)
}

pub fn shopify_create_cart_mutation_decoder() -> decode.Decoder(
  ShopifyCreateCartMutation,
) {
  use data <- decode.field("data", create_cart_decoder())
  decode.success(ShopifyCreateCartMutation(data:))
}

pub type CreateCart {
  CreateCart(cart: ShopifyCart)
}

pub fn create_cart_decoder() -> decode.Decoder(CreateCart) {
  use cart <- decode.field("cart", shopify_cart_decoder())
  decode.success(CreateCart(cart:))
}

pub fn edit_cart_mutation() {
  "
  mutation editCartItems($cartId: ID!, $lines: [CartLineUpdateInput!]!) {
    cartLinesUpdate(cartId: $cartId, lines: $lines) {
      cart {
        ...cart
      }
    }
  }
  " <> cart_fragment()
}

pub fn remove_from_cart_mutation() {
  "
  mutation removeFromCart($cartId: ID!, $lineIds: [ID!]!) {
    cartLinesRemove(cartId: $cartId, lineIds: $lineIds) {
      cart {
        ...cart
      }
    }
  }
  " <> cart_fragment()
}
