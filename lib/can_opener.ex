defmodule CanOpener do
  @moduledoc """
  Compile-time OpenAPI client generator.

  Given an OpenAPI 3.x JSON spec, generates typed Elixir structs for every
  schema and API functions for every path — all at compile time.

  ## Usage

      defmodule MyApp.API do
        use CanOpener,
          spec: "openapi.json",
          otp_app: :my_app,
          base_url: "https://api.example.com",
          auth: :bearer,
          path_prefix: "/api/v1/"
      end

  ## Options

    * `:spec` (required) — path to the OpenAPI JSON file, relative to the project root.
    * `:otp_app` (required) — the OTP application name, used for `Application.get_env/3`.
    * `:base_url` — default base URL. Defaults to `"http://localhost:4000"`.
    * `:auth` — authentication strategy. One of:
      - `:bearer` (default) — sends `Authorization: Bearer <api_key>`
      - `{:header, "X-API-Key"}` — sends the api_key in a custom header
      - `:none` — no authentication
    * `:path_prefix` — path prefix to strip when generating function names.
      Defaults to `"/"`.

  ## Generated API

    * `client/1` — creates a `%CanOpener.Client{}` struct
    * Schema structs under `YourModule.Schemas.*`, each with `from_map/1`
    * One function per OpenAPI path+method, named by stripping `path_prefix`
      and replacing `/` with `_`
  """

  @doc false
  defmacro __using__(opts) do
    spec = Keyword.fetch!(opts, :spec)
    otp_app = Keyword.fetch!(opts, :otp_app)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    auth = Macro.escape(Keyword.get(opts, :auth, :bearer))
    path_prefix = Keyword.get(opts, :path_prefix, "/")

    quote do
      @_co_spec_path Path.expand(unquote(spec))
      @external_resource @_co_spec_path
      @_co_spec File.read!(@_co_spec_path) |> Jason.decode!()
      @_co_path_prefix unquote(path_prefix)

      alias CanOpener.Client

      @doc "Create a new API client."
      def client(opts \\ []) do
        CanOpener.Client.new(unquote(otp_app), unquote(base_url), unquote(auth), opts)
      end

      # Generate schema modules
      _schemas_mod = Module.concat(__MODULE__, Schemas)
      CanOpener.Schema.__define_all__(_schemas_mod, @_co_spec, __ENV__)

      # Operations are generated in __before_compile__
      @before_compile CanOpener
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    spec = Module.get_attribute(env.module, :_co_spec)
    path_prefix = Module.get_attribute(env.module, :_co_path_prefix)
    schemas_mod = Module.concat(env.module, Schemas)

    for {path, methods} <- spec["paths"] || %{},
        {method, operation} <- methods do
      generate_operation(path, method, operation, path_prefix, schemas_mod)
    end
  end

  defp generate_operation(path, method, operation, path_prefix, schemas_mod) do
    func_name = CanOpener.Naming.from_path(path, path_prefix)
    http_method = String.to_atom(method)
    doc = operation_doc(operation)
    response_module = response_module_for(operation, schemas_mod)

    if operation["requestBody"] do
      generate_body_operation(func_name, http_method, path, doc, response_module)
    else
      generate_simple_operation(func_name, http_method, path, doc, response_module)
    end
  end

  defp operation_doc(operation) do
    summary = operation["summary"] || ""
    description = operation["description"] || ""
    "#{summary}\n\n#{description}"
  end

  defp response_module_for(operation, schemas_mod) do
    case get_in(operation, ["responses", "200", "content", "application/json", "schema", "$ref"]) do
      nil -> nil
      ref -> Module.concat(schemas_mod, ref |> String.split("/") |> List.last())
    end
  end

  defp generate_body_operation(func_name, http_method, path, doc, response_module) do
    quote do
      @doc unquote(doc)
      def unquote(func_name)(%CanOpener.Client{} = client, params) when is_map(params) do
        case CanOpener.Client.request(client, unquote(http_method), unquote(path), json: params) do
          {:ok, body} when is_map(body) ->
            {:ok, CanOpener.decode_response(unquote(response_module), body)}

          other ->
            other
        end
      end
    end
  end

  defp generate_simple_operation(func_name, http_method, path, doc, response_module) do
    quote do
      @doc unquote(doc)
      def unquote(func_name)(%CanOpener.Client{} = client) do
        case CanOpener.Client.request(client, unquote(http_method), unquote(path)) do
          {:ok, body} when is_map(body) ->
            {:ok, CanOpener.decode_response(unquote(response_module), body)}

          other ->
            other
        end
      end
    end
  end

  @doc false
  def decode_response(nil, body), do: body
  def decode_response(module, body), do: module.from_map(body)
end
