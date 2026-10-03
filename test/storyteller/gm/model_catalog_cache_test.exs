defmodule Storyteller.GM.ModelCatalogCacheTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.ModelCatalogCache

  test "stores successful catalogs by subject and ignores empty catalogs" do
    cache = start_supervised!({ModelCatalogCache, [name: nil]}, id: make_ref())
    models = [%{slug: "model-a", display_name: "Model A"}]

    assert :miss = ModelCatalogCache.get("account-a", cache)
    assert :ok = ModelCatalogCache.put("account-a", models, cache)
    assert {:ok, ^models} = ModelCatalogCache.get("account-a", cache)
    assert :miss = ModelCatalogCache.get("account-b", cache)

    assert :ok = ModelCatalogCache.put("account-b", [], cache)
    assert :miss = ModelCatalogCache.get("account-b", cache)
  end

  test "expires entries and bounds the number of retained account catalogs" do
    cache =
      start_supervised!({ModelCatalogCache, [name: nil, ttl_ms: 25]}, id: make_ref())

    models = [%{slug: "fixture-model", display_name: "Fixture Model"}]
    assert :ok = ModelCatalogCache.put("expiring-account", models, cache)
    Process.sleep(40)
    assert :miss = ModelCatalogCache.get("expiring-account", cache)

    capacity_cache = start_supervised!({ModelCatalogCache, [name: nil]}, id: make_ref())

    for index <- 1..17 do
      assert :ok = ModelCatalogCache.put("account-#{index}", models, capacity_cache)
    end

    assert :miss = ModelCatalogCache.get("account-1", capacity_cache)
    assert {:ok, ^models} = ModelCatalogCache.get("account-17", capacity_cache)
  end
end
