# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.User.Fetcher do
  alias Akkoma.Collections
  alias Pleroma.Config
  alias Pleroma.Object
  alias Pleroma.Object.Fetcher, as: APFetcher
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.MRF
  alias Pleroma.Web.ActivityPub.ObjectValidators.UserValidator
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.WebFinger

  import Pleroma.Web.ActivityPub.Utils

  require Logger

  @spec get_actor_url(any()) :: binary() | nil
  defp get_actor_url(url) when is_binary(url), do: url
  defp get_actor_url(%{"href" => href}) when is_binary(href), do: href

  defp get_actor_url(url) when is_list(url) do
    url
    |> List.first()
    |> get_actor_url()
  end

  defp get_actor_url(_url), do: nil

  defp normalize_image(%{"url" => url}) do
    %{
      "type" => "Image",
      "url" => [%{"href" => url}]
    }
  end

  defp normalize_image(urls) when is_list(urls), do: urls |> List.first() |> normalize_image()
  defp normalize_image(_), do: nil

  defp normalize_also_known_as(aka) when is_list(aka), do: aka
  defp normalize_also_known_as(aka) when is_binary(aka), do: [aka]
  defp normalize_also_known_as(nil), do: []

  defp normalize_attachment(%{} = attachment), do: [attachment]
  defp normalize_attachment(attachment) when is_list(attachment), do: attachment
  defp normalize_attachment(_), do: []

  defp maybe_make_public_key_object(data) do
    if is_map(data["publicKey"]) && is_binary(data["publicKey"]["publicKeyPem"]) do
      %{
        public_key: data["publicKey"]["publicKeyPem"],
        key_id: data["publicKey"]["id"]
      }
    else
      nil
    end
  end

  defp object_to_user_data(data, additional) do
    fields =
      data
      |> Map.get("attachment", [])
      |> normalize_attachment()
      |> Enum.filter(fn
        %{"type" => t} -> t == "PropertyValue"
        _ -> false
      end)
      |> Enum.map(fn fields -> Map.take(fields, ["name", "value"]) end)

    emojis =
      data
      |> Map.get("tag", [])
      |> Enum.filter(fn
        %{"type" => "Emoji"} -> true
        _ -> false
      end)
      |> Map.new(fn %{"icon" => %{"url" => url}, "name" => name} ->
        {String.trim(name, ":"), url}
      end)

    is_locked = data["manuallyApprovesFollowers"] || false
    data = Transmogrifier.maybe_fix_user_object(data)
    is_discoverable = data["discoverable"] || false
    invisible = data["invisible"] || false
    actor_type = data["type"] || "Person"

    {featured_address, pinned_objects} =
      case process_featured_collection(data["featured"]) do
        {:ok, featured_address, pinned_objects} -> {featured_address, pinned_objects}
        _ -> {nil, %{}}
      end

    # first, check that the owner is correct
    signing_key =
      if data["id"] !== data["publicKey"]["owner"] do
        Logger.error(
          "Owner of the public key is not the same as the actor - not saving the public key."
        )

        nil
      else
        maybe_make_public_key_object(data)
      end

    shared_inbox =
      if is_map(data["endpoints"]) && is_binary(data["endpoints"]["sharedInbox"]) do
        data["endpoints"]["sharedInbox"]
      end

    # if WebFinger request was already done, we probably have acct, otherwise
    # we request WebFinger here
    # nickname = additional[:nickname_from_acct] || generate_nickname(data)
    # TEMPORARILY DISABLE foreign webfinger domains!
    # Old code did not properly validate consistency between actor and webfinge data,
    # allowing nickname associations domains or actor do not consent with
    nickname =
      (is_binary(data["preferredUsername"]) &&
         "#{data["preferredUsername"]}@#{URI.parse(data["id"]).host}") || nil

    # also_known_as must be a URL
    also_known_as =
      data
      |> Map.get("alsoKnownAs", [])
      |> normalize_also_known_as()
      |> Enum.filter(fn url ->
        case URI.parse(url) do
          %URI{scheme: "http"} -> true
          %URI{scheme: "https"} -> true
          _ -> false
        end
      end)

    %{
      ap_id: data["id"],
      uri: get_actor_url(data["url"]),
      banner: normalize_image(data["image"]),
      background: normalize_image(data["backgroundUrl"]),
      fields: fields,
      emoji: emojis,
      is_locked: is_locked,
      is_discoverable: is_discoverable,
      invisible: invisible,
      avatar: normalize_image(data["icon"]),
      name: data["name"],
      follower_address: data["followers"],
      following_address: data["following"],
      featured_address: featured_address,
      bio: data["summary"] || "",
      actor_type: actor_type,
      also_known_as: also_known_as,
      signing_key: signing_key,
      inbox: data["inbox"],
      shared_inbox: shared_inbox,
      pinned_objects: pinned_objects,
      nickname: nickname
    }
  end

  defp generate_nickname(%{"preferredUsername" => username} = data) when is_binary(username) do
    generated = "#{username}@#{URI.parse(data["id"]).host}"

    if Config.get([WebFinger, :update_nickname_on_user_fetch]) do
      case WebFinger.Finger.finger(generated) do
        {:ok, %{"subject" => "acct:" <> acct}} -> acct
        _ -> generated
      end
    else
      generated
    end
  end

  # nickname can be nil because of virtual actors
  defp generate_nickname(_), do: nil

  def fetch_follow_information_for_user(user) do
    with {:ok, following_data} <-
           APFetcher.fetch_and_contain_remote_object_from_id(user.following_address),
         {:ok, hide_follows} <- collection_private(following_data),
         {:ok, followers_data} <-
           APFetcher.fetch_and_contain_remote_object_from_id(user.follower_address),
         {:ok, hide_followers} <- collection_private(followers_data) do
      {:ok,
       %{
         hide_follows: hide_follows,
         follower_count: normalize_counter(followers_data["totalItems"]),
         following_count: normalize_counter(following_data["totalItems"]),
         hide_followers: hide_followers
       }}
    else
      {:error, _} = e -> e
      e -> {:error, e}
    end
  end

  defp normalize_counter(counter) when is_integer(counter), do: counter
  defp normalize_counter(_), do: 0

  def maybe_update_follow_information(user_data) do
    with {:enabled, true} <- {:enabled, Config.get([:instance, :external_user_synchronization])},
         {_, true} <- {:user_type_check, user_data[:type] in ["Person", "Service"]},
         {_, true} <-
           {:collections_available,
            !!(user_data[:following_address] && user_data[:follower_address])},
         {:ok, info} <-
           fetch_follow_information_for_user(user_data) do
      info = Map.merge(user_data[:info] || %{}, info)

      user_data
      |> Map.put(:info, info)
    else
      {:user_type_check, false} ->
        user_data

      {:collections_available, false} ->
        user_data

      {:enabled, false} ->
        user_data

      e ->
        Logger.error(
          "Follower/Following counter update for #{user_data.ap_id} failed.\n" <> inspect(e)
        )

        user_data
    end
  end

  defp collection_private(%{"first" => %{"type" => type}})
       when type in ["CollectionPage", "OrderedCollectionPage"],
       do: {:ok, false}

  defp collection_private(%{"first" => first}) do
    with {:ok, %{"type" => type}} when type in ["CollectionPage", "OrderedCollectionPage"] <-
           APFetcher.fetch_and_contain_remote_object_from_id(first) do
      {:ok, false}
    else
      {:error, _} -> {:ok, true}
    end
  end

  defp collection_private(_data), do: {:ok, true}

  def user_data_from_user_object(data, additional \\ []) do
    with {:ok, data} <- MRF.filter(data),
         {:valid, {:ok, _, _}} <- {:valid, UserValidator.validate(data, [])} do
      {:ok, object_to_user_data(data, additional)}
    else
      {:valid, reason} ->
        {:error, {:validate, reason}}

      e ->
        {:error, e}
    end
  end

  defp fetch_and_prepare_user_from_ap_id(ap_id, additional) do
    with {:ok, data} <- APFetcher.fetch_and_contain_remote_object_from_id(ap_id),
         {:ok, data} <- user_data_from_user_object(data, additional) do
      {:ok, maybe_update_follow_information(data)}
    else
      # If this has been deleted, only log a debug and not an error
      {:error, {"Object has been deleted", _, _} = e} ->
        Logger.debug("User was explicitly deleted #{ap_id}, #{inspect(e)}")
        {:error, :not_found}

      {:reject, _reason} = e ->
        {:error, e}

      {:error, e} ->
        {:error, e}
    end
  end

  def maybe_handle_clashing_nickname(data) do
    with nickname when is_binary(nickname) <- data[:nickname],
         %User{} = old_user <- User.get_by_nickname(nickname),
         {_, false} <- {:ap_id_comparison, data[:ap_id] == old_user.ap_id} do
      Logger.info(
        "Found an old user for #{nickname}, the old ap id is #{old_user.ap_id}, new one is #{data[:ap_id]}, renaming.
"
      )

      old_user
      |> User.remote_user_changeset(%{nickname: "#{old_user.id}.#{old_user.nickname}"})
      |> User.update_and_set_cache()
    else
      {:ap_id_comparison, true} ->
        Logger.info(
          "Found an old user for #{data[:nickname]}, but the ap id #{data[:ap_id]} is the same as the new user. Race
condition? Not changing anything."
        )

      _ ->
        nil
    end
  end

  def process_featured_collection(nil), do: {:ok, nil, %{}}
  def process_featured_collection(""), do: {:ok, nil, %{}}

  def process_featured_collection(featured_collection) do
    featured_address =
      case get_ap_id(featured_collection) do
        id when is_binary(id) -> id
        _ -> nil
      end

    # TODO: allow passing item/page limit as function opt and use here
    case Collections.Fetcher.fetch_collection(featured_collection) do
      {:ok, items} ->
        now = NaiveDateTime.utc_now()
        dated_obj_ids = Map.new(items, fn obj -> {get_ap_id(obj), now} end)
        {:ok, featured_address, dated_obj_ids}

      error ->
        Logger.error(
          "Could not decode featured collection at fetch #{inspect(featured_collection)}: #{inspect(error)}"
        )

        error =
          case error do
            {:error, e} -> e
            e -> e
          end

        {:error, error}
    end
  end

  def enqueue_pin_fetches(%{pinned_objects: pins}) do
    # enqueue a task to fetch all pinned objects
    Enum.each(pins, fn {ap_id, _} ->
      if is_nil(Object.get_cached_by_ap_id(ap_id)) do
        Pleroma.Workers.RemoteFetcherWorker.enqueue("fetch_remote", %{
          "id" => ap_id,
          "depth" => 1
        })
      end
    end)
  end

  def enqueue_pin_fetches(_), do: nil

  def make_user_from_ap_id(ap_id, additional \\ []) do
    user = User.get_cached_by_ap_id(ap_id)

    with {:ok, data} <- fetch_and_prepare_user_from_ap_id(ap_id, additional) do
      user =
        if data.ap_id != ap_id do
          User.get_cached_by_ap_id(data.ap_id)
        else
          user
        end

      if user do
        user
        |> User.remote_user_changeset(data)
        |> User.update_and_set_cache()
        |> tap(fn _ -> enqueue_pin_fetches(data) end)
      else
        maybe_handle_clashing_nickname(data)

        data
        |> User.remote_user_changeset()
        |> Repo.insert()
        |> User.set_cache()
        |> tap(fn _ -> enqueue_pin_fetches(data) end)
      end
    end
  end

  def make_user_from_nickname(nickname) do
    with {:ok, %{"ap_id" => ap_id, "subject" => "acct:" <> acct}} when not is_nil(ap_id) <-
           WebFinger.Finger.finger(nickname) do
      make_user_from_ap_id(ap_id, nickname_from_acct: acct)
    else
      _e -> {:error, "No AP id in WebFinger"}
    end
  end
end
