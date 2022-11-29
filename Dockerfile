# Docker container for chip-atlas dev env
FROM ruby:3.1.3
RUN apt-get update -y && apt-get install -y libffi-dev build-essential libpq-dev libsqlite3-dev lftp
COPY . /app
WORKDIR /app
RUN bundle install
CMD ["bundle", "exe", "rackup", "--host", "0.0.0.0", "-p", "9292"]
