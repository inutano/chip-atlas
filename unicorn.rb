@dir = File.expand_path(__dir__)

worker_processes 2
working_directory @dir

timeout 300
listen 80

pid "#{@dir}/tmp/pids/unicorn.pid"

stderr_path "#{@dir}/log/unicorn.stderr.log"
stdout_path "#{@dir}/log/unicorn.stdout.log"

listen "#{@dir}/tmp/unicorn.sock", backlog: 1024
