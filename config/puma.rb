# frozen_string_literal: true

# Puma configuration for ChIP-Atlas
#
# Production: 2 workers × 5 threads = 10 concurrent requests
# SQLite WAL mode supports concurrent reads from multiple threads.

environment ENV.fetch('RACK_ENV', 'production')

# Bind to port
port ENV.fetch('PORT', 9292)

# Workers (processes) - match CPU cores
workers ENV.fetch('WEB_CONCURRENCY', 2).to_i

# Threads per worker
threads_count = ENV.fetch('MAX_THREADS', 5).to_i
threads threads_count, threads_count

# Preload the app before forking workers (copy-on-write memory savings)
preload_app!

# Worker timeout (seconds)
worker_timeout 60

# PID and state files
pidfile 'tmp/pids/puma.pid'
state_path 'tmp/pids/puma.state'

# Log to files in production, stdout in development
if ENV.fetch('RACK_ENV', 'production') == 'production'
  stdout_redirect 'log/puma.stdout.log', 'log/puma.stderr.log', true
end

# Before forking: disconnect DB so each worker gets its own connection
before_fork do
  DB.disconnect if defined?(DB)
end
