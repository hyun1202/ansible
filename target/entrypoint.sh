#!/bin/sh
set -eu
install -d -m 755 /run/sshd
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh /home/deploy/staging
install -m 600 -o deploy -g deploy /run/lab/authorized_keys /home/deploy/.ssh/authorized_keys
printf 'adminuser:%s\n' "$(cat /run/lab/adminuser_password)" | chpasswd
install -m 600 /run/lab/host_key /etc/ssh/ssh_host_ed25519_key
/usr/sbin/sshd -t
nginx -t
nginx
exec /usr/sbin/sshd -D -e
