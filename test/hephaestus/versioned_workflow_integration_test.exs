defmodule Hephaestus.VersionedWorkflowIntegrationTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  setup do
    start_supervised!(Hephaestus.Test.Hephaestus)
    :ok
  end

  describe "version resolution chain" do
    test "default resolution uses compile current (V2)" do
      {:ok, id} =
        Hephaestus.Test.Hephaestus.start_instance(
          Hephaestus.Test.Versioned,
          %{},
          id: "testversioned::default"
        )

      {:ok, instance} = get_instance(id)
      assert instance.workflow == Hephaestus.Test.Versioned.V2
      assert instance.workflow_version == 2
    end

    test "opts[:version] overrides to V1" do
      {:ok, id} =
        Hephaestus.Test.Hephaestus.start_instance(
          Hephaestus.Test.Versioned,
          %{},
          id: "testversioned::v1override",
          version: 1
        )

      {:ok, instance} = get_instance(id)
      assert instance.workflow == Hephaestus.Test.Versioned.V1
      assert instance.workflow_version == 1
    end

    test "raises ArgumentError for non-existent version" do
      assert_raise ArgumentError, fn ->
        Hephaestus.Test.Hephaestus.start_instance(Hephaestus.Test.Versioned, %{},
          id: "testversioned::bad",
          version: 99
        )
      end
    end

    test "version_for/2 callback resolves version" do
      {:ok, id} =
        Hephaestus.Test.Hephaestus.start_instance(
          Hephaestus.Test.VersionedWithCallback,
          %{},
          id: "testversionedcb::forcev1",
          force_v1: true
        )

      {:ok, instance} = get_instance(id)
      assert instance.workflow_version == 1
    end

    test "version_for/2 returning nil falls to compile default" do
      {:ok, id} =
        Hephaestus.Test.Hephaestus.start_instance(
          Hephaestus.Test.VersionedWithCallback,
          %{},
          id: "testversionedcb::nilcb"
        )

      {:ok, instance} = get_instance(id)
      assert instance.workflow_version == 2
    end

    test "non-versioned workflow resolves to version 1" do
      {:ok, id} =
        Hephaestus.Test.Hephaestus.start_instance(
          Hephaestus.Test.V2.LinearWorkflow,
          %{},
          id: "testv2::nonversioned"
        )

      {:ok, instance} = get_instance(id)
      assert instance.workflow == Hephaestus.Test.V2.LinearWorkflow
      assert instance.workflow_version == 1
    end
  end

  defp get_instance(id) do
    ETSStorage.get(Hephaestus.Test.Hephaestus.Storage, id)
  end
end
