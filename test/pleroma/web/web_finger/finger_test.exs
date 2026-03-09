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
          "https://social.heldscal.la/.well-known/webfinger?resource=acct:invalid_content@social.heldscal.la"
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

  describe "finger_mention/1" do
    test "should use the webfinger property to look up the webfinger data for an actor" do
      Tesla.Mock.mock(fn
        %{
          url: "https://example.com/.well-known/webfinger?resource=acct:user@example.com"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "example.com")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{subdomain}}", "fingered.example.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url: "https://example.com/.well-known/webfinger?resource=acct:user@example.com"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}

        %{url: "https://fingered.example.com/users/user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/fep-2c59/user-with-webfinger.json")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{domain}}", "fingered.example.com")
               |> String.replace("{{webfinger_property}}", "user@example.com")
           }}
      end)

      {:ok, "user@example.com", _data} = Finger.finger_mention("@user@example.com")
    end

    test "should permit the use of the webfinger property to act as a redirect" do
      Tesla.Mock.mock(fn
        %{
          url: "https://example.com/.well-known/webfinger?resource=acct:user@example.com"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "somewhere-else.com")
               |> String.replace("{{nickname}}", "another-user")
               |> String.replace("{{subdomain}}", "somewhere-else.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://somewhere-else.com/.well-known/webfinger?resource=acct:user@example.com"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}

        %{url: "https://somewhere-else.com/users/another-user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/fep-2c59/user-with-webfinger.json")
               |> String.replace("{{nickname}}", "another-user")
               |> String.replace("{{domain}}", "somewhere-else.com")
               |> String.replace("{{webfinger_property}}", "another-user@somewhere-else.com")
           }}
      end)

      {:ok, "another-user@somewhere-else.com", _data} = Finger.finger_mention("@user@example.com")
    end

    test "should reject a cross-domain webfinger if the final actor has an incorrect webfinger property" do
      Tesla.Mock.mock(fn
        %{
          url: "https://example.com/.well-known/webfinger?resource=acct:user@example.com"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "somewhere-else.com")
               |> String.replace("{{nickname}}", "another-user")
               |> String.replace("{{subdomain}}", "somewhere-else.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://somewhere-else.com/.well-known/webfinger?resource=acct:user@example.com"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}

        %{url: "https://somewhere-else.com/users/another-user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/fep-2c59/user-with-webfinger.json")
               |> String.replace("{{nickname}}", "another-user")
               |> String.replace("{{domain}}", "somewhere-else.com")
               |> String.replace("{{webfinger_property}}", "oops-you-cant-redirect-here@nope.com")
           }}
      end)

      {:error, :finger_data_mismatch} = Finger.finger_mention("@user@example.com")
    end

    test "should refetch the initial actor if no backlink exists on the final actor" do
      Tesla.Mock.mock(fn
        # first, the initial webfinger we fetch points to somewhere-else.com
        %{
          url: "https://example.com/.well-known/webfinger?resource=acct:user@example.com"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "somewhere-else.com")
               |> String.replace("{{nickname}}", "another-user")
               |> String.replace("{{subdomain}}", "somewhere-else.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://somewhere-else.com/.well-known/webfinger?resource=acct:user@example.com"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}

        # then we fetch the actor, but no backlink on this one!
        %{url: "https://somewhere-else.com/users/another-user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/pleroma-user.json")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{domain}}", "example.com")
           }}

        # so we need to refetch this one
        %{url: "https://example.com/users/user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/pleroma-user.json")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{domain}}", "example.com")
           }}

        # and finally refetch the webfinger resource from the ID found above
        %{
          url: "https://example.com/.well-known/webfinger?resource=https://example.com/users/user"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "example.com")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{subdomain}}", "example.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://example.com/.well-known/webfinger?resource=https://example.com/users/user"
           }}
      end)

      assert {:ok, "user@example.com"} =
               Finger.finger_mention("@user@example.com")
    end

    test "should reject when the actor refetch does not agree with the intial query" do
      Tesla.Mock.mock(fn
        # first, the initial webfinger we fetch points to somewhere-else.com
        %{
          url: "https://example.com/.well-known/webfinger?resource=acct:user@example.com"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "somewhere-else.com")
               |> String.replace("{{nickname}}", "another-user")
               |> String.replace("{{subdomain}}", "somewhere-else.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://somewhere-else.com/.well-known/webfinger?resource=acct:user@example.com"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}

        # then we fetch the actor, but no backlink on this one!
        %{url: "https://somewhere-else.com/users/another-user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/pleroma-user.json")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{domain}}", "example.com")
           }}

        # so we need to refetch this one - but oops, we have a data mismatch in here!
        %{url: "https://example.com/users/user"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "application/activity+json"}],
             body:
               File.read!("test/fixtures/webfinger/pleroma-user.json")
               |> String.replace("{{nickname}}", "not-a-user-we-expected")
               |> String.replace("{{domain}}", "example.com")
           }}
      end)

      assert {:error, :id_mismatch} =
               Finger.finger_mention("@user@example.com")
    end
  end

  describe "finger_actor/1" do
    test "should use the webfinger property if it exists" do
      Tesla.Mock.mock(fn
        # we should finger the webfinger property
        %{
          url:
            "https://example.com/.well-known/webfinger?resource=https://social.example.com/users/user"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "example.com")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{subdomain}}", "social.example.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://example.com/.well-known/webfinger?resource=https://social.example.com/users/user"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}
      end)

      # all of the following are valid forms the webfinger property can take
      possible_forms = [
        # the expected
        "user@example.com",
        # a leading @
        "@user@example.com",
        # prefixed with acct:,
        "acct:user@example.com",
        # with both, because why not honestly
        "acct:@user@example.com"
      ]

      for form <- possible_forms do
        assert {:ok, "user@example.com"} =
                 Finger.finger_actor(%{
                   "id" => "https://social.example.com/users/user",
                   "webfinger" => form
                 })
      end
    end

    test "should not permit a redirect on the webfinger" do
      Tesla.Mock.mock(fn
        # we should finger the webfinger property
        %{
          url:
            "https://example.com/.well-known/webfinger?resource=https://social.example.com/users/user"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "example.com")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{subdomain}}", "social.example.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url: "https://oops-this-was-a-redirect/somewhere"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}
      end)

      assert {:error, :redirect} =
               Finger.finger_actor(%{
                 "id" => "https://social.example.com/users/user",
                 "webfinger" => "user@example.com"
               })
    end

    test "should fallback to user@domain if no webfinger property is present on the actor" do
      Tesla.Mock.mock(fn
        # we should finger the ID directly
        %{
          url: "https://example.com/.well-known/webfinger?resource=https://example.com/users/user"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/pleroma-webfinger.json")
               |> String.replace("{{domain}}", "example.com")
               |> String.replace("{{nickname}}", "user")
               |> String.replace("{{subdomain}}", "example.com"),
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://example.com/.well-known/webfinger?resource=https://example.com/users/user"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}
      end)

      assert {:ok, "user@example.com"} =
               Finger.finger_actor(%{
                 "id" => "https://example.com/users/user"
               })
    end

    test "should gracefully handle the username being an empty string" do
      # oopsie we had the wrong format
      assert {:error, :no_domain} =
               Finger.finger_actor(%{
                 "id" => "https://social.example.com/users/user",
                 "webfinger" => "@oops"
               })
    end

    test "should gracefully handle the webfinger returning something silly" do
      Tesla.Mock.mock(fn
        # we should finger the ID directly
        %{
          url: "https://example.com/.well-known/webfinger?resource=https://example.com/users/user"
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: "woah this isn't json???",
             headers: [{"content-type", "application/jrd+json"}],
             url:
               "https://example.com/.well-known/webfinger?resource=https://example.com/users/user"
           }}

        %{url: "https://example.com/.well-known/host-meta"} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               File.read!("test/fixtures/webfinger/masto-host-meta.xml")
               |> String.replace("{{domain}}", "example.com")
           }}
      end)

      # a nil error is expected here, nothing technically went wrong for the caller to think about
      # a remote issue isn't our concern
      assert {:ok, nil} =
               Finger.finger_actor(%{
                 "id" => "https://example.com/users/user"
               })
    end
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
        url: "https://mastodon.social/.well-known/webfinger?resource=acct:emelie@mastodon.social"
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
        url: "https://pawoo.net/.well-known/webfinger?resource=acct:pekorino@pawoo.net"
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
        url: "https://bad.com/.well-known/webfinger?resource=acct:meanie@bad.com"
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
      %{url: "https://bad.com/.well-known/webfinger?resource=acct:meanie@bad.com"} ->
        fake_webfinger =
          File.read!("test/fixtures/webfinger/imposter-webfinger.json") |> Jason.decode!()

        Tesla.Mock.json(fake_webfinger)

      %{url: "https://bad.com/.well-known/host-meta"} ->
        {:ok, %Tesla.Env{status: 404}}
    end)

    assert {:error, :finger_domain_spoof} = Finger.finger_mention("meanie@bad.com")
  end
end
