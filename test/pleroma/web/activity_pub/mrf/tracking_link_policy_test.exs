defmodule Pleroma.Web.ActivityPub.MRF.TrackingLinkPolicyTest do
  use Pleroma.DataCase

  alias Pleroma.Web.ActivityPub.MRF.TrackingLinkPolicy

  defp assert_query_params_equal(url, params) do
    new_params =
      url
      |> URI.parse()
      |> Map.get(:query)
      |> URI.query_decoder()
      |> Enum.to_list()

    assert(Enum.count(new_params) == Enum.count(params), "Params differ in length")

    assert(
      Enum.all?(new_params, fn pair ->
        Enum.member?(params, pair)
      end),
      "Params do not match"
    )
  end

  defp assert_params_rewritten(input_url, params) do
    {:ok, %{"object" => %{"content" => new_url}}} =
      TrackingLinkPolicy.filter(%{
        "type" => "Create",
        "object" => %{"content" => input_url}
      })

    assert_query_params_equal(new_url, params)
  end

  defp assert_url_unchanged(input_url) do
    {:ok, %{"object" => %{"content" => new_url}}} =
      TrackingLinkPolicy.filter(%{
        "type" => "Create",
        "object" => %{"content" => input_url}
      })

    assert input_url == new_url
  end

  describe "youtube" do
    test "strips non-permitted URL parameters" do
      clear_config([:mrf_tracking_link, :youtube], true)

      assert_params_rewritten(
        "https://youtube.com?v=1&t=2&ci=3&thing=4&list=5&index=6&start_radio=true",
        [{"v", "1"}, {"t", "2"}, {"list", "5"}, {"index", "6"}, {"start_radio", "true"}]
      )

      assert_params_rewritten(
        "https://youtu.be?v=1&t=2&ci=3&thing=4&list=5&index=6&start_radio=true",
        [{"v", "1"}, {"t", "2"}, {"list", "5"}, {"index", "6"}, {"start_radio", "true"}]
      )
    end

    test "does nothing on other domains" do
      clear_config([:mrf_tracking_link, :youtube], true)

      assert_url_unchanged(
        "https://youtube.net?v=1&t=2&ci=3&thing=4&list=5&index=6&start_radio=true"
      )
    end

    test "does nothing when disabled" do
      clear_config([:mrf_tracking_link, :youtube], false)

      assert_url_unchanged(
        "https://youtube.com?v=1&t=2&ci=3&thing=4&list=5&index=6&start_radio=true"
      )
    end
  end
end
