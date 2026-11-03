defmodule Pleroma.HTML.Scrubbers.Behaviour do
  @callback extensions() :: [atom()]

  @callback sanitize_config() :: Keyword.t()

  @callback transform(String.t()) :: String.t()
end
