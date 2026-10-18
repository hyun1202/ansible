#!/bin/sh
set -eu
cd "$(dirname "$0")"
umask 077
mkdir -p .lab

if [ ! -s .lab/adminuser_password ]; then
  openssl rand -hex 12 > .lab/adminuser_password
fi
chmod 600 .lab/adminuser_password

ensure_key() {
  if [ ! -f "$1" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "$2" -f "$1"
  fi
}

ensure_key .lab/id_ed25519 ansible-study-client
ssh-keygen -y -f .lab/id_ed25519 > .lab/id_ed25519.pub

# 키 파일명은 기존 실습 환경과 호환되게 유지합니다.
: > .lab/known_hosts
for host in target target2 source; do
  case "$host" in
    target) key_file=.lab/ssh_host_ed25519_key ;;
    *) key_file=".lab/ssh_host_${host}_ed25519_key" ;;
  esac
  ensure_key "$key_file" "ansible-study-$host"
  ssh-keygen -y -f "$key_file" | awk -v host="$host" '{print host " " $0}' >> .lab/known_hosts
done
printf '실습용 SSH 키 준비 완료\n'
