# bundle exec puma -C puma.rb -e production
#
# Replaces unicorn.rb: unicorn 6.1.0 (its kgio extension) segfaults on Ruby 4.0.
require "fileutils"

dir = File.expand_path(__dir__)
directory dir

# None of these directories is in git
%w[tmp/pids tmp/sockets log].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }

# 2 processes, as with unicorn. Each now also runs several threads, so a few
# slow requests (NCBI, the data storage, DDBJ) no longer occupy the whole site.
workers Integer(ENV.fetch("WEB_CONCURRENCY", 2))
max_threads = Integer(ENV.fetch("MAX_THREADS", 5))
threads max_threads, max_threads

preload_app!

# Loading the app leaves well over a gigabyte of empty heap behind.
# Process.warmup compacts the heap and gives those pages back before the
# workers are forked (measured: 2.5 GB -> 0.8 GB in the master process).
before_fork { Process.warmup }

# The socket keeps its old name so that the nginx configuration does not change.
# PUMA_BIND overrides it for local runs, e.g. PUMA_BIND=tcp://0.0.0.0:9292
bind ENV.fetch("PUMA_BIND", "unix://#{dir}/tmp/sockets/unicorn.sock?backlog=1024")

pidfile "#{dir}/tmp/pids/puma.pid"

# Log files, as with unicorn; set PUMA_LOG_STDOUT=1 to keep the output on the terminal
unless ENV["PUMA_LOG_STDOUT"]
  stdout_redirect "#{dir}/log/puma.stdout.log", "#{dir}/log/puma.stderr.log", true
end
