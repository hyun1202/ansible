# Ansible 신규 서버 구축 실습

신규 서버를 Rocky Linux 8로 가정한 실습입니다. 실제 운영 서버의 CentOS 버전은 아직 확인하지 않았습니다.

| 컨테이너 | OS | 역할 |
| --- | --- | --- |
| control | Ubuntu 24.04 | Ansible Core 2.19.14와 rsync 실행 |
| source | Rocky Linux 8 | 운영 서버 역할의 nginx와 정적 파일 원본 |
| target, target2 | Rocky Linux 8 | 신규 서버, 일반 계정 업로드 후 관리자 계정으로 반영 |

Compose 프로젝트는 `ansible-study`이며 호스트 포트는 공개하지 않습니다. 기존 MariaDB는 별도 프로젝트로 유지됩니다. Rocky 컨테이너에는 Ansible 모듈 실행용 Python 3.9를 설치했습니다.

## 구성과 경로

```text
source:/etc/nginx/             → control:/workspace/collected/nginx/
source:/usr/share/nginx/html/  → control:/workspace/collected/static/
                                       ↓
                          target, target2:/home/deploy/staging/
                                       ↓ su → sudo cp
                          /etc/nginx/ + /usr/share/nginx/html/
```

Mac의 `workspace/`가 control의 `/workspace`에 연결됩니다. 수집본은 한 벌만 유지합니다. rsync는 설정과 정적 파일을 각각 동기화하며, 원본에서 삭제된 파일은 수집 및 업로드용 폴더에서도 제거합니다. 원본 서버의 파일을 변경하지 않습니다.

source의 nginx 설정은 `/usr/share/nginx/html`을 root로 사용합니다. `/`는 HTML을, `/static/app.css`는 CSS 파일을 제공합니다. 타겟의 초기 응답은 `new target: before deployment`입니다. 실제 운영 서버에서는 `nginx -T`와 `root`·`alias`를 확인해 경로를 맞춰야 합니다. `/etc/nginx/` 밖의 인증서나 모듈, 다른 웹 루트는 자동 수집되지 않습니다.

## 계정

- source의 `ansible`: 설정·정적 파일을 읽는 SSH 계정
- 타겟의 `deploy`: SSH 및 업로드 전용, sudo 권한 없음
- 타겟의 `adminuser`: su 전환용, wheel 그룹 소속이며 비밀번호로 sudo 사용

타겟은 deploy만 SSH 접속할 수 있습니다. 실습용 adminuser 비밀번호는 두 타겟에서 동일하고 아래 명령으로 확인합니다. 실제 운영 비밀번호를 사용하지 마세요.

```sh
cat .lab/adminuser_password
```

키와 비밀번호는 `.lab/`에 보관하고 Git 및 이미지 빌드에서 제외합니다. 컨테이너를 시작하면 비밀번호 파일의 값으로 adminuser 비밀번호를 다시 설정합니다.

## 시작하기

```sh
cd /Users/hyun/Study/ansible
./init.sh
/opt/homebrew/bin/docker-compose up -d --build
/opt/homebrew/bin/docker-compose exec control ansible lab -m ansible.builtin.ping
```

이 Mac은 Colima와 `/opt/homebrew/bin/docker-compose`를 사용합니다. 타겟의 nginx는 실습 환경 구성 시 미리 설치하고 실행합니다.

## 전체 실습을 한 번에 실행

```sh
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory.ini -i inventory-source.ini setup-nginx.yml
```

수집 → 업로드 → su 전환 → sudo로 설정·정적 파일 복사 및 교체 → nginx -t → reload → HTML·CSS HTTP 200 확인 순서입니다. 최종 반영 단계에서 관리자 계정명과 su 및 sudo 비밀번호를 입력합니다. 실습에서는 두 비밀번호가 같습니다.

## 단계별 실행

