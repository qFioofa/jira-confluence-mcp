# frozen_string_literal: true

require "fileutils"
require "time"
require "active_record"

module JiraCld
  class DB
    MIGRATIONS_PATH = File.expand_path("../../db/migrate", __dir__)

    class << self
      attr_reader :config

      def setup!(config)
        @config = config
        connect_cache!(config)
        connect_reference!(config)
        connect_stats!(config)
        migrate! if config.db_auto_migrate?
        self
      end

      def connection
        ActiveRecord::Base.connection
      end

      def reference_connection
        Models::ReferenceRecord.connection
      end

      def stats_connection
        Models::StatsRecord.connection
      end

      def migrate!
        return unless File.directory?(MIGRATIONS_PATH)
        return if schema_current?

        ActiveRecord::Migration.verbose = false
        context = ActiveRecord::MigrationContext.new(MIGRATIONS_PATH)
        context.migrate
        connection.execute("ANALYZE")
      end

      def schema_current?
        tables = connection.exec_query(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('schema_migrations', 'cache_entries')"
        ).to_a
        return false unless tables.length == 2

        latest = Dir[File.join(MIGRATIONS_PATH, "[0-9]*_*.rb")].map do |path|
          File.basename(path)[/\A\d+/].to_i
        end.max || 0
        current = connection.select_value("SELECT MAX(version) FROM schema_migrations").to_i
        current >= latest
      rescue StandardError
        false
      end

      def checkpoint(mode = "PASSIVE")
        return unless connected?

        connection.execute("PRAGMA wal_checkpoint(#{mode})")
      rescue StandardError
        nil
      end

      def optimize!
        return unless connected?

        connection.execute("PRAGMA optimize")
      end

      def vacuum!
        connection.execute("VACUUM")
        connection.execute("PRAGMA optimize")
      end

      def integrity_check
        connection.select_value("PRAGMA integrity_check")
      end

      def size_bytes
        path = config&.db_path
        return 0 unless path && File.file?(path)

        page_count = connection.select_value("PRAGMA page_count").to_i
        freelist = connection.select_value("PRAGMA freelist_count").to_i
        page_size = connection.select_value("PRAGMA page_size").to_i
        [page_count - freelist, 0].max * page_size
      end

      def stats
        return {} unless connected?

        rows = connection.exec_query(
          "SELECT ns, COUNT(*) AS entries, COALESCE(SUM(size), 0) AS bytes, " \
          "MIN(fetched_at) AS oldest FROM cache_entries GROUP BY ns ORDER BY ns"
        ).to_a
        rows.map do |row|
          {
            namespace: row["ns"],
            entries: row["entries"].to_i,
            bytes: row["bytes"].to_i,
            oldest: row["oldest"] && Time.at(row["oldest"].to_i / 1000.0).utc.iso8601
          }
        end
      end

      def disconnected_reason
        ActiveRecord::Base.connection_pool.disconnect!
        Models::ReferenceRecord.connection_pool.disconnect!
        Models::StatsRecord.connection_pool.disconnect!
      rescue StandardError
        nil
      end

      def disconnect!
        checkpoint("TRUNCATE")
        optimize!
        ActiveRecord::Base.connection_pool.disconnect!
        Models::ReferenceRecord.connection_pool.disconnect!
        Models::StatsRecord.connection_pool.disconnect!
      rescue StandardError
        nil
      end

      private

      def connected?
        ActiveRecord::Base.connected?
      end

      def connect_cache!(config)
        path = config.db_path
        new_file = ensure_path(path, page_size: config.db_page_size)
        ActiveRecord::Base.establish_connection(
          adapter: "sqlite3", database: path, pool: 1, timeout: 5000,
          pragmas: { "journal_mode" => "delete" }
        )
        ActiveRecord::Base.logger = nil
        ActiveRecord::Migration.verbose = false
        ActiveRecord.default_timezone = :utc
        apply_pragmas(connection, page_size: config.db_page_size, cache_kb: config.db_cache_size_kb,
                                  mmap_bytes: config.db_mmap_bytes, journal_limit: config.db_journal_size_limit,
                                  new_file: new_file)
        max_pages = [config.cache_max_bytes / config.db_page_size, 1].max + 1024
        connection.execute("PRAGMA max_page_count = #{max_pages.to_i}")
        safe_chmod(path, 0o600)
      end

      def connect_reference!(config)
        path = config.reference_db_path
        new_file = ensure_path(path, page_size: 4096)
        Models::ReferenceRecord.establish_connection(
          adapter: "sqlite3", database: path, pool: 1, timeout: 5000
        )
        conn = Models::ReferenceRecord.connection
        apply_pragmas(conn, page_size: 4096, cache_kb: 2048, mmap_bytes: config.db_mmap_bytes,
                            journal_limit: config.db_journal_size_limit, new_file: new_file)
        conn.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS reference_entries (
            ns TEXT NOT NULL,
            key TEXT NOT NULL,
            value_json TEXT NOT NULL,
            version TEXT,
            expires_at INTEGER,
            fetched_at INTEGER NOT NULL,
            PRIMARY KEY (ns, key)
          )
        SQL
        safe_chmod(path, 0o600)
      end

      def connect_stats!(config)
        path = config.stats_path
        new_file = ensure_path(path, page_size: 4096)
        Models::StatsRecord.establish_connection(
          adapter: "sqlite3", database: path, pool: 1, timeout: 5000
        )
        conn = Models::StatsRecord.connection
        apply_pragmas(conn, page_size: 4096, cache_kb: 2048, mmap_bytes: config.db_mmap_bytes,
                            journal_limit: config.db_journal_size_limit, new_file: new_file)
        conn.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS metric_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at INTEGER NOT NULL,
            project_id TEXT,
            kind TEXT NOT NULL,
            tool TEXT,
            outcome TEXT,
            cache TEXT,
            duration_ms REAL,
            meta_json TEXT
          )
        SQL
        conn.execute("CREATE INDEX IF NOT EXISTS index_metric_events_on_at ON metric_events (at)")
        conn.execute("CREATE INDEX IF NOT EXISTS index_metric_events_on_project ON metric_events (project_id, at)")
        conn.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS metric_counters (
            project_id TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL,
            value INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (project_id, name)
          )
        SQL
        conn.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS audit_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at INTEGER NOT NULL,
            project_id TEXT,
            action TEXT NOT NULL,
            source TEXT NOT NULL,
            request_id TEXT,
            detail_json TEXT
          )
        SQL
        safe_chmod(path, 0o600)
      end

      def safe_chmod(path, mode)
        File.chmod(mode, path)
      rescue SystemCallError
        nil
      end

      def ensure_path(path, page_size:)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir, mode: 0o700)
        safe_chmod(dir, 0o700)
        new_file = !File.exist?(path) || File.empty?(path)
        FileUtils.touch(path)
        safe_chmod(path, 0o600)
        new_file
      end

      def apply_pragmas(conn, page_size:, cache_kb:, mmap_bytes:, journal_limit:, new_file:)
        if new_file
          begin
            conn.execute("PRAGMA page_size = #{page_size.to_i}")
            conn.execute("VACUUM")
          rescue StandardError
            nil
          end
        end
        conn.execute("PRAGMA busy_timeout = 5000")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA temp_store = MEMORY")
        conn.execute("PRAGMA journal_size_limit = #{journal_limit.to_i}")
        conn.execute("PRAGMA cache_size = -#{cache_kb.to_i}")
        conn.execute("PRAGMA mmap_size = #{mmap_bytes.to_i}")
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA auto_vacuum = NONE")
        conn.execute("PRAGMA secure_delete = OFF")
      end
    end
  end
end
