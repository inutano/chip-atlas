@dir = __dir__

worker_processes 4
working_directory @dir

timeout 300
listen 80

pid "#{@dir}/tmp/pids/unicorn.pid"

stderr_path "#{@dir}/log/unicorn.strerr.log"
stdout_path "#{@dir}/log/unicorn.strout.log"

listen "#{@dir}/tmp/unicorn.sock", backlog: 1024