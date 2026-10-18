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
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory.ini -i inventory-source.ini setup.yml
```

수집 → 업로드 → su 전환 → sudo로 설정·정적 파일 복사 및 교체 → nginx -t → reload → HTML·CSS HTTP 200 확인 순서입니다. 최종 반영 단계에서 관리자 계정명과 su 및 sudo 비밀번호를 입력합니다. 실습에서는 두 비밀번호가 같습니다.

## 단계별 실행

```sh
# 1. 최신 nginx 설정과 정적 파일 수집
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory-source.ini fetch.yml

# 2. 두 신규 서버의 deploy 폴더에 업로드
/opt/homebrew/bin/docker-compose exec control ansible-playbook upload.yml

# 3. 관리자 계정 전환 후 최종 반영
/opt/homebrew/bin/docker-compose exec control ansible-playbook apply.yml
```

완료한 단계를 건너뛰려면 필요한 플레이북만 실행합니다. `setup.yml`은 항상 수집부터 다시 실행합니다. `apply.yml --limit target`으로 한 대만 먼저 반영할 수도 있습니다.

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

## role과 변수 구조

```text
workspace/
├─ setup.yml                    # 전체 실행
├─ fetch.yml / upload.yml / apply.yml
├─ v1/                         # 이전 nginx 전용 진입점
├─ vars/
│  ├─ environment.yml           # role 선택, 공통 경로, nginx 경로·검증 주소
│  └─ services.yml              # Loki·Alloy·Scouter·node exporter·deploy 목록
└─ roles/
   ├─ nginx/
   │  ├─ defaults/main.yml
   │  └─ tasks/main.yml, fetch.yml, upload.yml, apply.yml
   └─ common_services/
      ├─ defaults/main.yml
      └─ tasks/main.yml, fetch.yml, upload.yml, apply.yml,
               fetch_service.yml, upload_service.yml, apply_service.yml
```

상위의 setup.yml, fetch.yml, upload.yml, apply.yml은 현재 사용하는 진입 플레이북입니다. 대상 서버와 단계, 비밀번호 입력을 담당하며 role이 실제 작업을 수행합니다.

이전 nginx 전용 진입점 네 개는 `workspace/v1/`로 옮겼습니다. 과거 구현 전체의 복사본이 아니라 현재 nginx role을 참조하는 호환용 진입점이며 common_services는 실행하지 않습니다. role 검색 경로는 ansible.cfg에 지정했고, v1에서도 공통 vars와 기존 collected 폴더를 사용합니다.

```sh
# 이전 nginx 전용 전체 실행
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory.ini -i inventory-source.ini v1/setup-nginx.yml

# 이전 nginx 전용 최종 반영만 실행
/opt/homebrew/bin/docker-compose exec control ansible-playbook v1/apply-nginx.yml
```

일반적으로는 상위 setup.yml 또는 fetch.yml/upload.yml/apply.yml을 사용하면 됩니다.

### 경로 변경: vars/environment.yml

- `collection_root`: control에 보관하는 공통 수집 폴더
- `staging_root`: 신규 서버 SSH 계정이 쓰는 업로드 폴더
- `nginx_config_dir`, `nginx_static_dir`: 신규 서버 최종 경로
- `nginx_source_config_dir`, `nginx_source_static_dir`: 원본 경로, 기본값은 신규 서버와 동일
- `nginx_binary`: nginx 실행 파일 경로
- `nginx_check_base_url`, `nginx_check_paths`: HTTP 확인 주소와 경로
- `enabled_roles`: 실행할 role 목록. 기본값은 nginx와 common_services

nginx 경로를 바꾸면 nginx.conf 안의 include/root/pid 경로 및 nginx 실행 설정도 일치해야 합니다. 수집한 설정 파일 내용은 자동 치환하지 않습니다. SSH 계정·주소·Python 경로는 inventory에서 관리합니다.

### 서비스 추가: vars/services.yml

`services.yml`에는 /home/deploy 아래의 loki, alloy, scouter, node_exporter, deploy 폴더를 가정한 예시 다섯 개가 들어 있습니다. 실제 서버에 이 폴더들을 생성하지는 않았습니다. 전체 실행 전에 경로와 제외 목록을 확인하세요. 현재 start_argv와 check_argv가 비어 있어 복사만 하고 실행·기동 검증은 생략합니다. 공통 서비스를 건너뛰려면 common_services: []로 바꾸거나 environment.yml의 enabled_roles를 [nginx]로 지정합니다. 아래도 설명용 예시입니다.

```yaml
common_services:
  - name: alloy
    path: /home/deploy/alloy
    owner: alloy
    group: alloy
    excludes: ["logs/", "data/"]
    start_user: alloy
    start_argv: ["./start.sh"]
    check_argv: ["./check.sh"]
  - name: deploy
    path: /home/deploy/deploy
    owner: deploy
    group: deploy
    start_argv: []
