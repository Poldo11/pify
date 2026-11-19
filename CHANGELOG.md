# Changelog

## 2.0.0

A rewrite. No module of 1.x keeps its name or its API.

### Breaking

- Every module lives under `pify/`. The top-level `admin/*` and
  `storefront/*` modules are gone.
- `CreateAdminApiClient`, `AdminHandler`, `CreateStorefrontApiClient` and
  `ShopifyHandler` are replaced by `pify.Client` and
  `pify/storefront.StorefrontClient`. A call is a function of its module
  that answers a midas `Effect`; there is no `fetch` field to call.
- The API version is an `api_version.ApiVersion`, not a string, and
  shapes each request.
- Errors are one `pify/error.ShopifyError` type, in place of `snag`
  messages.
- Money is an opaque `pify/decimal.Decimal`, in place of strings.
- midas 2.x, in place of 1.x. `snag` and `gleam_fetch` are no longer
  dependencies.
- The Storefront client calls `/api/<version>/graphql.json` with the
  Storefront token headers. 1.x called the Admin endpoint with the Admin
  header.
- The prêt-à-porter fragments, the `reshape_*` helpers and the
  `cookie_name` constant are gone. Product reads take the metafields to
  read as an argument, in place of a fixed list.

### Added

- Admin API: orders (list, get, cancel, shipping address), products
  (`productSet`, update, status, media), variants (find by SKU, bulk
  create and update, inventory policy), inventory (levels, activate,
  compare-and-set writes), locations, fulfillments, publications,
  webhook subscriptions, the shop probe, access scopes and the
  client-credentials grant.
- Storefront API: products by handle, a page of the catalog,
  recommendations; collections by handle, a page of them, their products;
  the cart (get, create, add, update and remove lines, note), with the
  warnings of each write. `storefront.new` checks the shop domain, and
  `storefront.parse_buyer_ip` checks the buyer's IP.
- `pify/money`: one `Money` type for the Admin and the Storefront API.
- Webhooks: header parsing, HMAC verification over the raw body, a dedupe
  key, a topic and body check, and the order reference.
- `api_version`: the release, retirement and support window of each
  version. `default()` is 2026-10.
