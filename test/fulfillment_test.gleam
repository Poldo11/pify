import fixtures
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/string
import gleeunit/should
import pify/api_version
import pify/error
import pify/fulfillment
import scripted

pub fn for_order_reads_fulfillment_orders_and_fulfillments_test() {
  let assert #(Ok(option.Some(found)), [sent]) =
    fulfillment.for_order(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Order/5500000001",
    )
    |> scripted.run([scripted.ok(fixtures.order_fulfillments())])
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/Order/5500000001")
  found.read |> should.equal(fulfillment.ReadComplete)
  let assert [open, held] = found.fulfillment_orders
  open
  |> should.equal(
    fulfillment.FulfillmentOrder(
      id: "gid://shopify/FulfillmentOrder/6100000001",
      status: fulfillment.FulfillmentOrderStatusOpen,
      location_id: option.Some("gid://shopify/Location/8800000001"),
      holds: [],
      supported_actions: [
        fulfillment.FulfillmentOrderActionCreateFulfillment,
        fulfillment.FulfillmentOrderActionReportProgress,
        fulfillment.FulfillmentOrderActionHold,
      ],
      line_items: [
        fulfillment.FulfillmentOrderLineItem(
          id: "gid://shopify/FulfillmentOrderLineItem/6200000001",
          line_item_id: "gid://shopify/LineItem/3300000001",
          sku: option.Some("9786500000001"),
          remaining_quantity: 2,
        ),
        fulfillment.FulfillmentOrderLineItem(
          id: "gid://shopify/FulfillmentOrderLineItem/6200000002",
          line_item_id: "gid://shopify/LineItem/3300000002",
          sku: option.None,
          remaining_quantity: 0,
        ),
      ],
    ),
  )
  held.location_id |> should.equal(option.None)
  held.status |> should.equal(fulfillment.FulfillmentOrderStatusOnHold)
  held.holds
  |> should.equal([
    fulfillment.FulfillmentHold(
      id: "gid://shopify/FulfillmentHold/6300000001",
      reason: fulfillment.FulfillmentHoldReasonInventoryOutOfStock,
    ),
  ])
  held.supported_actions
  |> should.equal([
    fulfillment.FulfillmentOrderActionReleaseHold,
    fulfillment.FulfillmentOrderActionOther("SOMETHING_NEW"),
  ])
  fulfillment.accepts_fulfillment(held.status) |> should.be_false
  let assert [shipped, cancelled] = found.fulfillments
  shipped
  |> should.equal(
    fulfillment.Fulfillment(
      id: "gid://shopify/Fulfillment/7100000001",
      status: fulfillment.FulfillmentStatusSuccess,
      display_status: option.Some(fulfillment.FulfillmentDisplayStatusDelivered),
      tracking_numbers: ["AA000000005BR"],
      line_items: [
        fulfillment.FulfillmentLineItem(
          line_item_id: "gid://shopify/LineItem/3300000002",
          sku: option.Some("9786500000002"),
          quantity: 1,
        ),
      ],
    ),
  )
  fulfillment.ships_goods(cancelled.status) |> should.be_false
  cancelled.display_status |> should.equal(option.None)
}

pub fn for_order_marks_a_read_with_more_lines_truncated_test() {
  let body =
    string.replace(
      fixtures.order_fulfillments(),
      "\"remainingQuantity\":0,\"lineItem\":{\"id\":\"gid://shopify/LineItem/3300000002\"}}],\"pageInfo\":{\"hasNextPage\":false}",
      "\"remainingQuantity\":0,\"lineItem\":{\"id\":\"gid://shopify/LineItem/3300000002\"}}],\"pageInfo\":{\"hasNextPage\":true}",
    )
  let assert #(Ok(option.Some(found)), _) =
    fulfillment.for_order(scripted.client(api_version.v2026_07), "order")
    |> scripted.run([scripted.ok(body)])
  found.read |> should.equal(fulfillment.ReadTruncated)
}

pub fn for_order_answers_none_for_an_unknown_order_test() {
  let #(found, _) =
    fulfillment.for_order(scripted.client(api_version.v2026_07), "order")
    |> scripted.run([scripted.ok("{\"data\":{\"order\":null}}")])
  found |> should.equal(Ok(option.None))
}

