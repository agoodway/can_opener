# CanOpener

CanOpener is a compile-time OpenAPI 3.x client generator for Elixir.

You point it at an OpenAPI JSON file, define a small API module, and CanOpener generates:

- A `client/1` constructor for configuring base URL, auth, and Req options
- One function per OpenAPI path and method
- Struct modules for every schema under `components.schemas`
- `from_map/1` decoders that convert JSON-decoded maps into generated structs

CanOpener is intentionally small. It is useful when you want a lightweight generated client without adding an external code generation step to your build pipeline.

## Requirements

- Elixir `~> 1.19`
- An OpenAPI 3.x JSON document
- JSON responses decoded by `Req`

## Installation

Add `can_opener` directly from GitHub:

```elixir
def deps do
  [
    {:can_opener, git: "git@github.com:agoodway/can_opener.git"}
  ]
end
```

If you prefer HTTPS:

```elixir
def deps do
  [
    {:can_opener, git: "https://github.com/agoodway/can_opener.git"}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

## Quick Start

Put your OpenAPI JSON file in your project, for example `priv/openapi.json`.

Define an API module:

```elixir
defmodule MyApp.ExampleApi do
  use CanOpener,
    spec: "priv/openapi.json",
    otp_app: :my_app,
    base_url: "https://api.example.com",
    auth: :bearer,
    path_prefix: "/api/v1/"
end
```

Create a client and call generated functions:

```elixir
client = MyApp.ExampleApi.client(api_key: "sk_test_123")

{:ok, status} = MyApp.ExampleApi.status(client)
status.status
#=> "ok"
```

For operations with a request body, pass a map as the second argument:

```elixir
client = MyApp.ExampleApi.client(api_key: "sk_test_123")

{:ok, widget} =
  MyApp.ExampleApi.widgets(client, %{
    name: "Gear",
    color: "blue"
  })

widget.name
#=> "Gear"
```

## Defining An API Module

`use CanOpener` accepts these options:

- `:spec` is required. It is the path to an OpenAPI JSON file, relative to the project root.
- `:otp_app` is required. It is used for runtime `Application.get_env/3` lookups.
- `:base_url` is optional. It defaults to `"http://localhost:4000"`.
- `:auth` is optional. It defaults to `:bearer`.
- `:path_prefix` is optional. It defaults to `"/"`.

Example:

```elixir
defmodule MyApp.BillingApi do
  use CanOpener,
    spec: "priv/billing-openapi.json",
    otp_app: :my_app,
    base_url: "https://billing.example.com",
    auth: {:header, "X-API-Key"},
    path_prefix: "/api/v1/"
end
```

The spec is read at compile time. When the OpenAPI file changes, the module recompiles because the spec is registered as an external resource.

## Generated Function Names

CanOpener generates function names from OpenAPI paths by:

- Removing the configured `path_prefix`
- Replacing `/` with `_`
- Converting the result to an atom

For example, with `path_prefix: "/api/v1/"`:

| OpenAPI path | Generated function |
| --- | --- |
| `/api/v1/status` | `status/1` |
| `/api/v1/widgets` without request body | `widgets/1` |
| `/api/v1/widgets` with request body | `widgets/2` |
| `/api/v1/verify/email` | `verify_email/1` |
| `/api/v1/widgets/{id}` | `widgets_{id}/1` |

CanOpener does not currently substitute path parameters. A path like `/widgets/{id}` is sent literally as `/widgets/{id}`.

## Generated Operation Arity

Operations without `requestBody` generate a one-argument function:

```elixir
MyApp.ExampleApi.status(client)
```

Operations with `requestBody` generate a two-argument function:

```elixir
MyApp.ExampleApi.widgets(client, %{name: "Gear"})
```

The request body argument must be a map. It is sent to `Req` as `json: params`.

## Client Configuration

Every generated API module includes `client/1`.

```elixir
client = MyApp.ExampleApi.client()
```

You can override the base URL:

```elixir
client = MyApp.ExampleApi.client(base_url: "https://staging.example.com")
```

You can pass an API key:

```elixir
client = MyApp.ExampleApi.client(api_key: "sk_test_123")
```

You can pass additional Req options:

```elixir
client =
  MyApp.ExampleApi.client(
    api_key: "sk_test_123",
    req_options: [receive_timeout: 5_000]
  )
