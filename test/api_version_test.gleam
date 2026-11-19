import gleam/order
import gleeunit/should
import pify/api_version.{Day}

pub fn parse_round_trip_test() {
  let assert Ok(version) = api_version.parse("2026-07")
  api_version.to_string(version) |> should.equal("2026-07")
  version |> should.equal(api_version.v2026_07)
  api_version.parse(" 2025-10 ") |> should.equal(Ok(v2025_10()))
}

pub fn parse_rejects_off_quarter_months_test() {
  api_version.parse("2026-02")
  |> should.equal(Error(api_version.ApiVersionErrorNotQuarterly("2026-02")))
  api_version.parse("2026-12")
  |> should.equal(Error(api_version.ApiVersionErrorNotQuarterly("2026-12")))
}

pub fn parse_rejects_unstable_and_junk_test() {
  api_version.parse("unstable")
  |> should.equal(Error(api_version.ApiVersionErrorUnstable))
  api_version.parse("2026-7")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("2026-7")))
  api_version.parse("26-07")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("26-07")))
  api_version.parse("2026-07-01")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("2026-07-01")))
  api_version.parse("")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("")))
  api_version.parse("+202-07")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("+202-07")))
  api_version.parse("2026-+4")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("2026-+4")))
  api_version.parse("-2026-07")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("-2026-07")))
  api_version.parse("0026-07")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("0026-07")))
  api_version.parse("2026- 7")
  |> should.equal(Error(api_version.ApiVersionErrorMalformed("2026- 7")))
}

pub fn compare_orders_by_year_then_quarter_test() {
  api_version.compare(v2025_10(), api_version.v2026_01)
  |> should.equal(order.Lt)
  api_version.compare(api_version.v2026_07, api_version.v2026_04)
  |> should.equal(order.Gt)
  api_version.compare(api_version.v2026_04, api_version.v2026_04)
  |> should.equal(order.Eq)
  api_version.at_least(api_version.v2026_04, api_version.v2026_01)
  |> should.be_true
  api_version.at_least(v2025_10(), api_version.v2026_01)
  |> should.be_false
}

pub fn release_candidate_is_not_released_before_day_one_test() {
  let assert Ok(october) = api_version.parse("2026-10")
  api_version.released_on(october, Day(2026, 9, 30)) |> should.be_false
  api_version.released_on(october, Day(2026, 10, 1)) |> should.be_true
}

pub fn accessible_until_day_sixteen_one_year_later_test() {
  api_version.accessible_on(v2025_10(), Day(2026, 10, 15))
  |> should.be_true
  api_version.accessible_on(v2025_10(), Day(2026, 10, 16))
  |> should.be_false
}

pub fn default_is_2026_10_test() {
  api_version.default() |> should.equal(api_version.v2026_10)
  api_version.parse("2026-10") |> should.equal(Ok(api_version.v2026_10))
}

pub fn retired_on_is_day_16_one_year_later_test() {
  api_version.retired_on(v2025_10())
  |> should.equal(Day(year: 2026, month: 10, day: 16))
}

pub fn days_until_retired_counts_calendar_days_test() {
  let today = Day(year: 2026, month: 9, day: 27)
  api_version.days_until_retired(v2025_10(), today)
  |> should.equal(19)
  api_version.days_until_retired(api_version.v2026_07, today)
  |> should.equal(292)
  api_version.days_until_retired(
    v2025_10(),
    Day(year: 2026, month: 10, day: 16),
  )
  |> should.equal(0)
}

pub fn days_until_retired_crosses_a_leap_day_test() {
  let assert Ok(version) = api_version.parse("2027-04")
  api_version.days_until_retired(version, Day(year: 2028, month: 2, day: 1))
  |> should.equal(75)
}

fn v2025_10() -> api_version.ApiVersion {
  let assert Ok(version) = api_version.parse("2025-10")
  version
}
