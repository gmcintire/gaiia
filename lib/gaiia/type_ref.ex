defmodule Gaiia.TypeRef do
  @moduledoc """
  Helpers for working with GraphQL type-reference maps as returned by
  introspection (`__Type`).

  A type reference is a recursive map of the shape:

      %{"kind" => "NON_NULL" | "LIST" | "SCALAR" | ..., "name" => name, "ofType" => inner_or_nil}

  This module renders such structures to GraphQL syntax (`Int!`,
  `[String!]!`, etc.) and unwraps modifiers to find the underlying named type.
  """

  @type t :: %{required(String.t()) => term()}

  @doc "Render a type-reference map as a GraphQL type string."
  @spec render(t()) :: String.t()
  def render(%{"kind" => "NON_NULL", "ofType" => inner}), do: render(inner) <> "!"
  def render(%{"kind" => "LIST", "ofType" => inner}), do: "[" <> render(inner) <> "]"
  def render(%{"name" => name}) when is_binary(name), do: name

  @doc "Unwrap NON_NULL/LIST modifiers to return the innermost named type ref."
  @spec named_type(t()) :: t()
  def named_type(%{"kind" => kind, "ofType" => inner}) when kind in ["NON_NULL", "LIST"], do: named_type(inner)
  def named_type(%{"name" => name} = type) when is_binary(name), do: type

  @doc """
  Strip an introspection type reference to the keys this library reads.

  Introspection responses carry descriptions and `__typename` on every
  nesting level; the bundled schema dumps keep only `kind`, `name`, and
  `ofType` so the compile-time literals stay small.
  """
  @spec prune(t() | nil) :: t() | nil
  def prune(nil), do: nil

  def prune(%{"kind" => kind, "name" => name} = type),
    do: %{"kind" => kind, "name" => name, "ofType" => prune(type["ofType"])}
end
