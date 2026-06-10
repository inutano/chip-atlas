FROM ruby:4.0.5-slim
RUN apt-get update -y && apt-get install -y build-essential libsqlite3-dev
COPY . /app
WORKDIR /app
RUN bundle config set --local without 'development test' && bundle install
RUN mkdir -p tmp/pids log
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
