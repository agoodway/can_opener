defmodule CanOpener.Naming do
  @moduledoc false

  @doc """
  Derive a function name from an OpenAPI path by stripping `prefix`
  and replacing `/` with `_`.

      iex> CanOpener.Naming.from_path("/api/v1/verify/email", "/api/v1/")
      :verify_email

      iex> CanOpener.Naming.from_path("/health", "/")
      :health
  """
  def from_path(path, prefix) do
    path
    |> String.replace_prefix(prefix, "")
    |> String.replace("/", "_")
    |> String.to_atom()
  end
end
