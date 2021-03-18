defmodule ArgosAPITest do
  use ExUnit.Case
  doctest ArgosAPI

  test "greets the world" do
    assert ArgosAPI.hello() == :world
  end
end
