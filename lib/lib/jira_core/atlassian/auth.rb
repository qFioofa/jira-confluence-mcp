# frozen_string_literal: true

require "base64"

module JiraCore
  module Atlassian
    module Auth
      module_function

      def headers(config, service: :jira)
        case service
        when :jira
          return bearer(config.jira_oauth_token, "JIRA_OAUTH_TOKEN") unless config.jira_oauth_token.to_s.empty?

          config.cloud? ? basic_cloud(config) : bearer(config.jira_pat, "JIRA_PAT")
        when :confluence
          unless config.confluence_oauth_token.to_s.empty?
            return bearer(config.confluence_oauth_token, "CONFLUENCE_OAUTH_TOKEN")
          end

          if config.cloud?
            basic(config.confluence_email || config.jira_email,
                  config.confluence_api_token || config.jira_api_token,
                  "JIRA_EMAIL and JIRA_API_TOKEN/CONFLUENCE_API_TOKEN")
          else
            bearer(config.confluence_pat || config.jira_pat, "CONFLUENCE_PAT")
          end
        else
          raise ArgumentError, "unknown service #{service.inspect}"
        end
      end

      def basic_cloud(config)
        basic(config.jira_email, config.jira_api_token, "JIRA_EMAIL and JIRA_API_TOKEN")
      end

      def basic(user, token, names)
        raise AuthError, "#{names} are required for Cloud basic authentication" if user.to_s.empty? || token.to_s.empty?

        { "Authorization" => "Basic #{Base64.strict_encode64("#{user}:#{token}")}" }
      end

      def bearer(token, name)
        raise AuthError, "#{name} is required for Data Center bearer authentication" if token.to_s.empty?

        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
