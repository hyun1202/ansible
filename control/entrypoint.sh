#!/bin/sh
set -eu
install -d -m 700 /root/.ssh
install -m 600 /run/lab/id_ed25519 /root/.ssh/id_ed25519
install -m 600 /run/lab/known_hosts /root/.ssh/known_hosts
exec "$@"
