defmodule Queue do
  @moduledoc """
  Documentation for Queue.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_arg) do
    {:ok, {:queue.new(), :queue.new()}}
  end

  def push(q, val) do
    GenServer.call(q, {:push, val})
  end

  def pop(q, timeout \\ :infinity) do
    GenServer.call(q, :pop, timeout)
  end

  def handle_call({:push, val}, from, {state, {[], []} = waiters}) do
    new_state = :queue.in(val, state)
    {:reply, :ok, {new_state, waiters}} |> IO.inspect
  end

  def handle_call({:push, val}, from, {state, waiters}) do
    {{:value, waiter}, new_waiters} = :queue.out(waiters)
    # require IEx; IEx.pry
    GenServer.reply(waiter, val)
    {:noreply, {state, new_waiters}} |> IO.inspect
  end


  def handle_call(:pop, from, {state, waiters}) do
    case :queue.out(state) do
      {{:value, val}, new_state} -> {:reply, val, {new_state, waiters}}
      {:empty, new_state} -> wait_for_value(from, {new_state, waiters})
    end
  end

  defp wait_for_value(waiter, {state, waiters}) do
    {:noreply, {state, :queue.in(waiter, waiters)}}
  end

  def demo_t do
    {:ok, q} = Queue.start_link
    spawn(fn ->
      IO.puts("task start")
      Process.sleep(2050)
      IO.puts("task sleep finish")
      Queue.push(q, :foo)
    end)

    GenServer.call(q, :pop)
  end
end

# with a timeout:
#
# ----------*
