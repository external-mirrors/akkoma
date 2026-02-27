# Akkoma: Magically expressive social media
# Copyright © 2026 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule HttpRequestMockMacros do
  defmacro mock_masto_webfinger(url, nick, webfinger_domain, ap_domain \\ nil, ap_id \\ nil) do
    quote do
      def get(unquote(url) = url, _, _, _) do
        webfinger_response_masto(
          url,
          unquote(nick),
          unquote(webfinger_domain),
          unquote(ap_domain),
          unquote(ap_id)
        )
      end
    end
  end
end
