defmodule HephaestusTest do
  use ExUnit.Case, async: false

  defmodule DefaultEntry do
    use Hephaestus
  end

  test "use Hephaestus configures default runtime adapters" do
    {:ok, _pid} = start_supervised(DefaultEntry)

    assert Process.whereis(DefaultEntry.Registry) != nil
    assert Process.whereis(DefaultEntry.DynamicSupervisor) != nil
    assert Process.whereis(DefaultEntry.TaskSupervisor) != nil
    assert Process.whereis(DefaultEntry.Storage) != nil
  end
end
