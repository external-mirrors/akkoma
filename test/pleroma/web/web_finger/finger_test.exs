# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.WebFinger.FingerTest do
  use Pleroma.DataCase
  alias Pleroma.Web.WebFinger.Finger
  import Tesla.Mock

  setup do
    mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  test "returns error for nonsensical input" do
    assert {:error, _} = Finger.finger_actor(%{"id" => "bliblablu"})
    assert {:error, _} = Finger.finger_mention("pleroma.social")
  end

  test "returns error when there is no content-type header" do
    Tesla.Mock.mock(fn
      %{url: "https://social.heldscal.la/.well-known/host-meta"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/social.heldscal.la_host_meta")
         }}

      %{
        url:
          "https://social.heldscal.la/.well-known/webfinger?resource=invalid_content@social.heldscal.la"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}
    end)

    user = "invalid_content@social.heldscal.la"
    assert {:error, {:content_type, nil}} = Finger.finger_mention(user)
  end

  test "returns error when fails parse xml or json" do
    user = "invalid_content@social.heldscal.la"
    assert {:error, %Jason.DecodeError{}} = Finger.finger_mention(user)
  end

  test "returns the ActivityPub actor URI for an ActivityPub user" do
    user = "framasoft@framatube.org"

    {:ok, _nick, _data} = Finger.finger_mention(user)
  end

  test "it work for AP-only user" do
    user = "kpherox@mstdn.jp"

    {:ok, data} = Finger.finger_raw_data(user)

    assert data["magic_key"] == nil
    assert data["salmon"] == nil

    assert data["topic"] == nil
    assert data["subject"] == "acct:kPherox@mstdn.jp"
    assert data["ap_id"] == "https://mstdn.jp/users/kPherox"
    assert data["subscribe_address"] == "https://mstdn.jp/authorize_interaction?acct={uri}"
  end

  test "it gets the xrd endpoint" do
    {:ok, template} = Finger.find_lrdd_template("social.heldscal.la")

    assert template == "https://social.heldscal.la/.well-known/webfinger?resource={uri}"
  end

  test "it gets the xrd endpoint for hubzilla" do
    {:ok, template} = Finger.find_lrdd_template("macgirvin.com")

    assert template == "https://macgirvin.com/xrd/?uri={uri}"
  end

  test "it gets the xrd endpoint for statusnet" do
    {:ok, template} = Finger.find_lrdd_template("status.alpicola.com")

    assert template == "https://status.alpicola.com/main/xrd?uri={uri}"
  end

  test "it works with idna domains as nickname" do
    nickname = "lain@" <> to_string(:idna.encode("zetsubou.みんな"))

    {:ok, _data} = Finger.finger_raw_data(nickname)
  end

  test "it works with idna domains as link" do
    ap_id = "https://" <> to_string(:idna.encode("zetsubou.みんな")) <> "/users/lain"
    {:ok, _data} = Finger.finger_raw_data(ap_id)
  end

  test "respects json content-type" do
    Tesla.Mock.mock(fn
      %{
        url: "https://mastodon.social/.well-known/webfinger?resource=emelie@mastodon.social"
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/webfinger_emelie.json"),
           headers: [{"content-type", "application/jrd+json"}]
         }}

      %{url: "https://mastodon.social/.well-known/host-meta"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/mastodon.social_host_meta")
         }}
    end)

    {:ok, _data} = Finger.finger_raw_data("emelie@mastodon.social")
  end

  test "respects xml content-type" do
    Tesla.Mock.mock(fn
      %{
        url: "https://pawoo.net/.well-known/webfinger?resource=pekorino@pawoo.net"
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/https___pawoo.net_users_pekorino.xml"),
           headers: [{"content-type", "application/xrd+xml"}]
         }}

      %{url: "https://pawoo.net/.well-known/host-meta"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/pawoo.net_host_meta")
         }}
    end)

    {:ok, _data} = Finger.finger_raw_data("pekorino@pawoo.net")
  end

  test "prevents spoofing" do
    Tesla.Mock.mock(fn
      %{
        url: "https://bad.com/.well-known/webfinger?resource=meanie@bad.com"
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/webfinger_spoof.json"),
           headers: [{"content-type", "application/jrd+json"}]
         }}

      %{url: "https://bad.com/.well-known/host-meta"} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: File.read!("test/fixtures/tesla_mock/bad.com_host_meta")
         }}
    end)

    {:error, _data} = Finger.finger_mention("meanie@bad.com")
  end

  test "prevents forgeries" do
    Tesla.Mock.mock(fn
      %{url: "https://bad.com/.well-known/webfinger?resource=meanie@bad.com"} ->
        fake_webfinger =
          File.read!("test/fixtures/webfinger/imposter-webfinger.json") |> Jason.decode!()

        Tesla.Mock.json(fake_webfinger)

      %{url: "https://bad.com/.well-known/host-meta"} ->
        {:ok, %Tesla.Env{status: 404}}
    end)

    assert {:error, :finger_domain_spoof} = Finger.finger_mention("meanie@bad.com")
  end
end
