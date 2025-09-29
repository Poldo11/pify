import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response, Response}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import midas/task as t
import snag

// Admin Functions
pub type CreateAdminApiClient {
  CreateAdminApiClient(
    ///
    ///  The domain of the store.
    ///
    store_domain: String,
    ///
    ///  The requested Admin API version.
    ///
    api_version: String,
    ///
    /// Admin API private access token.
    ///
    access_token: String,
    /// The number of HTTP request retries if the request was abandoned or the server responded
    /// with a Too Many Requests (429) or Service Unavailable (503) response.
    /// Default value is 0. Maximum value is 3.
    ///
    retries: Option(Int),
    // TODO: Work in progress [wip]
    // A replacement fetch function that will be used in all client network requests.
    // By default, the client uses window.fetch().
    // custom_fetch_api: Option(CustomFetchApi),
    // A logger function that accepts log content objects.
    // This logger will be called in certain conditions with contextual information.
    // logger: Option(Logger),
  )
}

// Admin
//
pub type AdminApiClientConfig {
  AdminApiClientConfig(
    store_domain: String,
    api_version: String,
    access_token: String,
    headers: #(String, List(#(String, String))),
    api_url: String,
    retries: Option(Int),
  )
}

pub type AdminHandler(msg) {
  AdminHandler(
    /// Configuration for the client
    config: AdminApiClientConfig,
    // get_headers: fn(Option(#(String, List(#(String, String))))) ->
    // #(String, List(#(String, String))),
    /// Returns Storefront API specific headers needed to interact with the API.
    /// If additional headers are provided, the custom headers will be included in the returned headers object.
    /// Fetches data from Storefront API using the provided GQL operation string
    /// and ApiClientRequestOptions object and returns the network response.
    fetch: fn(String, Option(Json), Decoder(AdminClientResponse(msg))) ->
      t.Effect(AdminClientResponse(msg), AdminResponseErrors),
  )
}

pub type AdminClientResponse(msg) {
  AdminClientResponse(data: Option(msg))
}

pub type AdminResponseErrors {
  AdminResponseErrors(
    network_status_code: Option(Int),
    message: Option(String),
    graphql_errors: Option(List(String)),
    response: Option(response.Response(String)),
  )
}

pub fn admin_response_errors_decoder() -> Decoder(AdminResponseErrors) {
  use network_status_code <- decode.field(
    "network_status_code",
    decode.optional(decode.int),
  )
  use message <- decode.field("message", decode.optional(decode.string))
  use graphql_errors <- decode.field(
    "graphql_errors",
    decode.optional(decode.list(decode.string)),
  )
  use response <- decode.field(
    "response",
    decode.optional(response_string_decoder()),
  )
  decode.success(AdminResponseErrors(
    network_status_code:,
    message:,
    graphql_errors:,
    response:,
  ))
}

