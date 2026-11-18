# frozen_string_literal: true

module JiraCore
  module Serialize
    module Person
      module_function

      def compact(user, show_email: false)
        return nil unless user.is_a?(Hash)

        account_id = user["accountId"] || user["key"] || user["name"] || user["username"]
        display = user["displayName"] || user["name"] || user["emailAddress"] || account_id
        email = user["emailAddress"]
        {
          "account_id" => account_id,
          "name" => user["name"] || user["username"],
          "display_name" => display,
          "email" => show_email ? email : nil,
          "active" => user.fetch("active", true),
          "bot" => bot?(user),
          "avatar_url" => dig(user, "avatarUrls", "48x48"),
          "profile_url" => dig(user, "self")
        }.compact
      end

      def bot?(user)
        return true if user["accountType"].to_s.casecmp("bot").zero?
        return true if user["type"].to_s.casecmp("bot").zero?

        name = user["displayName"].to_s.downcase
        name.include?("[bot]") || name.end_with?(" bot") || name.start_with?("bot ")
      end

      def person_key(user)
        return nil unless user.is_a?(Hash)

        (user["account_id"] || user["accountId"] || user["key"] || user["name"] || user["username"] ||
          user["email"] || user["emailAddress"] || user["display_name"] || user["displayName"]).to_s
      end

      def confidence(evidence_count)
        case evidence_count.to_i
        when 0 then "none"
        when 1, 2 then "low"
        when 3, 4 then "medium"
        else "high"
        end
      end

      def dig(hash, *keys)
        keys.reduce(hash) do |memo, key|
          return nil unless memo.is_a?(Hash)

          memo[key]
        end
      end
    end
  end
end
