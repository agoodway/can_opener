defmodule CanOpener.Schema do
  @moduledoc false

  @doc """
  Define all schema struct modules from an OpenAPI spec.

  Called at compile time inside the caller's module body.
  Generates one module per schema under `schemas_mod`.
  """
  def __define_all__(schemas_mod, spec, env) do
    schemas = get_in(spec, ["components", "schemas"]) || %{}

    for {schema_name, schema_def} <- schemas do
      mod_name = Module.concat(schemas_mod, schema_name)
      define_one(mod_name, schema_def, schemas_mod, env)
    end

    :ok
  end

  defp define_one(mod_name, schema_def, schemas_mod, env) do
    props = schema_def["properties"] || %{}
    desc = schema_def["description"] || ""

    field_names = props |> Map.keys() |> Enum.sort() |> Enum.map(&String.to_atom/1)
    conversions = build_conversions(props)
    escaped_conversions = Macro.escape(conversions)

    Module.create(
      mod_name,
      quote do
        @moduledoc unquote(desc)

        defstruct unquote(field_names)

        @field_set MapSet.new(unquote(field_names))
        @conversions unquote(escaped_conversions)
        @schemas_mod unquote(schemas_mod)

        @doc "Convert a JSON-decoded map into a `#{inspect(__MODULE__)}` struct."
        def from_map(nil), do: nil

        def from_map(map) when is_map(map) do
          fields =
            for {key, value} <- map,
                atom_key = to_field_atom(key),
                atom_key in @field_set,
                into: %{} do
              {atom_key, convert_field(atom_key, value)}
            end

          struct(__MODULE__, fields)
        end

        defp to_field_atom(key) when is_atom(key), do: key
        defp to_field_atom(key) when is_binary(key), do: String.to_atom(key)

        defp convert_field(_key, nil), do: nil

        defp convert_field(key, value) do
          case Map.get(@conversions, key) do
            {:struct, ref_name} when is_map(value) ->
              Module.concat(@schemas_mod, ref_name).from_map(value)

            {:list, ref_name} when is_list(value) ->
              mod = Module.concat(@schemas_mod, ref_name)
              Enum.map(value, &mod.from_map/1)

            _ ->
              value
          end
        end
      end,
      env
    )
  end

  defp build_conversions(props) do
    for {prop_name, prop_def} <- props, into: %{} do
      conv =
        cond do
          match?(%{"$ref" => _}, prop_def) ->
            {:struct, prop_def["$ref"] |> String.split("/") |> List.last()}

          is_list(prop_def["anyOf"]) ->
            case Enum.find(prop_def["anyOf"], &match?(%{"$ref" => _}, &1)) do
              %{"$ref" => ref} -> {:struct, ref |> String.split("/") |> List.last()}
              _ -> :passthrough
            end

          is_list(prop_def["allOf"]) ->
            case Enum.find(prop_def["allOf"], &match?(%{"$ref" => _}, &1)) do
              %{"$ref" => ref} -> {:struct, ref |> String.split("/") |> List.last()}
              _ -> :passthrough
            end

          prop_def["type"] == "array" && is_map(prop_def["items"]) &&
              Map.has_key?(prop_def["items"], "$ref") ->
            {:list, prop_def["items"]["$ref"] |> String.split("/") |> List.last()}

          true ->
            :passthrough
        end

      {String.to_atom(prop_name), conv}
    end
  end
end
