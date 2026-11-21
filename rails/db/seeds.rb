# frozen_string_literal: true

return unless Rails.env.development? || ENV["SEED_ADMIN"] == "1"

email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
password = ENV.fetch("ADMIN_PASSWORD", "password")

admin = User.find_or_initialize_by(email: email.downcase)
admin.name = "Admin"
admin.password = password if admin.new_record? || ENV["ADMIN_PASSWORD"].present?
admin.admin = true
admin.save!

team = Team.find_or_create_by!(slug: ENV.fetch("SEED_TEAM_SLUG", "demo")) do |record|
  record.name = ENV.fetch("SEED_TEAM_NAME", "Demo")
end

Membership.find_or_create_by!(team: team, user: admin) do |membership|
  membership.role = "admin"
end

jira = Connection.find_or_create_by!(team: team, provider: "jira", base_url: ENV.fetch("SEED_JIRA_URL", "https://example.atlassian.net")) do |connection|
  connection.name = "Jira"
  connection.deployment = "cloud"
end

confluence = Connection.find_or_create_by!(team: team, provider: "confluence", base_url: ENV.fetch("SEED_CONFLUENCE_URL", "https://example.atlassian.net/wiki")) do |connection|
  connection.name = "Confluence"
  connection.deployment = "cloud"
end

project = Project.find_or_create_by!(team: team, slug: ENV.fetch("SEED_PROJECT_SLUG", "demo-project")) do |record|
  record.name = ENV.fetch("SEED_PROJECT_NAME", "Demo project")
  record.jira_connection = jira
  record.confluence_connection = confluence
  record.jira_keys = [ENV.fetch("SEED_JIRA_KEY", "CLD")]
  record.spaces = [ENV.fetch("SEED_SPACE", "CLD")]
end

{
  "my_work" => ["Моя работа", "assignee = currentUser() AND statusCategory != Done", 20],
  "sprint" => ["Мой спринт", "assignee = currentUser() AND sprint in openSprints()", 20],
  "review" => ["На ревью", "assignee = currentUser() AND status in (Review, \"In Review\")", 20],
  "blocked" => ["Заблокировано", "status = Blocked OR flagged = Impediment", 20],
  "recent" => ["Недавно обновлено", "assignee = currentUser() AND updated >= -7d", 20]
}.each do |key, (label, query, limit)|
  Preset.find_or_create_by!(project: project, kind: "jql", key: key) do |preset|
    preset.label = label
    preset.query = query
    preset.order_by = "updated DESC"
    preset.default_limit = limit
  end
end

Preset.find_or_create_by!(project: project, kind: "cql", key: "runbooks") do |preset|
  preset.label = "Runbooks"
  preset.query = "label = runbook AND type = page"
  preset.order_by = "lastmodified DESC"
  preset.default_limit = 10
end

puts "Seeded admin #{admin.email} / team #{team.slug} / project #{project.slug}"
