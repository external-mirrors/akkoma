defmodule Pleroma.HTML.Scrubbers.MediaProxy do
  @behaviour Pleroma.HTML.Scrubbers.Behaviour

  @impl true
  def extensions(), do: []

  def transform(html) do
    {:ok, doc} = MDEx.parse_fragment(html)

    selector = fn
      %MDEx.Image{} -> true
      _ -> false
    end

    update_in(
      doc,
      [:document, Access.key!(:nodes), Access.all(), selector],
      fn %MDEx.Image{
           url: url
         } = node ->
        Map.put(node, :url, Pleroma.Web.MediaProxy.url(url))
      end
    )
    # this should already be safe
    |> MDEx.to_html!(render: [unsafe: true])
  end

  @impl true
  def sanitize_config(), do: false
end
