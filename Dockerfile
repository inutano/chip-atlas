# Docker container for chip-atlas dev env
ARG RUBY_VERSION=4.0.10
FROM ruby:${RUBY_VERSION}-slim
RUN apt-get update -y && apt-get install -y libffi-dev build-essential libpq-dev libsqlite3-dev sqlite3
WORKDIR /app
# Gems first, so that editing the app does not reinstall them
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . /app
CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "9292"]
