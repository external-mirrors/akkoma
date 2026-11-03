defmodule Pleroma.HTML.Scrubbers.LinksOnly do
  @behaviour Pleroma.HTML.Scrubbers

  @impl true
  def extensions(), do: []

  @impl true
  def transform(html), do: html

  @impl true
  def sanitize_config() do
    [
      tags: ["a"],
      tag_attributes: %{
        "a" => ["href", "name"]
      },
      tag_attribute_values: %{
        "a" => %{
          "rel" => [
            "tag",
            "nofollow",
            "noopener",
            "noreferrer",
            "me",
            "ugc",
            "tag ugc",
            "ugc tag"
          ]
        }
      }
    ]
  end
end
