defmodule Pleroma.Web.ActivityPub.MRF.TrackingLinkPolicy do
  @moduledoc "Rewrite tracking links to exclude their tracking parameters"
  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  # stolen directly from formatter
  @link_regex ~r"((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+"ui

  # permit timestamp
  @youtube %{
    allowed_params: ["v", "t", "list", "index", "start_radio"],
    domains: ["youtube.com", "youtu.be"]
  }

  @impl true
  def history_awareness, do: :auto

  @impl true
  def filter(%{"type" => type, "object" => %{"content" => content} = object} = activity)
      when type in ["Create", "Update"] do
    # find all links
    links =
      Regex.scan(@link_regex, content, capture: :first)
      |> Enum.map(&Kernel.hd/1)

    new_content =
      Enum.reduce(links, content, fn link, cont ->
        String.replace(cont, link, maybe_rewrite_link(link))
      end)

    {:ok, %{activity | "object" => Map.put(object, "content", new_content)}}
  end

  def filter(object), do: {:ok, object}

  defp maybe_rewrite_link(link) do
    url = URI.parse(link)
    maybe_rewrite_link(url, @youtube, Pleroma.Config.get([:mrf_tracking_link, :youtube]))
  end

  def maybe_rewrite_link(link, _policy, false), do: URI.to_string(link)
  def maybe_rewrite_link(link, policy, true) do
    # either the exact domain or an exact subdomain
    if Enum.any?(policy.domains, fn domain ->
         link.host == domain || String.ends_with?(link.host, ".#{domain}")
       end) do
      # filter out params
      params =
        link.query
        |> URI.decode_query()
        |> Enum.filter(fn {k, _v} -> Enum.member?(policy.allowed_params, k) end)

      %{
        link
        | query:
            if Enum.empty?(params) do
              nil
            else
              URI.encode_query(params)
            end
      }
    else
      link
    end
    |> URI.to_string()
  end

  @impl true
  def describe, do: {:ok, %{}}

  @impl true
  def config_description do
    %{
      key: :mrf_tracking_link,
      related_policy: "Pleroma.Web.ActivityPub.MRF.TrackingLinkPolicy",
      label: "Tracking Link Policy",
      description: @moduledoc,
      children: [
        %{
          key: :youtube,
          type: :boolean,
          description: "Rewrite youtube links?"
        }
      ]
    }
  end
end
