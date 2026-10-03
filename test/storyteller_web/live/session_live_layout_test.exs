defmodule StorytellerWeb.SessionLiveLayoutTest do
  use ExUnit.Case, async: true

  @stylesheet Path.expand("../../../assets/css/app.css", __DIR__)

  test "roomy desktop can scroll the main column to reach the composer" do
    css = File.read!(@stylesheet)
    roomy_desktop = "@media (min-width: 1024px) and (min-height: 700px)"
    [short_or_narrow_css, roomy_desktop_css] = String.split(css, roomy_desktop, parts: 2)

    refute short_or_narrow_css =~ "html:has(body.tabletop-shell .play-page)"
    refute short_or_narrow_css =~ "body.tabletop-shell:has(.play-page)"

    assert [page_shell_rules] =
             Regex.run(
               ~r/html:has\(body\.tabletop-shell \.play-page\),\s*body\.tabletop-shell:has\(\.play-page\) \{([^}]+)\}/,
               roomy_desktop_css,
               capture: :all_but_first
             )

    assert page_shell_rules =~ "overflow: hidden;"

    assert [main_rules] =
             Regex.run(
               ~r/\.play-page > div:has\(> #campaign-panels\) > \.grid:has\(> main\) > main \{([^}]+)\}/,
               css,
               capture: :all_but_first
             )

    assert main_rules =~ "overflow-x: hidden;"
    assert main_rules =~ "overflow-y: auto;"

    assert [story_rules] =
             Regex.run(~r/\.play-page #story-timeline \{([^}]+)\}/, css, capture: :all_but_first)

    assert story_rules =~ "overflow-y: auto;"
  end
end
