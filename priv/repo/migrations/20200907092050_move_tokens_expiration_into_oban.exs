defmodule Pleroma.Repo.Migrations.MoveTokensExpirationIntoOban do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  def change do
    # This runs against Oban table schema version 8.
    # See 20200825061316_move_activity_expirations_to_oban.exs for a general layout.
    # For this specifically:
    #  queue = 'token_expiration'
    #  worker = 'Pleroma.Workers.PurgeExpiredToken'
    #  args = jsonb('{"token_id": …, "mod": "Pleroma.Web.OAuth.Token"}')

    if Pleroma.Config.get([:oauth2, :clean_expired_tokens]) do
      source =
        from(t in Pleroma.Web.OAuth.Token,
          where: t.valid_until > ^NaiveDateTime.utc_now(),
          select: %{
            state: "scheduled",
            queue: "token_expiration",
            worker: "Pleroma.Workers.PurgeExpiredToken",
            max_attempts: 1,
            scheduled_at: fragment("? AT TIME ZONE 'UTC'", t.valid_until),
            args: %{
              mod: "Pleroma.Workers.PurgeExpiredToken",
              token_id: t.id
            }
          }
        )

      Pleroma.Repo.insert_all(Oban.Job, source)
    end
  end
end