pub fn create_sends_lines_tracking_and_notice_test() {
  let assert #(Ok(written), [sent]) =
    fulfillment.create(
      scripted.client(api_version.v2026_07),
      [
        fulfillment.FulfillmentOrderLines(
          fulfillment_order_id: "gid://shopify/FulfillmentOrder/6100000001",
          line_items: [
            fulfillment.LineQuantity(
              fulfillment_order_line_item_id: "gid://shopify/FulfillmentOrderLineItem/6200000001",
              quantity: 2,
            ),
          ],
        ),
      ],
      option.Some(fulfillment.Tracking(
        number: "AA000000005BR",
        company: option.Some("Correios"),
        url: option.None,
      )),
      fulfillment.NoticeNotifyCustomer,
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_create())])
  written.id |> should.equal("gid://shopify/Fulfillment/7100000003")
  scripted.variable(sent, ["fulfillment", "notifyCustomer"], decode.bool)
  |> should.be_true
  scripted.variable(
    sent,
    ["fulfillment", "trackingInfo", "company"],
    decode.string,
  )
  |> should.equal("Correios")
  scripted.has_variable(sent, ["fulfillment", "trackingInfo", "url"])
  |> should.be_false
  scripted.variable(
    sent,
    ["fulfillment", "lineItemsByFulfillmentOrder"],
    decode.list({
      use id <- decode.field("fulfillmentOrderId", decode.string)
      use quantities <- decode.field(
        "fulfillmentOrderLineItems",
        decode.list(decode.field("quantity", decode.int, decode.success)),
      )
      decode.success(#(id, quantities))
    }),
  )
  |> should.equal([#("gid://shopify/FulfillmentOrder/6100000001", [2])])
}

pub fn create_without_tracking_sends_no_tracking_info_test() {
  let assert #(Ok(_), [sent]) =
    fulfillment.create(
      scripted.client(api_version.v2026_07),
      [],
      option.None,
      fulfillment.NoticeSilent,
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_create())])
  scripted.has_variable(sent, ["fulfillment", "trackingInfo"])
  |> should.be_false
  scripted.variable(sent, ["fulfillment", "notifyCustomer"], decode.bool)
  |> should.be_false
}

pub fn create_fails_on_user_errors_test() {
  let assert #(Error(error.ShopifyErrorUserErrors([refused])), _) =
    fulfillment.create(
      scripted.client(api_version.v2026_07),
      [],
      option.None,
      fulfillment.NoticeNotifyCustomer,
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_create_user_errors())])
  refused.field |> should.equal(["fulfillment"])
}

pub fn update_tracking_sends_the_fulfillment_and_tracking_test() {
  let assert #(Ok(written), [sent]) =
    fulfillment.update_tracking(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Fulfillment/7100000001",
      fulfillment.Tracking(
        number: "AA000000005BR",
        company: option.Some("Correios"),
        url: option.Some(
          "https://rastreamento.correios.com.br/app/index.php?objetos=AA000000005BR",
        ),
      ),
      fulfillment.NoticeNotifyCustomer,
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_tracking_update())])
  written.status |> should.equal(fulfillment.FulfillmentStatusSuccess)
  scripted.variable(sent, ["fulfillmentId"], decode.string)
  |> should.equal("gid://shopify/Fulfillment/7100000001")
  scripted.variable(sent, ["trackingInfoInput", "number"], decode.string)
  |> should.equal("AA000000005BR")
  scripted.variable(sent, ["notifyCustomer"], decode.bool)
  |> should.be_true
}

pub fn cancel_sends_the_fulfillment_id_test() {
  let assert #(Ok(written), [sent]) =
    fulfillment.cancel(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Fulfillment/7100000001",
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_cancel())])
  written
  |> should.equal(fulfillment.Written(
    id: "gid://shopify/Fulfillment/7100000001",
    status: fulfillment.FulfillmentStatusCancelled,
  ))
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/Fulfillment/7100000001")
}

pub fn cancel_fails_on_user_errors_test() {
  let assert #(Error(error.ShopifyErrorUserErrors([refused])), _) =
    fulfillment.cancel(scripted.client(api_version.v2026_07), "fulfillment")
    |> scripted.run([scripted.ok(fixtures.fulfillment_cancel_user_errors())])
  refused.field |> should.equal(["id"])
}

pub fn create_event_sends_the_status_and_time_test() {
  let assert #(Ok(event_id), [sent]) =
    fulfillment.create_event(
      scripted.client(api_version.v2026_07),
      "gid://shopify/Fulfillment/7100000001",
      fulfillment.FulfillmentEventStatusDelivered,
      option.Some("2026-10-02T14:30:00Z"),
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_event_create())])
  event_id |> should.equal("gid://shopify/FulfillmentEvent/7300000001")
  scripted.variable(sent, ["fulfillmentEvent", "fulfillmentId"], decode.string)
  |> should.equal("gid://shopify/Fulfillment/7100000001")
  scripted.variable(sent, ["fulfillmentEvent", "status"], decode.string)
  |> should.equal("DELIVERED")
  scripted.variable(sent, ["fulfillmentEvent", "happenedAt"], decode.string)
  |> should.equal("2026-10-02T14:30:00Z")
}

