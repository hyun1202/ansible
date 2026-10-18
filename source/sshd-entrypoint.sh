#!/bin/sh
set -eu
# systemd가 없는 컨테이너에서 부팅 중 로그인 차단 표시를 해제합니다.
rm -f /run/nologin
install -d -m 755 /run/sshd
install -d -m 700 -o ansible -g ansible /home/ansible/.ssh
install -m 600 -o ansible -g ansible /run/lab/authorized_keys /home/ansible/.ssh/authorized_keys
install -m 600 /run/lab/host_key /etc/ssh/ssh_host_ed25519_key
/usr/sbin/sshd -t
exec /usr/sbin/sshd -D -e
