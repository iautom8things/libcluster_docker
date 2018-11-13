defmodule ClusterDocker.Strategy.Service do
  use GenServer
  use Cluster.Strategy
  import Cluster.Logger

  alias Cluster.Strategy.State

  @default_polling_interval 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # libcluster ~> 3.0
  @impl GenServer
  def init([%State{} = state]) do
    state = state |> Map.put(:meta, MapSet.new())

    {:ok, state, 0}
  end

  # libcluster ~> 2.0
  def init(opts) do
    state = %State{
      topology: Keyword.fetch!(opts, :topology),
      connect: Keyword.fetch!(opts, :connect),
      disconnect: Keyword.fetch!(opts, :disconnect),
      list_nodes: Keyword.fetch!(opts, :list_nodes),
      config: Keyword.fetch!(opts, :config),
      meta: MapSet.new([])
    }

    {:ok, state, 0}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    handle_info(:load, state)
  end

  def handle_info(
        :load,
        %State{
          topology: topology,
          connect: connect,
          disconnect: disconnect,
          list_nodes: list_nodes
        } = state
      ) do
    case get_nodes(state) do
      {:ok, new_nodelist} ->
        added = MapSet.difference(new_nodelist, state.meta)
        removed = MapSet.difference(state.meta, new_nodelist)

        new_nodelist =
          case Cluster.Strategy.disconnect_nodes(
                 topology,
                 disconnect,
                 list_nodes,
                 MapSet.to_list(removed)
               ) do
            :ok ->
              new_nodelist

            {:error, bad_nodes} ->
              # Add back the nodes which should have been removed, but which couldn't be for some reason
              Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
                MapSet.put(acc, n)
              end)
          end

        new_nodelist =
          case Cluster.Strategy.connect_nodes(
                 topology,
                 connect,
                 list_nodes,
                 MapSet.to_list(added)
               ) do
            :ok ->
              new_nodelist

            {:error, bad_nodes} ->
              # Remove the nodes which should have been added, but couldn't be for some reason
              Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
                MapSet.delete(acc, n)
              end)
          end

        Process.send_after(
          self(),
          :load,
          Keyword.get(state.config, :polling_interval, @default_polling_interval)
        )

        {:noreply, %{state | :meta => new_nodelist}}

      _ ->
        Process.send_after(
          self(),
          :load,
          Keyword.get(state.config, :polling_interval, @default_polling_interval)
        )

        {:noreply, state}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  @spec get_nodes(State.t()) :: {:ok, [atom()]} | {:error, []}
  def get_nodes(%{config: config}) do
    app_prefix = Keyword.get(config, :app_prefix, "app")

    containers = ClusterDocker.filter(["Labels", "maintainer"], fn x -> not is_nil(x) end)

    response =
      containers
      |> Enum.map(&get_in(&1, ["Config", "Hostname"]))
      |> Enum.map(&:"#{app_prefix}@#{&1}")

    {:ok, MapSet.new(response)}
  end
end
