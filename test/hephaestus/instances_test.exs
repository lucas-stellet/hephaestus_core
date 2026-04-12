defmodule Hephaestus.InstancesTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Instances
  alias Hephaestus.Instances.Tracker

  setup do
    on_exit(fn ->
      for pid <- Registry.select(Hephaestus.Instances.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}]) do
        Process.exit(pid, :kill)
      end

      Process.sleep(10)
    end)

    :ok
  end

  describe "lookup!/0 with no registrations" do
    test "raises when no Hephaestus instance is registered" do
      assert_raise RuntimeError, ~r/No Hephaestus instance running/, fn ->
        Instances.lookup!()
      end
    end
  end

  describe "Tracker registration" do
    test "registers module on start_link" do
      {:ok, _pid} = Tracker.start_link(MyApp.TestHephaestus)

      assert Instances.lookup!() == MyApp.TestHephaestus
    end
  end

  describe "lookup!/0 with single registration" do
    test "returns the registered module" do
      {:ok, _pid} = Tracker.start_link(MyApp.SingleInstance)

      assert Instances.lookup!() == MyApp.SingleInstance
    end
  end

  describe "lookup!/0 with multiple registrations" do
    test "raises listing all registered modules" do
      {:ok, _pid1} = Tracker.start_link(MyApp.InstanceA)
      {:ok, _pid2} = Tracker.start_link(MyApp.InstanceB)

      assert_raise RuntimeError, ~r/Multiple Hephaestus instances/, fn ->
        Instances.lookup!()
      end
    end
  end

  describe "auto-deregistration" do
    test "deregisters when tracker process is killed" do
      {:ok, pid} = Tracker.start_link(MyApp.Ephemeral)
      assert Instances.lookup!() == MyApp.Ephemeral

      Process.exit(pid, :kill)
      Process.sleep(50)

      assert_raise RuntimeError, ~r/No Hephaestus instance running/, fn ->
        Instances.lookup!()
      end
    end

    test "deregisters when tracker process stops normally" do
      {:ok, pid} = Tracker.start_link(MyApp.Graceful)
      assert Instances.lookup!() == MyApp.Graceful

      GenServer.stop(pid, :normal)
      Process.sleep(50)

      assert_raise RuntimeError, ~r/No Hephaestus instance running/, fn ->
        Instances.lookup!()
      end
    end
  end
end
