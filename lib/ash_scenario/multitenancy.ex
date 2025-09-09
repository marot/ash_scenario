defmodule AshScenario.Multitenancy do
  @moduledoc """
  Helper functions for detecting and handling multitenancy in Ash resources.
  
  This module provides automatic detection of attribute-based multitenancy
  and extracts tenant values from attributes without requiring any changes
  to prototype or scenario definitions.
  """

  alias AshScenario.Log

  @doc """
  Extracts tenant information from attributes for a given resource.
  
  For resources with attribute-based multitenancy, this function:
  1. Detects the tenant attribute name
  2. Extracts the tenant value from attributes
  3. Returns clean attributes without the tenant attribute
  
  For resources without multitenancy or with context-based multitenancy,
  returns the original attributes unchanged.
  
  ## Examples
  
      # Resource with attribute multitenancy on :organization_id
      iex> extract_tenant_info(MyApp.Post, %{title: "Test", organization_id: "org-123"})
      {:ok, "org-123", %{title: "Test"}}
      
      # Resource without multitenancy
      iex> extract_tenant_info(MyApp.Blog, %{name: "Test Blog"})
      {:ok, nil, %{name: "Test Blog"}}
  """
  @spec extract_tenant_info(module(), map()) :: {:ok, any() | nil, map()}
  def extract_tenant_info(resource, attributes) when is_map(attributes) do
    case Ash.Resource.Info.multitenancy_strategy(resource) do
      :attribute ->
        tenant_attr = Ash.Resource.Info.multitenancy_attribute(resource)
        tenant_value = Map.get(attributes, tenant_attr)
        
        Log.debug(
          fn ->
            "multitenancy_detected resource=#{inspect(resource)} strategy=:attribute tenant_attr=#{tenant_attr} tenant_value=#{inspect(tenant_value)}"
          end,
          component: :multitenancy,
          resource: resource
        )
        
        # Remove tenant attribute from attributes that will go in changeset
        clean_attrs = Map.delete(attributes, tenant_attr)
        
        {:ok, tenant_value, clean_attrs}
        
      :context ->
        # Context-based multitenancy is handled differently and not through attributes
        Log.debug(
          fn ->
            "multitenancy_detected resource=#{inspect(resource)} strategy=:context (no attribute extraction needed)"
          end,
          component: :multitenancy,
          resource: resource
        )
        
        {:ok, nil, attributes}
        
      nil ->
        # No multitenancy configured
        Log.debug(
          fn ->
            "no_multitenancy resource=#{inspect(resource)}"
          end,
          component: :multitenancy,
          resource: resource
        )
        
        {:ok, nil, attributes}
    end
  end

  @doc """
  Checks if a resource has multitenancy configured.
  
  ## Examples
  
      iex> has_multitenancy?(MyApp.Post)
      true
      
      iex> has_multitenancy?(MyApp.Blog)
      false
  """
  @spec has_multitenancy?(module()) :: boolean()
  def has_multitenancy?(resource) do
    Ash.Resource.Info.multitenancy_strategy(resource) != nil
  end

  @doc """
  Checks if a resource uses attribute-based multitenancy.
  
  ## Examples
  
      iex> has_attribute_multitenancy?(MyApp.Post)
      true
      
      iex> has_attribute_multitenancy?(MyApp.Blog)
      false
  """
  @spec has_attribute_multitenancy?(module()) :: boolean()
  def has_attribute_multitenancy?(resource) do
    Ash.Resource.Info.multitenancy_strategy(resource) == :attribute
  end

  @doc """
  Gets the multitenancy strategy for a resource.
  
  Returns `:attribute`, `:context`, or `nil`.
  """
  @spec multitenancy_strategy(module()) :: :attribute | :context | nil
  def multitenancy_strategy(resource) do
    Ash.Resource.Info.multitenancy_strategy(resource)
  end

  @doc """
  Gets the tenant attribute name for a resource with attribute-based multitenancy.
  
  Returns `nil` if the resource doesn't use attribute-based multitenancy.
  """
  @spec tenant_attribute(module()) :: atom() | nil
  def tenant_attribute(resource) do
    if has_attribute_multitenancy?(resource) do
      Ash.Resource.Info.multitenancy_attribute(resource)
    else
      nil
    end
  end

  @doc """
  Builds create options with tenant if needed.
  
  Takes existing options and adds the tenant option if a tenant value is provided.
  """
  @spec add_tenant_to_opts(keyword(), any() | nil) :: keyword()
  def add_tenant_to_opts(opts, nil), do: opts
  def add_tenant_to_opts(opts, tenant_value) do
    Log.debug(
      fn ->
        "adding_tenant_to_opts tenant=#{inspect(tenant_value)}"
      end,
      component: :multitenancy
    )
    
    Keyword.put(opts, :tenant, tenant_value)
  end
end