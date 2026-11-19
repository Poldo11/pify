import fixtures
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import pify/api_version
import pify/decimal
import pify/error
import pify/money
import pify/order
import scripted

fn get(fixture: String) -> order.Order {
  let #(result, _) =
    order.get(scripted.client(api_version.v2026_07), "gid://shopify/Order/1")
    |> scripted.run([scripted.ok(fixture)])
  let assert Ok(option.Some(found)) = result
  found
}

fn money(amount: String) -> money.Money {
  let assert Ok(value) = decimal.parse(amount)
  money.Money(amount: value, currency_code: "BRL")
}

pub fn paid_order_decodes_test() {
  let paid = get(fixtures.order_paid())
  paid.id |> should.equal("gid://shopify/Order/820982911946154508")
  paid.legacy_resource_id |> should.equal("820982911946154508")
  paid.name |> should.equal("#1001")
  paid.is_test |> should.be_false
  paid.financial_status |> should.equal(option.Some(order.FinancialStatusPaid))
  paid.fulfillment_status |> should.equal(order.FulfillmentStatusUnfulfilled)
  paid.cancel_reason |> should.equal(option.None)
  paid.current_totals
  |> should.equal(order.CurrentTotals(
    subtotal: money("89.8"),
    shipping: money("15.0"),
    tax: money("0.0"),
    discounts: money("10.0"),
    total: money("104.8"),
  ))
  paid.original_totals.subtotal |> should.equal(option.Some(money("89.8")))
  let assert option.Some(customer) = paid.customer
  customer.email |> should.equal(option.Some("maria@example.com"))
  customer.phone |> should.equal(option.Some("+5511999990000"))
  paid.has_more_line_items |> should.be_false
  paid.payment_gateway_names |> should.equal(["mercado_pago"])
  paid.tax_pricing |> should.equal(order.TaxesAdded)
}

/// A store with tax-inclusive prices says so in `taxesIncluded`, a scalar
/// that costs no points.
pub fn an_order_reads_whether_its_prices_include_tax_test() {
  order.get_query() |> string.contains(" taxesIncluded ") |> should.be_true
  get(fixtures.order_guest()).tax_pricing |> should.equal(order.TaxesIncluded)
}

pub fn line_items_carry_sku_variant_and_prices_test() {
  let assert [item] = get(fixtures.order_paid()).line_items
  item.sku |> should.equal(option.Some("9786500000001"))
  item.quantity |> should.equal(2)
  item.current_quantity |> should.equal(2)
  item.requires_shipping |> should.be_true
  item.variant
  |> should.equal(
    option.Some(order.LineItemVariant(
      id: "gid://shopify/ProductVariant/4400000001",
      sku: option.Some("9786500000001"),
      barcode: option.Some("9786500000001"),
    )),
  )
  item.original_unit_price |> should.equal(money("49.9"))
  item.discount_allocations
  |> should.equal([
    order.DiscountAllocation(allocated_amount: money("6.0")),
    order.DiscountAllocation(allocated_amount: money("4.0")),
  ])
  item.total_discount |> should.equal(money("0.0"))
  let assert Ok(hundredths) =
    decimal.to_scaled(item.original_unit_price.amount, 2)
  hundredths |> should.equal(4990)
}

pub fn line_items_read_their_discount_allocations_test() {
  order.get_query()
  |> string.contains(
    "discountAllocations { allocatedAmountSet { ...ShopMoney } }",
  )
  |> should.be_true
  let assert [custom, _] = get(fixtures.order_guest()).line_items
  custom.discount_allocations |> should.equal([])
}

pub fn guest_order_keeps_null_fields_absent_test() {
  let guest = get(fixtures.order_guest())
  guest.customer |> should.equal(option.None)
  guest.email |> should.equal(option.None)
  guest.billing_address |> should.equal(option.None)
  guest.financial_status
  |> should.equal(option.Some(order.FinancialStatusPending))
  guest.original_totals.subtotal |> should.equal(option.None)
  guest.original_totals.tax |> should.equal(option.None)
  guest.original_totals.discounts |> should.equal(option.None)
  let assert option.Some(shipping) = guest.shipping_address
  shipping.first_name |> should.equal(option.None)
  shipping.last_name |> should.equal(option.None)
  shipping.name |> should.equal(option.Some("Loja Exemplo"))
  guest.has_more_line_items |> should.be_true
  let assert [custom, deleted_sku] = guest.line_items
  custom.variant |> should.equal(option.None)
  custom.sku |> should.equal(option.None)
  custom.requires_shipping |> should.be_false
  deleted_sku.variant
  |> should.equal(
    option.Some(order.LineItemVariant(
      id: "gid://shopify/ProductVariant/4400000001",
      sku: option.None,
      barcode: option.None,
    )),
  )
}

