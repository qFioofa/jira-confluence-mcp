# frozen_string_literal: true

module JiraCore
  module Repositories
    class Context
      SOURCES = %w[jira kb git people].freeze
      CATEGORIES = %w[acceptance scope behavior data_api ux dependencies nfr rollout analytics docs].freeze
      TECHNICAL = %w[data_api nfr dependencies rollout].freeze
      PRIORITY_ORDER = { "blocking" => 0, "high" => 1, "medium" => 2, "low" => 3 }.freeze

      def initialize(config:, issues:, knowledge_base:, people:, git: nil, logger: nil)
        @config = config
        @issues = issues
        @knowledge_base = knowledge_base
        @people = people
        @git = git
        @logger = logger
      end

      def task_context(key, sources: nil, depth: "standard", since: "180d", limits: nil)
        sources = normalize_sources(sources)
        limits = normalize_limits(limits, depth)
        warnings = []
        brief = @issues.brief(key, intent: "understand", depth: depth,
                                      include: brief_include(sources), limits: limits)
        issue = brief["issue"]
        kb_pages = sources.include?("kb") ? collect_kb(issue, limits[:kb], warnings) : []
        git_section = sources.include?("git") ? collect_git(issue, since, limits, warnings) : nil
        people_section = sources.include?("people") ? collect_people(issue, depth, limits, git_section, warnings) : nil

        result = {
          "issue" => issue,
          "context" => build_context(issue, brief, git_section, people_section),
          "acceptance_criteria" => Array(brief["acceptance_criteria"]),
          "decisions" => Array(brief["decisions"]),
          "open_questions" => Array(brief["open_questions"]),
          "dependencies" => Array(brief["dependencies"]),
          "related_issues" => Array(brief["similar"]),
          "knowledge_base" => kb_pages,
          "git" => git_section,
          "people" => people_section,
          "timeline" => build_timeline(issue, brief, git_section),
          "gaps" => build_gaps(sources, issue, brief, kb_pages, git_section, people_section),
          "warnings" => warnings + Array(git_section && git_section["warnings"]) +
                        Array(people_section && people_section["warnings"]),
          "citations" => build_citations(issue, kb_pages, git_section, people_section)
        }.compact
        result["context_markdown"] = task_markdown(result)
        result
      end

      def clarify_issue(key, audience: "analyst", focus: nil, include: nil, max_questions: 10)
        focus = normalize_focus(focus)
        sources = normalize_sources(include || %w[jira kb git])
        warnings = []
        brief = @issues.brief(key, intent: "understand", depth: "standard",
                                      include: %w[comments changelog links similar],
                                      limits: normalize_limits({}, "standard"))
        issue = brief["issue"]
        kb_pages = sources.include?("kb") ? collect_kb(issue, 5, warnings) : []
        git_section = sources.include?("git") ? collect_git(issue, "365d", { commits: 10, people: 5 }, warnings) : nil
        recipients = build_recipients(issue, git_section, warnings)
        questions = build_questions(issue, brief, git_section, focus)
        attach_kb(questions, kb_pages)
        attach_recipients(questions, recipients)
        questions = order_questions(questions).first([[max_questions.to_i, 1].max, 20].min)
        questions.each_with_index { |question, index| question["id"] = "Q#{index + 1}" }

        result = {
          "issue" => issue,
          "readiness" => readiness(questions),
          "questions" => questions,
          "recipients" => recipients,
          "resolved" => [],
          "gaps" => clarify_gaps(kb_pages, git_section, recipients),
          "warnings" => warnings + Array(git_section && git_section["warnings"]),
          "citations" => clarify_citations(issue, questions, recipients)
        }
        result["message_markdown"] = clarify_markdown(result, audience)
        result
      end

      private

      def normalize_sources(value)
        list = Array(value).map(&:to_s).reject(&:empty?)
        list = SOURCES if list.empty?
        list & SOURCES
      end

      def normalize_focus(value)
        list = Array(value).map(&:to_s).reject(&:empty?)
        return CATEGORIES if list.empty? || list.include?("all")

        list & CATEGORIES
      end

      def normalize_limits(limits, depth)
        deep = depth.to_s == "deep"
        base = {
          comments: deep ? 100 : 30,
          changelog: deep ? 100 : 30,
          similar: deep ? 10 : 5,
          kb: deep ? 10 : 5,
          commits: deep ? 20 : 10,
          people: deep ? 10 : 5
        }
        (limits || {}).each do |key, value|
          symbol = key.to_s.to_sym
          base[symbol] = value.to_i if base.key?(symbol) && value.to_i.positive?
        end
        base
      end

      def brief_include(sources)
        return [] unless sources.include?("jira")

        %w[comments changelog links similar]
      end

      def collect_kb(issue, limit, warnings)
        return [] unless @knowledge_base&.enabled?

        queries = [
          issue["summary"],
          Array(issue["components"]).join(" "),
          Array(issue["labels"]).join(" "),
          first_terms(issue["description"], 6)
        ].map(&:to_s).map(&:strip).reject(&:empty?).uniq
        pages = {}
        queries.each do |query|
          data = @knowledge_base.search(query: query, limit: limit)
          Array(data["pages"]).each do |page|
            id = page["id"].to_s
            entry = pages[id] ||= page.merge("matched_terms" => [])
            entry["matched_terms"] |= [query[0, 60]]
          end
        rescue StandardError => e
          warnings << warning(e, "knowledge_base")
        end
        pages.values.sort_by { |page| -Array(page["matched_terms"]).length }.first(limit)
      end

      def collect_git(issue, since, limits, warnings)
        return nil unless @git&.enabled?

        refs = @git.find_issue_refs(issue["key"], since: since, limit: limits[:commits])
        experts = @git.experts(issue_key: issue["key"], component: Array(issue["components"]).first,
                               since: since, limit: limits[:people])
        {
          "repositories" => refs["repositories"],
          "commits" => refs["commits"],
          "branches" => refs["branches"],
          "experts" => experts["experts"],
          "bus_factor" => experts["bus_factor"],
          "gaps" => Array(experts["gaps"]),
          "warnings" => Array(refs["warnings"]) + Array(experts["warnings"])
        }
      rescue StandardError => e
        warnings << warning(e, "git")
        nil
      end

      def collect_people(issue, depth, limits, git_section, warnings)
        return nil unless @people

        who = @people.who_knows(issue_key: issue["key"], depth: depth, sources: %w[jira kb],
                               limit: limits[:people], window: 365)
        {
          "key_contributors" => Array(git_section && git_section["experts"]).first(3),
          "participants" => Array(who["people"]),
          "bus_factor" => git_section && git_section["bus_factor"],
          "gaps" => Array(who["gaps"]),
          "warnings" => Array(who["warnings"])
        }
      rescue StandardError => e
        warnings << warning(e, "people")
        nil
      end

      def build_context(issue, brief, git_section, people_section)
        {
          "goal" => goal(issue),
          "scope" => scope(issue),
          "non_goals" => section_items(issue["description"], /(out of scope|non-goals|не входит|вне скоупа)/i),
          "constraints" => constraints(issue, brief),
          "current_state" => current_state(issue),
          "recent_changes" => recent_changes(brief, git_section),
          "risks" => risks(brief, people_section),
          "key_people_note" => key_people_note(people_section),
          "confidence" => context_confidence(brief, git_section, people_section)
        }.compact
      end

      def goal(issue)
        paragraphs = issue["description"].to_s.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
        text = paragraphs.first.to_s.gsub(/\A#+\s*/, "")
        text = issue["summary"].to_s if text.empty?
        text[0, 500]
      end

      def scope(issue)
        [Array(issue["components"]), Array(issue["labels"]), Array(issue["fix_versions"])].flatten.compact.map(&:to_s).uniq
      end

      def section_items(description, header)
        lines = description.to_s.lines.map(&:chomp)
        start = lines.index { |line| line.match?(header) }
        return [] unless start

        items = []
        lines[(start + 1)..].to_a.each do |line|
          break if line.match?(/\A\s*#+\s/)

          item = line.sub(/\A\s*[-*]\s+/, "").strip
          items << item unless item.empty?
        end
        items.first(10)
      end

      def constraints(issue, brief)
        list = Array(brief["dependencies"]).map { |dep| "#{dep["type"]}: #{dep["key"]}" }
        list << "due #{issue["due"]}" if issue["due"]
        list.first(10)
      end

      def current_state(issue)
        parts = [issue["status"]]
        parts << "assignee: #{issue.dig("assignee", "display_name")}" if issue["assignee"]
        parts << "resolution: #{issue["resolution"]}" if issue["resolution"]
        parts.compact.join("; ")
      end

      def recent_changes(brief, git_section)
        changes = Array(brief["recent_changes"]).first(3).map do |entry|
          "#{entry["field"]}: #{entry["from"]} -> #{entry["to"]}"
        end
        changes.concat(Array(git_section && git_section["commits"]).first(3).map do |commit|
          "#{commit["repo"]}: #{commit["subject"]}"
        end)
        changes.first(5)
      end

      def risks(brief, people_section)
        list = []
        list << "no acceptance criteria" if Array(brief["acceptance_criteria"]).empty?
        count = Array(brief["open_questions"]).length
        list << "#{count} open questions in the description" if count.positive?
        blockers = Array(brief["dependencies"]).select { |dep| dep["type"].to_s.match?(/block/i) }
        list << "blocking dependencies: #{blockers.map { |dep| dep["key"] }.join(", ")}" unless blockers.empty?
        bus = people_section && people_section["bus_factor"]
        list << bus["note"] if bus && bus["note"]
        list
      end

      def key_people_note(people_section)
        expert = Array(people_section && people_section["key_contributors"]).first
        return nil unless expert

        name = expert.dig("jira_person", "display_name") || expert.dig("git_identity", "name")
        counts = expert["counts"] || {}
        "Most changes in related paths: #{name} (#{counts["commits"]} commits, last #{expert["last_active"]}). " \
          "This is a signal, not a confirmed owner."
      end

      def context_confidence(brief, git_section, people_section)
        score = 1
        score += 1 if Array(brief["acceptance_criteria"]).any?
        score += 1 if git_section && Array(git_section["commits"]).any?
        score += 1 if people_section && Array(people_section["participants"]).any?
        case score
        when 4 then "high"
        when 3 then "medium"
        else "low"
        end
      end

      def build_timeline(issue, brief, git_section)
        items = []
        items << { "at" => issue["created"], "source" => "jira", "type" => "created",
                   "title" => issue["summary"], "url" => issue["url"] }
        Array(brief["comments"]).each do |comment|
          author = comment.dig("author", "display_name")
          items << { "at" => comment["created"], "source" => "jira", "type" => "comment",
                     "title" => [author, comment["body"].to_s[0, 120]].compact.join(": "),
                     "url" => comment_url(issue, comment) }
        end
        Array(brief["recent_changes"]).each do |entry|
          items << { "at" => entry["created"], "source" => "jira", "type" => "change",
                     "title" => "#{entry["field"]}: #{entry["from"]} -> #{entry["to"]}",
                     "url" => issue["url"] }
        end
        Array(git_section && git_section["commits"]).each do |commit|
          items << { "at" => commit["date"], "source" => "git", "type" => "commit",
                     "title" => "#{commit["repo"]}: #{commit["subject"]}", "url" => commit["url"] }
        end
        items.compact.sort_by { |item| item["at"].to_s }.reverse.first(20)
      end

      def comment_url(issue, comment)
        base = issue["url"]
        return nil unless base

        id = comment["id"]
        id ? "#{base}?focusedCommentId=#{id}" : base
      end

      def build_gaps(sources, issue, brief, kb_pages, git_section, people_section)
        gaps = []
        if Array(brief["acceptance_criteria"]).empty?
          gaps << { "source" => "jira", "reason" => "no acceptance criteria",
                    "hint" => "ask the analyst for measurable outcomes" }
        end
        if sources.include?("kb") && kb_pages.empty?
          gaps << { "source" => "kb", "reason" => "no matching pages",
                    "hint" => "widen the query or check the space allowlist" }
        end
        if sources.include?("git")
          if git_section.nil?
            gaps << { "source" => "git", "reason" => "git is not configured or unavailable",
                      "hint" => "set GIT_REPOS to a local repository" }
          elsif Array(git_section["commits"]).empty?
            gaps << { "source" => "git", "reason" => "no commits mention #{issue["key"]}",
                      "hint" => "check branch naming or widen since" }
          end
        end
        gaps.concat(Array(git_section && git_section["gaps"]))
        gaps.concat(Array(people_section && people_section["gaps"]).map { |reason| { "source" => "people", "reason" => reason } })
        gaps
      end

      def build_citations(issue, kb_pages, git_section, people_section)
        list = []
        list << { "source" => "jira_issue", "title" => issue["key"], "url" => issue["url"] } if issue["url"]
        kb_pages.each { |page| list << { "source" => "kb_page", "title" => page["title"], "url" => page["url"] } }
        Array(git_section && git_section["commits"]).each do |commit|
          list << { "source" => "git_commit", "title" => commit["subject"], "url" => commit["url"] }
        end
        Array(people_section && people_section["key_contributors"]).each do |expert|
          url = expert.dig("evidence", 0, "url")
          next unless url

          name = expert.dig("jira_person", "display_name") || expert.dig("git_identity", "name")
          list << { "source" => "git_commit", "title" => name, "url" => url }
        end
        list.uniq { |item| item["url"] }.first(30)
      end

      def build_recipients(issue, git_section, warnings)
        list = []
        if @people
          who = @people.who_knows(issue_key: issue["key"], depth: "standard", sources: %w[jira kb],
                                 limit: 5, window: 365)
          Array(who["people"]).each do |person|
            list << {
              "display_name" => person["display_name"],
              "account_id" => person["account_id"],
              "why" => "participated in the issue or related knowledge base",
              "confidence" => person["confidence"],
              "topics" => topics_for_person(person),
              "evidence" => Array(person["evidence"]).first(3)
            }.compact
          end
          warnings.concat(Array(who["warnings"]))
        end
        Array(git_section && git_section["experts"]).each do |expert|
          name = expert.dig("jira_person", "display_name") || expert.dig("git_identity", "name")
          next if name.to_s.empty?
          next if list.any? { |recipient| recipient["display_name"].to_s.casecmp?(name.to_s) }

          list << {
            "display_name" => name,
            "account_id" => expert.dig("jira_person", "account_id"),
            "why" => "recent author of related paths in git",
            "confidence" => expert["confidence"],
            "topics" => %w[data_api nfr dependencies],
            "evidence" => Array(expert["evidence"]).first(3)
          }.compact
        end
        list.first(5).each_with_index { |recipient, index| recipient["id"] = "R#{index + 1}" }
        list
      rescue StandardError => e
        warnings << warning(e, "people")
        []
      end

      def topics_for_person(person)
        sources = Array(person["evidence"]).map { |item| item["source"].to_s }
        topics = []
        topics.concat(%w[behavior scope]) if sources.any? { |source| source.start_with?("jira") }
        topics.concat(%w[data_api nfr dependencies]) if sources.any? { |source| source.start_with?("git") }
        topics.concat(%w[scope behavior]) if sources.include?("confluence_page")
        topics.empty? ? CATEGORIES : topics.uniq
      end

      def build_questions(issue, brief, git_section, focus)
        questions = []
        description = issue["description"].to_s
        ac = Array(brief["acceptance_criteria"])
        components = Array(issue["components"])
        labels = Array(issue["labels"]).map(&:downcase)
        commits = Array(git_section && git_section["commits"])
        files = commits.flat_map { |commit| Array(commit["files"]) }
        api_hint = files.any? { |file| file.match?(%r{(api|controller|serializer|schema|migration|openapi|graphql)}i) } ||
                   commits.any? { |commit| commit["subject"].to_s.match?(/(api|endpoint|field|schema|migration|contract)/i) }

        if focus.include?("acceptance")
          if ac.empty?
            add_question(questions, category: "acceptance", priority: "blocking",
                                    question: "What observable outcomes define done for this task?",
                                    why: "without measurable acceptance criteria the task cannot be verified or accepted",
                                    evidence: [evidence_issue(issue)])
          elsif !measurable?(ac)
            add_question(questions, category: "acceptance", priority: "high",
                                    question: "How should each acceptance criterion be verified in measurable terms?",
                                    why: "criteria exist but are not measurable, so completion is subjective",
                                    evidence: [evidence_issue(issue)])
          end
          if ac.length < 2 || !description.match?(/(error|invalid|empty|timeout|permission|edge|failure)/i)
            add_question(questions, category: "acceptance", priority: "high",
                                    question: "Which edge, error and empty-state cases must be handled?",
                                    why: "only the happy path is described; negative cases affect implementation and testing",
                                    evidence: [evidence_issue(issue)])
          end
        end

        if focus.include?("scope") && components.empty? &&
           !description.match?(/(in scope|out of scope|scope|входит|не входит|компонент)/i)
          add_question(questions, category: "scope", priority: "blocking",
                                  question: "Which components, environments and user roles are in scope?",
                                  why: "scope is not stated, so impact, ownership and testing are unclear",
                                  evidence: [evidence_issue(issue)])
        end

        if focus.include?("ux") && description.match?(/(ui|screen|page|form|button|email|notification|ux)/i) &&
           !description.match?(/(empty|error|loading|disabled|permission)/i)
          add_question(questions, category: "ux", priority: "high",
                                  question: "What are the expected empty, loading, error and permission states?",
                                  why: "the UI flow is mentioned but its states and failure behavior are not specified",
                                  evidence: [evidence_issue(issue)])
        end

        if focus.include?("data_api") && api_hint
          add_question(questions, category: "data_api", priority: "high",
                                  question: "Which contract changes are intended (fields, validation, status codes) and what is the backward-compatibility expectation?",
                                  why: "git shows changes in a contract area, but the intended behavior is not stated",
                                  evidence: commits.first(3).map { |commit| evidence_commit(commit) })
        end

        if focus.include?("dependencies")
          Array(brief["dependencies"]).each do |dep|
            add_question(questions, category: "dependencies", priority: "blocking",
                                    question: "What is the contract and sequencing with #{dep["key"]} (#{dep["type"]})?",
                                    why: "a linked dependency can block start or change the implementation",
                                    evidence: [{ "source" => "jira_link", "key" => dep["key"], "type" => dep["type"],
                                                 "url" => issue["url"] }])
          end
        end

        nfr_hint = (labels + components.map(&:downcase)).any? do |value|
          value.to_s.match?(/(performance|security|auth|privacy|rate|scale|latency)/)
        end || description.match?(/(latency|throughput|security|privacy|performance)/i)
        if focus.include?("nfr") && nfr_hint
          add_question(questions, category: "nfr", priority: "high",
                                  question: "What are the measurable non-functional targets (latency, throughput, security, privacy)?",
                                  why: "non-functional constraints affect architecture and acceptance",
                                  evidence: [evidence_issue(issue)])
        end

        type = issue["type"].to_s.downcase
        if focus.include?("rollout") && (type.match?(/feature|story|epic/) || labels.any? { |label| label.match?(/release|flag|rollout/) })
          add_question(questions, category: "rollout", priority: "medium",
                                  question: "Is a feature flag, staged rollout and rollback plan required?",
                                  why: "the release strategy is not specified",
                                  evidence: [evidence_issue(issue)])
        end

        if focus.include?("analytics") && type.match?(/feature|story/)
          add_question(questions, category: "analytics", priority: "medium",
                                  question: "Which events or metrics define success, and where should they be tracked?",
                                  why: "success measurement is not specified",
                                  evidence: [evidence_issue(issue)])
        end

        if focus.include?("acceptance")
          Array(brief["decisions"]).each do |decision|
            next unless decision["text"].to_s.length > 20

            add_question(questions, category: "acceptance", priority: "high",
                                    question: "Which decision in the comments is authoritative, and should it be reflected in the description and acceptance criteria?",
                                    why: "decisions in comments may conflict with the current description",
                                    evidence: [evidence_decision(issue, decision)])
            break
          end
        end

        Array(brief["open_questions"]).each do |question|
          add_question(questions, category: "scope", priority: "high", question: question,
                                  why: "the issue description already contains an unresolved question",
                                  evidence: [evidence_issue(issue)])
        end

        if commits.any? && !api_hint && focus.include?("behavior")
          add_question(questions, category: "behavior", priority: "high",
                                  question: "Commits already change this area; is the implemented behavior intended and should it be added to acceptance criteria?",
                                  why: "implementation may have started before the requirements are clear",
                                  evidence: commits.first(3).map { |commit| evidence_commit(commit) })
        end

        questions
      end

      def add_question(list, category:, priority:, question:, why:, evidence:, options: nil, answer_type: "text")
        text = question.to_s.strip
        return if text.empty?
        return if list.any? { |item| item["category"] == category && similar_question?(item["question"], text) }

        list << {
          "category" => category,
          "priority" => priority,
          "question" => text,
          "why_it_matters" => why,
          "suggested_options" => options,
          "answer_type" => answer_type,
          "owner" => owner_for(category),
          "evidence" => Array(evidence).compact,
          "already_answered_by" => [],
          "unblocks" => unblocks_for(category)
        }.compact
      end

      def similar_question?(left, right)
        left.to_s.downcase[0, 40] == right.to_s.downcase[0, 40]
      end

      def owner_for(category)
        case category
        when "data_api", "nfr", "dependencies", "rollout" then "tech_lead"
        when "docs" then "team"
        else "analyst"
        end
      end

      def unblocks_for(category)
        case category
        when "acceptance" then %w[implementation qa]
        when "dependencies" then %w[start]
        else %w[implementation]
        end
      end

      def measurable?(criteria)
        Array(criteria).any? do |item|
          item.to_s.match?(/\d|returns?|shows?|status|within|less than|greater than|>=|<=|error|success|должен|показ|верн/i)
        end
      end

      def evidence_issue(issue)
        { "source" => "jira_issue", "field" => "description",
          "quote" => issue["description"].to_s[0, 300], "url" => issue["url"] }.compact
      end

      def evidence_commit(commit)
        { "source" => "git_commit", "repo" => commit["repo"], "sha" => commit["sha"].to_s[0, 12],
          "title" => commit["subject"], "quote" => commit["subject"], "url" => commit["url"] }.compact
      end

      def evidence_decision(issue, decision)
        id = decision["source"].to_s.split(":").last
        url = if issue["url"] && !id.empty?
                "#{issue["url"]}?focusedCommentId=#{id}"
              else
                issue["url"]
              end
        { "source" => "jira_comment", "id" => id, "author" => decision["author"],
          "quote" => decision["text"].to_s[0, 300], "url" => url }.compact
      end

      def attach_kb(questions, pages)
        return if pages.empty?

        questions.each do |question|
          page = pages.find { |candidate| kb_match?(question, candidate) }
          next unless page

          question["already_answered_by"] = [{ "source" => "kb_page", "id" => page["id"],
                                               "title" => page["title"], "url" => page["url"] }]
          question["priority"] = "medium" if question["priority"] == "blocking"
        end
      end

      def kb_match?(question, page)
        tokens = tokens_for([question["question"], question["why_it_matters"], question["category"]].join(" "))
        haystack = [page["title"], page["excerpt"]].join(" ").downcase
        tokens.count { |token| haystack.include?(token) } >= 2
      end

      def tokens_for(text)
        text.to_s.downcase.scan(/[a-zа-я0-9_]{4,}/).uniq.first(20)
      end

      def attach_recipients(questions, recipients)
        return if recipients.empty?

        technical = recipients.select { |recipient| (Array(recipient["topics"]) & TECHNICAL).any? }
        technical = recipients if technical.empty?
        questions.each do |question|
          if TECHNICAL.include?(question["category"])
            match = technical.find { |recipient| Array(recipient["topics"]).include?(question["category"]) } || technical.first
            question["suggested_recipient_id"] = match && match["id"]
          else
            consult = technical.first
            question["consult"] = [consult["id"]].compact if consult
          end
        end
      end

      def order_questions(questions)
        questions.sort_by do |question|
          [PRIORITY_ORDER.fetch(question["priority"], 9), CATEGORIES.index(question["category"]) || 99]
        end
      end

      def readiness(questions)
        blocking = questions.count do |question|
          question["priority"] == "blocking" && Array(question["already_answered_by"]).empty?
        end
        high = questions.count { |question| question["priority"] == "high" }
        score = [[100 - (blocking * 15) - (high * 5), 0].max, 100].min
        reasons = questions.select { |question| %w[blocking high].include?(question["priority"]) }
                           .map { |question| question["why_it_matters"] }.uniq.first(5)
        { "can_start" => blocking.zero?, "blocking" => blocking, "score" => score, "reasons" => reasons }
      end

      def clarify_gaps(kb_pages, git_section, recipients)
        gaps = []
        gaps << { "source" => "clarify", "reason" => "no recipients found; ask the analyst directly" } if recipients.empty?
        gaps << { "source" => "kb", "reason" => "no KB pages matched; the answer may need research" } if kb_pages.empty?
        if git_section && Array(git_section["commits"]).empty?
          gaps << { "source" => "git", "reason" => "no commits mention the issue; code context is limited" }
        end
        gaps
      end

      def clarify_citations(issue, questions, recipients)
        list = []
        list << { "source" => "jira_issue", "title" => issue["key"], "url" => issue["url"] } if issue["url"]
        questions.each do |question|
          Array(question["evidence"]).each do |item|
            next unless item["url"]

            list << { "source" => item["source"], "title" => item["title"] || item["field"] || item["key"],
                      "url" => item["url"] }
          end
          Array(question["already_answered_by"]).each do |item|
            list << { "source" => "kb_page", "title" => item["title"], "url" => item["url"] } if item["url"]
          end
        end
        recipients.each do |recipient|
          Array(recipient["evidence"]).each do |item|
            next unless item["url"]

            list << { "source" => item["source"], "title" => item["title"] || item["title"], "url" => item["url"] }
          end
        end
        list.uniq { |item| item["url"] }.first(30)
      end

      def task_markdown(result)
        issue = result["issue"]
        context = result["context"] || {}
        lines = []
        lines << "# #{issue["key"]}: #{issue["summary"]}"
        lines << ""
        lines << "Status: #{issue["status"]} | Type: #{issue["type"]} | Priority: #{issue["priority"]}"
        lines << "Assignee: #{issue.dig("assignee", "display_name")}" if issue["assignee"]
        lines << ""
        append_section(lines, "Goal", context["goal"])
        append_list(lines, "Scope", context["scope"])
        append_list(lines, "Out of scope", context["non_goals"])
        append_list(lines, "Acceptance criteria", result["acceptance_criteria"])
        append_list(lines, "Recent changes", context["recent_changes"])
        append_list(lines, "Dependencies", result["dependencies"].map { |dep| "#{dep["type"]}: #{dep["key"]}" })
        append_list(lines, "Open questions", result["open_questions"])
        append_kb(lines, result["knowledge_base"])
        append_git(lines, result["git"])
        append_people(lines, result["people"])
        append_list(lines, "Gaps", result["gaps"].map { |gap| gap["reason"] })
        lines.join("\n")
      end

      def append_section(lines, title, value)
        return if value.to_s.empty?

        lines << "## #{title}"
        lines << value.to_s
        lines << ""
      end

      def append_list(lines, title, items)
        values = Array(items).compact.map(&:to_s).reject(&:empty?)
        return if values.empty?

        lines << "## #{title}"
        values.each { |value| lines << "- #{value}" }
        lines << ""
      end

      def append_kb(lines, pages)
        values = Array(pages)
        return if values.empty?

        lines << "## Knowledge base"
        values.each { |page| lines << "- [#{page["title"]}](#{page["url"]})" }
        lines << ""
      end

      def append_git(lines, git_section)
        return unless git_section

        commits = Array(git_section["commits"])
        return if commits.empty?

        lines << "## Git"
        commits.first(5).each do |commit|
          lines << "- [#{commit["sha"].to_s[0, 8]}](#{commit["url"]}) #{commit["subject"]} — #{commit["repo"]}"
        end
        lines << ""
      end

      def append_people(lines, people_section)
        return unless people_section

        contributors = Array(people_section["key_contributors"])
        return if contributors.empty?

        lines << "## People"
        contributors.each do |expert|
          name = expert.dig("jira_person", "display_name") || expert.dig("git_identity", "name")
          lines << "- #{name} (#{expert["confidence"]}) — #{Array(expert["role_hint"]).join(", ")}"
        end
        note = people_section.dig("bus_factor", "note")
        lines << "- #{note}" if note
        lines << ""
      end

      def clarify_markdown(result, audience)
        issue = result["issue"]
        readiness = result["readiness"]
        lines = []
        lines << "# Clarification request: #{issue["key"]} — #{issue["summary"]}"
        lines << ""
        lines << "Audience: #{audience}. Readiness: #{readiness["can_start"] ? "can start" : "blocked"} " \
                 "(blocking: #{readiness["blocking"]}, score: #{readiness["score"]})."
        lines << ""
        grouped = result["questions"].group_by { |question| question["priority"] }
        %w[blocking high medium low].each do |priority|
          items = grouped[priority]
          next if items.nil? || items.empty?

          lines << "## #{priority.capitalize}"
          items.each do |question|
            lines << "#{question["id"]}. [#{question["category"]}] #{question["question"]}"
            lines << "   Why: #{question["why_it_matters"]}"
            options = Array(question["suggested_options"])
            lines << "   Options: #{options.join(" / ")}" unless options.empty?
            evidence = Array(question["evidence"]).map { |item| evidence_label(item) }.compact
            lines << "   Evidence: #{evidence.join(", ")}" unless evidence.empty?
            covered = Array(question["already_answered_by"]).map { |item| "#{item["title"]} (#{item["url"]})" }
            lines << "   Possibly covered: #{covered.join(", ")}" unless covered.empty?
            recipient = recipient_label(result["recipients"], question)
            lines << "   Recipient: #{recipient}" if recipient
          end
          lines << ""
        end
        unless result["recipients"].empty?
          lines << "## Recipients"
          result["recipients"].each do |recipient|
            lines << "- #{recipient["display_name"]} — #{recipient["why"]} (confidence: #{recipient["confidence"]})"
          end
        end
        lines.join("\n")
      end

      def evidence_label(item)
        label = item["title"] || item["field"] || item["key"] || item["source"]
        item["url"] ? "[#{label}](#{item["url"]})" : label.to_s
      end

      def recipient_label(recipients, question)
        id = question["suggested_recipient_id"] || Array(question["consult"]).first
        recipient = recipients.find { |item| item["id"] == id }
        recipient && "#{recipient["display_name"]} (#{recipient["why"]})"
      end

      def first_terms(text, count)
        text.to_s.gsub(/[#*`>\-]/, " ").split(/\s+/).reject { |word| word.length < 4 }.first(count).join(" ")
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
