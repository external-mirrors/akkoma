# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# Copyright © 2026 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.WebFinger.Finger do
  @moduledoc """
  Used to query validated WebFinger data from remote hosts.
  """

  alias Pleroma.HTTP
  alias Pleroma.Object.Fetcher
  alias Pleroma.Web.XML

  require Jason
  require Logger

  @spec webfinger_from_xml(binary()) :: {:ok, map()} | nil
  defp webfinger_from_xml(body) do
    with {:ok, doc} <- XML.parse_document(body) do
      subject = XML.string_from_xpath("//Subject", doc)

      subscribe_address =
        ~s{//Link[@rel="http://ostatus.org/schema/1.0/subscribe"]/@template}
        |> XML.string_from_xpath(doc)

      ap_id_compat =
        ~s{//Link[@rel="self" and @type="application/activity+json"]/@href}
        |> XML.string_from_xpath(doc)

      ap_id_spec =
        ~s{//Link[@rel="self" and @type='application/ld+json; profile="https://www.w3.org/ns/activitystreams"']/@href}
        |> XML.string_from_xpath(doc)

      data = %{
        "subject" => subject,
        "subscribe_address" => subscribe_address,
        "ap_id" => ap_id_spec || ap_id_compat
      }

      {:ok, data}
    else
      _ -> {:error, :invalid_xml}
    end
  end

  defp webfinger_from_json(body) do
    with {:ok, doc} <- Jason.decode(body) do
      data =
        Enum.reduce(doc["links"], %{"subject" => doc["subject"]}, fn link, data ->
          case {link["type"], link["rel"]} do
            {"application/activity+json", "self"} ->
              Map.put(data, "ap_id", link["href"])

            {"application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"", "self"} ->
              Map.put(data, "ap_id", link["href"])

            {nil, "http://ostatus.org/schema/1.0/subscribe"} ->
              Map.put(data, "subscribe_address", link["template"])

            _ ->
              Logger.debug("Unhandled type: #{inspect(link["type"])}")
              data
          end
        end)

      {:ok, data}
    end
  end

  # discover webfinger domain delegation
  # (does NOT imply delgated-to domain agrees; only consent of domain doing the delegation!)
  defp get_template_from_xml(body) do
    xpath = "//Link[@rel='lrdd']/@template"

    with {:ok, doc} <- XML.parse_document(body),
         template when template != nil <- XML.string_from_xpath(xpath, doc) do
      {:ok, template}
    end
  end

  defp fetch_lrdd_template(domain) do
    # WebFinger is restricted to HTTPS - https://tools.ietf.org/html/rfc7033#section-9.1
    meta_url = "https://#{domain}/.well-known/host-meta"

    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           HTTP.Backoff.get(meta_url) do
      get_template_from_xml(body)
    else
      error ->
        Logger.warning("Can't find LRDD template in #{inspect(meta_url)}: #{inspect(error)}")
        {:error, :lrdd_not_found}
    end
  end

  # public for tests
  @cachex Pleroma.Config.get([:cachex, :provider], Cachex)
  def find_lrdd_template(domain) do
    @cachex.fetch!(:host_meta_cache, domain, fn _ ->
      {:commit, fetch_lrdd_template(domain)}
    end)
  rescue
    e -> {:error, "Cachex error: #{inspect(e)}"}
  end

  defp make_finger_uri(domain, resource, allow_delegation) do
    encoded_resource = URI.encode(resource)
    discovered_template = allow_delegation && find_lrdd_template(domain)

    case discovered_template do
      {:ok, template} ->
        # RFC 6415 LRDD (Link-based Resource Descriptor Documents) query endpoint
        String.replace(template, "{uri}", encoded_resource)

      _ ->
        # Canonical WebFinger endpoint from its own RFC 7033
        "https://#{domain}/.well-known/webfinger?resource=#{encoded_resource}"
    end
  end

  defp parse_finger_response(%{body: body, headers: headers}) do
    case List.keyfind(headers, "content-type", 0) do
      {_, content_type} ->
        case Plug.Conn.Utils.media_type(content_type) do
          {:ok, "application", subtype, _} when subtype in ~w(xrd+xml xml) ->
            webfinger_from_xml(body)

          {:ok, "application", subtype, _} when subtype in ~w(jrd+json json) ->
            webfinger_from_json(body)

          _ ->
            {:error, {:content_type, content_type}}
        end

      _ ->
        {:error, {:content_type, nil}}
    end
  end

  defp map_fetch_error_reason(%{status: code}) when code in [401, 403], do: :forbidden
  defp map_fetch_error_reason(%{status: 404}), do: :not_found
  defp map_fetch_error_reason(%{status: 410}), do: :deleted

  defp map_fetch_error_reason(%{status: code, headers: headers}) when is_integer(code),
    do: {:http_error, code, headers}

  defp map_fetch_error_reason(%Tesla.Env{} = env), do: {:http_error, :connect, env}

  defp finger_unverified_data(domain, resource, allow_delegation \\ true) do
    query_uri = make_finger_uri(domain, resource, allow_delegation)
    resp = HTTP.Backoff.get(query_uri, [{"accept", "application/xrd+xml,application/jrd+json"}])

    with {:ok, %{url: resolved_uri, status: status} = resp_data} when status in 200..299 <- resp,
         {_, true} <- {:redirect, allow_delegation || query_uri == resolved_uri},
         {_, {:ok, parsed_data}} <- {:parse, parse_finger_response(resp_data)} do
      resolved_domain = URI.parse(resolved_uri).host

      {:ok, resolved_domain, parsed_data}
    else
      {:ok, %Tesla.Env{} = env} -> {:error, map_fetch_error_reason(env)}
      {:redirect, _} -> {:error, :redirect}
      {:parse, {:error, _} = error} -> error
      {:error, _reason} = e -> e
    end
  end

  defp normalise_webfinger_handle("acct:" <> handle), do: handle
  defp normalise_webfinger_handle(handle) when is_binary(handle), do: handle

  defp parse_handle(handle) do
    case String.split(handle, "@", parts: 2) do
      [name, domain] -> {name, domain}
      [name] -> {name, nil}
      [] -> {nil, nil}
    end
  end

  @doc """
  Discovers and verifies the WebFinger handle of an ActivityPub actor for use as a nickname.
  If the actor or instance does not use WebFinger or just temporarily unavailable no value
  is returned and it is up to callers to decide ona na apropiate fallback or stop processing.

  Returns {:ok, handle} if discovered and successfully verified,
  {:ok, nil} if no WebFinger can be discovered but was also not required and
  {:error, reason} if validation failed or a required WebFinger link is missing.
  """
  @spec finger_actor(map()) :: {:ok, String.t() | nil} | {:error, any()}
  def finger_actor(%{"webfinger" => preferred_handle, "id" => ap_id})
      when is_binary(preferred_handle) and is_binary(ap_id) do
    # As per FEP-2c59 an "acct:" prefix is discouraged but allowed in the actor property
    preferred_handle = normalise_webfinger_handle(preferred_handle)
    {_, domain} = parse_handle(preferred_handle)
    ap_domain = URI.parse(ap_id).host

    with {_, false} <- {:no_domain, domain == nil || ap_domain == nil},
         {_, false} <- {:matching_domain, domain == ap_domain},
         # Per FEP-2c59 no form of redirects are allowed when fingering the handle
         {_, {:ok, _, %{"ap_id" => fingered_ap_id, "subject" => finger_subject}}} <-
           {:query, finger_unverified_data(domain, ap_id, false)},
         {_, false} <- {:fingered_data_mismatch, ap_id != fingered_ap_id},
         finger_handle <- normalise_webfinger_handle(finger_subject),
         {_, false} <- {:fingered_data_mismatch, preferred_handle != finger_handle} do
      {:ok, preferred_handle}
    else
      {:matching_domain, true} ->
        {:ok, preferred_handle}

      {:query, error} ->
        error

      {reason, _} ->
        {:error, reason}
    end
  end

  def finger_actor(%{"id" => ap_id} = actor_data) when is_binary(ap_id) do
    ap_domain = URI.parse(ap_id).host

    with {_, false} <- {:no_domain, ap_domain == nil},
         {_, {:ok, finger_domain, %{"ap_id" => fingered_ap_id, "subject" => finger_subject}}} <-
           {:query, finger_unverified_data(ap_domain, ap_id)},
         {_, false} <- {:fingered_data_mismatch, fingered_ap_id != ap_id},
         handle <- normalise_webfinger_handle(finger_subject),
         {nick_user, nick_domain} <- parse_handle(handle),
         # Mastodon in its infinite wisdom encourages setups for custom WebFinger domains,
         # such that the actual WebFinger response is _never_ served directly from the domain used in handles.
         # Unlike in domain authority checks for AP IDs, here only fixed /.well-known URLs are queried,
         # thus a redirect on this endpoint can be considered an approval from the redirecting domain
         # (but not the redericted-to domain!) and it should be safe to accept both domain authorities here.
         {_, false} <-
           {:finger_domain_spoof, nick_domain != finger_domain && nick_domain != ap_domain},
         ap_name <- actor_data["preferredUsername"],
         {_, false} <- {:fingered_data_mismatch, ap_name != nil && ap_name != nick_user} do
      {:ok, handle}
    else
      {:query, _} ->
        # Instance either doesn’t use WebFinger or WebFinger setup temporarily unreachable.
        # This is no error (WebFinger isn’t mandatory for AP); we just have no WebFinger handle to report.
        {:ok, nil}

      {reason, _} ->
        {:error, reason}
    end
  end

  defp verify_ap_data_from_finger(%{"webfinger" => preferred_handle} = data, finger_handle, _, _) do
    if normalise_webfinger_handle(preferred_handle) == finger_handle do
      {:ok, finger_handle, data}
    else
      {:error, :finger_data_mismatch}
    end
  end

  defp verify_ap_data_from_finger(%{"id" => ap_id} = data, handle, finger_domain, finger_name) do
    ap_domain = URI.parse(ap_id).host

    with {_, false} <- {:domain_mismatch, ap_domain != finger_domain},
         ap_name <- data["preferredUsername"],
         {_, false} <- {:fingered_nick_mismatch, ap_name != nil && ap_name != finger_name} do
      {:ok, handle, data}
    else
      {:domain_mismatch, true} ->
        # Actor has no webfinger backlink and is from different domain. We
        # need to make sure actor agrees to be associated with this domain.
        # Thus restart querying from actor data.
        case finger_actor(data) do
          {:ok, verified_nick} -> {:ok, verified_nick, data}
          error -> error
        end

      {reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Resolve mention handle to unparsed ActivityPub data,
  but verified consistency with resolved webfinger handle.
  The final handle may differ from initially queried handle.
  Callers thus MUST use the returned handle for further processing, NOT the initially queried handle!

  E.g. the AP actor may live on social.example.org and employ a redirect or LRDD tmeplate
  to allow discovering the preferred handle on example.org. Or the actor changed their
  username and queries to the old handle now respond with the updated information to gracefully
  transitioning old references.
  """
  @spec finger_mention(String.t()) :: {:ok, String.t(), map()} | {:error, any()}
  def finger_mention(mention_handle) when is_binary(mention_handle) do
    {qname, qdomain} = parse_handle(mention_handle)

    with {_, false} <- {:invalid_handle, qname == nil || qdomain == nil},
         {_, {:ok, finger_domain, %{"ap_id" => fingered_ap_id, "subject" => finger_subject}}} <-
           {:query, finger_unverified_data(qdomain, mention_handle)},
         handle <- normalise_webfinger_handle(finger_subject),
         {nick_user, nick_domain} <- parse_handle(handle),
         # see comment in finger_actor for why both domains can and need to be accepted
         {_, false} <-
           {:finger_domain_spoof, nick_domain != finger_domain && nick_domain != qdomain},
         {_, {:ok, data}} <-
           {:fetch, Fetcher.fetch_and_contain_remote_object_from_id(fingered_ap_id)} do
      verify_ap_data_from_finger(data, handle, finger_domain, nick_user)
    else
      {:query, error} -> error
      {:fetch, error} -> error
      {reason, _} -> {:error, reason}
    end
  end

  @doc """
  Retrieve raw, UNVERFIFIED webfinger data for a resource,
  guessing the WebFinger domain from the resource itself.

  Only use this when no verification needed! (E.g. to discover subsription addresses)
  """
  @spec finger_raw_data(String.t()) :: {:ok, map()} | {:error, any()}
  def finger_raw_data(resource) do
    domain =
      if Regex.match?(~r/^https?:\/\//, resource) do
        URI.parse(resource).host
      else
        case String.split(resource, "@", parts: 3) do
          [_, domain] -> domain
          ["", _, domain] -> domain
          _ -> {:error, :invalid_resource}
        end
      end

    with {_, domain} when is_binary(domain) <- {:domain, domain},
         {:ok, _, data} <- finger_unverified_data(domain, resource) do
      {:ok, data}
    else
      {:domain, _} -> {:error, :no_domain}
      error -> error
    end
  end
end
