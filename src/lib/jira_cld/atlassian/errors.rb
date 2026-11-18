# frozen_string_literal: true

module JiraCld
  module Atlassian
    module Errors
      module_function

      def from_response(response, domain:, deployment: nil)
        status = response.status
        message = parse_message(response.body)
        case status
        when 401
          JiraCld::Atlassian::AuthError.new(
            message || "authentication failed",
            status: status,
            domain: domain,
            hint: "check JIRA_EMAIL/JIRA_API_TOKEN (Cloud) or JIRA_PAT/CONFLUENCE_PAT (Data Center); tokens must be read-only"
          )
        when 403
          JiraCld::Atlassian::ForbiddenError.new(
            message || "access forbidden", status: status, domain: domain,
                                           hint: "the token cannot read this resource or project/space is outside the allowlist"
          )
        when 404, 410
          JiraCld::Atlassian::NotFoundError.new(
            message || "resource not found", status: status, domain: domain,
                                             hint: "verify key/id and allowlist; the endpoint may not exist on this deployment"
          )
        when 429
          JiraCld::Atlassian::RateLimitedError.new(message || "rate limited", status: status, domain: domain,
                                                                              hint: "slow down; the server honours Retry-After")
        when 500..599
          JiraCld::Atlassian::ServerError.new(message || "Atlassian server error", status: status, domain: domain,
                                                                                   hint: "retry later; the request was not cached")
        else
          JiraCld::Atlassian::Error.new(message || "HTTP #{status}", status: status, domain: domain)
        end
      end

      def parse_message(body)
        return nil if body.nil? || body.empty?

        data = JSON.parse(body)
        messages = data["errorMessages"]
        return messages.join("; ") if messages.is_a?(Array) && !messages.empty?

        data["message"] || (data["errors"].is_a?(Hash) ? data["errors"].values.join("; ") : nil)
      rescue JSON::ParserError
        body.to_s[0, 300]
      end

      def raise_for!(response, domain:, deployment: nil)
        return response if response.success?

        raise from_response(response, domain: domain, deployment: deployment)
      end
    end
  end
end
