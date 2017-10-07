defmodule QueueTest do
  use ExUnit.Case, async: false
  doctest Queue

  test "basic sync usage" do
    {:ok, q} = Queue.start_link

    Queue.push(q, 1)
    Queue.push(q, 2)
    Queue.push(q, 3)
    assert Queue.pop(q) == 1
    assert Queue.pop(q) == 2
    Queue.push(q, 4)
    assert Queue.pop(q) == 3
    assert Queue.pop(q) == 4
  end

  test "with infinite pop timeout" do
    {:ok, q} = Queue.start_link

    spawn fn ->
      Process.sleep(200)
      Queue.push(q, :foo)
    end

    assert Queue.pop(q) == :foo
  end

  test "messages are preserved on pop timeout" do
    {:ok, q} = Queue.start_link

    spawn fn ->
      Process.sleep(300)
      Queue.push(q, :foo)
    end

    assert Queue.pop(q, 50) == {:error, :timeout}
    assert Queue.pop(q, 50) == {:error, :timeout}
    assert Queue.pop(q, 50) == {:error, :timeout}
    assert Queue.pop(q, 500) == :foo
  end

  test "streaming" do
    {:ok, q} = Queue.start_link
    Task.start fn ->
      Stream.interval(30)
      |> Stream.each(fn (i) -> Queue.push(q, i) end)
      |> Stream.take(10)
      |> Stream.run
    end

    assert (0..9) |> Enum.into([]) == Queue.stream(q) |> Enum.take(10)
  end

  test "multiple pending pops" do
    {:ok, q} = Queue.start_link
    tasks = Stream.repeatedly(fn ->
      :timer.sleep(15) # ensure order
      Task.async(fn -> Queue.pop(q) end)
    end)
    |> Enum.take(5)

    :timer.sleep(15 * 6) # ensure tasks have started

    # 10 processes are waiting on the queue
    {{[], []}, {pa, pb}} = :sys.get_state(q)
    pending = pa ++ pb
    assert Enum.count(pending) == 5

    for x <- (1..5), do: Queue.push(q, x)
    # order not guaranteed because of task synch issues
    assert (1..5) |> Enum.into([]) == tasks |> Enum.map(&Task.await/1)
  end

  test "dead pending pops" do
    {:ok, q} = Queue.start_link
    t1 = Task.async fn -> Queue.pop(q) end
    t2 = Task.async fn -> Queue.pop(q) end
    t3 = Task.async fn -> Queue.pop(q) end

    Task.shutdown(t1)
    :timer.sleep(15)

    Queue.push(q, 1)
    Queue.push(q, 2)
    Queue.push(q, 3)
    # first push is sent to t2
    assert 1 == t2 |> Task.await
    assert 2 == t3 |> Task.await
  end
end
