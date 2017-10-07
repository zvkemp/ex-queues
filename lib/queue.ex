defmodule Queue do
  @moduledoc """
  blocking FIFO queue agent (wrapper around erlang's :queue
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  @impl true
  def init(_arg) do
    {:ok, {:queue.new(), :queue.new()}}
  end

  def push(q, val) do
    GenServer.call(q, {:push, val})
  end

  def pop(q, timeout \\ :infinity) do
    case GenServer.call(q, :pop, timeout) do
      {:ok, val} -> val
      {:wait, ref} ->
        receive do
          {^ref, val} -> val
        after
          timeout -> unregister_pending(q, ref)
                     {:error, :timeout}
        end
    end
  end

  def stream(q) do
    Stream.repeatedly(fn -> Queue.pop(q) end)
  end

  def unregister_pending(q, ref) do
    GenServer.call(q, {:unregister_pending, ref})
  end

  @impl true
  def handle_call({:unregister_pending, ref}, {pid, _}, {queue, pending}) do
    # Filters on original call ref and same pid
    new_pending = :queue.filter(fn
      {^pid, ^ref} -> false
      _ -> true end,
      pending)
    {:reply, :ok, {queue, new_pending}}
  end

  # Push, no one is waiting
  @impl true
  def handle_call({:push, val}, _from, {state, {[], []} = pending}) do
    new_state = :queue.in(val, state)
    {:reply, :ok, {new_state, pending}}
  end

  # Push, and notify first pending pop
  @impl true
  def handle_call({:push, val}, _from, {state, pending}) do
    {{:value, {pid, ref}}, new_pending} = :queue.out(pending)
    Process.send(pid, {ref, val}, [])
    {:reply, :ok, {state, new_pending}}
  end

  @impl true
  def handle_call(:pop, from, {state, pending}) do
    case :queue.out(state) do
      {{:value, val}, new_state} -> {:reply, {:ok, val}, {new_state, pending}}
      {:empty, new_state} -> wait_for_value(from, {new_state, pending})
    end
  end

  defp wait_for_value({_pid, ref} = from, {state, pending}) do
    {:reply, {:wait, ref}, {state, :queue.in(from, pending)}}
  end

  # NOTE: adding this as an additional push mechanism to support sending messages generically;
  # has been useful for dev and testing environments.
  @impl true
  def handle_info({:push, val}, state) do
    {:reply, :ok, new_state} = handle_call({:push, val}, nil, state)
    {:noreply, new_state}
  end
end