```

Request options are merged into the generated request. CanOpener builds the request with `method`, `url`, and `headers`, merges operation options such as `json`, then merges `client.req_options` last.

## Runtime Configuration

`client/1` reads runtime defaults from the configured OTP app.

For example, if your API module uses `otp_app: :my_app`, CanOpener reads:

- `Application.get_env(:my_app, :base_url)`
- `Application.get_env(:my_app, :api_key)`

You can configure those values in `config/runtime.exs`:

```elixir
import Config

config :my_app,
  base_url: System.fetch_env!("EXAMPLE_API_BASE_URL"),
  api_key: System.fetch_env!("EXAMPLE_API_KEY")
```

Explicit options passed to `client/1` take precedence over application env:

```elixir
client =
  MyApp.ExampleApi.client(
    base_url: "https://override.example.com",
    api_key: "override-key"
  )
```

## Authentication

CanOpener supports three auth strategies.

### Bearer Auth

Use `auth: :bearer` to send an authorization header:

```elixir
defmodule MyApp.ExampleApi do
  use CanOpener,
    spec: "priv/openapi.json",
    otp_app: :my_app,
    base_url: "https://api.example.com",
    auth: :bearer
end
```

```elixir
client = MyApp.ExampleApi.client(api_key: "sk_test_123")
```

Generated requests include:

```text
authorization: Bearer sk_test_123
```

### Custom Header Auth

Use `auth: {:header, "X-API-Key"}` to send the API key in a custom header:

```elixir
defmodule MyApp.ExampleApi do
  use CanOpener,
    spec: "priv/openapi.json",
    otp_app: :my_app,
    base_url: "https://api.example.com",
    auth: {:header, "X-API-Key"}
end
```

Generated requests include:

```text
X-API-Key: sk_test_123
```

### No Auth

Use `auth: :none` to avoid auth headers entirely:

```elixir
defmodule MyApp.PublicApi do
  use CanOpener,
    spec: "priv/openapi.json",
    otp_app: :my_app,
    base_url: "https://api.example.com",
    auth: :none
end
```

If `auth: :none` is configured, passing `api_key` to `client/1` is ignored.

## Response Handling

`CanOpener.Client.request/4` treats HTTP status codes in `200..299` as success.

Successful responses return:

```elixir
{:ok, body}
```

Non-2xx responses return:

```elixir
{:error, %{status: status, body: body}}
```

Transport errors from `Req` are passed through:

```elixir
{:error, exception}
```

Generated operation functions decode successful map bodies when the OpenAPI operation declares a `200` JSON response schema with a `$ref`:

```json
{
  "responses": {
    "200": {
      "content": {
        "application/json": {
          "schema": { "$ref": "#/components/schemas/StatusResponse" }
        }
      }
    }
  }
}
```

If no supported `200` response schema is found, successful map responses are returned as raw maps.

Important: CanOpener currently only looks at `responses["200"]` for response decoding. A `201` response is still treated as HTTP success, but its schema is not used for decoding unless the spec also declares a supported `200` response schema.

## Generated Schemas

For every schema under `components.schemas`, CanOpener generates a module under `YourApiModule.Schemas`.

For example, this schema:

```json
{
  "components": {
    "schemas": {
      "StatusResponse": {
        "type": "object",
        "properties": {
          "status": { "type": "string" },
          "version": { "type": "string" }
        }
      }
    }
  }
}
```

Generates a struct like:

```elixir
%MyApp.ExampleApi.Schemas.StatusResponse{
  status: nil,
  version: nil
}
```

You can convert JSON-decoded maps manually:

```elixir
alias MyApp.ExampleApi.Schemas.StatusResponse