pub fn redacted_customer_keeps_names_absent_test() {
  let redacted = get(fixtures.order_redacted_customer())
  redacted.customer
  |> should.equal(
    option.Some(order.Customer(
      id: "gid://shopify/Customer/1",
      first_name: option.None,
      last_name: option.None,
      display_name: "maria@example.com",
      email: option.None,
      phone: option.None,
    )),
  )
  redacted.financial_status |> should.equal(option.None)
}

pub fn cancelled_order_carries_its_flags_test() {
  let cancelled = get(fixtures.order_cancelled())
  cancelled.cancelled_at |> should.equal(option.Some("2026-09-21T09:00:00Z"))
  cancelled.cancel_reason
  |> should.equal(option.Some(order.CancelReasonCustomer))
  cancelled.closed_at |> should.equal(option.Some("2026-09-21T09:00:01Z"))
  cancelled.is_test |> should.be_true
  cancelled.financial_status
  |> should.equal(option.Some(order.FinancialStatusRefunded))
  cancelled.fulfillment_status |> should.equal(order.FulfillmentStatusRestocked)
  let assert [item] = cancelled.line_items
  item.quantity |> should.equal(2)
  item.current_quantity |> should.equal(0)
  cancelled.current_totals.total |> should.equal(money("0.0"))
  cancelled.original_totals.total |> should.equal(money("104.8"))
}

pub fn get_of_a_missing_order_is_none_test() {
  let #(result, _) =
    order.get(scripted.client(api_version.v2026_07), "gid://shopify/Order/9")
    |> scripted.run([scripted.ok("{\"data\":{\"order\":null}}")])
  result |> should.equal(Ok(option.None))
}

pub fn get_sends_the_id_and_line_item_size_test() {
  let assert #(_, [sent]) =
    order.get(scripted.client(api_version.v2026_07), "gid://shopify/Order/7")
    |> scripted.run([scripted.ok(fixtures.order_paid())])
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/Order/7")
  scripted.variable(sent, ["lineItems"], decode.int) |> should.equal(90)
}

pub fn list_reads_a_page_test() {
  let assert #(result, [sent]) =
    order.list(
      scripted.client(api_version.v2026_07),
      order.ListParams(
        first: 50,
        after: option.None,
        updated_at_min: option.None,
      ),
    )
    |> scripted.run([scripted.ok(fixtures.orders_page())])
  let assert Ok(page) = result
  page.orders
  |> list.map(fn(found) { found.name })
  |> should.equal(["#1001", "#1003"])
  page.orders
  |> list.map(fn(found) { found.payment_gateway_names })
  |> should.equal([["shopify_payments"], ["gift_card", "manual"]])
  page.has_next_page |> should.be_true
  page.next_cursor
  |> should.equal(option.Some("eyJsYXN0X2lkIjo4MjA5ODI5MTE5NDYxNTQ1MTB9"))
  scripted.variable(sent, ["first"], decode.int)
  |> should.equal(order.max_list_first())
  scripted.variable(sent, ["query"], decode.optional(decode.string))
  |> should.equal(option.None)
  scripted.query(sent)
  |> string.contains("sortKey: UPDATED_AT")
  |> should.be_true
}

pub fn list_filters_by_updated_at_with_escaping_test() {
  order.search_query(order.ListParams(
    first: 5,
    after: option.Some("cursor"),
    updated_at_min: option.Some("2026-09-01T00:00:00Z"),
  ))
  |> should.equal(option.Some("updated_at:>=\"2026-09-01T00:00:00Z\""))
  order.search_query(order.ListParams(
    first: 5,
    after: option.None,
    updated_at_min: option.Some("x\" OR status:any"),
  ))
  |> should.equal(option.Some("updated_at:>=\"x\\\" OR status:any\""))
}

