//// An amount of money as Shopify sends it: a decimal string and a currency
//// code.

import gleam/dynamic/decode
import pify/decimal.{type Decimal}

pub type Money {
  Money(amount: Decimal, currency_code: String)
}

/// The selection of a `MoneyV2`.
pub const fields = " amount currencyCode"

pub fn decoder() -> decode.Decoder(Money) {
  use amount <- decode.field("amount", decimal.decoder())
  use currency_code <- decode.field("currencyCode", decode.string)
  decode.success(Money(amount:, currency_code:))
}