pub fn create_event_leaves_out_an_unknown_time_test() {
  fulfillment.create_event_variables(
    "fulfillment",
    fulfillment.FulfillmentEventStatusInTransit,
    option.None,
  )
  |> json.to_string
  |> should.equal(
    "{\"fulfillmentEvent\":{\"fulfillmentId\":\"fulfillment\",\"status\":\"IN_TRANSIT\"}}",
  )
}

pub fn create_event_fails_on_user_errors_test() {
  let assert #(Error(error.ShopifyErrorUserErrors([refused])), _) =
    fulfillment.create_event(
      scripted.client(api_version.v2026_07),
      "fulfillment",
      fulfillment.FulfillmentEventStatusDelivered,
      option.None,
    )
    |> scripted.run([
      scripted.ok(fixtures.fulfillment_event_create_user_errors()),
    ])
  refused.field |> should.equal(["fulfillmentEvent", "fulfillmentId"])
}

pub fn statuses_keep_an_unknown_value_test() {
  fulfillment.parse_fulfillment_order_status("IN_PROGRESS")
  |> should.equal(fulfillment.FulfillmentOrderStatusInProgress)
  fulfillment.parse_fulfillment_order_status("SOMETHING_NEW")
  |> should.equal(fulfillment.FulfillmentOrderStatusOther("SOMETHING_NEW"))
  fulfillment.parse_fulfillment_status("FAILURE")
  |> should.equal(fulfillment.FulfillmentStatusFailure)
  fulfillment.parse_fulfillment_status("SOMETHING_NEW")
  |> should.equal(fulfillment.FulfillmentStatusOther("SOMETHING_NEW"))
  fulfillment.parse_fulfillment_display_status("MARKED_AS_FULFILLED")
  |> should.equal(fulfillment.FulfillmentDisplayStatusMarkedAsFulfilled)
  fulfillment.parse_fulfillment_display_status("SOMETHING_NEW")
  |> should.equal(fulfillment.FulfillmentDisplayStatusOther("SOMETHING_NEW"))
}

pub fn release_hold_names_the_holds_it_releases_test() {
  let assert #(Ok(written), [sent]) =
    fulfillment.release_hold(
      scripted.client(api_version.v2026_07),
      "gid://shopify/FulfillmentOrder/6100000002",
      ["gid://shopify/FulfillmentHold/6300000001"],
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_order_release_hold())])
  written.status |> should.equal(fulfillment.FulfillmentOrderStatusOpen)
  fulfillment.supports(
    written.supported_actions,
    fulfillment.FulfillmentOrderActionReportProgress,
  )
  |> should.be_true
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/FulfillmentOrder/6100000002")
  scripted.variable(sent, ["holdIds"], decode.list(decode.string))
  |> should.equal(["gid://shopify/FulfillmentHold/6300000001"])
}

pub fn release_hold_with_no_hold_read_sends_no_hold_ids_test() {
  let assert #(Ok(_), [sent]) =
    fulfillment.release_hold(
      scripted.client(api_version.v2026_07),
      "gid://shopify/FulfillmentOrder/6100000002",
      [],
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_order_release_hold())])
  scripted.has_variable(sent, ["holdIds"]) |> should.be_false
}

pub fn release_hold_user_errors_fail_the_call_test() {
  let assert #(Error(error.ShopifyErrorUserErrors(_)), _) =
    fulfillment.release_hold(
      scripted.client(api_version.v2026_07),
      "gid://shopify/FulfillmentOrder/6100000002",
      [],
    )
    |> scripted.run([
      scripted.ok(fixtures.fulfillment_order_release_hold_user_errors()),
    ])
}

pub fn report_progress_moves_the_order_in_progress_test() {
  let assert #(Ok(written), [sent]) =
    fulfillment.report_progress(
      scripted.client(api_version.v2026_07),
      "gid://shopify/FulfillmentOrder/6100000001",
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_order_report_progress())])
  written.status |> should.equal(fulfillment.FulfillmentOrderStatusInProgress)
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/FulfillmentOrder/6100000001")
}

pub fn open_marks_the_order_open_test() {
  let assert #(Ok(written), [sent]) =
    fulfillment.open(
      scripted.client(api_version.v2026_07),
      "gid://shopify/FulfillmentOrder/6100000001",
    )
    |> scripted.run([scripted.ok(fixtures.fulfillment_order_open())])
  written.status |> should.equal(fulfillment.FulfillmentOrderStatusOpen)
  scripted.variable(sent, ["id"], decode.string)
  |> should.equal("gid://shopify/FulfillmentOrder/6100000001")
}
