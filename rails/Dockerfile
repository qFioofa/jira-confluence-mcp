ARG RUBY_VERSION=4.0-slim
ARG NODE_VERSION=24-slim

FROM node:${NODE_VERSION} AS node_modules
WORKDIR /app
COPY rails/package.json rails/package-lock.json ./
RUN npm ci

FROM ruby:${RUBY_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential pkg-config libsqlite3-dev libpq-dev libyaml-dev git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY lib /app/lib
COPY mcp /app/mcp

WORKDIR /app/rails
COPY rails/Gemfile rails/Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY rails/ ./
COPY --from=node_modules /app/node_modules ./node_modules

RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=1
ENV MCP_ALLOWED_HOSTS=localhost,127.0.0.1

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