```

`path`를 원본·대상에 동일하게 사용하며 필요한 경우 `source_path`로 원본만 바꿀 수 있습니다. 서비스별 수집본은 `collected/common_services/<name>/files/`, 업로드는 `<staging_root>/common_services/<name>/files/`에 보관합니다. 제외 패턴은 원본 디렉터리 기준입니다. 수집 폴더마다 완료 표시를 확인합니다.

복사할 때 실행 권한과 심볼릭 링크를 보존하고 소유권을 owner/group으로 맞춥니다. 해당 사용자·그룹은 대상에 미리 있어야 합니다. 실행·검증 명령은 문자열 하나가 아니라 인자 목록이며, 서비스 폴더에서 start_user(생략 시 owner) 계정으로 실행됩니다. 시작 스크립트는 서비스를 기동한 후 종료되어야 합니다. start_argv가 비어 있으면 복사만 하며 deploy 스크립트를 자동 실행하지 않습니다. check_argv는 선택 사항으로, 정상일 때 종료 코드 0을 반환하는 명령을 지정합니다.

공통 서비스는 기존 폴더를 백업한 뒤 파일을 덮어씁니다. 대상에서 파일을 삭제하지 않으므로 제외된 기존 로그·데이터를 유지하지만, 원본에서 사라진 일반 파일도 대상에 남을 수 있습니다. 신규 구축을 기준으로 합니다. 기존 폴더의 전체 백업에는 데이터도 포함되므로 기존 운영 서버 갱신용으로 무심코 실행하지 마세요. 서비스별 중지·복구 명령을 아직 모르므로 공통 서비스 실패 시 자동 중지·원복하지 않고 백업 위치를 알립니다. nginx는 기존 검사·원복 동작을 유지합니다.

일반 파일의 위치만 바뀌면 변수 파일만 수정하면 됩니다. Loki와 Alloy, Scouter, node exporter는 각 서비스마다 role이나 fetch 파일을 추가하지 않고 목록에 항목을 추가합니다.

## 중지와 실습 범위

`docker-compose stop`과 `start`는 컨테이너 내부 작업을 유지합니다. `down`이나 컨테이너 재생성은 내부 실습 변경을 초기화합니다. Mac의 workspace 및 .lab은 유지됩니다.

Ubuntu 실습 당시 설정과 업로드 파일은 `.lab/pre-rocky-*`에 백업했습니다. 이전 수집본은 Rocky에 그대로 적용하지 않도록 백업으로 옮겼습니다. 새 환경에서는 수집부터 다시 진행하세요.

일반 Docker 컨테이너이므로 systemd, 부팅 시 서비스 실행, 실제 SELinux 정책 및 파일 컨텍스트는 이 실습으로 검증하지 않습니다. 실제 Rocky 서버에서는 이 항목을 추가 검증해야 합니다. 현재 Mac 실습은 ARM64이며 운영 서버의 CPU 아키텍처·nginx 버전·모듈도 별도로 확인해야 합니다. CentOS에서 수집한 설정을 Rocky에 그대로 적용할 수 있다고 보장하지 않습니다.
