defmodule Pleroma.Web.ActivityPub.MRF.TrackingLinkPolicy do
  alias Pleroma.Object

  @moduledoc "Rewrite tracking links to exclude their tracking parameters"
  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  # stolen directly from formatter
  @link_regex ~r"((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+"ui
  
  # permit timestamp
  @youtube %{
    allowed_params: ["v", "t"],
    domains: "youtube.com, "youtu.be", "www.youtube.com"
  }
  @youtube_allowed_params ["v", "t"]

  def history_awareness, do: :auto

  def filter(%{"content" => content} = object) do
    # find all links
    links = Regex.scan(@link_regex, content)
    {:ok, object}
  end

  def filter(object), do: {:ok, object}

  defp maybe_rewrite_link(link) do
    url = URI.parse(link)
    maybe_rewrite_link(url, @youtube)
  end

  defp maybe_rewrite_link(link, policy) do
    if Enum.any?(policy.domains, fn domain -> link.host == domain end) do
      # filter out params
      link
    else
      link
    end
  end

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