pub fn list_and_get_share_one_selection_test() {
  let fragment = fn(query) {
    let assert Ok(#(_, fields)) =
      string.split_once(query, "fragment OrderFields")
    fields
  }
  fragment(order.list_query()) |> should.equal(fragment(order.get_query()))
  order.get_query() |> string.contains("presentmentMoney") |> should.be_false
  order.get_query() |> string.contains("shopMoney") |> should.be_true
}

pub fn queries_stay_under_the_cost_limit_test() {
  order.order_cost(90) |> should.equal(863)
  { order.order_cost(90) <= 1000 } |> should.be_true
  order.get_query()
  |> string.contains("refunds(first: 4) { refundLineItems(first: 15)")
  |> should.be_true
  order.get_variables("gid://shopify/Order/1")
  |> json.to_string
  |> string.contains("\"lineItems\":90")
  |> should.be_true
  { order.order_cost(90) + 4 * { 3 + 2 * 15 } <= 1000 } |> should.be_true
  { order.max_list_first() * order.order_cost(10) + 3 <= 1000 }
  |> should.be_true
  { order.max_list_first() >= 5 } |> should.be_true
}

pub fn shop_money_is_read_over_presentment_test() {
  json.parse(
    "{\"shopMoney\":{\"amount\":\"49.90\",\"currencyCode\":\"BRL\"},"
      <> "\"presentmentMoney\":{\"amount\":\"9.50\",\"currencyCode\":\"USD\"}}",
    order.shop_money_decoder(),
  )
  |> should.equal(Ok(money("49.90")))
}

pub fn unknown_statuses_keep_their_value_test() {
  order.parse_financial_status("SOMETHING_NEW")
  |> should.equal(order.FinancialStatusOther("SOMETHING_NEW"))
  order.parse_fulfillment_status("SOMETHING_NEW")
  |> should.equal(order.FulfillmentStatusOther("SOMETHING_NEW"))
  order.parse_fulfillment_status("FULFILLMENT_NOT_REQUIRED")
  |> should.equal(order.FulfillmentStatusNotRequired)
  order.fulfillment_status_to_string(order.FulfillmentStatusNotRequired)
  |> should.equal("FULFILLMENT_NOT_REQUIRED")
  order.parse_cancel_reason("OTHER") |> should.equal(order.CancelReasonOther)
  order.parse_cancel_reason("NEW_REASON")
  |> should.equal(order.CancelReasonUnknown("NEW_REASON"))
  order.financial_status_to_string(order.FinancialStatusPartiallyRefunded)
  |> should.equal("PARTIALLY_REFUNDED")
}

fn with_refunds(refunds: String) -> String {
  string.replace(
    fixtures.order_paid(),
    "\"order\":{",
    "\"order\":{\"refunds\":" <> refunds <> ",",
  )
}

fn refund(lines: String, has_next_page: Bool) -> String {
  "{\"refundLineItems\":{\"nodes\":["
  <> lines
  <> "],\"pageInfo\":{\"hasNextPage\":"
  <> case has_next_page {
    True -> "true"
    False -> "false"
  }
  <> "}}}"
}

fn refund_line(line_item_id: String, quantity: Int, restock: String) -> String {
  "{\"lineItem\":{\"id\":\""
  <> line_item_id
  <> "\"},\"quantity\":"
  <> int.to_string(quantity)
  <> ",\"restockType\":\""
  <> restock
  <> "\"}"
}

pub fn get_reads_refund_lines_and_their_restock_test() {
  let lines =
    refund_line("gid://shopify/LineItem/1", 1, "NO_RESTOCK")
    <> ","
    <> refund_line("gid://shopify/LineItem/2", 2, "RETURN")
  get(with_refunds("[" <> refund(lines, False) <> "]")).refunds
  |> should.equal(
    order.RefundLinesRead([
      order.RefundLine(
        "gid://shopify/LineItem/1",
        1,
        order.RestockTypeNoRestock,
      ),
      order.RefundLine("gid://shopify/LineItem/2", 2, order.RestockTypeReturn),
    ]),
  )
  order.get_query() |> string.contains("restockType") |> should.be_true
  order.list_query() |> string.contains("refunds") |> should.be_false
}

pub fn a_full_page_of_refunds_is_truncated_test() {
  let one = refund(refund_line("gid://shopify/LineItem/1", 1, "CANCEL"), False)
  get(with_refunds("[" <> string.join(list.repeat(one, 4), ",") <> "]")).refunds
  |> should.equal(
    order.RefundLinesTruncated(list.repeat(
      order.RefundLine("gid://shopify/LineItem/1", 1, order.RestockTypeCancel),
      4,
    )),
  )
  get(with_refunds("[" <> refund("", True) <> "]")).refunds
  |> should.equal(order.RefundLinesTruncated([]))
}

pub fn an_order_read_without_refunds_leaves_them_unread_test() {
  get(fixtures.order_paid()).refunds |> should.equal(order.RefundLinesUnread)
  order.parse_restock_type("SOMETHING_NEW")
  |> should.equal(order.RestockTypeOther("SOMETHING_NEW"))
}

pub fn recent_shipping_titles_are_each_named_once_test() {
  let answer =
    "{\"data\":{\"orders\":{\"nodes\":["
    <> "{\"shippingLines\":{\"nodes\":[{\"title\":\"Frete reduzido\"}]}},"
    <> "{\"shippingLines\":{\"nodes\":[]}},"
    <> "{\"shippingLines\":{\"nodes\":[{\"title\":\"PAC\"},"
    <> "{\"title\":\"Frete reduzido\"}]}}]}}}"
  let assert #(result, [sent]) =
    order.recent_shipping_titles(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(answer)])
  result |> should.equal(Ok(["Frete reduzido", "PAC"]))
  scripted.variable(sent, ["first"], decode.int) |> should.equal(100)
  scripted.query(sent) |> string.contains("customer") |> should.be_false
}

