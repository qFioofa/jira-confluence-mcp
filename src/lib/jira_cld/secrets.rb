# frozen_string_literal: true

require "open3"
require "shellwords"
require "timeout"

module JiraCld
  module Secrets
    module_function

    def resolve(ref, env: ENV, provider: nil)
      return nil if ref.nil? || ref.to_s.empty?

      kind, value = parse_ref(ref, provider: provider)
      case kind
      when :env
        secret = env[value]
        raise SecretError, "secret env variable #{value} is not set" if secret.nil? || secret.empty?

        secret
      when :file
        path = File.expand_path(value)
        raise SecretError, "secret file not found: #{path}" unless File.file?(path)

        secret = File.read(path).strip
        raise SecretError, "secret file is empty: #{path}" if secret.empty?

        secret
      when :command
        run_command(value)
      when :keyring
        run_command("secret-tool lookup service #{Shellwords.escape(value)}")
      else
        raise SecretError, "unsupported secret reference #{ref.inspect}"
      end
    end

    def parse_ref(ref, provider: nil)
      text = ref.to_s
      return [provider.to_sym, text] if provider && !text.include?(":")

      kind, value = text.split(":", 2)
      unless value && !value.empty? && %w[env file command keyring].include?(kind)
        raise SecretError, "invalid secret reference #{ref.inspect}; use env:NAME, file:PATH, command:CMD or keyring:NAME"
      end

      [kind.to_sym, value]
    end

    def run_command(command)
      argv = Shellwords.split(command)
      raise SecretError, "empty secret command" if argv.empty?

      out = err = nil
      status = nil
      Timeout.timeout(10) do
        out, err, status = Open3.capture3(*argv)
      end
      unless status.success?
        detail = err.to_s.strip.lines.first
        raise SecretError, "secret command failed#{" (#{detail})" if detail && !detail.empty?}"
      end

      secret = out.strip
      raise SecretError, "secret command returned empty output" if secret.empty?

      secret
    rescue Errno::ENOENT => e
      raise SecretError, "secret command is not available: #{e.message}"
    rescue Timeout::Error
      raise SecretError, "secret command timed out"
    end

    def mask(value)
      value.nil? || value.empty? ? nil : "********"
    end

    def describe(ref, env: ENV, provider: nil)
      resolve(ref, env: env, provider: provider)
      { ref: ref, status: "ok" }
    rescue SecretError => e
      { ref: ref, status: "error", error: e.message }
    end
  end
end
