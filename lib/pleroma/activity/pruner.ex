defmodule Pleroma.Activity.Pruner do
  @moduledoc """
  Prunes activities from the database.
  """
  @cutoff 30

  alias Pleroma.Activity
  alias Pleroma.Repo
  import Ecto.Query
  require Logger

  def prune_deletes do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Delete") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_undos do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Undo") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_updates do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Update") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_removes do
    before_time = cutoff()

    from(a in Activity,
      where: fragment("?->>'type' = ?", a.data, "Remove") and a.inserted_at < ^before_time
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  def prune_stale_follow_requests do
    before_time = cutoff()

    from(a in Activity,
      where:
        fragment("?->>'type' = ?", a.data, "Follow") and a.inserted_at < ^before_time and
          fragment("?->>'state' = ?", a.data, "reject")
    )
    |> Repo.delete_all(timeout: :infinity)
  end

  defp cutoff do
    DateTime.utc_now() |> Timex.shift(days: -@cutoff)
  end

  def prune_orphans(limit) do
    del_array = prune_orphans_arrays(limit)
    del_single = prune_orphans_singles(limit)

    del_single + del_array
  end

  # Activities can either refer to a single object id, and array of object ids
  # or contain an inlined object (at least after going through our normalisation)
  #
  # Flag is the only type we support with an array (and always has arrays).
  # Update the only one with inlined objects.
  #
  # We already regularly purge old Delete, Undo, Update and Remove and if
  # rejected Follow requests anyway; no need to explicitly deal with those here.
  #
  # Since there’s an index on types and there are typically only few Flag
  # activites, it’s _much_ faster to utilise the index. To avoid accidentally
  # deleting useful activities should more types be added, keep typeof for singles.
  defp prune_orphans_arrays(limit) do
    %{:num_rows => del_array} =
      """
      delete from public.activities
      where id in (
        select a.id from public.activities a
        join json_array_elements_text((a."data" -> 'object')::json) as j
             on a.data->>'type' = 'Flag'
        left join public.objects o on j.value = o.data ->> 'id'
        left join public.activities a2 on j.value = a2.data ->> 'id'
        left join public.users u  on j.value = u.ap_id
        group by a.id
        having max(o.data ->> 'id') is null
        and max(a2.data ->> 'id') is null
        and max(u.ap_id) is null
        #{limit_statement(limit)}
      )
      """
      |> Repo.query!([], timeout: :infinity)

    Logger.info("Prune activity arrays: deleted #{del_array} rows...")
    del_array
  end

  defp prune_orphans_singles(limit) do
    %{:num_rows => del_single} =
      """
      delete from public.activities
      where id in (
        select a.id from public.activities a
        left join public.objects o on a.data ->> 'object' = o.data ->> 'id'
        left join public.activities a2 on a.data ->> 'object' = a2.data ->> 'id'
        left join public.users u  on a.data ->> 'object' = u.ap_id
        where not a.local
        and jsonb_typeof(a."data" -> 'object') = 'string'
        and o.id is null
        and a2.id is null
        and u.id is null
        #{limit_statement(limit)}
      )
      """
      |> Repo.query!([], timeout: :infinity)

    Logger.info("Prune activity singles: deleted #{del_single} rows...")
    del_single
  end

  defp limit_statement(limit) when is_number(limit) do
    if limit > 0 do
      "LIMIT #{limit}"
    else
      ""
    end
  end
end
