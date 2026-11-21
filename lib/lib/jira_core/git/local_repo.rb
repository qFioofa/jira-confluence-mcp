# frozen_string_literal: true

require "open3"
require "timeout"
require "time"

module JiraCore
  module Git
    class LocalRepo
      COMMAND_TIMEOUT = 10
      MAX_OUTPUT = 2 * 1024 * 1024
      FIELD = "\x1f"
      COMMIT_MARK = "__JC__"
      MAX_FILES = 10
      BOT_PATTERN = /\[bot\]|dependabot|renovate|github-actions|jenkins|\bci\b/i
      NOISE_PATTERN = /\A(chore\(deps\)|build\(deps\)|bump .+ from|format|prettier|eslint --fix)/i

      attr_reader :id, :path, :url, :provider, :default_branch, :jira_keys, :components, :authors

      def initialize(id:, path:, url: nil, provider: "generic", default_branch: "main",
                     jira_keys: [], components: {}, authors: {}, logger: nil)
        @id = id.to_s
        @path = path.to_s
        @url = url.to_s.empty? ? nil : url.to_s.delete_suffix("/")
        @provider = provider.to_s
        @default_branch = default_branch.to_s
        @jira_keys = Array(jira_keys).map { |key| key.to_s.upcase }
        @components = components || {}
        @authors = authors || {}
        @logger = logger
      end

      def available?
        File.directory?(path) && File.exist?(File.join(path, ".git"))
      end

      def head_sha
        stdout, _stderr, status = run("rev-parse", "HEAD")
        status.success? ? stdout.strip : nil
      end

      def commits(grep: nil, since: nil, path_filter: nil, limit: 50, include_files: false)
        args = ["log", "--all", "--no-merges", "--max-count=#{limit.to_i.clamp(1, 500)}"]
        args << "--since=#{since}" if since.to_s.empty? == false
        if grep.to_s.empty? == false
          args << "--regexp-ignore-case"
          args << "--grep=#{grep}"
        end
        args << "--pretty=format:#{COMMIT_MARK}%H%x1f%an%x1f%ae%x1f%aI%x1f%s"
        args << "--numstat"
        args << "--" << path_filter.to_s if path_filter
        stdout, _stderr, status = run(*args)
        return [] unless status.success?

        parse_commits(stdout, include_files: include_files)
      end

      def file_history(path_filter:, since: nil, limit: 50)
        commits(since: since, path_filter: path_filter, limit: limit, include_files: true)
      end

      def branches_matching(text)
        stdout, _stderr, status = run(
          "for-each-ref", "--format=%(refname:short)%x1f%(objectname:short)%x1f%(committerdate:iso8601)",
          "refs/heads", "refs/remotes"
        )
        return [] unless status.success?

        needle = text.to_s.downcase
        stdout.lines.filter_map do |line|
          name, sha, date = line.chomp.split(FIELD, 3)
          next unless name.to_s.downcase.include?(needle)

          { "name" => name, "sha" => sha, "date" => date, "url" => branch_url(name) }
        end.first(20)
      end

      def search_code(pattern, path_filter: nil, limit: 50)
        return [] if pattern.to_s.empty?

        args = ["grep", "-n", "-I", "--fixed-strings", "-e", pattern.to_s[0, 200]]
        args << "--" << path_filter.to_s if path_filter
        stdout, _stderr, status = run(*args)
        return [] unless status.success? || status.exitstatus == 1

        stdout.lines.first([limit.to_i, 1].max.clamp(1, 200)).map do |line|
          file, line_number, text = line.chomp.split(":", 3)
          { "path" => file, "line" => line_number.to_i, "text" => text.to_s.strip,
            "url" => code_url(file, line_number) }
        end
      end

      def component_path(component)
        return nil if component.to_s.empty?

        components[component.to_s] || components[component.to_s.downcase]
      end

      def bot?(commit)
        author = commit["author"].to_s
        email = commit["email"].to_s
        subject = commit["subject"].to_s
        BOT_PATTERN.match?(author) || BOT_PATTERN.match?(email) || NOISE_PATTERN.match?(subject)
      end

      def commit_url(sha)
        return nil unless url

        case provider
        when "gitlab" then "#{url}/-/commit/#{sha}"
        when "bitbucket" then "#{url}/commits/#{sha}"
        else "#{url}/commit/#{sha}"
        end
      end

      def branch_url(name)
        return nil unless url

        case provider
        when "gitlab" then "#{url}/-/tree/#{name}"
        when "bitbucket" then "#{url}/branch/#{name}"
        else "#{url}/tree/#{name}"
        end
      end

      def code_url(file, line = nil)
        return nil unless url

        base = case provider
               when "gitlab" then "#{url}/-/blob/#{default_branch}/#{file}"
               when "bitbucket" then "#{url}/src/#{default_branch}/#{file}"
               else "#{url}/blob/#{default_branch}/#{file}"
               end
        line.to_i.positive? ? "#{base}#L#{line}" : base
      end

      private

      def parse_commits(output, include_files:)
        commits = []
        current = nil
        output.each_line do |raw|
          line = raw.chomp
          if line.start_with?(COMMIT_MARK)
            sha, author, email, date, subject = line.delete_prefix(COMMIT_MARK).split(FIELD, 5)
            current = {
              "sha" => sha, "author" => author, "email" => email, "date" => date, "subject" => subject,
              "files_changed" => 0, "lines_added" => 0, "lines_deleted" => 0, "files" => []
            }
            commits << current
          elsif current && line.match?(/\A\d+\t/)
            added, deleted, file = line.split("\t", 3)
            current["files_changed"] += 1
            current["lines_added"] += added.to_i
            current["lines_deleted"] += deleted.to_i
            if include_files && file && current["files"].length < MAX_FILES
              current["files"] << file
            end
          end
        end
        commits
      end

      def run(*args)
        raise Error, "repository #{id} is not available at #{path}" unless available?

        command = ["git", "-C", path, *args.map(&:to_s)]
        stdout = +""
        stderr = +""
        status = nil
        Timeout.timeout(COMMAND_TIMEOUT) do
          stdout, stderr, status = Open3.capture3(*command)
        end
        output = stdout.byteslice(0, MAX_OUTPUT).to_s.force_encoding(Encoding::UTF_8).scrub
        [output, stderr.to_s, status]
      rescue Timeout::Error
        raise Error, "git command timed out in #{id}"
      rescue Errno::ENOENT
        raise Error, "git executable is not available"
      end
    end
  end
end
