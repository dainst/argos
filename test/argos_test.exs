defmodule ArgosTest do
  use ExUnit.Case
  doctest Argos

  test "greets the world" do
    assert Argos.hello() == :world
  end
end
