//// Shopify sends money as decimal strings such as `"49.90"` or `"49.9"`.
//// A `Decimal` keeps the digits as an integer count of units at the scale
//// the text carried, never a Float.

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order.{type Order}
import gleam/string

/// `units / 10^scale`. `"49.90"` is 4990 units at scale 2.
pub opaque type Decimal {
  Decimal(units: Int, scale: Int)
}

pub type DecimalError {
  DecimalInvalid(text: String)
}

/// Parse `"49.9"`, `"49.90"`, `"0"` or `"-1.5"`. Rejects an empty string,
/// a bare `.`, a leading `+`, exponents and grouping separators.
pub fn parse(text: String) -> Result(Decimal, DecimalError) {
  let parsed = case string.trim(text) {
    "-" <> rest -> parse_unsigned(rest) |> option.map(negate)
    rest -> parse_unsigned(rest)
  }
  option.to_result(parsed, DecimalInvalid(text:))
}

pub fn decoder() -> decode.Decoder(Decimal) {
  use text <- decode.then(decode.string)
  case parse(text) {
    Ok(decimal) -> decode.success(decimal)
    Error(DecimalInvalid(..)) -> decode.failure(Decimal(0, 0), "decimal string")
  }
}

/// `units / 10^scale`. A negative scale multiplies: 5 at scale -1 is 50.
pub fn from_scaled(units units: Int, scale scale: Int) -> Decimal {
  case scale < 0 {
    True -> Decimal(units: units * pow10(0 - scale), scale: 0)
    False -> Decimal(units:, scale:)
  }
}

pub fn from_hundredths(hundredths: Int) -> Decimal {
  from_scaled(units: hundredths, scale: 2)
}

pub type ScaleError {
  /// The value has more significant fraction digits than `scale` holds.
  ScaleDropsDigits(scale: Int)
}

pub fn scale_error_to_string(error: ScaleError) -> String {
  case error {
    ScaleDropsDigits(scale:) ->
      "has more than " <> int.to_string(scale) <> " decimal places"
  }
}

/// The integer count of units at `scale`. `"49.9"` at scale 2 is 4990.
/// Fails when the value has more significant fraction digits than `scale`,
/// because dropping them would change the amount.
pub fn to_scaled(decimal: Decimal, scale: Int) -> Result(Int, ScaleError) {
  case int.compare(scale, decimal.scale) {
    order.Gt | order.Eq -> Ok(decimal.units * pow10(scale - decimal.scale))
    order.Lt -> {
      let divisor = pow10(decimal.scale - scale)
      case decimal.units % divisor {
        0 -> Ok(decimal.units / divisor)
        _ -> Error(ScaleDropsDigits(scale:))
      }
    }
  }
}

/// The text form Shopify accepts on writes. It keeps the scale, so
/// `from_hundredths(4990)` is `"49.90"`.
pub fn to_string(decimal: Decimal) -> String {
  let sign = case decimal.units < 0 {
    True -> "-"
    False -> ""
  }
  let magnitude = int.absolute_value(decimal.units)
  case decimal.scale {
    0 -> sign <> int.to_string(magnitude)
    scale -> {
      let divisor = pow10(scale)
      sign
      <> int.to_string(magnitude / divisor)
      <> "."
      <> string.pad_start(int.to_string(magnitude % divisor), scale, "0")
    }
  }
}

/// Compares values, not text: `"49.9"` equals `"49.90"`.
pub fn compare(left: Decimal, right: Decimal) -> Order {
  let scale = int.max(left.scale, right.scale)
  int.compare(
    left.units * pow10(scale - left.scale),
    right.units * pow10(scale - right.scale),
  )
}

pub fn negate(decimal: Decimal) -> Decimal {
  Decimal(..decimal, units: -decimal.units)
}

fn parse_unsigned(text: String) -> Option(Decimal) {
  case string.split(text, ".") {
    [whole] -> digits(whole) |> option.map(fn(units) { Decimal(units, 0) })
    [whole, fraction] -> {
      use whole_units <- option.then(digits(whole))
      use fraction_units <- option.then(digits(fraction))
      let scale = string.length(fraction)
      option.Some(Decimal(
        units: whole_units * pow10(scale) + fraction_units,
        scale:,
      ))
    }
    _ -> option.None
  }
}

fn digits(text: String) -> Option(Int) {
  let graphemes = string.to_graphemes(text)
  case graphemes != [] && list.all(graphemes, is_digit) {
    True -> option.from_result(int.parse(text))
    False -> option.None
  }
}

fn is_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn pow10(exponent: Int) -> Int {
  case exponent <= 0 {
    True -> 1
    False -> 10 * pow10(exponent - 1)
  }
}
