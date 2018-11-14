defmodule ClusterDocker do
  @moduledoc """
  Documentation for ClusterDocker.
  """

  @doc """
  Hello world.

  ## Examples

      iex> ClusterDocker.hello()
      :world

  """
  def hello do
    :world
  end

  def filter(keys, filterer) do
    config = Docker.config()

    config
    |> Docker.containers()
    |> Enum.filter(&get_container_with(&1, keys, filterer))
    |> Enum.filter(&running?/1)
    |> Enum.map(&Map.get(&1, "Id"))
    |> Enum.map(&Docker.container(config, &1))
  end

  def exists?(nil), do: false
  def exists?(_), do: true

  def get_container_with(container, keys, filterer) do
    container
    |> get_in(keys)
    |> filterer.()
  end

  defp running?(%{"State" => "running"}), do: true
  defp running?(_), do: false
end
