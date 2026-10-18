#!/bin/sh
# 스크립트가 있는 서비스 폴더에서 실습 프로세스를 제어합니다.
set -eu
cd -- "$(dirname -- "$0")"
exec /usr/bin/python3.9 ./runner.py stop
