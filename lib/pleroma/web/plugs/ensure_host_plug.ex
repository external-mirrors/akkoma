# Akkoma: Magically expressive social media
# Copyright Â© 2022-2026 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.EnsureHostPlug do
  @moduledoc """
  Ensures the request has a Host header, and that it matches this server
  """
  import Plug.Conn

  alias Pleroma.Web.Endpoint

  def init(options) do
    options
  end

  def call(conn, _) do
    %{host: host} = conn

    handle_host_header(host, conn)
  end

  defp handle_host_header(value, conn) when is_binary(value) do
    # this header should match our currently configured endpoint
    # and _may or may not_ include a port.
    # it's technically possible for a `host` to contain colons, so we can't split naively. best to rely on URI here.
    # no protocol so we don't get any default port shennanigans
    uri = URI.parse("//#{value}")
    our_uri = URI.parse(Endpoint.url())

    if host_matches(uri, our_uri) do
      conn
    else
      conn
      |> resp(400, "Host header does not match")
      |> halt()
    end
  end

  defp handle_host_header(_, conn) do
    conn
    |> resp(400, "Host header not present")
    |> halt()
  end

  defp case_insensitive_matches?(a, b) do
    String.equivalent?(
      String.downcase(a), String.downcase(b)
    )
  end

  # if the host header does not specify a port, match against our host only
  defp host_matches(%URI{host: inbound_host, port: nil}, %URI{host: our_host}) do
    case_insensitive_matches?(inbound_host, our_host)
  end

  defp host_matches(%URI{host: inbound_host, port: inbound_port}, %URI{host: our_host, port: our_port}) do
    (inbound_port == our_port) && case_insensitive_matches?(inbound_host, our_host)
  end
end
