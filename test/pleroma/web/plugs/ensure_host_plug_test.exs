defmodule Pleroma.Web.Plugs.EnsureHostPlugTest do
  use Pleroma.Web.ConnCase, async: false
  alias Pleroma.Web.Plugs.EnsureHostPlug

  import Plug.Conn

  describe "requires a host header that matches our server" do
    setup do
      conn = build_conn(:get, "/doesntmatter")

      [conn: conn]
    end

    test "rejects a request where no host value is present", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, nil)
        |> EnsureHostPlug.call(%{})

      assert conn.halted == true
      assert conn.status == 400
      assert conn.state == :sent
      assert conn.resp_body == "Host header not present"
    end

    test "rejects a request where the host value does not match", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "oops-not-us.info")
        |> EnsureHostPlug.call(%{})

      assert conn.halted == true
      assert conn.status == 400
      assert conn.state == :sent
      assert conn.resp_body == "Host header does not match"
    end

    test "rejects a request where the port value does not match", %{conn: conn} do
      host = Pleroma.Web.Endpoint.host()

      conn =
        conn
        |> Map.put(:host, "#{host}:9")
        |> EnsureHostPlug.call(%{})

      assert conn.halted == true
      assert conn.status == 400
      assert conn.state == :sent
      assert conn.resp_body == "Host header does not match"
    end

    test "accepts a request where the hostname matches and there is no port", %{conn: conn} do
      host = Pleroma.Web.Endpoint.host()

      conn =
        conn
        |> Map.put(:host, host)
        |> EnsureHostPlug.call(%{})

      assert conn.halted == false
    end

    test "accepts a request where the hostname matches, with a port", %{conn: conn} do
      %{host: host, port: port} = URI.parse(Pleroma.Web.Endpoint.url())

      conn =
        conn
        |> Map.put(:host, "#{host}:#{port}")
        |> EnsureHostPlug.call(%{})

      assert conn.halted == false
    end
  end
end
