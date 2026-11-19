import fixtures
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleeunit
import gleeunit/should
import pify
import pify/api_version
import pify/auth
import pify/error
import pify/execute
import pify/order
import pify/request
import pify/shop
import scripted

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn new_client_defaults_test() {
  let client =
    pify.new(
      access_token: "shpat_abc",
      shop_domain: "loja-exemplo.myshopify.com",
      version: api_version.v2026_07,
    )
  client.timeout_ms |> should.equal(pify.default_timeout_ms)
  client.version |> should.equal(api_version.v2026_07)
}

pub fn endpoint_url_is_the_admin_path_test() {
  pify.new(
    access_token: "shpat_abc",
    shop_domain: "loja-exemplo.myshopify.com",
    version: api_version.v2026_04,
  )
  |> pify.endpoint_url
  |> should.equal(
    "https://loja-exemplo.myshopify.com/admin/api/2026-04/graphql.json",
  )
}

pub fn parse_shop_domain_normalizes_test() {
  pify.parse_shop_domain("  HTTPS://Loja-Exemplo.myshopify.com/ ")
  |> should.equal(Ok("loja-exemplo.myshopify.com"))
  pify.parse_shop_domain("http://loja1.myshopify.com//")
  |> should.equal(Ok("loja1.myshopify.com"))
}

pub fn parse_shop_domain_rejects_other_hosts_test() {
  pify.parse_shop_domain("loja.com.br")
  |> should.equal(Error(pify.ShopDomainNotMyshopify(domain: "loja.com.br")))
  pify.parse_shop_domain("loja.myshopify.com/admin")
  |> should.equal(
    Error(pify.ShopDomainNotMyshopify(domain: "loja.myshopify.com/admin")),
  )
  pify.parse_shop_domain("evil.com?x=.myshopify.com")
  |> should.equal(Error(pify.ShopDomainInvalidHandle(handle: "evil.com?x=")))
}

pub fn parse_shop_domain_rejects_bad_handles_test() {
  pify.parse_shop_domain(".myshopify.com")
  |> should.equal(Error(pify.ShopDomainInvalidHandle(handle: "")))
  pify.parse_shop_domain("-loja.myshopify.com")
  |> should.equal(Error(pify.ShopDomainInvalidHandle(handle: "-loja")))
  pify.parse_shop_domain("a.b.myshopify.com")
  |> should.equal(Error(pify.ShopDomainInvalidHandle(handle: "a.b")))
  pify.parse_shop_domain("loja_1.myshopify.com")
  |> should.equal(Error(pify.ShopDomainInvalidHandle(handle: "loja_1")))
}

pub fn client_credentials_request_shape_test() {
  let assert #(_, [sent]) =
    auth.client_credentials(
      shop_domain: "loja-exemplo.myshopify.com",
      client_id: "client-id",
      client_secret: "client-secret",
    )
    |> scripted.run([scripted.ok(fixtures.access_token())])
  sent.path |> should.equal("/admin/oauth/access_token")
  sent.host |> should.equal("loja-exemplo.myshopify.com")
  let field = fn(name) {
    let assert Ok(value) =
      json.parse(scripted.body(sent), decode.at([name], decode.string))
    value
  }
  field("client_id") |> should.equal("client-id")
  field("client_secret") |> should.equal("client-secret")
  field("grant_type") |> should.equal("client_credentials")
}

pub fn client_credentials_decodes_the_token_test() {
  let #(token, _) =
    auth.client_credentials(
      shop_domain: "loja-exemplo.myshopify.com",
      client_id: "client-id",
      client_secret: "client-secret",
    )
    |> scripted.run([scripted.ok(fixtures.access_token())])
  token
  |> should.equal(
    Ok(auth.AccessToken(
      token: "shpat_redacted",
      scope: [
        "read_orders",
        "write_inventory",
        "read_locations",
        "write_products",
      ],
      expires_in_seconds: 86_399,
    )),
  )
}

pub fn a_null_scope_grants_no_scope_test() {
  let assert #(Ok(token), _) =
    auth.client_credentials(
      shop_domain: "loja-exemplo.myshopify.com",
      client_id: "client-id",
      client_secret: "client-secret",
    )
    |> scripted.run([
      scripted.ok(
        "{\"access_token\":\"shpat_redacted\",\"scope\":null,\"expires_in\":86399}",
      ),
    ])
  token.scope |> should.equal([])
}

pub fn refused_credentials_are_authentication_errors_test() {
  let refused = fn(status) {
    let #(result, _requests) =
      auth.client_credentials(
        shop_domain: "loja-exemplo.myshopify.com",
        client_id: "client-id",
        client_secret: "wrong",
      )
      |> scripted.run([
        scripted.Reply(
          status:,
          headers: [],
          body: "{\"error\":\"invalid_client\"}",
        ),
      ])
    result
  }
  refused(400) |> should.equal(Error(error.ShopifyErrorAuthentication))
  refused(401) |> should.equal(Error(error.ShopifyErrorAuthentication))
  refused(423) |> should.equal(Error(error.ShopifyErrorShopUnavailable(423)))
}

pub fn to_http_request_names_the_url_without_its_query_test() {
  request.ShopifyRequest(
    url: "shop.example/admin/api.json?access_token=secret",
    headers: [],
    body: "{}",
  )
  |> request.to_http_request
  |> should.equal(
    Error(request.ShopifyRequestUrlInvalid(text: "shop.example/admin/api.json")),
  )
}

pub fn probe_keeps_the_served_version_test() {
  let #(result, _) =
    shop.probe(scripted.client(api_version.v2026_07))
    |> scripted.run([
      scripted.Reply(
        status: 200,
        headers: [#("x-shopify-api-version", "2026-07")],
        body: fixtures.shop(),
      ),
    ])
  result
  |> should.equal(
    Ok(execute.Served(
      value: shop.Shop(
        name: "Loja Exemplo",
        myshopify_domain: "loja-exemplo.myshopify.com",
        currency_code: "BRL",
        plan_name: option.Some("Basic"),
        tax_pricing: order.TaxesIncluded,
      ),
      served_version: option.Some("2026-07"),
    )),
  )
}

pub fn access_scopes_lists_each_handle_test() {
  let assert #(result, [sent]) =
    shop.access_scopes(scripted.client(api_version.v2026_07))
    |> scripted.run([scripted.ok(fixtures.access_scopes())])
  result
  |> should.equal(
    Ok(["read_orders", "write_products", "read_products", "write_inventory"]),
  )
  scripted.query(sent)
  |> should.equal(shop.access_scopes_query)
}