status = StatusResponse.from_map(%{"status" => "ok", "version" => "1.0"})
status.status
#=> "ok"
```

`from_map/1` supports:

- `nil` input, returning `nil`
- String keys and atom keys
- Ignoring unknown fields
- Direct `$ref` properties
- `$ref` inside `anyOf`
- `$ref` inside `allOf`
- Arrays whose `items` is a `$ref`
- Primitive and unsupported fields as passthrough values

Nested example:

```json
{
  "WidgetResponse": {
    "type": "object",
    "properties": {
      "id": { "type": "integer" },
      "owner": { "$ref": "#/components/schemas/User" },
      "tags": {
        "type": "array",
        "items": { "type": "string" }
      }
    }
  }
}
```

```elixir
widget =
  MyApp.ExampleApi.Schemas.WidgetResponse.from_map(%{
    "id" => 42,
    "owner" => %{"id" => 7, "email" => "owner@example.com"},
    "tags" => ["new", "blue"]
  })

widget.owner.email
#=> "owner@example.com"

widget.tags
#=> ["new", "blue"]
```

## Example OpenAPI Fixture

Here is a minimal supported OpenAPI shape:

```json
{
  "openapi": "3.0.0",
  "info": { "title": "Example API", "version": "1.0.0" },
  "paths": {
    "/api/v1/status": {
      "get": {
        "summary": "Get status",
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/StatusResponse" }
              }
            }
          }
        }
      }
    },
    "/api/v1/widgets": {
      "post": {
        "summary": "Create widget",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "$ref": "#/components/schemas/WidgetRequest" }
            }
          }
        },
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/WidgetResponse" }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "StatusResponse": {
        "type": "object",
        "properties": {
          "status": { "type": "string" },
          "version": { "type": "string" }
        }
      },
      "WidgetRequest": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "color": { "type": "string" }
        }
      },
      "WidgetResponse": {
        "type": "object",
        "properties": {
          "id": { "type": "integer" },
          "name": { "type": "string" },
          "color": { "type": "string" }
        }
      }
    }
  }
}
```

## Testing A Generated Client

CanOpener uses `Req.request/1` underneath. In tests, you can use `Mimic` to assert the generated request options.

In `test/test_helper.exs`:

```elixir
Mimic.copy(Req)
ExUnit.start()
```

In a test:

```elixir
defmodule MyApp.ExampleApiTest do
  use ExUnit.Case
  use Mimic

  setup :verify_on_exit!

  test "GET status sends bearer auth" do
    client = MyApp.ExampleApi.client(api_key: "sk_test")

    expect(Req, :request, fn opts ->
      assert opts[:method] == :get
      assert opts[:url] == "https://api.example.com/api/v1/status"
      assert opts[:headers] == [{"authorization", "Bearer sk_test"}]

      {:ok, %Req.Response{status: 200, body: %{"status" => "ok", "version" => "1.0"}}}
    end)

    assert {:ok, %MyApp.ExampleApi.Schemas.StatusResponse{status: "ok"}} =
             MyApp.ExampleApi.status(client)
  end
end
```

## Development

Fetch dependencies:

```sh
mix deps.get
```

Run tests:

```sh
mix test
```

Check formatting:

```sh
mix format --check-formatted
```

Compile with warnings as errors:

```sh
mix compile --warnings-as-errors
```

Run coverage:

```sh
mix test --cover
```

The built-in coverage report can understate useful scenario coverage because many modules are generated at compile time for fixture APIs.

## Current Limitations

CanOpener is not a full OpenAPI implementation yet. Current limitations include:

- Only JSON OpenAPI specs are supported.
- Operation names are generated from paths only; method names are not included.
- Path parameters are not substituted.
- Query parameters are not generated or encoded.
- Header and cookie parameters are not generated.
- Response decoding only looks at `responses["200"]`.
- `201`, `204`, and other `2xx` statuses are treated as success by the client, but their schemas are not used for decoding.
- Inline response schemas are not converted into generated structs.
- `oneOf`, enums, required fields, validation rules, and `additionalProperties` are not interpreted.
- Request body schemas are not used to validate outgoing params.

These limitations are intentional for the current lightweight implementation. Prefer adding focused tests before expanding behavior.

## License

See `LICENSE`.
