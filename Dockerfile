# syntax=docker/dockerfile:1
# check=error=true

# Production image:  docker build -t forecast_lookup .
# Test image:        docker build --target test -t forecast_lookup:test .
# Both are wired up in compose.yaml.

ARG RUBY_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages only: jemalloc for memory, sqlite3 for the Solid Cache database
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Throw-away stage that compiles gems and assets
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompile assets without the real secret key
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Runs the suite with the development and test gems: docker compose run --rm test
FROM build AS test

ENV RAILS_ENV="test" \
    BUNDLE_WITHOUT=""

RUN bundle install

CMD ["bundle", "exec", "rspec"]

# Final, minimal runtime image
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

# Prepares the databases before the server starts
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
