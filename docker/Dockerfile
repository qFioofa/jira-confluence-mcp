ARG RUBY_VERSION=4.0-slim

FROM ruby:${RUBY_VERSION} AS build

ARG INSTALL_UI=false
ENV BUNDLE_WITHOUT="development test"

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential pkg-config libsqlite3-dev libyaml-dev git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY src/Gemfile src/Gemfile.lock src/jira-cld.gemspec ./
COPY src/lib/jira_cld/version.rb lib/jira_cld/version.rb
RUN if [ "$INSTALL_UI" = "false" ]; then bundle config set --local without "development test ui"; fi \
  && bundle install --jobs 4 --retry 3

COPY src/ .

RUN if [ "$INSTALL_UI" = "false" ]; then rm -rf assets/ui; fi \
  && gem build jira-cld.gemspec

FROM ruby:${RUBY_VERSION} AS runtime

ENV BUNDLE_WITHOUT="development test"
ENV MCP_PROJECT_ID=""
ENV CONFIG_PATH=/home/jira/.config/jira-cld/config.yml
ENV DATA_DIR=/home/jira/.local/share/jira-cld
ENV MCP_HTTP_HOST=0.0.0.0
ENV MCP_HTTP_PORT=8765
ENV UI_HOST=0.0.0.0
ENV UI_PORT=9292

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-0 libyaml-0-2 \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --gid 10001 jira \
  && useradd --uid 10001 --gid jira --create-home --home-dir /home/jira jira \
  && mkdir -p /home/jira/.config/jira-cld /home/jira/.local/share/jira-cld \
  && chown -R jira:jira /home/jira \
  && chmod -R a+rX /home/jira

WORKDIR /app
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

USER jira
EXPOSE 8765 9292
ENTRYPOINT ["/app/bin/jira-cld"]
CMD ["mcp-http"]
