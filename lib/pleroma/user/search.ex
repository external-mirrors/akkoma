# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# Copyright © 2026 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.User.Search do
  alias Pleroma.Pagination
  alias Pleroma.Repo
  alias Pleroma.User

  require Logger

  import Ecto.Query

  @limit 20

  def search(query_string, opts \\ []) do
    for_user = Keyword.get(opts, :for_user)
    local_only = should_restrict_local(for_user)
    resolve = Keyword.get(opts, :resolve, false) && !local_only

    query_string = String.trim(query_string)

    is_uri = Regex.match?(~r/https?:/, query_string)
    likely_nick = String.contains?(query_string, "@") && !String.contains?(query_string, " ")

    []
    |> maybe_search(fn -> uri_match(query_string, is_uri, resolve) end)
    |> maybe_search(fn -> nick_match(query_string, likely_nick, resolve) end)
    |> maybe_search(fn ->
      fts_matches(query_string, for_user, local_only, opts)
    end)
    |> Enum.filter(&(&1 && (!local_only || &1.local)))
  end

  defp maybe_search([], finder) do
    case finder.() do
      [_ | _] = res -> res
      {:ok, a} when a != nil -> [a]
      {:error, _} -> []
      nil -> []
      [] -> []
      a -> [a]
    end
  end

  defp maybe_search(previous_results, _), do: previous_results

  defp uri_match(uri, true, resolve) do
    known =
      from(u in User)
      |> where([u], u.ap_id == ^uri or u.uri == ^uri)
      |> filter_invisible_users()
      |> filter_internal_users()
      |> filter_deactivated_users()
      |> Repo.all()

    cond do
      known != [] -> known
      resolve -> User.fetch_by_ap_id(uri)
      true -> nil
    end
  end

  defp uri_match(_, _, _), do: nil

  # NOTE: User.get_cached_by_nickname falls back to a netowrk lookup if not cached. DO NOT USE
  defp do_nick_match(nick, true), do: User.get_or_fetch_by_nickname(nick)
  defp do_nick_match(nick, false), do: User.get_by_nickname(nick)
  defp do_nick_match(_, _), do: nil

  defp verify_and_normalise_nick(nick) do
    nick =
      nick
      |> String.trim_leading("@")
      |> String.trim_trailing("@#{Pleroma.Web.WebFinger.Schema.domain()}")
      |> String.trim_trailing("@#{local_domain()}")

    case String.split(nick, "@", parts: 3) do
      # local nick
      [nick] ->
        nick

      # remote nick; maybe Unicode domain
      [name, domain] ->
        if Regex.match?(~r/[!-\,|@|?|<|>|[-`|{-~|\/|:|\s]/, domain) do
          nil
        else
          encoded_domain =
            domain
            |> String.to_charlist()
            |> :idna.encode()

          "#{name}@#{encoded_domain}"
        end

      # not a valid nick
      _ ->
        nil
    end
  end

  defp nick_match(nick, true, resolve) do
    normalised_nick = verify_and_normalise_nick(nick)

    if normalised_nick,
      do: do_nick_match(normalised_nick, resolve),
      else: nil
  end

  defp nick_match(_, _, _), do: nil

  defp fts_matches(query_string, for_user, local_only, opts) do
    following = Keyword.get(opts, :following, false)
    result_limit = Keyword.get(opts, :limit, @limit)
    offset = Keyword.get(opts, :offset, 0)

    gin_limit = Pleroma.Config.get([Pleroma.Search.DatabaseSearch, :gin_fuzzy_search_limit])

    if is_integer(gin_limit) do
      Repo.transact(fn ->
        # SET LOCAL statement cannot be parametrised it seems; safe because integer
        Repo.query!("SET LOCAL gin_fuzzy_search_limit TO #{gin_limit}", [])

        {:ok, do_fts_search(query_string, for_user, local_only, following, offset, result_limit)}
      end)
      |> then(fn
        {:ok, result} ->
          result

        error ->
          Logger.error("#{__MODULE__}: user search transaction failed: #{inspect(error)}")
          []
      end)
    else
      do_fts_search(query_string, for_user, local_only, following, offset, result_limit)
    end
  end

  defp do_fts_search(query_string, for_user, local_only, following, offset, result_limit) do
    base_query(for_user, following)
    |> filter_blocked_user(for_user)
    |> filter_invisible_users()
    |> filter_internal_users()
    |> filter_blocked_domains(for_user)
    |> fts_search(query_string)
    |> trigram_rank(query_string)
    |> boost_search_rank(for_user)
    |> subquery()
    |> order_by(desc: :search_rank)
    |> maybe_restrict_local(local_only)
    |> filter_deactivated_users()
    |> Pagination.fetch_paginated(%{"offset" => offset, "limit" => result_limit}, :offset)
  end

  defp fts_search(query, query_string) do
    query_string = to_tsquery(query_string)

    from(
      u in query,
      where:
        fragment(
          # The fragment must _exactly_ match `users_fts_index`, otherwise the index won't work
          """
          (
            setweight(to_tsvector('simple', regexp_replace(?, '\\W', ' ', 'g')), 'A') ||
            setweight(to_tsvector('simple', regexp_replace(coalesce(?, ''), '\\W', ' ', 'g')), 'B')
          ) @@ to_tsquery('simple', ?)
          """,
          u.nickname,
          u.name,
          ^query_string
        )
    )
  end

  defp to_tsquery(query_string) do
    String.trim_trailing(query_string, "@" <> local_domain())
    |> String.replace(~r/[!-\/|@|[-`|{-~|:-?]+/, " ")
    |> String.trim()
    |> String.split()
    |> Enum.map(&(&1 <> ":*"))
    |> Enum.join(" | ")
  end

  # Considers nickname match, localized nickname match, name match; preferences nickname match
  defp trigram_rank(query, query_string) do
    from(
      u in query,
      select_merge: %{
        search_rank:
          fragment(
            """
            similarity(?, ?) +
            similarity(?, regexp_replace(?, '@.+', '')) +
            similarity(?, trim(coalesce(?, '')))
            """,
            ^query_string,
            u.nickname,
            ^query_string,
            u.nickname,
            ^query_string,
            u.name
          )
      }
    )
  end

  defp base_query(%User{} = user, true), do: User.get_friends_query(user)
  defp base_query(_user, _following), do: User

  defp filter_invisible_users(query) do
    from(q in query, where: q.invisible == false)
  end

  defp filter_internal_users(query) do
    from(q in query, where: q.actor_type != "Application")
  end

  defp filter_deactivated_users(query) do
    from(q in query, where: q.is_active == true)
  end

  defp filter_blocked_user(query, %User{} = blocker) do
    query
    |> join(:left, [u], b in Pleroma.UserRelationship,
      as: :blocks,
      on: b.relationship_type == ^:block and b.source_id == ^blocker.id and u.id == b.target_id
    )
    |> where([blocks: b], is_nil(b.target_id))
  end

  defp filter_blocked_user(query, _), do: query

  defp filter_blocked_domains(query, %User{domain_blocks: domain_blocks})
       when length(domain_blocks) > 0 do
    domains = Enum.join(domain_blocks, ",")

    from(
      q in query,
      where: fragment("split_part(ap_id, '/', 3) NOT IN (?)", ^domains)
    )
  end

  defp filter_blocked_domains(query, _), do: query

  defp limit, do: Pleroma.Config.get([:instance, :limit_to_local_content], :unauthenticated)

  defp should_restrict_local(user) do
    case {limit(), user} do
      {:all, _} -> true
      {:unauthenticated, %User{}} -> false
      {:unauthenticated, _} -> true
      {false, _} -> false
    end
  end

  defp maybe_restrict_local(q, true), do: restrict_local(q)
  defp maybe_restrict_local(q, false), do: q

  defp restrict_local(q), do: where(q, [u], u.local == true)

  defp local_domain, do: Pleroma.Config.get([Pleroma.Web.Endpoint, :url, :host])

  defp boost_search_rank(query, %User{} = for_user) do
    friends_ids = User.get_friends_ids(for_user)
    followers_ids = User.get_followers_ids(for_user)

    from(u in subquery(query),
      select_merge: %{
        search_rank:
          fragment(
            """
             CASE WHEN (?) THEN (?) * 1.5
             WHEN (?) THEN (?) * 1.3
             WHEN (?) THEN (?) * 1.1
             ELSE (?) END
            """,
            u.id in ^friends_ids and u.id in ^followers_ids,
            u.search_rank,
            u.id in ^friends_ids,
            u.search_rank,
            u.id in ^followers_ids,
            u.search_rank,
            u.search_rank
          )
      }
    )
  end

  defp boost_search_rank(query, _), do: query
end