pub fn recent_gateway_names_are_each_named_once_test() {
  let answer =
    "{\"data\":{\"orders\":{\"nodes\":["
    <> "{\"paymentGatewayNames\":[\"manual\"]},"
    <> "{\"paymentGatewayNames\":[\"gift_card\",\"shopify_payments\"]},"
    <> "{\"paymentGatewayNames\":[]},"
    <> "{\"paymentGatewayNames\":[\"manual\"]}]}}}"
  let assert #(result, [sent]) =
    order.recent_gateway_names(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(answer)])
  result |> should.equal(Ok(["manual", "gift_card", "shopify_payments"]))
  scripted.variable(sent, ["first"], decode.int) |> should.equal(100)
  scripted.query(sent) |> string.contains("customer") |> should.be_false
}

fn input() -> order.MailingAddressInput {
  order.MailingAddressInput(
    first_name: option.Some("Maria"),
    last_name: option.Some("Silva"),
    address1: "Rua das Flores,\u{2060}123",
    address2: option.Some("Apto 12,\u{2060}Centro"),
    city: option.Some("São Paulo"),
    province_code: option.Some("SP"),
    zip: "01310-100",
    country_code: "BR",
    phone: option.Some("+5511900000000"),
  )
}

pub fn shipping_state_reads_the_status_and_the_address_test() {
  let assert #(Ok(option.Some(state)), [sent]) =
    order.shipping_state(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Order/5500000001",
    )
    |> scripted.run([scripted.ok(fixtures.order_shipping_state())])
  state.id |> should.equal("gid://shopify/Order/5500000001")
  state.fulfillment_status |> should.equal(order.FulfillmentStatusUnfulfilled)
  state.cancelled_at |> should.equal(option.None)
  let assert option.Some(address) = state.shipping_address
  order.holds_address(address, input()) |> should.be_true
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/Order/5500000001")
}

pub fn shipping_state_answers_none_for_an_unknown_order_test() {
  let #(found, _) =
    order.shipping_state(scripted.client(api_version.v2026_07), "order")
    |> scripted.run([scripted.ok("{\"data\":{\"order\":null}}")])
  found |> should.equal(Ok(option.None))
}

pub fn an_address_with_another_field_is_not_held_test() {
  let assert #(Ok(option.Some(state)), _) =
    order.shipping_state(scripted.client(api_version.v2026_07), "order")
    |> scripted.run([scripted.ok(fixtures.order_shipping_state())])
  let assert option.Some(address) = state.shipping_address
  order.holds_address(
    address,
    order.MailingAddressInput(..input(), address2: option.None),
  )
  |> should.be_false
}

