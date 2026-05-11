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
    escaped_conversions = props |> build_conversions() |> Macro.escape()

    Module.create(mod_name, schema_body(field_names, desc, escaped_conversions, schemas_mod), env)
  end

  defp schema_body(field_names, desc, escaped_conversions, schemas_mod) do
    List.wrap(struct_and_from_map(field_names, desc)) ++
      List.wrap(field_conversion(escaped_conversions, schemas_mod))
  end

  defp struct_and_from_map(field_names, desc) do
    quote do
      @moduledoc unquote(desc)

      defstruct unquote(field_names)

      @field_set MapSet.new(unquote(field_names))

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
    end
  end

  defp field_conversion(escaped_conversions, schemas_mod) do
    quote do
      @conversions unquote(escaped_conversions)
      @schemas_mod unquote(schemas_mod)

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
    end
  end

  defp build_conversions(props) do
    Map.new(props, fn {prop_name, prop_def} ->
      {String.to_atom(prop_name), convert_prop(prop_def)}
    end)
  end

  defp convert_prop(%{"$ref" => ref}), do: {:struct, ref_name(ref)}

  defp convert_prop(%{"anyOf" => variants}) when is_list(variants) do
    find_ref_in(variants)
  end

  defp convert_prop(%{"allOf" => variants}) when is_list(variants) do
    find_ref_in(variants)
  end

  defp convert_prop(%{"type" => "array", "items" => %{"$ref" => ref}}) do
    {:list, ref_name(ref)}
  end

  defp convert_prop(_), do: :passthrough

  defp find_ref_in(variants) do
    case Enum.find(variants, &match?(%{"$ref" => _}, &1)) do
      %{"$ref" => ref} -> {:struct, ref_name(ref)}
      _ -> :passthrough
    end
  end

  defp ref_name(ref), do: ref |> String.split("/") |> List.last()
end
