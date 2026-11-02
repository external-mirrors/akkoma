defmodule Pleroma.HTML.Scrubbers.TwitterText do
  @behaviour Pleroma.HTML.Scrubbers.Behaviour

  @impl
  def extensions(), do: []

  @impl true
  def transform(html), do: html

  @impl
  def sanitize_config() do
    [
      add_tags: ["br", "p"],
      add_tag_attributes: %{
        "a" => ["href", "data-user", "data-tag", "name", "title"]
      },
      add_allowed_classes: %{
        "a" => ["hashtag", "u-url", "mention", "hashtag"],
        "span" => ["h-card"]
      },
      add_allowed_attribute_values: %{
        "rel" => ["tag", "nofollow", "noopener", "noreferrer", "tag", "ugc", "tag ugc", "ugc tag"]
      }
    ]
  end
end