```sh
# 1. 최신 nginx 설정과 정적 파일 수집
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory-source.ini fetch-nginx.yml

# 2. 두 신규 서버의 deploy 폴더에 업로드
/opt/homebrew/bin/docker-compose exec control ansible-playbook upload-nginx.yml

# 3. 관리자 계정 전환 후 최종 반영
/opt/homebrew/bin/docker-compose exec control ansible-playbook apply-nginx.yml
```

완료한 단계를 건너뛰려면 필요한 플레이북만 실행합니다. `setup-nginx.yml`은 항상 수집부터 다시 실행합니다. `apply-nginx.yml --limit target`으로 한 대만 먼저 반영할 수도 있습니다.

수집 시작 시 `.complete` 표시를 지우고 설정과 정적 파일 모두 성공했을 때 다시 만듭니다. 업로드는 이 표시를 확인합니다. 수집·업로드·반영은 순서대로 실행하고 동시에 진행하지 않습니다.

최종 반영은 한 대씩 처리합니다. su는 Ansible become으로, sudo는 `sudo -S` 표준 입력 인증으로 처리합니다. 비밀번호 관련 명령은 no_log로 숨기고 명령행 인자에 비밀번호를 넣지 않습니다. 계정 간 임시 파일 접근을 위해 acl을 설치합니다.

기존 설정 및 정적 파일은 각 작업 디렉터리 옆의 `.backup` 경로로 보관합니다. 복사·배치·nginx 검사·reload 블록에서 실패하면 이미 백업한 항목을 복구하고 중단합니다. 이후 HTTP 확인 실패는 자동 원복하지 않습니다. 여러 서버 전체를 일괄 원복하지 않으며 앞서 성공한 서버는 유지됩니다. 백업과 진단용 작업 폴더는 자동 삭제하지 않습니다.

## 직접 확인

```sh
/opt/homebrew/bin/docker-compose exec control ssh deploy@target
su - adminuser
sudo nginx -t
python3.9 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1/').read().decode())"
python3.9 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1/static/app.css').read().decode())"
```

HTML에 `legacy nginx configuration v1`이 표시되고 CSS가 응답하면 정적 파일까지 반영된 것입니다. 두 번째 타겟은 `deploy@target2`로 접속합니다.

## 파일 역할

- `workspace/inventory.ini`: 신규 타겟 두 대와 deploy 계정
- `workspace/inventory-source.ini`: 수집용 source와 ansible 계정
- `workspace/ansible.cfg`: SSH 및 inventory 기본값
- `workspace/setup-nginx.yml`: 전체 실행 진입점
- `workspace/fetch-nginx.yml`: 설정·정적 파일 수집
- `workspace/upload-nginx.yml`: 일반 계정 업로드
- `workspace/apply-nginx.yml`: 관리자 전환 후 최종 반영
- `target/nginx.conf`: Rocky 실습용 nginx 설정
- `source/html/`: 원본 서버의 예제 HTML·CSS

## 중지와 실습 범위

`docker-compose stop`과 `start`는 컨테이너 내부 작업을 유지합니다. `down`이나 컨테이너 재생성은 내부 실습 변경을 초기화합니다. Mac의 workspace 및 .lab은 유지됩니다.

Ubuntu 실습 당시 설정과 업로드 파일은 `.lab/pre-rocky-*`에 백업했습니다. 이전 수집본은 Rocky에 그대로 적용하지 않도록 백업으로 옮겼습니다. 새 환경에서는 수집부터 다시 진행하세요.

일반 Docker 컨테이너이므로 systemd, 부팅 시 서비스 실행, 실제 SELinux 정책 및 파일 컨텍스트는 이 실습으로 검증하지 않습니다. 실제 Rocky 서버에서는 이 항목을 추가 검증해야 합니다. 현재 Mac 실습은 ARM64이며 운영 서버의 CPU 아키텍처·nginx 버전·모듈도 별도로 확인해야 합니다. CentOS에서 수집한 설정을 Rocky에 그대로 적용할 수 있다고 보장하지 않습니다.
