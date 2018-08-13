# Docker container for chip-atlas dev env
# bundle install && bundle exe rackup --host 0.0.0.0 -p 9292
FROM ruby:2.5.0-slim
RUN apt-get update -y && apt-get install -y libffi-dev build-essential libpq-dev libsqlite3-dev
CMD ["bash"]
