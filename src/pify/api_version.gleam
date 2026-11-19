//// The Shopify API version a client uses.
////
//// Shopify releases a stable version on the first day of each quarter
//// (`2026-01`, `2026-04`, `2026-07`, `2026-10`) and keeps it accessible for
//// twelve months, until about day 16 of the same month one year later. A
//// request for a retired version falls forward to the oldest accessible
//// one, so a response can be serialized by a version the consumer did not
//// ask for. `execute.run_served` reports the version that served each
//// response.
////
//// The library holds no clock. Every date question takes a `Day` that the
//// caller supplies.

import gleam/bool
import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/result
import gleam/string

pub opaque type ApiVersion {
  ApiVersion(year: Int, month: Int)
}

pub type ApiVersionError {
  /// The text is not `YYYY-MM`.
  ApiVersionErrorMalformed(raw: String)
  /// The month is not a quarter start (01, 04, 07, 10).
  ApiVersionErrorNotQuarterly(raw: String)
  /// `unstable` changes without notice and is never accepted.
  ApiVersionErrorUnstable
}

/// A calendar day in UTC.
pub type Day {
  Day(year: Int, month: Int, day: Int)
}

pub const v2026_01 = ApiVersion(year: 2026, month: 1)

pub const v2026_04 = ApiVersion(year: 2026, month: 4)

pub const v2026_07 = ApiVersion(year: 2026, month: 7)

pub const v2026_10 = ApiVersion(year: 2026, month: 10)

/// The version a new connection starts on.
pub fn default() -> ApiVersion {
  v2026_10
}

pub fn parse(text: String) -> Result(ApiVersion, ApiVersionError) {
  let trimmed = string.trim(text)
  use <- bool.guard(trimmed == "unstable", Error(ApiVersionErrorUnstable))
  use #(year, month) <- result.try(year_month(trimmed))
  case is_quarter_month(month) {
    True -> Ok(ApiVersion(year:, month:))
    False -> Error(ApiVersionErrorNotQuarterly(trimmed))
  }
}

/// The year and month of `YYYY-MM`, four and two ASCII digits.
fn year_month(text: String) -> Result(#(Int, Int), ApiVersionError) {
  case string.split(text, "-") {
    [year_text, month_text] -> {
      use year <- result.try(digits(year_text, of: text))
      use month <- result.try(digits(month_text, of: text))
      case string.length(year_text), string.length(month_text) {
        4, 2 if year >= 1000 -> Ok(#(year, month))
        _, _ -> Error(ApiVersionErrorMalformed(text))
      }
    }
    _ -> Error(ApiVersionErrorMalformed(text))
  }
}

/// The handle Shopify uses in URLs and headers, such as `2026-07`.
pub fn to_string(version: ApiVersion) -> String {
  int.to_string(version.year)
  <> "-"
  <> string.pad_start(int.to_string(version.month), 2, "0")
}

pub fn compare(left: ApiVersion, right: ApiVersion) -> Order {
  int.compare(left.year, right.year)
  |> order.lazy_break_tie(fn() { int.compare(left.month, right.month) })
}

/// True when `version` is `since` or newer. Request shapes that changed
/// between versions branch on this, never on the handle text.
pub fn at_least(version: ApiVersion, since: ApiVersion) -> Bool {
  case compare(version, since) {
    order.Gt | order.Eq -> True
    order.Lt -> False
  }
}

/// A version is stable from the first day of its month. Before that day it
/// is a release candidate.
pub fn released_on(version: ApiVersion, today: Day) -> Bool {
  compare_days(today, Day(year: version.year, month: version.month, day: 1))
  != order.Lt
}

/// Shopify retires a version at 15:00 UTC on day 16 of the same month one
/// year later. That day counts as closed.
pub fn accessible_on(version: ApiVersion, today: Day) -> Bool {
  released_on(version, today)
  && compare_days(today, retired_on(version)) == order.Lt
}

/// Day 16 of the same month one year later, the first day the version is
/// closed.
pub fn retired_on(version: ApiVersion) -> Day {
  Day(year: version.year + 1, month: version.month, day: 16)
}

/// Days from `today` to `retired_on(version)`. Zero or less means the
/// version is retired, so a request for it falls forward.
pub fn days_until_retired(version: ApiVersion, today: Day) -> Int {
  day_number(retired_on(version)) - day_number(today)
}

/// The number `segment` spells in ASCII digits only, since `int.parse` alone
/// takes a sign. Anything else leaves the whole version `text` malformed.
fn digits(segment: String, of text: String) -> Result(Int, ApiVersionError) {
  case list.all(string.to_graphemes(segment), is_digit), int.parse(segment) {
    True, Ok(number) -> Ok(number)
    True, Error(Nil) | False, _ -> Error(ApiVersionErrorMalformed(text))
  }
}

fn is_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_quarter_month(month: Int) -> Bool {
  month == 1 || month == 4 || month == 7 || month == 10
}

/// Days since 1970-01-01 in the proleptic Gregorian calendar, for years
/// from 1 on.
fn day_number(day: Day) -> Int {
  let year = case day.month <= 2 {
    True -> day.year - 1
    False -> day.year
  }
  let era = year / 400
  let year_of_era = year - era * 400
  let shifted_month = case day.month > 2 {
    True -> day.month - 3
    False -> day.month + 9
  }
  let day_of_year = { 153 * shifted_month + 2 } / 5 + day.day - 1
  let day_of_era =
    year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
  era * 146_097 + day_of_era - 719_468
}

fn compare_days(left: Day, right: Day) -> Order {
  int.compare(left.year, right.year)
  |> order.lazy_break_tie(fn() { int.compare(left.month, right.month) })
  |> order.lazy_break_tie(fn() { int.compare(left.day, right.day) })
}
