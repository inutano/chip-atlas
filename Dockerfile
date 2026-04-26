FROM ruby:3.3-slim
RUN apt-get update -y && apt-get install -y build-essential libsqlite3-dev
COPY . /app
WORKDIR /app
RUN bundle install --without development test
RUN mkdir -p tmp/pids log
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
