#!/bin/sh
# source의 수집 원본을 준비합니다. 실제 제품 바이너리가 아닌 실습용 HTTP 서비스입니다.
set -eu
template=${1:-/opt/lab-service-template}
if ! id deploy >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash deploy
fi
# 원본 SSH 계정 ansible이 수집할 수 있도록 디렉터리 진입을 허용합니다.
chmod 755 /home/deploy
port=19101
for service in loki alloy scouter node_exporter; do
    destination=/home/deploy/$service
    if [ -e "$destination" ]; then
        echo "기존 경로를 덮어쓰지 않습니다: $destination" >&2
        exit 1
    fi
    install -d -m 755 "$destination"
    cp "$template/runner.py" "$destination/runner.py"
    for action in start stop check; do
        install -m 755 "$template/$action.sh" "$destination/$action.sh"
    done
    printf '{"name":"%s","port":%s,"kind":"ansible-lab-mock"}\n' "$service" "$port" > "$destination/service.json"
    # 이 샘플은 rsync 제외 규칙을 확인하는 데 사용합니다.
    install -d -m 755 "$destination/logs"
    printf '수집에서 제외되는 원본 로그\n' > "$destination/logs/source-only.log"
    chown -R deploy:deploy "$destination"
    port=$((port + 1))
done
if [ -e /home/deploy/deploy ]; then
    echo '기존 /home/deploy/deploy는 덮어쓰지 않습니다.' >&2
    exit 1
fi
install -d -m 755 /home/deploy/deploy
cat > /home/deploy/deploy/deploy.sh <<'EOF'
#!/bin/sh
# 이 파일은 복사 실습용이며 플레이북이 자동 실행하지 않습니다.
printf '실습용 deploy.sh: 실제 JAR 배포는 수행하지 않습니다.\n'
EOF
chmod 755 /home/deploy/deploy/deploy.sh
chown -R deploy:deploy /home/deploy/deploy
