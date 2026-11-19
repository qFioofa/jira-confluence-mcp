# frozen_string_literal: true

module JiraCore
  module Repositories
    class Issues
      SCOPE_TO_PRESET = {
        "assigned" => "my_work",
        "sprint" => "sprint",
        "review" => "review",
        "blocked" => "blocked",
        "recent" => "recent"
      }.freeze

      attr_reader :config, :jira, :cache, :knowledge_base

      def initialize(config:, jira:, cache:, knowledge_base: nil, logger: nil)
        @config = config
        @jira = jira
        @cache = cache
        @knowledge_base = knowledge_base
        @logger = logger
      end

      def search_issues(jql: nil, preset: nil, limit: 25, cursor: nil)
        raise Atlassian::QueryError.new("pass exactly one of jql or preset", query_code: :query_invalid) if !jql.nil? && !preset.nil?
        raise Atlassian::QueryError.new("either jql or preset is required", query_code: :query_invalid) if jql.nil? && preset.nil?

        if preset
          project = config.require_project!
          query, order_by, default_limit = Query::JQL.preset(project, preset)
          limit = default_limit if limit.nil?
          preset_source = Query::JQL.preset_source(project, preset)
        else
          query = jql.to_s
          order_by = Query::JQL::DEFAULT_ORDER
        end

        wrapped = Query::JQL.wrap(query, allowlist: config.jira_keys,
                                         order_by: order_by, max_chars: config.query_max_chars)
        logical = { query: wrapped, limit: limit, cursor: cursor }
        fetcher = lambda do
          raw = jira.search(jql: wrapped, limit: limit, cursor: cursor)
          {
            "issues" => raw[:issues].map { |issue| Serialize::Issue.compact(issue, base_url: config.base_url) },
            "next_cursor" => raw[:next_cursor],
            "total" => raw[:total],
            "deployment" => raw[:deployment]
          }
        end

        data = if cursor.nil?
                 cache.fetch(ns: "search", logical: logical, &fetcher)
               else
                 fetcher.call
               end
        result = data.merge("limit" => limit)
        if preset
          result["preset"] = preset.to_s
          result["preset_source"] = preset_source
        end
        result
      end

      def my_work(scope: "assigned", limit: 20, project_id: nil)
        raise ConfigError, "project #{project_id} is not bound to this server" if project_id && project_id.to_s != config.project_id

        preset_id = SCOPE_TO_PRESET[scope.to_s]
        unless preset_id
          raise Atlassian::QueryError.new("unknown my_work scope #{scope.inspect}", query_code: :query_invalid,
                                                                               hint: "use one of: #{SCOPE_TO_PRESET.keys.join(", ")}")
        end

        data = search_issues(preset: preset_id, limit: limit)
        issues = data["issues"].map { |issue| issue.merge(work_hints(issue, scope)) }
        data.merge("issues" => issues, "scope" => scope, "preset" => preset_id)
      end

      def get_issue(key, include: [])
        raw = raw_issue(key)
        result = { "issue" => Serialize::Issue.compact(raw, base_url: config.base_url) }
        include = Array(include).map(&:to_s)

        if include.include?("comments")
          begin
            result["comments"] = jira.comments(key, limit: 50)[:comments]
          rescue Atlassian::Error => e
            result["warnings"] = warnings(result) << warning(e, "comments")
          end
        end
        if include.include?("changelog")
          begin
            result["changelog"] = jira.changelog(key, limit: 50)[:entries]
          rescue Atlassian::Error => e
            result["warnings"] = warnings(result) << warning(e, "changelog")
          end
        end
        result["links"] = result["issue"]["links"] if include.include?("links")
        result
      end

      def brief(key, intent: "understand", depth: "standard", include: nil, limits: nil)
        raw = raw_issue(key)
        issue = Serialize::Issue.compact(raw, base_url: config.base_url)
        limits = normalize_limits(depth, limits)
        include = Array(include).map(&:to_s)
        include = %w[comments changelog links similar kb] if include.empty?
        result = {
          "issue" => issue,
          "intent" => intent,
          "depth" => depth,
          "acceptance_criteria" => acceptance_criteria(issue["description"]),
          "decisions" => [],
          "open_questions" => open_questions(issue["description"]),
          "dependencies" => dependency_keys(issue),
          "next_actions" => next_actions(issue, intent)
        }
        warnings = []

        if include.include?("comments")
          begin
            comments = jira.comments(key, limit: limits[:comments])[:comments]
            result["comments"] = comments
            result["decisions"] = decisions(comments)
          rescue Atlassian::Error => e
            warnings << warning(e, "comments")
          end
        end
        if include.include?("changelog")
          begin
            result["recent_changes"] = jira.changelog(key, limit: limits[:changelog])[:entries]
          rescue Atlassian::Error => e
            warnings << warning(e, "changelog")
          end
        end
        if include.include?("similar")
          begin
            result["similar"] = similar_issues(issue, limit: limits[:similar])
          rescue Atlassian::Error => e
            warnings << warning(e, "similar")
          end
        end
        if include.include?("kb") && knowledge_base
          begin
            result["knowledge_base"] = knowledge_base.search(query: issue["summary"], limit: limits[:kb])["pages"]
          rescue StandardError => e
            warnings << warning(e, "knowledge_base")
          end
        end

        if intent.to_s == "verify"
          result["acceptance_checklist"] = result["acceptance_criteria"].map do |item|
            { "item" => item, "checked" => false, "verification" => "manual" }
          end
        end

        result["warnings"] = warnings unless warnings.empty?
        result
      end

      def unblock(key: nil, query: nil, symptom: nil, window: "30d", limit: 5)
        raise Atlassian::QueryError.new("either key or query is required", query_code: :query_invalid) if key.nil? && query.nil?

        warnings = []
        issue = nil
        if key
          issue = Serialize::Issue.compact(raw_issue(key), base_url: config.base_url)
          text = [issue["summary"], symptom].compact.join(" ")
        else
          text = [query, symptom].compact.join(" ")
        end

        result = {
          "issue" => issue,
          "query" => query,
          "symptom" => symptom,
          "window" => window,
          "similar_resolved" => [],
          "experts" => [],
          "recent_changes" => [],
          "runbooks" => [],
          "hypotheses" => hypotheses(text, symptom),
          "questions" => []
        }

        begin
          result["similar_resolved"] = similar_issues({ "summary" => text }, limit: limit,
                                                                             window_days: window_days(window), resolved_only: true)
        rescue StandardError => e
          warnings << warning(e, "similar_resolved")
        end

        begin
          result["recent_changes"] = jira.changelog(key, limit: 20)[:entries] if key
        rescue StandardError => e
          warnings << warning(e, "recent_changes")
        end

        if knowledge_base
          begin
            preset = config.project&.cql_preset("runbooks") ? "runbooks" : nil
            result["runbooks"] = knowledge_base.search(query: text.split.first(8).join(" "), preset: preset, limit: limit)["pages"]
          rescue StandardError => e
            warnings << warning(e, "runbooks")
          end
        end

        result["experts"] = experts_from(result["similar_resolved"])
        result["questions"] = unblock_questions(result, text)
        result["warnings"] = warnings unless warnings.empty?
        result
      end

      def changelog(key, limit: 50, cursor: nil)
        jira.changelog(key, limit: limit, cursor: cursor)
      end

      def attachments(key)
        jira.attachments(key)
      end

      def issue_links(key)
        raw = raw_issue(key)
        links = Serialize::Issue.links(raw.dig("fields", "issuelinks"))
        { "key" => raw["key"] || key.to_s.upcase, "links" => links, "total" => links.length }
      end

      def boards(**options)
        jira.boards(**options)
      end

      def board_issues(board_id, jql: nil, limit: 50, cursor: nil)
        wrapped = Query::JQL.wrap(jql.to_s, allowlist: config.jira_keys,
                                               max_chars: config.query_max_chars)
        raw = jira.board_issues(board_id, jql: wrapped, limit: limit, cursor: cursor)
        {
          "issues" => Array(raw[:issues]).map { |issue| Serialize::Issue.compact(issue, base_url: config.base_url) },
          "next_cursor" => raw[:next_cursor],
          "total" => raw[:total],
          "jql" => wrapped,
          "deployment" => config.deployment
        }
      end

      def sprints(board_id, state: nil)
        jira.sprints(board_id, state: state)
      end

      def sprint_issues(sprint_id, limit: 50, cursor: nil)
        data = jira.sprint_issues(sprint_id, limit: limit, cursor: cursor)
        {
          "issues" => data[:issues].map { |issue| Serialize::Issue.compact(issue, base_url: config.base_url) },
          "next_cursor" => data[:next_cursor],
          "total" => data[:total]
        }
      end

      def raw_issue(key)
        enforce_key!(key)
        cache.fetch(ns: "issue", logical: { key: key.upcase }) do
          jira.issue(key)
        end
      end

      def comments(key, limit: 50)
        cache.fetch(ns: "comments", logical: { key: key.upcase }) do
          jira.comments(key, limit: limit)[:comments]
        end
      end

      private

      def enforce_key!(key)
        value = key.to_s.upcase
        raise Atlassian::Error.new("invalid issue key #{key.inspect}", code: :query_invalid, domain: :jira) unless value.match?(/\A[A-Z][A-Z0-9_]*-[0-9]+\z/)

        keys = config.jira_keys
        return value if keys.empty? || keys.include?(value.split("-").first)

        raise Atlassian::Error.new("issue #{value} is outside the project allowlist", code: :scope_forbidden,
                                                                                      domain: :jira)
      end

      def work_hints(issue, scope)
        status = issue["status"].to_s.downcase
        blocked = status.include?("blocked") || Array(issue["labels"]).any? { |label| label.to_s.downcase.include?("block") }
        {
          "why_now" => why_now(scope, issue),
          "next_action" => next_action(issue, blocked),
          "blockers" => blocked ? [{ "kind" => "status_or_label", "value" => issue["status"] }] : []
        }
      end

      def why_now(scope, _issue)
        case scope.to_s
        when "assigned" then "assigned to you and not done"
        when "sprint" then "in an open sprint assigned to you"
        when "review" then "waiting for your review"
        when "blocked" then "marked blocked or flagged"
        when "recent" then "updated recently (last 7 days)"
        else "matched preset for #{scope}"
        end
      end

      def next_action(issue, blocked)
        return "identify and remove the blocker" if blocked

        status = issue["status"].to_s.downcase
        return "review the change and leave feedback" if status.include?("review")
        return "verify acceptance criteria and close" if status.include?("done") || status.include?("closed")

        "continue implementation and update the issue"
      end

      def similar_issues(issue, limit: 5, window_days: nil, resolved_only: false)
        summary = issue["summary"].to_s.split.first(8).join(" ")
        return [] if summary.empty?

        clauses = [Query::JQL.text_query(summary)]
        clauses << "statusCategory = Done" if resolved_only
        clauses << "updated >= -#{window_days}d" if window_days
        result = search_issues(jql: Query::JQL.combine(*clauses), limit: limit)
        result["issues"].reject { |item| item["key"] == issue["key"] }
      end

      def acceptance_criteria(description)
        return [] if description.nil? || description.empty?

        lines = description.lines.map(&:chomp)
        start = lines.index do |line|
          line.match?(/\A\s*(#+\s*)?(acceptance criteria|ac|критерии приёмки|критерии приемки)\s*:?\s*\z/i)
        end
        selected = start ? lines[(start + 1)..] : []
        criteria = selected.take_while { |line| !line.match?(/\A\s*#+\s/) }
        items = criteria.filter_map do |line|
          if (match = line.match(/\A\s*[-*]\s*\[[ xX]\]\s*(.+)\z/))
            match[1].strip
          elsif line.match?(/\A\s*[-*]\s+\S/)
            line.sub(/\A\s*[-*]\s+/, "").strip
          end
        end
        items = description.lines.map(&:chomp).filter_map { |line| line[/\A\s*[-*]\s*\[[ xX]\]\s*(.+)\z/, 1]&.strip } if items.empty?
        items.uniq.first(20)
      end

      def open_questions(description)
        return [] if description.nil?

        description.lines.filter_map do |line|
          text = line.strip
          text if text.end_with?("?") && text.length > 8
        end.first(10)
      end

      def decisions(comments)
        comments.filter_map do |comment|
          body = comment["body"].to_s
          next unless body.match?(/\b(decision|decided|решили|решение|agreed)\b/i)

          { "source" => "comment:#{comment["id"]}", "author" => comment.dig("author", "display_name"), "text" => body[0, 500] }
        end.first(10)
      end

      def dependency_keys(issue)
        Array(issue["links"]).filter_map do |link|
          next unless link["type"].to_s.match?(/block|depend|relate|связ/i)

          { "key" => link["key"], "type" => link["type"], "direction" => link["direction"] }
        end
      end

      def next_actions(issue, intent)
        actions = []
        actions << "read acceptance criteria and confirm scope" if intent.to_s == "understand"
        actions << "break the work into implementation steps" if intent.to_s == "plan"
        actions << "verify each acceptance criterion and attach evidence" if intent.to_s == "verify"
        actions << "check linked issues for blockers" unless Array(issue["links"]).empty?
        actions
      end

      def experts_from(similar)
        counts = Hash.new { |hash, key| hash[key] = { person: nil, count: 0 } }
        similar.each do |issue|
          [issue["assignee"], issue["reporter"]].compact.each do |person|
            key = person["account_id"] || person["display_name"]
            next if key.nil? || person["bot"]

            counts[key][:person] = person
            counts[key][:count] += 1
          end
        end
        counts.values.sort_by { |item| -item[:count] }.first(5).map do |item|
          item[:person].merge("evidence_count" => item[:count],
                              "confidence" => Serialize::Person.confidence(item[:count]))
        end
      end

      def unblock_questions(result, text)
        questions = []
        questions << "Which component or change introduced the failure?" if result["similar_resolved"].empty?
        questions << "Which of the similar resolved issues matches this symptom closest?" unless result["similar_resolved"].empty?
        questions << "Is there an existing runbook for #{text.split.first(6).join(" ")}?" if result["runbooks"].empty?
        questions << "Who owned the most recent change touching this area?" if result["recent_changes"].empty?
        questions << "What evidence would confirm or reject the top hypothesis?"
        questions.first(5)
      end

      def hypotheses(text, symptom)
        base = [text, symptom].compact.join(" ").strip
        return [] if base.empty?

        [
          { "hypothesis" => "recent configuration or dependency change caused it", "confidence" => "low" },
          { "hypothesis" => "known failure mode exists in prior resolved issues", "confidence" => "medium" },
          { "hypothesis" => "environment or permission drift differs from working instances", "confidence" => "low" }
        ]
      end

      def window_days(window)
        case window.to_s
        when /(\d+)d/ then Regexp.last_match(1).to_i
        when /(\d+)w/ then Regexp.last_match(1).to_i * 7
        else 30
        end
      end

      def normalize_limits(depth, limits)
        deep = depth.to_s == "deep"
        base = {
          comments: deep ? 100 : 30,
          changelog: deep ? 100 : 30,
          similar: deep ? 10 : 5,
          kb: deep ? 10 : 5
        }
        (limits || {}).each do |key, value|
          base[key.to_sym] = value.to_i if base.key?(key.to_sym)
        end
        base
      end

      def warnings(result)
        result["warnings"] ||= []
      end

      def warning(error, source)
        {
          "source" => source,
          "code" => error.respond_to?(:code) ? error.code.to_s : "error",
          "message" => error.message
        }
      end
    end
  end
end
