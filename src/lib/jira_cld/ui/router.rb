# frozen_string_literal: true

require "roda"

module JiraCld
  module UI
    class Router < Roda
      plugin :all_verbs
      plugin :cookies

      route do |r|
        context = Context.new(self, r)
        context.security_headers!

        unless context.authorize!
          response.status = 401
          next "Unauthorized. Open the URL printed by `bin/jira-cld ui`."
        end

        Routes.dispatch(context, r)
      end
    end
  end
end
