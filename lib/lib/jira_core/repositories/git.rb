# frozen_string_literal: true

require "time"

module JiraCore
  module Repositories
    class Git
      PER_REPO_CAP = 100.0
      MAX_WINDOW_DAYS = 3650

      attr_reader :config, :cache

      def initialize(config:, cache: nil, logger: nil)
        @config = config
        @cache = cache
        @logger = logger
        @repos = Array(config.git_repos).map do |repo|
          ::JiraCore::Git::LocalRepo.new(
            id: repo["id"], path: repo["path"], url: repo["url"], provider: repo["provider"],
            default_branch: repo["default_branch"], jira_keys: repo["jira_keys"],
            components: repo["components"], authors: repo["authors"], logger: logger
          )
        end
      end

      def enabled?
        !@repos.empty?
      end

      def repos
        @repos
      end

      def list
        @repos.map do |repo|
          {
            "id" => repo.id,
            "url" => repo.url,
            "provider" => repo.provider,
            "default_branch" => repo.default_branch,
            "jira_keys" => repo.jira_keys,
            "components" => repo.components.keys,
            "path" => repo.path,
            "available" => repo.available?
          }.compact
        end
      end

      def experts(issue_key: nil, repo: nil, path: nil, component: nil, since: "180d", limit: 5)
        criteria = [issue_key, repo, path, component].compact.reject { |value| value.to_s.empty? }
        raise ArgumentError, "one of issue_key, repo, path or component is required" if criteria.empty?

        selected = select_repos(repo, issue_key)
        raise ArgumentError, "unknown git repository #{repo}" if repo && selected.empty?

        window = normalize_since(since)
        issue_commits = {}
        unless issue_key.to_s.empty?
          selected.each do |item|
            issue_commits[item.id] = safe { item.commits(grep: issue_key, since: window, limit: 200, include_files: true) } || []
          end
        end
        paths = relevant_paths(selected, path, component, issue_commits)
        entries = {}
        selected.each do |item|
          aggregate(item, issue_commits[item.id] || [], entries, weight: 5.0, kind: "issue_commit")
          Array(paths[item.id]).each do |path_filter|
            commits = safe { item.commits(since: window, path_filter: path_filter, limit: 200) } || []
            aggregate(item, commits, entries, weight: 2.0, kind: "path_commit")
          end
        end

        experts = entries.values.filter_map { |entry| finalize_entry(entry) }
                        .sort_by { |entry| -entry["score"] }
                        .first([limit.to_i, 1].max.clamp(1, 20))
        {
          "criteria" => {
            "issue_key" => issue_key, "repo" => repo, "path" => path,
            "component" => component, "since" => since
          }.compact,
          "experts" => experts,
          "bus_factor" => bus_factor(experts),
          "repositories" => selected.map { |item| item.id },
          "gaps" => gaps(selected, issue_key, experts),
          "warnings" => []
        }
      end

      def find_issue_refs(key, repos: [], since: "365d", limit: 20)
        raise ArgumentError, "key is required" if key.to_s.empty?

        selected = select_repos(nil, key)
        filter = Array(repos).map(&:to_s).reject(&:empty?)
        selected = selected.select { |item| filter.include?(item.id) } unless filter.empty?
        window = normalize_since(since)
        commits = []
        branches = []
        warnings = []
        selected.each do |item|
          unless item.available?
            warnings << { "source" => "git:#{item.id}", "code" => "repo_unavailable",
                          "message" => "repository is not available on this host" }
            next
          end
          (safe { item.commits(grep: key, since: window, limit: limit, include_files: true) } || []).each do |commit|
            commits << commit.merge("repo" => item.id, "url" => item.commit_url(commit["sha"]))
          end
          branches.concat(item.branches_matching(key).map { |branch| branch.merge("repo" => item.id) })
        end
        {
          "key" => key.to_s.upcase,
          "commits" => commits,
          "branches" => branches,
          "repositories" => selected.map(&:id),
          "warnings" => warnings
        }
      end

      def file_history(repo_id, path, since: "180d", limit: 50)
        item = find_repo!(repo_id)
        raise ArgumentError, "path is required" if path.to_s.empty?

        commits = safe { item.file_history(path_filter: path, since: normalize_since(since), limit: limit) } || []
        {
          "repo" => item.id,
          "path" => path,
          "commits" => commits.map { |commit| commit.merge("repo" => item.id, "url" => item.commit_url(commit["sha"])) },
          "total" => commits.length
        }
      end

      def search_code(repo_id, pattern, path: nil, limit: 50)
        item = find_repo!(repo_id)
        raise ArgumentError, "pattern is required" if pattern.to_s.empty?

        matches = safe { item.search_code(pattern, path_filter: path, limit: limit) } || []
        { "repo" => item.id, "pattern" => pattern, "matches" => matches, "total" => matches.length }
      end

      private

      def select_repos(repo_id, issue_key)
        selected = if repo_id.to_s.empty?
                     @repos
                   else
                     @repos.select { |item| item.id == repo_id.to_s }
                   end
        if issue_key.to_s.empty? == false
          prefix = issue_key.to_s.split("-").first.to_s.upcase
          scoped = selected.select { |item| item.jira_keys.empty? || item.jira_keys.include?(prefix) }
          selected = scoped unless scoped.empty?
        end
        selected
      end

      def find_repo!(repo_id)
        @repos.find { |item| item.id == repo_id.to_s } ||
          raise(ArgumentError, "unknown git repository #{repo_id}")
      end

      def relevant_paths(selected, path, component, issue_commits)
        result = {}
        selected.each do |item|
          paths = []
          paths << path.to_s unless path.to_s.empty?
          mapped = item.component_path(component)
          paths << mapped unless mapped.to_s.empty?
          if paths.empty? && !issue_commits[item.id].to_a.empty?
            files = issue_commits[item.id].flat_map { |commit| Array(commit["files"]) }.uniq
            paths.concat(files.map { |file| File.dirname(file) }.reject { |dir| dir == "." }.uniq.first(5))
          end
          paths << nil if paths.empty?
          result[item.id] = paths.uniq
        end
        result
      end

      def aggregate(repo, commits, entries, weight:, kind:)
        Array(commits).each do |commit|
          next if repo.bot?(commit)

          key = identity_key(commit)
          entry = entries[key] ||= {
            "name" => commit["author"], "email" => commit["email"].to_s.downcase,
            "per_repo" => Hash.new(0.0), "seen" => [], "commits" => 0, "files" => 0, "lines" => 0,
            "kinds" => [], "evidence" => [], "last_active" => nil
          }
          next if entry["seen"].include?(commit["sha"])

          entry["seen"] << commit["sha"]
          contribution = weight * recency_multiplier(commit["date"])
          current = entry["per_repo"][repo.id]
          entry["per_repo"][repo.id] = [current + contribution, PER_REPO_CAP].min
          entry["commits"] += 1
          entry["files"] += commit["files_changed"].to_i
          entry["lines"] += commit["lines_added"].to_i + commit["lines_deleted"].to_i
          entry["kinds"] << kind
          entry["last_active"] = latest_time(entry["last_active"], commit["date"])
          entry["evidence"] << evidence_item(repo, commit, kind)
        end
      end

      def finalize_entry(entry)
        return nil if entry["commits"].zero?

        score = entry["per_repo"].values.sum + (0.5 * Math.log1p([entry["lines"], 50_000].min))
        person = jira_person(entry)
        {
          "git_identity" => { "name" => entry["name"] }.compact,
          "jira_person" => person,
          "identity_confidence" => person ? "high" : "low",
          "score" => score.round(2),
          "confidence" => confidence(entry),
          "role_hint" => role_hints(entry),
          "last_active" => entry["last_active"]&.iso8601,
          "counts" => {
            "commits" => entry["commits"],
            "files_touched" => entry["files"],
            "lines_changed" => entry["lines"]
          },
          "repositories" => entry["per_repo"].keys,
          "evidence" => entry["evidence"].first(10)
        }
      end

      def jira_person(entry)
        mapped = @config.git_author_map[entry["email"]] ||
                 @config.git_author_map[entry["name"].to_s.downcase]
        mapped ||= @repos.filter_map do |repo|
          repo.authors[entry["email"]] || repo.authors[entry["name"].to_s.downcase]
        end.first
        case mapped
        when Hash
          {
            "account_id" => mapped["account_id"] || mapped[:account_id],
            "display_name" => mapped["display_name"] || mapped[:display_name] || entry["name"]
          }.compact
        when String
          { "account_id" => mapped, "display_name" => entry["name"] }
        end
      end

      def role_hints(entry)
        hints = []
        hints << "issue_author" if entry["kinds"].include?("issue_commit")
        hints << "frequent_contributor" if entry["commits"] >= 5
        hints << "recent_author" if recent?(entry, 30)
        hints
      end

      def confidence(entry)
        return "high" if entry["commits"] >= 10 && recent?(entry, 90)
        return "high" if entry["kinds"].include?("issue_commit") && recent?(entry, 180)
        return "medium" if entry["commits"] >= 3 || recent?(entry, 180)

        "low"
      end

      def recent?(entry, days)
        entry["last_active"] && entry["last_active"] > Time.now - (days * 86_400)
      end

      def recency_multiplier(value)
        time = parse_time(value)
        return 0.5 unless time

        age_days = (Time.now - time) / 86_400
        return 1.0 if age_days <= 30
        return 0.7 if age_days <= 90
        return 0.4 if age_days <= 180

        0.2
      end

      def latest_time(current, value)
        time = parse_time(value)
        return current unless time
        return time unless current

        time > current ? time : current
      end

      def parse_time(value)
        Time.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def identity_key(commit)
        email = commit["email"].to_s.downcase
        email.empty? ? commit["author"].to_s.downcase : email
      end

      def evidence_item(repo, commit, kind)
        {
          "source" => "git_commit",
          "repo" => repo.id,
          "sha" => commit["sha"].to_s[0, 12],
          "title" => commit["subject"],
          "date" => commit["date"],
          "url" => repo.commit_url(commit["sha"]),
          "kind" => kind,
          "files_changed" => commit["files_changed"].to_i
        }.compact
      end

      def bus_factor(experts)
        return {} if experts.empty?

        total = experts.sum { |entry| entry["score"].to_f }
        top = experts.first["score"].to_f
        share = total.positive? ? (top / total).round(2) : nil
        note = if share && share >= 0.6
                 "high concentration: one author accounts for #{(share * 100).round}% of changes"
               end
        { "top1_share" => share, "note" => note }.compact
      end

      def gaps(selected, issue_key, experts)
        gaps = []
        if selected.empty?
          gaps << { "source" => "git", "reason" => "no matching repositories",
                    "hint" => "configure GIT_REPOS and jira_keys" }
        elsif selected.none?(&:available?)
          gaps << { "source" => "git", "reason" => "repositories are not available on this host",
                    "hint" => "mount or clone the repositories" }
        elsif experts.empty?
          gaps << { "source" => "git", "reason" => "no recent commits matched",
                    "hint" => "widen since or check the path/component mapping" }
        end
        if issue_key.to_s.empty? == false && experts.none? { |entry| entry["role_hint"].include?("issue_author") }
          gaps << { "source" => "git", "reason" => "no commit mentions #{issue_key}",
                    "hint" => "the branch may not be merged or the key is formatted differently" }
        end
        gaps
      end

      def normalize_since(value)
        text = value.to_s.strip
        return "365 days ago" if text.empty?

        match = text.match(/\A(\d+)([dwmy])\z/i)
        return text unless match

        units = { "d" => "days", "w" => "weeks", "m" => "months", "y" => "years" }
        "#{match[1].to_i} #{units[match[2].downcase]} ago"
      end

      def safe
        yield
      rescue ::JiraCore::Git::Error => e
        @logger&.warn("git command failed", error: e.message)
        nil
      end
    end
  end
end