pub fn update_shipping_address_sends_every_field_test() {
  let assert #(Ok(id), [sent]) =
    order.update_shipping_address(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Order/5500000001",
      order.MailingAddressInput(..input(), address2: option.None),
    )
    |> scripted.run([scripted.ok(fixtures.order_update())])
  id |> should.equal("gid://shopify/Order/5500000001")
  scripted.variable(sent, ["input", "id"], decode.string)
  |> should.equal("gid://shopify/Order/5500000001")
  scripted.variable(
    sent,
    ["input", "shippingAddress", "address1"],
    decode.string,
  )
  |> should.equal("Rua das Flores,\u{2060}123")
  scripted.variable(
    sent,
    ["input", "shippingAddress", "address2"],
    decode.optional(decode.string),
  )
  |> should.equal(option.None)
  scripted.variable(
    sent,
    ["input", "shippingAddress", "countryCode"],
    decode.string,
  )
  |> should.equal("BR")
  scripted.variable(
    sent,
    ["input", "shippingAddress", "provinceCode"],
    decode.string,
  )
  |> should.equal("SP")
  scripted.query(sent)
  |> string.contains("orderUpdate(input: $input)")
  |> should.be_true
}

pub fn update_shipping_address_fails_on_user_errors_test() {
  let assert #(Error(error.ShopifyErrorUserErrors([refused])), _) =
    order.update_shipping_address(
      scripted.client(api_version.v2026_07),
      "order",
      input(),
    )
    |> scripted.run([scripted.ok(fixtures.order_update_user_errors())])
  refused.field |> should.equal(["shippingAddress", "zip"])
}

fn cancel_input() -> order.CancelInput {
  order.CancelInput(
    order_id: "gid://shopify/Order/5500000001",
    reason: order.CancelReasonStaff,
    restock: order.CancelRestockNone,
    refund: order.CancelRefundOriginalPayment,
    notice: order.CancelNoticeNone,
    staff_note: option.Some(string.repeat("a", 300)),
  )
}

pub fn cancel_sends_the_reason_the_refund_and_no_restock_test() {
  let assert #(Ok(option.Some(job)), [sent]) =
    order.cancel(scripted.client(api_version.v2026_07), cancel_input())
    |> scripted.run([scripted.ok(fixtures.order_cancel())])
  job.done |> should.be_false
  scripted.variable(sent, ["orderId"], decode.string)
  |> should.equal("gid://shopify/Order/5500000001")
  scripted.variable(sent, ["reason"], decode.string)
  |> should.equal("STAFF")
  scripted.variable(sent, ["restock"], decode.bool) |> should.be_false
  scripted.variable(sent, ["notifyCustomer"], decode.bool) |> should.be_false
  scripted.variable(
    sent,
    ["refundMethod", "originalPaymentMethodsRefund"],
    decode.bool,
  )
  |> should.be_true
  scripted.variable(sent, ["staffNote"], decode.string)
  |> string.length
  |> should.equal(order.staff_note_max)
  scripted.query(sent)
  |> string.contains("userErrors: orderCancelUserErrors")
  |> should.be_true
}

pub fn cancel_without_a_refund_sends_no_refund_method_test() {
  let assert #(Ok(_), [sent]) =
    order.cancel(
      scripted.client(api_version.v2026_07),
      order.CancelInput(
        ..cancel_input(),
        refund: order.CancelRefundNone,
        staff_note: option.None,
      ),
    )
    |> scripted.run([scripted.ok(fixtures.order_cancel())])
  scripted.variable(sent, ["refundMethod"], decode.optional(decode.bool))
  |> should.equal(option.None)
  scripted.variable(sent, ["staffNote"], decode.optional(decode.string))
  |> should.equal(option.None)
}

pub fn cancel_fails_on_order_cancel_user_errors_test() {
  let assert #(Error(error.ShopifyErrorUserErrors([refused])), _) =
    order.cancel(scripted.client(api_version.v2026_07), cancel_input())
    |> scripted.run([scripted.ok(fixtures.order_cancel_user_errors())])
  refused.code |> should.equal(option.Some("INVALID"))
}
