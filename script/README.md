# Startup script

- chkconfig no longer available
	- https://askubuntu.com/questions/299371/correct-way-to-install-a-custom-upstart-service
- rbenv init does not work
	- https://gist.github.com/chsh/10739192

Use `update-rc.d`, the only option available by default:

```
1. Create the service file in /etc/init.d/<service name>
2. chmod 700 /etc/init.d/<service name>
3. update-rc.d <service name> defaults
4. update-rc.d <service name> enable
```

Inside `/etc/init.d/chip-atlas`:

```
#!/bin/bash
### BEGIN INIT INFO
# Provides:          chip-atlas
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Start ChIP-Atlas web application
### END INIT INFO

ARG=$1

RBENV_HOME=/home/ubuntu/.rbenv
WORKDIR=/home/ubuntu/chip-atlas


start(){
  PATH=${RBENV_HOME}/bin:${RBENV_HOME}/shims:${PATH}; cd ${WORKDIR}; bundle exe unicorn -c ${WORKDIR}/unicorn.rb -E production -D
}

stop(){
  cat ${WORKDIR}/tmp/pids/unicorn.pid | xargs kill
}

case $ARG in
  "start")
    start
    ;;
  "stop")
    stop
    ;;
  "restart")
    stop
    start
    ;;
esac
```
