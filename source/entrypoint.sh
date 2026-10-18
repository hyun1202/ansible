#!/bin/sh
set -eu
nginx -t
nginx
exec /usr/local/bin/lab-sshd-entrypoint
