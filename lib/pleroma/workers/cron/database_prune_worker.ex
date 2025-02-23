defmodule Pleroma.Workers.Cron.PruneDatabaseWorker do
  @moduledoc """
  The worker to prune old data from the database.
  """
  require Logger
  use Oban.Worker, queue: "database_prune"

  alias Pleroma.Activity.Pruner, as: ActivityPruner
  alias Pleroma.Object.Pruner, as: ObjectPruner

  @impl Oban.Worker
  def perform(%{args: %{"task" => "prune_deletes"}}) do
    Logger.info("Pruning old deletes")
    ActivityPruner.prune_deletes()
    :ok
  end

  def perform(%{args: %{"task" => "prune_follow_requests"}}) do
    Logger.info("Pruning old follow requests")
    ActivityPruner.prune_stale_follow_requests()
    :ok
  end

  def perform(%{args: %{"task" => "prune_undos"}}) do
    Logger.info("Pruning old undos")
    ActivityPruner.prune_undos()
    :ok
  end

  def perform(%{args: %{"task" => "prune_updates"}}) do
    Logger.info("Pruning old updates")
    ActivityPruner.prune_updates()
    :ok
  end

  def perform(%{args: %{"task" => "prune_removes"}}) do
    Logger.info("Pruning old removes")
    ActivityPruner.prune_removes()
    :ok
  end

  def perform(%{args: %{"task" => "prune_tombstoned_deliveries"}}) do
    Logger.info("Pruning old tombstone delivery entries")
    ObjectPruner.prune_tombstoned_deliveries()
    :ok
  end

  def perform(%{args: %{"task" => "prune_tombstones"}}) do
    Logger.info("Pruning old tombstones")
    ObjectPruner.prune_tombstones()
    :ok
  end

  def perform(%{args: %{"task" => "prune_objects_beyond_retention"}}) do
    Logger.info("Pruning objects beyond :remote_post_retention_days")

    ObjectPruner.prune_objects_beyond_retention(
      keep_non_public: true,
      keep_threads: true,
      vacuum: false,
      limit: Pleroma.Config.get([:instance, :remote_post_prune_limit], 1000)
    )

    :ok
  end

  def perform(%{args: %{"task" => "prune_orphaned_activities"}}) do
    Logger.info("Pruning orphaned activities")
    ActivityPruner.prune_orphans(1000)
    :ok
  end

  def perform(job) do
    Logger.error("Cannot process prune job: #{inspect(job)}")
    :discard
  end
end
