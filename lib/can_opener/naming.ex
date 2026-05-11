defmodule CanOpener.Naming do
  @moduledoc false

  @doc """
  Derive a function name from an OpenAPI operation.

  Uses `operationId` when present. Otherwise, falls back to a method-prefixed
  path name with path parameters normalized into regular identifier parts.

      iex> CanOpener.Naming.operation_name(%{"operationId" => "verifyEmail"}, "get", "/api/v1/verify/email", "/api/v1/")
      :verify_email

      iex> CanOpener.Naming.operation_name(%{}, "delete", "/api/v1/widgets/{id}", "/api/v1/")
      :delete_widget
  """
  def operation_name(operation, method, path, prefix) do
    operation
    |> Map.get("operationId")
    |> case do
      nil -> fallback_name(method, path, prefix)
      "" -> fallback_name(method, path, prefix)
      operation_id -> normalize(operation_id)
    end
    |> String.to_atom()
  end

  defp fallback_name(method, path, prefix) do
    path_parts =
      path
      |> String.replace_prefix(prefix, "")
      |> String.split("/", trim: true)
      |> path_name_parts()

    case path_parts do
      [] -> normalize(method)
      _ -> normalize(Enum.join([method | path_parts], "_"))
    end
  end

  defp path_name_parts([]), do: []

  defp path_name_parts(segments) do
    case List.last(segments) do
      "{" <> _param -> member_path_name_parts(Enum.drop(segments, -1))
      _segment -> Enum.map(segments, &segment_name/1)
    end
  end

  defp member_path_name_parts([]), do: []

  defp member_path_name_parts(segments) do
    segments
    |> Enum.map(&segment_name/1)
    |> List.update_at(-1, &singularize/1)
  end

  defp segment_name("{" <> rest) do
    rest
    |> String.trim_trailing("}")
    |> normalize()
  end

  defp segment_name(segment), do: normalize(segment)

  defp singularize(name) do
    cond do
      String.ends_with?(name, "ies") ->
        String.replace_suffix(name, "ies", "y")

      String.ends_with?(name, "ses") ->
        String.replace_suffix(name, "es", "")

      String.ends_with?(name, "s") and not String.ends_with?(name, "ss") ->
        String.trim_trailing(name, "s")

      true ->
        name
    end
  end

  defp normalize(value) do
    value
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
    |> String.trim("_")
  end

  @doc false
  def path_params(path) do
    ~r/\{([^}]+)\}/
    |> Regex.scan(path)
    |> Enum.map(fn [_match, name] -> name end)
  end

  @doc false
  def param_var_name(name) do
    name
    |> normalize()
    |> String.to_atom()
  end

  @doc false
  def from_path(path, prefix) do
    path
    |> String.replace_prefix(prefix, "")
    |> String.replace("/", "_")
    |> String.to_atom()
  end
end
