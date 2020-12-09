```
$ uname -a
> Linux ip-172-30-2-171 4.4.0-1052-aws #61-Ubuntu SMP Mon Feb 12 23:05:58 UTC 2018 x86_64 x86_64 x86_64 GNU/Linux

# register hostname
$ sudo sh -c 'echo 127.0.1.1 $(hostname) >> /etc/hosts'

# swap file
$ sudo su -
$ dd if=/dev/zero of=/swapfile1 bs=1M count=512
$ chmod 600 /swapfile1
$ mkswap /swapfile1
$ swapon /swapfile1
$ cp -p /etc/fstab /etc/fstab.ORG
$ echo "/swapfile1  swap        swap    defaults        0   0" >> /etc/fstab
$ reboot

# set timezone
$ sudo timedatectl set-timezone Asia/Tokyo

# update packages
$ sudo apt-get update -y && sudo apt-get install -y git gcc nginx make make-guile libssl-dev libreadline-dev zlib1g-dev libpq-dev sqlite3 libsqlite3-dev

# install rbenv
$ git clone https://github.com/rbenv/rbenv.git ~/.rbenv
$ cd ~/.rbenv && src/configure && make -C src
$ echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
$ echo 'eval "$(rbenv init -)"' >> ~/.bashrc

# install ruby-build
$ mkdir -p "$(rbenv root)"/plugins
$ git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build

# install ruby
$ rbenv install 2.5.1
$ rbenv rehash
$ rbenv global 2.5.1

# install bundler
$ gem install bundler

# clone chip-atlas repo
$ git clone https://github.com/inutano/chip-atlas
$ cd chip-atlas
$ bundle install --path=vendor/bundle

# Setup unicorn/nginx following http://recipes.sinatrarb.com/p/deployment/nginx_proxied_to_unicorn
$ mkdir -p tmp/sockets tmp/pids log
$ sudo su -
$ cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.ORG
$ nano /etc/nginx/nginx.conf # Copy file on http://recipes.sinatrarb.com/p/deployment/nginx_proxied_to_unicorn and edit

# Fetch data
$ wget -O /home/ubuntu/chip-atlas/database.sqlite "http://data.dbcls.jp/~inutano/chip-atlas/sqlite/latest/database.sqlite"

# Launch app
$ cd /home/ubuntu/chip-atlas; bundle exe unicorn -c /home/ubuntu/chip-atlas/unicorn.rb -E production -D
$ sudo /etc/init.d/nginx restart

# Stop the app server
$ cat /home/ubuntu/chip-atlas/tmp/pids/unicorn.pid | xargs kill
```
