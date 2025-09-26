import gleam/dynamic/decode.{type Decoder}
import gleam/fetch
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/string
import snag

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
    fetch: fn(String, Option(Json), Decoder(msg)) ->
      Promise(Result(msg, ShopifyError)),
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

  case validate_private_access_token_usage(config.private_access_token) {
    Error(err) -> Error(err)
    Ok(Nil) -> {
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
  }
}

pub fn handler(config: StorefrontApiClientConfig) -> ShopifyHandler(msg) {
  ShopifyHandler(
    config: config,
    get_headers: get_headers,
    fetch: fn(query: String, variables: Option(Json), decoder: Decoder(msg)) {
      let request = base(config)

      let graphql_body = case variables {
        Some(vars) ->
          json.object([#("query", json.string(query)), #("variables", vars)])
        None -> json.object([#("query", json.string(query))])
      }

      request
      |> request.set_body(json.to_string(graphql_body))
      |> request.set_method(http.Post)
      |> fetch.send
      |> promise.try_await(fetch.read_text_body)
      |> promise.map(fn(result) {
        case result {
          Ok(response) -> {
            case json.parse(response.body, using: decoder) {
              Ok(decoded) -> Ok(decoded)
              Error(json_error) -> Error(JsonError(json_error))
            }
          }
          Error(_) -> Error(NetworkError)
        }
      })
    },
  )
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
    PublicAccessToken(token) -> #("X-Shopify-Storefront-Access-Token", token)
    PrivateAccessToken(token) -> #("Shopify-Storefront-Private-Token", token)
  }
  request.new()
  |> request.set_host(client.api_url)
  |> request.set_method(http.Post)
  |> request.set_header("Content-Type", "application/json")
  |> request.set_header("Accept", "application/json")
  |> request.set_header("X-SDK-Variant", "storefront-api-client")
  |> request.set_header("X-SDK-Version", "rollup_replace_client_version")
  |> request.set_header(access.0, access.1)
}

pub opaque type AccessToken {
  PublicAccessToken(String)
  PrivateAccessToken(String)
}

// pub opaque type CustomFetchApi {
//   CustomFetchApi(
//     custom_fetch: fn(Result(CustomFetchParams, ShopifyError)) ->
//       Response(String),
//   )
// }

// type CustomFetchParams {
//   CustomFetchParams(url: String, init: Option(CustomFetchInitializer))
// }

// type CustomFetchInitializer {
//   CustomFetchInitializer(
//     method: Option(String),
//     headers: #(String, List(#(String, String))),
//     body: Option(String),
//   )
// }

// /// TODO: Implement logger
// pub opaque type Logger {
//   Logger(log: fn(Result(LogContent, ShopifyError)) -> Nil)
// }

// pub opaque type LogContent {
//   UnsupportedApiVersionLog
//   HTTPResponseLog
//   HTTPRetryLog
// }

@external(javascript, "./env.ffi.mjs", "isBrowser")
fn is_browser_environment() -> Bool

fn validate_private_access_token_usage(
  private_access_token: Option(String),
) -> Result(Nil, ShopifyError) {
  case private_access_token, is_browser_environment() {
    Some(_), True ->
      Error(ClientError(
        snag.new(
          "Storefront API Client: private access tokens and headers should only be used in a server-to-server implementation. Use the public API access token in nonserver environments.",
        )
        |> snag.line_print,
      ))
    _, _ -> Ok(Nil)
  }
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
    PublicAccessToken(token) -> #("X-Shopify-Storefront-Access-Token", token)
    PrivateAccessToken(token) -> #("Shopify-Storefront-Private-Token", token)
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
  let domain = validate_store_domain(config)
  case config.api_version {
    Some(api) -> domain <> "/api/" <> string.trim(api) <> "/graphql.json"
    None -> domain <> "/api/" <> string.trim("2023-10") <> "/graphql.json"
  }
}

fn validate_store_domain(config: CreateStorefrontApiClient) -> String {
  let domain = string.trim(config.store_domain)
  case string.starts_with(domain, "https://") {
    True -> domain
    False -> string.append(to: "https://", suffix: domain)
  }
}
