# frozen_string_literal: true

module ApplicationHelper
  def hint(text)
    content_tag(
      :span,
      class: "jira-tooltip",
      tabindex: 0,
      role: "note",
      "aria-label": t("common.explanation", text: text),
      "data-tooltip": text
    ) do
      content_tag(:span, "?", class: "jira-tooltip-icon", "aria-hidden": "true")
    end
  end

  def field_label(form, attribute, label, hint_text)
    content_tag(:div, class: "flex items-center gap-1.5") do
      safe_join([
        form.label(attribute, label, class: "text-sm font-semibold"),
        hint(hint_text)
      ])
    end
  end

  def nav_link_to(label, path)
    classes = ["nav-link"]
    active = current_page?(path) || (path != root_path && request.path.start_with?(path))
    classes << "nav-link-active" if active
    link_to label, path, class: classes.join(" ")
  end

  def status_badge(status, label: nil)
    tone = {
      "ok" => "badge-success",
      "error" => "badge-error",
      "revoked" => "badge-error",
      "unknown" => "badge-ghost"
    }.fetch(status.to_s, "badge-ghost")
    content_tag(:span, label || status, class: "badge #{tone} badge-sm")
  end

  def provider_badge(provider)
    tone = provider.to_s == "jira" ? "badge-info" : "badge-accent"
    content_tag(:span, provider, class: "badge #{tone} badge-sm")
  end
end
