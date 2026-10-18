#!/bin/sh
set -eu
install -d -m 755 /run/sshd
install -d -m 700 -o ansible -g ansible /home/ansible/.ssh
install -m 600 -o ansible -g ansible /run/lab/authorized_keys /home/ansible/.ssh/authorized_keys
install -m 600 /run/lab/host_key /etc/ssh/ssh_host_ed25519_key
/usr/sbin/sshd -t
exec /usr/sbin/sshd -D -e