fn response_string_decoder() -> decode.Decoder(Response(String)) {
  use status <- decode.field("status", decode.int)
  use headers <- decode.field(
    "headers",
    decode.list({
      use a <- decode.field(0, decode.string)
      use b <- decode.field(1, decode.string)

      decode.success(#(a, b))
    }),
  )
  use body <- decode.field("body", decode.string)
  decode.success(Response(status:, headers:, body:))
}

pub fn create_admin_api_client(
  config: CreateAdminApiClient,
) -> Result(AdminApiClientConfig, ShopifyError) {
  let api_url = generate_admin_api_url_formatter(config)
  Ok(AdminApiClientConfig(
    store_domain: config.store_domain,
    api_version: config.api_version,
    access_token: config.access_token,
    retries: Some(0),
    api_url: api_url,
    headers: get_admin_headers(config),
  ))
}

pub fn admin_handler(config: AdminApiClientConfig) -> AdminHandler(msg) {
  AdminHandler(
    config: config,
    fetch: fn(
      query: String,
      variables: Option(Json),
      decoder: Decoder(AdminClientResponse(msg)),
    ) {
      let request = {
        let graphql_body = case variables {
          Some(vars) ->
            json.object([#("query", json.string(query)), #("variables", vars)])
          None -> json.object([#("query", json.string(query))])
        }
        admin_base(config)
        |> request.set_method(http.Post)
        |> request.set_body(<<json.to_string(graphql_body):utf8>>)
      }
      use response <- t.do(t.fetch(request))
      admin_decode_response(response, decoder)
    },
  )
}

fn admin_decode_response(
  response: response.Response(_),
  decoder: decode.Decoder(_),
) -> t.Effect(AdminClientResponse(b), AdminResponseErrors) {
  case response.status {
    200 | 201 ->
      case json.parse_bits(response.body, decoder) {
        Ok(data) -> t.done(data)
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
    _ ->
      case json.parse_bits(response.body, error_reason_decoder()) {
        Ok(reason) -> t.abort(snag.new(reason.message))
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
  }
}

fn generate_admin_api_url_formatter(config: CreateAdminApiClient) -> String {
  config.store_domain
  <> "/admin/api/"
  <> string.trim(config.api_version)
  <> "/graphql.json"
}

fn admin_base(client: AdminApiClientConfig) -> Request(String) {
  let assert Ok(parsed_url) = uri.parse("https://" <> client.api_url)
  let assert Some(host) = parsed_url.host
  let assert Some(original_schema) = parsed_url.scheme
  let assert Ok(scheme) = http.scheme_from_string(original_schema)
  request.new()
  |> request.set_scheme(scheme)
  |> request.set_host(host)
  |> request.set_path(parsed_url.path)
  |> request.set_method(http.Post)
  |> request.set_header("Content-Type", "application/json")
  |> request.set_header("Accept", "application/json")
  |> request.set_header("X-Shopify-Access-Token", client.access_token)
}

fn get_admin_headers(
  config: CreateAdminApiClient,
) -> #(String, List(#(String, String))) {
  let token = config.access_token
  #("headers", [
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("X-Shopify-Access-Token", token),
    #("X-SDK-Version", "rollup_replace_client_version"),
  ])
}

pub type CreateStorefrontApiClient {
  CreateStorefrontApiClient(
    /// The domain of the store. It can be the Shopify myshopify.com domain or a custom store domain.
    ///
    store_domain: String,
    /// The requested Storefront API version.
    ///
    api_version: Option(String),
    /// Storefront API public access token. Either publicAccessToken or privateAccessToken must be provided at initialization.
    ///
    public_access_token: Option(String),
    /// Storefront API private access token. Either publicAccessToken or privateAccessToken must be provided at initialization.
    /// Important: Storefront API private delegate access tokens should only be used in a server-to-server implementation.
    ///
    private_access_token: Option(String),
    /// Name of the client
    ///
    client_name: Option(String),
    /// The number of HTTP request retries if the request was abandoned or the server responded
    /// with a Too Many Requests (429) or Service Unavailable (503) response.
    /// Default value is 0. Maximum value is 3.
    ///
    retries: Option(Int),
    // TODO: Work in progress [wip]
    // A replacement fetch function that will be used in all client network requests.
    // By default, the client uses window.fetch().
    // custom_fetch_api: Option(CustomFetchApi),
    // A logger function that accepts log content objects.
    // This logger will be called in certain conditions with contextual information.
    // logger: Option(Logger),
  )
}

pub type ShopifyError {
  BadUrl(String)
  HttpError(Response(String))
  JsonError(json.DecodeError)
  NetworkError
  UnhandledResponse(Response(String))
  RateLimitError
  ClientError(String)
}

pub type ErrorReason {
  ErrorReason(error: String, message: String)
}

fn error_reason_decoder() -> Decoder(ErrorReason) {
  use error <- decode.field("error", decode.string)
  use message <- decode.field("message", decode.string)
  decode.success(ErrorReason(error:, message:))
}

// Base types
//
pub type StorefrontApiClientConfig {
  StorefrontApiClientConfig(
    store_domain: String,
    api_version: Option(String),
    access_token: AccessToken,
    headers: #(String, List(#(String, String))),
    api_url: String,
    client_name: Option(String),
    retries: Option(Int),
  )
}

pub type ShopifyHandler(msg) {
  ShopifyHandler(
    /// Configuration for the client
    config: StorefrontApiClientConfig,
    get_headers: fn(Option(#(String, List(#(String, String))))) ->
      #(String, List(#(String, String))),
    /// Returns Storefront API specific headers needed to interact with the API.
    /// If additional headers are provided, the custom headers will be included in the returned headers object.
    /// Fetches data from Storefront API using the provided GQL operation string
    /// and ApiClientRequestOptions object and returns the network response.
    fetch: fn(String, Option(Json), Decoder(msg)) -> t.Effect(msg, ShopifyError),
  )
}

pub fn create_store_front_api_client(
  config: CreateStorefrontApiClient,
) -> Result(StorefrontApiClientConfig, ShopifyError) {
  let access_token =
    validate_required_access_token_usage(
      config.public_access_token,
      config.private_access_token,
    )
  let token = case access_token {
    Ok(PublicAccessToken(token)) -> PublicAccessToken(token)
    Ok(PrivateAccessToken(token)) -> PrivateAccessToken(token)
    Error(_) -> panic
  }

  Ok(StorefrontApiClientConfig(
    store_domain: config.store_domain,
    api_version: config.api_version,
    access_token: token,
    client_name: config.client_name,
    retries: Some(0),
    api_url: generate_api_url_formatter(config),
    headers: create_headers(token, config.client_name),
  ))
}

pub fn handler(config: StorefrontApiClientConfig) -> ShopifyHandler(msg) {
  ShopifyHandler(
    config: config,
    get_headers: get_headers,
    fetch: fn(query: String, variables: Option(Json), decoder: Decoder(msg)) {
      let request = {
        let graphql_body = case variables {
          Some(vars) ->
            json.object([#("query", json.string(query)), #("variables", vars)])
          None -> json.object([#("query", json.string(query))])
        }
        base(config)
        |> request.set_method(http.Post)
        |> request.set_body(<<json.to_string(graphql_body):utf8>>)
      }
      use response <- t.do(t.fetch(request))
      decode_response(response, decoder)
    },
  )
}

fn decode_response(
  response: response.Response(_),
  decoder: decode.Decoder(_),
) -> t.Effect(b, c) {
  case response.status {
    200 | 201 ->
      case json.parse_bits(response.body, decoder) {
        Ok(data) -> t.done(data)
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
    _ ->
      case json.parse_bits(response.body, error_reason_decoder()) {
        Ok(reason) -> t.abort(snag.new(reason.message))
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
  }
}

fn get_headers(
  headers: Option(#(String, List(#(String, String)))),
) -> #(String, List(#(String, String))) {
  case headers {
    Some(header) -> {
      header
    }
    None -> {
      #("headers", [
        #("Content-Type", "application/json"),
        #("Accept", "application/json"),
        #("X-SDK-Variant", "storefront-api-client"),
        #("X-SDK-Version", "rollup_replace_client_version"),
      ])
    }
  }
}

fn base(client: StorefrontApiClientConfig) -> Request(String) {
  let access = case client.access_token {
    PublicAccessToken(token) -> #("X-Shopify-Access-Token", token)
    PrivateAccessToken(token) -> #("X-Shopify-Access-Token", token)
  }

  let assert Ok(parsed_url) = uri.parse("https://" <> client.api_url)
  let assert Some(host) = parsed_url.host
  let assert Some(original_schema) = parsed_url.scheme
  let assert Ok(scheme) = http.scheme_from_string(original_schema)
  request.new()
  |> request.set_scheme(scheme)
  |> request.set_host(host)
  |> request.set_path(parsed_url.path)
  |> request.set_method(http.Post)
  |> request.set_header("Content-Type", "application/json")
  |> request.set_header("Accept", "application/json")
  // |> request.set_header("X-SDK-Variant", "storefront-api-client")
  // |> request.set_header("X-SDK-Version", "rollup_replace_client_version")
  |> request.set_header(access.0, access.1)
}

pub opaque type AccessToken {
  PublicAccessToken(String)
  PrivateAccessToken(String)
}

fn validate_required_access_token_usage(
  private_access_token: Option(String),
  public_access_token: Option(String),
) -> Result(AccessToken, ShopifyError) {
  let is_valid_private_access_token = option.is_some(private_access_token)
  let is_valid_public_access_token = option.is_some(public_access_token)

  case !is_valid_private_access_token && !is_valid_public_access_token {
    True -> {
      Error(ClientError(
        snag.new("Storefront API Client: an access token must be provided.")
        |> snag.line_print,
      ))
    }
    False -> {
      case is_valid_private_access_token && is_valid_public_access_token {
        True -> {
          Error(ClientError(
            snag.new(
              "Storefront API Client: only provide either a public or private access token.",
            )
            |> snag.line_print,
          ))
        }
        False -> {
          case public_access_token {
            Some(key) -> Ok(PublicAccessToken(key))
            None ->
              case private_access_token {
                Some(key) -> Ok(PrivateAccessToken(key))
                None ->
                  Error(ClientError(
                    snag.new(
                      "Storefront API Client: an access token must be provided.",
                    )
                    |> snag.line_print,
                  ))
              }
          }
        }
      }
    }
  }
}

fn create_headers(
  access_token: AccessToken,
  client_variant: Option(String),
) -> #(String, List(#(String, String))) {
  let access = case access_token {
    PublicAccessToken(token) -> #("X-Shopify-Access-Token", token)
    PrivateAccessToken(token) -> #("X-Shopify-Access-Token", token)
  }
  let client = case client_variant {
    None -> #("X-SDK-Variant-Source", "")
    Some(key) -> #("X-SDK-Variant-Source", key)
  }

  #("headers", [
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("X-SDK-Variant", "storefront-api-client"),
    #("X-SDK-Version", "rollup_replace_client_version"),
    access,
    client,
  ])
}

fn generate_api_url_formatter(config: CreateStorefrontApiClient) -> String {
  case config.api_version {
    Some(api) ->
      config.store_domain
      <> "/admin/api/"
      <> string.trim(api)
      <> "/graphql.json"
    None ->
      config.store_domain
      <> "/admin/api/"
      <> string.trim("2023-10")
      <> "/graphql.json"
  }
}
