defmodule Hephaestus.UniquenessTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Uniqueness
  alias Hephaestus.Workflow.Unique

  describe "build_id/2" do
    test "constructs composite ID with key and value" do
      unique = %Unique{key: "blueprintid", scope: :workflow}

      id = Uniqueness.build_id(unique, "abc123")

      assert id == "blueprintid::abc123"
    end

    test "constructs composite ID with UUID value" do
      unique = %Unique{key: "blueprintid", scope: :workflow}
      uuid = "550e8400-e29b-41d4-a716-446655440000"

      id = Uniqueness.build_id(unique, uuid)

      assert id == "blueprintid::550e8400-e29b-41d4-a716-446655440000"
    end

    test "raises on invalid value" do
      unique = %Unique{key: "bp", scope: :workflow}

      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.build_id(unique, "ABC-invalid")
      end
    end
  end

  describe "build_id_with_suffix/2" do
    test "constructs composite ID with random suffix" do
      unique = %Unique{key: "userid", scope: :none}

      id = Uniqueness.build_id_with_suffix(unique, "abc123")

      assert String.starts_with?(id, "userid::abc123::")
      [_key, _value, suffix] = String.split(id, "::")
      assert byte_size(suffix) == 8
      assert Regex.match?(~r/^[a-f0-9]{8}$/, suffix)
    end

    test "generates unique suffixes on each call" do
      unique = %Unique{key: "userid", scope: :none}

      id1 = Uniqueness.build_id_with_suffix(unique, "abc123")
      id2 = Uniqueness.build_id_with_suffix(unique, "abc123")

      refute id1 == id2
    end
  end

  describe "validate_value!/1" do
    test "accepts lowercase alphanumeric" do
      assert Uniqueness.validate_value!("abc123") == :ok
    end

    test "accepts valid UUID with hyphens" do
      assert Uniqueness.validate_value!("550e8400-e29b-41d4-a716-446655440000") == :ok
    end

    test "rejects uppercase letters" do
      assert_raise ArgumentError, ~r/invalid id value: "ABC"/, fn ->
        Uniqueness.validate_value!("ABC")
      end
    end

    test "rejects hyphens outside UUID format" do
      assert_raise ArgumentError, ~r/invalid id value: "abc-123"/, fn ->
        Uniqueness.validate_value!("abc-123")
      end
    end

    test "rejects underscores" do
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("abc_123")
      end
    end

    test "rejects double colon separator" do
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("abc::123")
      end
    end

    test "rejects spaces" do
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("abc 123")
      end
    end

    test "rejects empty string" do
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("")
      end
    end
  end

  describe "extract_value/1" do
    test "extracts value from simple composite ID" do
      id = "blueprintid::abc123"

      value = Uniqueness.extract_value(id)

      assert value == "abc123"
    end

    test "extracts value from suffixed composite ID" do
      id = "userid::abc123::a1b2c3d4"

      value = Uniqueness.extract_value(id)

      assert value == "abc123"
    end

    test "extracts UUID value from composite ID" do
      id = "blueprintid::550e8400-e29b-41d4-a716-446655440000"

      value = Uniqueness.extract_value(id)

      assert value == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "raises on malformed ID without separator" do
      assert_raise ArgumentError, ~r/invalid unique id format/, fn ->
        Uniqueness.extract_value("noseparator")
      end
    end
  end
end
