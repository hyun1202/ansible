#!/bin/sh
set -eu
cd "$(dirname "$0")"
umask 077
mkdir -p .lab
if [ ! -s .lab/adminuser_password ]; then
  openssl rand -hex 12 > .lab/adminuser_password
fi
chmod 600 .lab/adminuser_password
if [ ! -f .lab/id_ed25519 ]; then
  ssh-keygen -q -t ed25519 -N '' -C ansible-study-client -f .lab/id_ed25519
fi
if [ ! -f .lab/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -C ansible-study-target -f .lab/ssh_host_ed25519_key
fi
ssh-keygen -y -f .lab/id_ed25519 > .lab/id_ed25519.pub
if [ ! -f .lab/ssh_host_target2_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -C ansible-study-target2 -f .lab/ssh_host_target2_ed25519_key
fi
if [ ! -f .lab/ssh_host_source_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -C ansible-study-source -f .lab/ssh_host_source_ed25519_key
fi
ssh-keygen -y -f .lab/ssh_host_ed25519_key | awk '{print "target " $0}' > .lab/known_hosts
ssh-keygen -y -f .lab/ssh_host_target2_ed25519_key | awk '{print "target2 " $0}' >> .lab/known_hosts
ssh-keygen -y -f .lab/ssh_host_source_ed25519_key | awk '{print "source " $0}' >> .lab/known_hosts
printf '실습용 SSH 키 준비 완료\n'
