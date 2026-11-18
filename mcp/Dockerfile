ARG RUBY_VERSION=4.0-slim

FROM ruby:${RUBY_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git libyaml-dev \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 jira \
  && useradd --uid 10001 --gid jira --create-home --home-dir /home/jira jira

WORKDIR /app
COPY lib /app/lib
COPY mcp /app/mcp

WORKDIR /app/mcp
RUN bundle config set --local without "test" \
  && bundle install --jobs 4 --retry 3

ENV MCP_HTTP_HOST=0.0.0.0
ENV MCP_HTTP_PORT=8765
ENV MCP_HTTP_PATH=/mcp
ENV MCP_HTTP_ALLOWED_HOSTS=localhost,127.0.0.1

USER jira
EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:8765/health")).is_a?(Net::HTTPSuccess) ? 0 : 1)'

CMD ["bundle", "exec", "ruby", "bin/jira-mcp-http"]
