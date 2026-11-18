# frozen_string_literal: true

require_relative "test_helper"

class RenderTest < BaseTest
  def test_adf_to_text
    doc = {
      "type" => "doc",
      "content" => [
        { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [{ "type" => "text", "text" => "Summary" }] },
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Hello ", "marks" => [{ "type" => "strong" }] },
                                               { "type" => "text", "text" => "world",
                                                 "marks" => [{ "type" => "link", "attrs" => { "href" => "https://x" } }] }] },
        { "type" => "bulletList", "content" => [
          { "type" => "listItem", "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "one" }] }] },
          { "type" => "listItem", "content" => [{ "type" => "paragraph", "content" => [{ "type" => "text", "text" => "two" }] }] }
        ] }
      ]
    }
    text = JiraCld::Render::ADF.to_text(doc)
    assert_includes text, "Summary"
    assert_includes text, "**Hello **"
    assert_includes text, "[world](https://x)"
    assert_includes text, "- one"
    assert_includes text, "- two"
  end

  def test_html_to_text_strips_scripts_and_macros
    html = '<p>Hello <strong>world</strong></p><script>alert(1)</script><ac:macro ac:name="toc"/>'
    text = JiraCld::Render::HTML.to_text(html)
    assert_includes text, "Hello"
    assert_includes text, "world"
    refute_includes text, "alert(1)"
    assert_includes JiraCld::Render::HTML.to_text("<ul><li>a</li><li>b</li></ul>"), "- a"
  end

  def test_adf_handles_plain_strings
    assert_equal "plain", JiraCld::Render::ADF.to_text("plain")
    assert_equal "", JiraCld::Render::ADF.to_text(nil)
  end
end
