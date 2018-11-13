defmodule ClusterDockerTest do
  use ExUnit.Case
  doctest ClusterDocker

  test "greets the world" do
    assert ClusterDocker.hello() == :world
  end
end
