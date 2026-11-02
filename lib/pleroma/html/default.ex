defmodule Pleroma.HTML.Scrubbers.Default do
  @behaviour Pleroma.HTML.Scrubbers.Behaviour

  @impl true
  def extensions(), do: []

  @impl true
  def transform(html), do: html

  @impl true
  def sanitize_config() do
    [
      strip_comments: true,
      add_allowed_classes: %{
        "a" => ["hashtag", "u-url", "mention"],
        "p" => ["quote-inline"],
        "code" => ["inline"],
        "span" => [
          "h-card",
          "quote-inline",
          "mfm-center",
          "mfm-flip",
          "mfm-font",
          "mfm-blur",
          "mfm-rotate",
          "mfm-x2",
          "mfm-x3",
          "mfm-x4",
          "mfm-position",
          "mfm-scale",
          "mfm-fg",
          "mfm-bg",
          "mfm-crop",
          "mfm-border",
          "mfm-unixtime",
          # The following are the animated MFM
          "mfm-jelly",
          "mfm-twitch",
          "mfm-shake",
          "mfm-spin",
          "mfm-jump",
          "mfm-bounce",
          "mfm-rainbow",
          "mfm-tada",
          "mfm-sparkle",
          "mfm-fade",
          "mfm-followmouse",
          # MFM legacy
          # This is for backwards compatibility with posts formatted on Akkoma before support for FEP-c16b
          "mfm",
          "mfm _mfm_tada_",
          "mfm _mfm_jelly_",
          "mfm _mfm_twitch_",
          "mfm _mfm_shake_",
          "mfm _mfm_spin_",
          "mfm _mfm_jump_",
          "mfm _mfm_bounce_",
          "mfm _mfm_flip_",
          "mfm _mfm_x2_",
          "mfm _mfm_x3_",
          "mfm _mfm_x4_",
          "mfm _mfm_blur_",
          "mfm _mfm_rainbow_"
        ]
      },
      add_tag_attribute_values: %{
        "a" => %{
          "rel" => [
            "tag",
            "nofollow",
            "noopener",
            "noreferrer",
            "ugc",
            "tag ugc",
            "ugc tag"
          ]
        }
      },
      add_tag_attributes: %{
        "a" => ["name", "title"],
        "abbr" => ["title"],
        "span" => [
          "data-mfm-h",
          "data-mfm-v",
          "data-mfm-x",
          "data-mfm-y",
          "data-mfm-alternate",
          "data-mfm-speed",
          "data-mfm-deg",
          "data-mfm-left",
          "data-mfm-serif",
          "data-mfm-monospace",
          "data-mfm-cursive",
          "data-mfm-fantasy",
          "data-mfm-emoji",
          "data-mfm-math",
          "data-mfm-color",
          "data-mfm-delay",
          "data-mfm-out",
          "data-mfm-top",
          "data-mfm-right",
          "data-mfm-bottom",
          "data-mfm-width",
          "data-mfm-radius",
          "data-mfm-style",
          "data-mfm-rotateByVelocity",
          "data-mfm-loop",
          # Not yet covered by the FEP; speculative name
          "data-mfm-unixtime",
          # MFM legacy
          # This is for backwards compatibility with posts formatted on Akkoma before support for FEP-c16b
          "data-x",
          "data-y",
          "data-h",
          "data-v",
          "data-left"
        ]
      },
      add_tags: [
        "b",
        "blcokquote",
        "br",
        "code",
        "del",
        "em",
        "hr",
        "i",
        "li",
        "ol",
        "p",
        "pre",
        "strong",
        "sub",
        "sup",
        "ruby",
        "rb",
        "rp",
        "rt",
        "rtc",
        "u",
        "ul"
      ]
    ]
  end
end
