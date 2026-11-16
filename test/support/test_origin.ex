defmodule LocalizeCacheProbe.TestOrigin do
  @moduledoc false

  # A scripted origin for tests. It answers each connection from a list
  # of responses or from a handler function, and sends the test process
  # the text of every request it received, so a test can assert on both
  # sides.

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  @doc """
  Starts an origin that sends `responses` in order, one for each request,
  and a 500 once they run out.

  Returns the base URL. The test process receives `{:request, text}` for
  each request.
  """
  def start(responses) when is_list(responses) do
    start(responses, &next_response/2)
  end

  @doc """
  Starts an origin that answers each request with `handler`.

  The handler is called with the text of the request and the state, and
  returns `{response, state}`.
  """
  def start(state, handler) when is_function(handler, 2) do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        reuseaddr: true,
        packet: :raw,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listen)
    test = self()

    # A test may start several origins, so each needs an id of its own.
    task = {Task, fn -> serve(listen, state, handler, test) end}
    start_supervised!(Supervisor.child_spec(task, id: make_ref()))

    "http://127.0.0.1:#{port}"
  end

  @doc """
  Builds the text of a response from a status, header lines and a body.
  """
  def response(status, headers, body \\ "") do
    lines = Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)

    IO.iodata_to_binary([
      "HTTP/1.1 #{status} OK\r\n",
      lines,
      "Content-Length: #{byte_size(body)}\r\n",
      "Connection: close\r\n\r\n",
      body
    ])
  end

  defp next_response(_request, [response | rest]) do
    {response, rest}
  end

  defp next_response(_request, []) do
    {response(500, []), []}
  end

  # The listening socket belongs to the test process, so it closes when
  # the test ends and the loop stops.
  defp serve(listen, state, handler, test) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} -> serve(listen, answer(socket, state, handler, test), handler, test)
      {:error, _closed} -> :ok
    end
  end

  defp answer(socket, state, handler, test) do
    request = read_request(socket, "")
    send(test, {:request, request})
    {response, state} = handler.(request, state)
    :ok = :gen_tcp.send(socket, response)
    :ok = :gen_tcp.close(socket)

    state
  end

  defp read_request(socket, received) do
    if String.contains?(received, "\r\n\r\n") do
      received
    else
      {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
      read_request(socket, received <> data)
    end
  end
end
