defmodule Pleroma.HTML.Scrubbers.StripTags do
  @behaviour Pleroma.HTML.Scrubbers.Behaviour

  @impl true
  def extensions() do
    []
  end

  @impl true
  def transform(html), do: html

  @impl true
  def sanitize_config() do
    [
      tags: []
    ]
  end
end
