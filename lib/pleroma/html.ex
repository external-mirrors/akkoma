# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTML do
  # Scrubbers are compiled on boot so they can be configured in OTP releases
  #  @on_load :compile_scrubbers

  defp get_scrubbers(scrubber) when is_atom(scrubber), do: [scrubber]
  defp get_scrubbers(scrubbers) when is_list(scrubbers), do: scrubbers
  defp get_scrubbers(_), do: [Pleroma.HTML.Scrubbers.Default]

  def get_scrubbers do
    Pleroma.Config.get([:markup, :scrub_policy])
    |> get_scrubbers
  end

  def filter_tags(nil, _), do: ""

  def filter_tags(html, nil) do
    filter_tags(html, get_scrubbers())
  end

  def filter_tags(html, scrubbers) when is_list(scrubbers) do
    Enum.reduce(scrubbers, html, fn scrubber, html ->
      filter_tags(html, scrubber)
    end)
  end

  def filter_tags(html, scrubber) do
    MDEx.safe_html(html, sanitize: scrubber.sanitize_config(), escape: [content: false])
    |> scrubber.transform()
  end

  def filter_tags(html), do: filter_tags(html, nil)

  def strip_tags(html) do
    filter_tags(html, Pleroma.HTML.Scrubbers.StripTags)
  end

  def ensure_scrubbed_html(
        content,
        scrubbers,
        fake,
        callback
      ) do
    content =
      content
      |> filter_tags(scrubbers)
      |> callback.()

    if fake do
      {:ignore, content}
    else
      {:commit, content}
    end
  end

  @spec extract_first_external_url_from_object(Pleroma.Object.t()) :: String.t() | nil
  def extract_first_external_url_from_object(%{data: %{"content" => content}})
      when is_binary(content) do
    content
    |> Floki.parse_fragment!()
    |> Floki.find("a:not(.mention,.hashtag,.attachment,[rel~=\"tag\"])")
    |> Enum.take(1)
    |> Floki.attribute("href")
    |> Enum.at(0)
  end

  def extract_first_external_url_from_object(_), do: nil
end
