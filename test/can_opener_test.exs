defmodule CanOpenerTest do
  use ExUnit.Case
  use Mimic

  alias CanOpener.Client
  alias FixtureApi.Schemas

  setup :verify_on_exit!

  # ── Client ───────────────────────────────────────────────────────

  describe "client/1" do
    test "creates client with defaults" do
      client = FixtureApi.client()
      assert %Client{base_url: "https://api.fixture.test", auth: nil} = client
    end

    test "creates client with explicit options" do
      client = FixtureApi.client(base_url: "https://other.test", api_key: "sk_test")
      assert client.base_url == "https://other.test"
      assert client.auth == {:bearer, "sk_test"}
    end

    test "passes through req_options" do
      client = FixtureApi.client(req_options: [receive_timeout: 5_000])
      assert client.req_options == [receive_timeout: 5_000]
    end

    test "uses application env when explicit options are absent" do
      previous_base_url = Application.get_env(:can_opener, :base_url)
      previous_api_key = Application.get_env(:can_opener, :api_key)

      on_exit(fn ->
        restore_env(:base_url, previous_base_url)
        restore_env(:api_key, previous_api_key)
      end)

      Application.put_env(:can_opener, :base_url, "https://env.fixture.test")
      Application.put_env(:can_opener, :api_key, "sk_env")

      client = FixtureApi.client()
      assert client.base_url == "https://env.fixture.test"
      assert client.auth == {:bearer, "sk_env"}
    end

    test "explicit options override application env" do
      previous_base_url = Application.get_env(:can_opener, :base_url)
      previous_api_key = Application.get_env(:can_opener, :api_key)

      on_exit(fn ->
        restore_env(:base_url, previous_base_url)
        restore_env(:api_key, previous_api_key)
      end)

      Application.put_env(:can_opener, :base_url, "https://env.fixture.test")
      Application.put_env(:can_opener, :api_key, "sk_env")

      client =
        FixtureApi.client(base_url: "https://explicit.fixture.test", api_key: "sk_explicit")

      assert client.base_url == "https://explicit.fixture.test"
      assert client.auth == {:bearer, "sk_explicit"}
    end
  end

  # ── Schemas ──────────────────────────────────────────────────────

  describe "schema generation" do
    test "generates struct with all fields" do
      result = Schemas.StatusResponse.from_map(%{"status" => "ok", "version" => "1.0"})
      assert %Schemas.StatusResponse{status: "ok", version: "1.0"} = result
    end

    test "accepts atom keys" do
      result = Schemas.StatusResponse.from_map(%{status: "ok", version: "1.0"})
      assert %Schemas.StatusResponse{status: "ok", version: "1.0"} = result
    end

    test "handles nil input" do
      assert nil == Schemas.StatusResponse.from_map(nil)
    end

    test "ignores unknown fields" do
      result = Schemas.StatusResponse.from_map(%{"status" => "ok", "extra" => "ignored"})
      assert result.status == "ok"
    end

    test "converts nested $ref via anyOf" do
      result =
        Schemas.WidgetResponse.from_map(%{
          "id" => 1,
          "name" => "Sprocket",
          "color" => "red",
          "metadata" => %{"created_at" => "2025-01-01", "updated_at" => "2025-01-02"}
        })

      assert %Schemas.WidgetResponse{id: 1, name: "Sprocket"} = result
      assert %Schemas.Metadata{created_at: "2025-01-01"} = result.metadata
    end

    test "converts direct $ref fields" do
      result =
        Schemas.WidgetResponse.from_map(%{
          "id" => 1,
          "owner" => %{"id" => 7, "email" => "owner@example.com"}
        })

      assert %Schemas.User{id: 7, email: "owner@example.com"} = result.owner
    end

    test "converts allOf $ref fields" do
      result =
        Schemas.WidgetResponse.from_map(%{
          "id" => 1,
          "audit" => %{"created_by" => "system", "request_id" => "req_123"}
        })

      assert %Schemas.AuditMetadata{created_by: "system", request_id: "req_123"} = result.audit
    end

    test "passes primitive arrays through unchanged" do
      result = Schemas.WidgetResponse.from_map(%{"id" => 1, "tags" => ["new", "blue"]})
      assert result.tags == ["new", "blue"]
    end

    test "handles nil nested ref" do
      result = Schemas.WidgetResponse.from_map(%{"id" => 2, "metadata" => nil})
      assert result.metadata == nil
    end

    test "converts array of $ref items" do
      result =
        Schemas.ItemList.from_map(%{
          "total" => 2,
          "items" => [
            %{"id" => 1, "label" => "Alpha"},
            %{"id" => 2, "label" => "Beta"}
          ]
        })

      assert %Schemas.ItemList{total: 2} = result

      assert [%Schemas.Item{id: 1, label: "Alpha"}, %Schemas.Item{id: 2, label: "Beta"}] =
               result.items
    end
  end

  # ── Operations ─────────────────────────────────────────────────

  describe "generated operations" do
    test "all expected functions exist" do
      Code.ensure_loaded!(FixtureApi)
      assert function_exported?(FixtureApi, :get_status, 1)
      assert function_exported?(FixtureApi, :list_widgets, 1)
      assert function_exported?(FixtureApi, :create_widget, 2)
      assert function_exported?(FixtureApi, :get_items, 1)
      assert function_exported?(FixtureApi, :post_jobs, 2)
      assert function_exported?(FixtureApi, :show_widget, 2)
      assert function_exported?(FixtureApi, :delete_widget, 2)
    end

    test "GET request without body" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] == "https://api.fixture.test/api/v1/status"
        assert opts[:headers] == [{"authorization", "Bearer sk_test"}]

        {:ok, %Req.Response{status: 200, body: %{"status" => "ok", "version" => "2.0"}}}
      end)

      assert {:ok, %Schemas.StatusResponse{status: "ok", version: "2.0"}} =
               FixtureApi.get_status(client)
    end

    test "POST request with body" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == "https://api.fixture.test/api/v1/widgets"
        assert opts[:json] == %{name: "Gear", color: "blue"}

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => 42,
             "name" => "Gear",
             "color" => "blue",
             "metadata" => %{"created_at" => "2025-06-01", "updated_at" => "2025-06-01"}
           }
         }}
      end)

      assert {:ok, result} = FixtureApi.create_widget(client, %{name: "Gear", color: "blue"})
      assert %Schemas.WidgetResponse{id: 42, name: "Gear"} = result
      assert %Schemas.Metadata{created_at: "2025-06-01"} = result.metadata
    end

    test "GET request on same path as POST uses arity 1" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] == "https://api.fixture.test/api/v1/widgets"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "total" => 1,
             "items" => [%{"id" => 42, "name" => "Gear", "color" => "blue"}]
           }
         }}
      end)

      assert {:ok, %Schemas.WidgetList{total: 1, items: [%Schemas.WidgetResponse{id: 42}]}} =
               FixtureApi.list_widgets(client)
    end

    test "201 response with non-200 schema currently returns raw map" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == "https://api.fixture.test/api/v1/jobs"
        assert opts[:json] == %{name: "Import"}

        {:ok, %Req.Response{status: 201, body: %{"id" => 9, "state" => "queued"}}}
      end)

      # The generator only decodes schemas declared under responses["200"] today.
      assert {:ok, %{"id" => 9, "state" => "queued"}} =
               FixtureApi.post_jobs(client, %{name: "Import"})
    end

    test "path parameters are substituted and encoded" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] == "https://api.fixture.test/api/v1/widgets/id%20with%2Fslash"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"id" => 42, "name" => "Gear", "color" => "blue"}
         }}
      end)

      assert {:ok, %Schemas.WidgetResponse{id: 42, name: "Gear"}} =
               FixtureApi.show_widget(client, "id with/slash")
    end

    test "204 response without schema returns raw body" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :delete
        assert opts[:url] == "https://api.fixture.test/api/v1/widgets/42"

        {:ok, %Req.Response{status: 204, body: nil}}
      end)

      assert {:ok, nil} = FixtureApi.delete_widget(client, 42)
    end

    test "request options are passed to Req.request/1" do
      client = FixtureApi.client(req_options: [receive_timeout: 5_000])

      expect(Req, :request, fn opts ->
        assert opts[:receive_timeout] == 5_000
        {:ok, %Req.Response{status: 200, body: %{"status" => "ok", "version" => "1.0"}}}
      end)

      assert {:ok, %Schemas.StatusResponse{}} = FixtureApi.get_status(client)
    end

    test "error response returns {:error, ...}" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "boom"}}}
      end)

      assert {:error, %{status: 500, body: %{"error" => "boom"}}} = FixtureApi.get_status(client)
    end

    test "transport error passes through" do
      client = FixtureApi.client(api_key: "sk_test")

      expect(Req, :request, fn _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} = FixtureApi.get_status(client)
    end

    test "no auth header when api_key is nil" do
      client = FixtureApi.client()

      expect(Req, :request, fn opts ->
        assert opts[:headers] == []
        {:ok, %Req.Response{status: 200, body: %{"status" => "ok", "version" => "1.0"}}}
      end)

      assert {:ok, _} = FixtureApi.get_status(client)
    end

    test "custom header auth sends configured header" do
      client = FixtureHeaderAuthApi.client(api_key: "sk_test")
      assert %Client{auth: {:header, "X-API-Key", "sk_test"}} = client

      expect(Req, :request, fn opts ->
        assert opts[:headers] == [{"X-API-Key", "sk_test"}]
        {:ok, %Req.Response{status: 200, body: %{"status" => "ok", "version" => "1.0"}}}
      end)

      assert {:ok, %FixtureHeaderAuthApi.Schemas.StatusResponse{}} =
               FixtureHeaderAuthApi.get_status(client)
    end

    test "none auth strategy ignores api_key" do
      client = FixtureNoAuthApi.client(api_key: "sk_test")
      assert %Client{auth: nil} = client

      expect(Req, :request, fn opts ->
        assert opts[:headers] == []
        {:ok, %Req.Response{status: 200, body: %{"status" => "ok", "version" => "1.0"}}}
      end)

      assert {:ok, %FixtureNoAuthApi.Schemas.StatusResponse{}} =
               FixtureNoAuthApi.get_status(client)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:can_opener, key)
  defp restore_env(key, value), do: Application.put_env(:can_opener, key, value)
end
