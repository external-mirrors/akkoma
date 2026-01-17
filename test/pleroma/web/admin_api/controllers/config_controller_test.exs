# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.ConfigControllerTest do
  use Pleroma.Web.ConnCase

  import ExUnit.CaptureLog
  import Pleroma.Factory

  setup do
    admin = insert(:user, is_admin: true)
    token = insert(:oauth_admin_token, user: admin)

    conn =
      build_conn()
      |> assign(:user, admin)
      |> assign(:token, token)

    {:ok, %{admin: admin, token: token, conn: conn}}
  end

  describe "POST /api/pleroma/admin/config" do
    test "doesn't allow updating the database_config_whitelist itself", %{conn: conn} do
      original_whitelist = Pleroma.Config.get(:database_config_whitelist)

      refute ConfigDB.get_by_group_and_key(:pleroma, :database_config_whitelist)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":database_config_whitelist",
              value: [%{"tuple" => [":pleroma", ":key1"]}]
            }
          ]
        })

      %{"configs" => configs} = json_response_and_validate_schema(conn, 200)

      assert configs == []
      assert Pleroma.Config.get(:database_config_whitelist) == original_whitelist
      refute ConfigDB.get_by_group_and_key(:pleroma, :database_config_whitelist)
    end
  end

  describe "GET /api/pleroma/admin/config/descriptions" do
    test "all keys from description are whitelisted", %{conn: conn} do
      conn = get(conn, "/api/pleroma/admin/config/descriptions")

      assert response = json_response_and_validate_schema(conn, 200)

      assert length(response) == length(Pleroma.Docs.JSON.compiled_descriptions())
    end
  end
end
