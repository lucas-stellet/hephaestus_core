defmodule Hephaestus.Core.Workflow.UniqueTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Workflow.Unique

  describe "new!/1 happy path" do
    test "creates struct with key and default scope" do
      # Arrange
      opts = [key: "blueprintid"]

      # Act
      unique = Unique.new!(opts)

      # Assert
      assert %Unique{key: "blueprintid", scope: :workflow} = unique
    end

    test "creates struct with explicit scope" do
      # Arrange
      opts = [key: "orderid", scope: :global]

      # Act
      unique = Unique.new!(opts)

      # Assert
      assert %Unique{key: "orderid", scope: :global} = unique
    end
  end

  describe "new!/1 valid scopes" do
    test "accepts scope :workflow" do
      # Arrange / Act / Assert
      assert %Unique{scope: :workflow} = Unique.new!(key: "k", scope: :workflow)
    end

    test "accepts scope :version" do
      # Arrange / Act / Assert
      assert %Unique{scope: :version} = Unique.new!(key: "k", scope: :version)
    end

    test "accepts scope :global" do
      # Arrange / Act / Assert
      assert %Unique{scope: :global} = Unique.new!(key: "k", scope: :global)
    end

    test "accepts scope :none" do
      # Arrange / Act / Assert
      assert %Unique{scope: :none} = Unique.new!(key: "k", scope: :none)
    end
  end

  describe "new!/1 key validation" do
    test "rejects uppercase letters in key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "Blueprint") end
    end

    test "rejects hyphens in key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "blueprint-id") end
    end

    test "rejects underscores in key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "blueprint_id") end
    end

    test "rejects non-string key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must be a string/,
                   fn -> Unique.new!(key: 123) end
    end

    test "rejects atom key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must be a string/,
                   fn -> Unique.new!(key: :blueprintid) end
    end

    test "rejects empty string key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "") end
    end
  end

  describe "new!/1 scope validation" do
    test "rejects invalid scope atom" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique scope must be one of/,
                   fn -> Unique.new!(key: "ok", scope: :invalid) end
    end

    test "rejects string scope" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique scope must be one of/,
                   fn -> Unique.new!(key: "ok", scope: "workflow") end
    end
  end

  describe "new!/1 missing key" do
    test "raises when key is not provided" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        Unique.new!(scope: :workflow)
      end
    end
  end
end
