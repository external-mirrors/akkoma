defmodule Pleroma.Repo.Migrations.MoveActivityExpirationsToOban do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  def change do
    # This runs against Oban table scheme version 8
    # i.e. we have:
    # V1
    #  (id: auto generated))
    #  state = 'scheduled')
    #  queue = 'activity_expiration'
    #  worker = 'Pleroma.Workers.PurgeExpiredActivity'
    #  args = jsonb('{activity_id: "…"}')
    #  max_attempts: 1
    #  scheduled_at: …
    #
    #  (errors: using default empty state)
    #  (attempt: using default 0)
    #  (inserted_at: using default now())
    #  (attempted_at: using default null)
    #  (completed_at: using default null)
    # V2
    #  (attempted_by: using default null)
    # V8
    #  (discarded_at: using default null)
    #  (priority: using default 0)
    #  (tags: using default empty array)

    # After adding jobs oban_jobs_notify() is already automatically run via a trigger
    # so a simple insert should suffice

    # Due to having convert Flake UUIDs to custom base62-encoded strings
    # we need to funnel this all through elixir and back; else this could be
    # one single, simple and efficient query

    from(e in "activity_expirations",
      select: %{
        id: e.id,
        state: "scheduled",
        queue: "activity_expiration",
        worker: "Pleroma.Workers.PurgeExpiredActivity",
        activity_id: e.activity_id,
        max_attempts: 1,
        scheduled_at: fragment("? AT TIME ZONE 'UTC'", e.scheduled_at)
      }
    )
    |> Pleroma.Repo.chunk_stream(600, :batches, timeout: :infinity)
    |> Stream.each(fn chunk ->
      chunk
      |> Enum.map(fn map ->
        activity_id_str = FlakeId.to_string(map.activity_id)

        map
        |> Map.drop([:id, :activity_id])
        |> Map.put(:args, %{"activity_id" => activity_id_str})
      end)
      |> then(fn batch ->
        Pleroma.Repo.insert_all(Oban.Job, batch)
      end)
    end)
    |> Stream.run()
  end
end
