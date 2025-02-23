defmodule Pleroma.Object.Pruner do
  @moduledoc """
  Prunes objects from the database.
  """
  @cutoff 30

  alias Pleroma.Object
  alias Pleroma.Delivery
  alias Pleroma.Repo
  import Ecto.Query

  require Logger

  def prune_tombstoned_deliveries do
    from(d in Delivery)
    |> join(:inner, [d], o in Object, on: d.object_id == o.id)
    |> where([d, o], fragment("?->>'type' = ?", o.data, "Tombstone"))
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_tombstones do
    before_time = cutoff()

    from(o in Object,
      where: fragment("?->>'type' = ?", o.data, "Tombstone") and o.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity, on_delete: :delete_all)
  end

  defp cutoff do
    DateTime.utc_now() |> Timex.shift(days: -@cutoff)
  end

  defp format_options_for_log_message(deadline, options) do
    limit_cnt = Keyword.get(options, :limit, 0)
    log_message = "Pruning objects older than #{deadline} days"

    log_message =
      if Keyword.get(options, :keep_non_public) do
        log_message <> ", keeping non public posts"
      else
        log_message
      end

    log_message =
      if Keyword.get(options, :keep_threads) do
        log_message <> ", keeping threads intact"
      else
        log_message
      end

    log_message =
      if Keyword.get(options, :vacuum) do
        log_message <>
          ", doing a full vacuum (you shouldn't do this as a recurring maintanance task)"
      else
        log_message
      end

    log_message =
      if limit_cnt > 0 do
        log_message <> ", limiting to #{limit_cnt} rows"
      else
        log_message
      end

    log_message
  end

  @doc """
  Prunes objects that have passed beyond :remote_post_retention_days

  options:
  - :keep_non_public, will not prune objects that cannot be refetched, as they are not public
  - :keep_threads, will analyse object relationships and keep threads in tact
  - :vacuum, does a database vacuum (be careful with this one)
  - :limit, the max number of objects to prune
  """
  def prune_objects_beyond_retention(options) do
    deadline = Pleroma.Config.get([:instance, :remote_post_retention_days])
    time_deadline = NaiveDateTime.utc_now() |> NaiveDateTime.add(-(deadline * 86_400))

    limit_cnt = Keyword.get(options, :limit, 0)

    Logger.info(format_options_for_log_message(deadline, options))

    {del_obj, _} =
      if Keyword.get(options, :keep_threads) do
        # We want to delete objects from threads where
        # 1. the newest post is still old
        # 2. none of the activities is local
        # 3. none of the activities is bookmarked
        # 4. optionally none of the posts is non-public
        deletable_context =
          if Keyword.get(options, :keep_non_public) do
            Pleroma.Activity
            |> join(:left, [a], b in Pleroma.Bookmark, on: a.id == b.activity_id)
            |> group_by([a], fragment("? ->> 'context'::text", a.data))
            |> having(
              [a],
              not fragment(
                # Posts (checked on Create Activity) is non-public
                "bool_or((not(?->'to' \\? ? OR ?->'cc' \\? ?)) and ? ->> 'type' = 'Create')",
                a.data,
                ^Pleroma.Constants.as_public(),
                a.data,
                ^Pleroma.Constants.as_public(),
                a.data
              )
            )
          else
            Pleroma.Activity
            |> join(:left, [a], b in Pleroma.Bookmark, on: a.id == b.activity_id)
            |> group_by([a], fragment("? ->> 'context'::text", a.data))
          end
          |> having([a], max(a.updated_at) < ^time_deadline)
          |> having([a], not fragment("bool_or(?)", a.local))
          |> having([_, b], fragment("max(?::text) is null", b.id))
          |> maybe_limit(limit_cnt)
          |> select([a], fragment("? ->> 'context'::text", a.data))

        Pleroma.Object
        |> where([o], fragment("? ->> 'context'::text", o.data) in subquery(deletable_context))
      else
        deletable =
          if Keyword.get(options, :keep_non_public) do
            Pleroma.Object
            |> where(
              [o],
              fragment(
                "?->'to' \\? ? OR ?->'cc' \\? ?",
                o.data,
                ^Pleroma.Constants.as_public(),
                o.data,
                ^Pleroma.Constants.as_public()
              )
            )
          else
            Pleroma.Object
          end
          |> where([o], o.updated_at < ^time_deadline)
          |> where(
            [o],
            fragment("split_part(?->>'actor', '/', 3) != ?", o.data, ^Pleroma.Web.Endpoint.host())
          )
          |> maybe_limit(limit_cnt)
          |> select([o], o.id)

        Pleroma.Object
        |> where([o], o.id in subquery(deletable))
      end
      |> Repo.delete_all(timeout: :infinity)

    Logger.info("Deleted #{del_obj} objects...")

    if !Keyword.get(options, :keep_threads) do
      # Without the --keep-threads option, it's possible that bookmarked
      # objects have been deleted. We remove the corresponding bookmarks.
      %{:num_rows => del_bookmarks} =
        """
        delete from public.bookmarks
        where id in (
          select b.id from public.bookmarks b
          left join public.activities a on b.activity_id = a.id
          left join public.objects o on a."data" ->> 'object' = o.data ->> 'id'
          where o.id is null
        )
        """
        |> Repo.query!([], timeout: :infinity)

      Logger.info("Deleted #{del_bookmarks} orphaned bookmarks...")
    end
  end

  defp maybe_limit(query, limit_cnt) do
    if is_number(limit_cnt) and limit_cnt > 0 do
      limit(query, [], ^limit_cnt)
    else
      query
    end
  end
end
