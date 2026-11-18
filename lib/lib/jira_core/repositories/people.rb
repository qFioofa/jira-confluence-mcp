# frozen_string_literal: true

module JiraCore
  module Repositories
    class People
      def initialize(config:, issues:, knowledge_base: nil, logger: nil)
        @config = config
        @issues = issues
        @knowledge_base = knowledge_base
        @logger = logger
      end

      def who_knows(topic: nil, issue_key: nil, component: nil, label: nil, window: 180, limit: 5, depth: "standard")
        criteria = { topic: topic, issue_key: issue_key, component: component, label: label }.compact
        raise Atlassian::QueryError.new("one of topic, issue_key, component or label is required", query_code: :query_invalid) if criteria.empty?

        evidence = Hash.new { |hash, key| hash[key] = { person: nil, score: 0, items: [] } }
        warnings = []

        if issue_key
          begin
            raw = @issues.raw_issue(issue_key)
            issue = Serialize::Issue.compact(raw, base_url: @config.base_url)
            collect_issue_people(evidence, issue, weight: 2)
            if depth.to_s == "deep"
              @issues.comments(issue_key, limit: 50).each do |comment|
                add_person(evidence, comment["author"], weight: 3, item: evidence_item(
                  source: "jira_comment", id: "#{issue_key}:#{comment["id"]}", title: issue["summary"],
                  role: "commenter", date: comment["created"], url: issue["url"]
                ))
              end
            end
          rescue Atlassian::Error => e
            warnings << warning(e, "issue")
          end
        end

        begin
          jql = build_jql(topic: topic, component: component, label: label, window: window)
          found = @issues.search_issues(jql: jql, limit: 25)["issues"]
          found.each do |issue|
            collect_issue_people(evidence, issue, weight: 1)
            next unless depth.to_s == "deep"

            begin
              @issues.comments(issue["key"], limit: 20).each do |comment|
                add_person(evidence, comment["author"], weight: 2, item: evidence_item(
                  source: "jira_comment", id: "#{issue["key"]}:#{comment["id"]}", title: issue["summary"],
                  role: "commenter", date: comment["created"], url: issue["url"]
                ))
              end
            rescue Atlassian::Error => e
              warnings << warning(e, "comments:#{issue["key"]}")
            end
          end
        rescue Atlassian::Error => e
          warnings << warning(e, "jira_search")
        end

        if @knowledge_base&.enabled? && (topic || component)
          begin
            pages = @knowledge_base.search(query: topic || component, limit: 10)["pages"]
            pages.each do |page|
              add_person(evidence, page["author"], weight: 2, item: evidence_item(
                source: "confluence_page", id: page["id"], title: page["title"],
                role: "page_author", date: page["updated"], url: page["url"]
              ))
            end
          rescue StandardError => e
            warnings << warning(e, "knowledge_base")
          end
        end

        people = rank(evidence, limit)
        result = {
          "criteria" => criteria,
          "window_days" => window,
          "people" => people,
          "gaps" => gaps(people, topic: topic),
          "suggested_questions" => questions_for(topic || issue_key || component || label, people)
        }
        result["warnings"] = warnings unless warnings.empty?
        result
      end

      def prepare_question(issue_key: nil, topic: nil, person: nil, goal: nil, context: nil, urgency: "normal")
        raise Atlassian::QueryError.new("either issue_key or topic is required", query_code: :query_invalid) if issue_key.nil? && topic.nil?

        evidence = who_knows(issue_key: issue_key, topic: topic, limit: 5, depth: "standard")
        recipient = select_person(evidence["people"], person) || evidence["people"].first
        issue = issue_key ? safe_issue(issue_key) : nil
        questions = build_questions(goal: goal, issue: issue, topic: topic, recipient: recipient, context: context)
        links = []
        links << { "label" => issue["key"], "url" => issue["url"] } if issue && issue["url"]
        Array(recipient && recipient["evidence"]).first(5).each do |item|
          links << { "label" => item["title"] || item["id"], "url" => item["url"] } if item["url"]
        end

        {
          "urgent" => urgency.to_s,
          "goal" => goal,
          "context" => context,
          "recipient" => recipient,
          "questions" => questions,
          "links" => links.uniq { |item| item["url"] },
          "evidence" => recipient ? recipient["evidence"] : [],
          "requested_via" => nil,
          "sent" => false,
          "gaps" => evidence["gaps"],
          "warnings" => evidence["warnings"]
        }.compact
      end

      private

      def build_jql(topic:, component:, label:, window:)
        clauses = []
        clauses << Query::JQL.text_query(topic) if topic
        clauses << Query::JQL.component_query(component) if component
        clauses << Query::JQL.label_query(label) if label
        clauses << "updated >= -#{window.to_i}d"
        Query::JQL.combine(*clauses)
      end

      def collect_issue_people(evidence, issue, weight:)
        item = evidence_item(source: "jira_issue", id: issue["key"], title: issue["summary"],
                             role: "participant", date: issue["updated"], url: issue["url"])
        add_person(evidence, issue["assignee"], weight: weight + 1, item: item.merge("role" => "assignee"))
        add_person(evidence, issue["reporter"], weight: weight, item: item.merge("role" => "reporter"))
      end

      def add_person(evidence, person, weight:, item:)
        return unless person.is_a?(Hash) && !person["bot"]

        key = Serialize::Person.person_key(person)
        return if key.empty?

        entry = evidence[key]
        entry[:person] ||= person
        entry[:score] += weight
        entry[:items] << item unless entry[:items].any? { |existing| existing["id"] == item["id"] }
      end

      def rank(evidence, limit)
        evidence.values.sort_by { |entry| -entry[:score] }.first([limit.to_i, 1].max).map do |entry|
          count = entry[:items].length
          entry[:person].merge(
            "score" => entry[:score],
            "evidence_count" => count,
            "confidence" => Serialize::Person.confidence(count),
            "evidence" => entry[:items].uniq { |item| [item["source"], item["id"], item["role"]] }.first(10)
          )
        end
      end

      def gaps(people, topic: nil)
        gaps = []
        gaps << "no evidence found; try a wider window or another topic" if people.empty?
        gaps << "weak evidence: this is a signal, not a confirmed expert" if people.any? && people.all? { |person| person["evidence_count"].to_i < 2 }
        gaps << "emails are hidden by policy (TEAM_SHOW_EMAIL=0)" if people.any? && !@config.team_show_email?
        gaps << "no authoritative page collected for #{topic}" if topic && people.any? && people.none? do |p|
          Array(p["evidence"]).any? do |e|
            e["source"] == "confluence_page"
          end
        end
        gaps
      end

      def questions_for(subject, people)
        return ["Who is the current owner of #{subject}?"] if people.empty?

        [
          "What changed most recently around #{subject}?",
          "Which failure modes have you seen before?",
          "Which runbook or dashboard should we start from?",
          "What evidence would confirm the diagnosis?"
        ]
      end

      def select_person(people, person)
        return nil if people.empty?
        return people.first if person.nil? || person.to_s.empty?

        needle = person.to_s.downcase
        people.find do |candidate|
          [candidate["account_id"], candidate["name"], candidate["display_name"], candidate["email"]]
            .compact.any? { |value| value.to_s.downcase.include?(needle) }
        end
      end

      def safe_issue(key)
        Serialize::Issue.compact(@issues.raw_issue(key), base_url: @config.base_url)
      rescue Atlassian::Error
        nil
      end

      def build_questions(goal:, issue:, topic:, recipient:, context:)
        subject = issue ? "#{issue["key"]}: #{issue["summary"]}" : topic
        questions = []
        questions << question(
          "Could you confirm who owns #{subject} right now and who reviewed the latest change?",
          reason: "confirm ownership before asking for deep help",
          evidence: recipient ? recipient["evidence"].first : nil
        )
        questions << question(
          "What is the fastest way to reproduce the problem locally or on staging?",
          reason: "reduce turnaround and avoid guessing",
          evidence: recipient ? recipient["evidence"][1] : nil
        )
        if goal
          questions << question(
            "For the goal \"#{goal}\", which approach would you choose and why?",
            reason: "capture a decision and rationale",
            evidence: recipient ? recipient["evidence"][2] : nil
          )
        end
        if (open = issue && open_questions(issue["description"]).first)
          questions << question(
            "Could you clarify: #{open}",
            reason: "unresolved question from the issue description",
            evidence: { "source" => "jira_issue", "id" => issue["key"], "url" => issue["url"] }
          )
        end
        questions << question(
          "What runbook, dashboard or past incident should we check first?",
          reason: "reuse prior art before debugging from scratch",
          evidence: recipient ? recipient["evidence"].last : nil
        )
        questions << question(
          "What evidence would make you confident that the issue is resolved?",
          reason: "define verification criteria",
          evidence: nil
        )
        questions.first(5)
      end

      def question(text, reason:, evidence:)
        { "question" => text, "reason" => reason, "evidence" => evidence }.compact
      end

      def open_questions(description)
        return [] if description.nil?

        description.lines.filter_map { |line| line.strip if line.strip.end_with?("?") }.first(3)
      end

      def evidence_item(source:, id:, title:, role:, date:, url:)
        { "source" => source, "id" => id.to_s, "title" => title, "role" => role, "date" => date, "url" => url }.compact
      end

      def warning(error, source)
        { "source" => source, "code" => error.respond_to?(:code) ? error.code.to_s : "error", "message" => error.message }
      end
    end
  end
end
