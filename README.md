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

사전 검사 → 누락 패키지·Java 11 설치 → 수집 → 업로드 → su 전환 → sudo로 설정·정적 파일 복사 및 교체 → nginx -t → reload → HTML·CSS HTTP 200 확인 순서입니다. 설치 단계와 최종 반영 단계에서 각각 관리자 계정명과 su 및 sudo 비밀번호를 입력합니다. 실습에서는 두 비밀번호가 같습니다.

## 단계별 실행

```sh
# 1. 원본과 신규 구축 대상의 준비 상태 확인
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory.ini -i inventory-source.ini preflight.yml

# 2. 누락된 패키지와 Java 11 설치
/opt/homebrew/bin/docker-compose exec control ansible-playbook install.yml

# 3. 최신 nginx 설정과 정적 파일 수집
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory-source.ini fetch.yml

# 4. 두 신규 서버의 deploy 폴더에 업로드
/opt/homebrew/bin/docker-compose exec control ansible-playbook upload.yml

# 5. 관리자 계정 전환 후 최종 반영
/opt/homebrew/bin/docker-compose exec control ansible-playbook apply.yml
```

완료한 단계를 건너뛰려면 필요한 플레이북만 실행합니다. `setup.yml`은 항상 사전 검사부터 다시 실행합니다. `apply.yml --limit target`으로 한 대만 먼저 반영할 수도 있습니다.

수집 시작 시 `.complete` 표시를 지우고 설정과 정적 파일 모두 성공했을 때 다시 만듭니다. 업로드는 이 표시를 확인합니다. 수집·업로드·반영은 순서대로 실행하고 동시에 진행하지 않습니다.

최종 반영은 한 대씩 처리합니다. su는 Ansible become으로, sudo는 `sudo -S` 표준 입력 인증으로 처리합니다. 비밀번호 관련 명령은 no_log로 숨기고 명령행 인자에 비밀번호를 넣지 않습니다. 계정 간 임시 파일 접근을 위해 acl을 설치합니다.

기존 설정 및 정적 파일은 각 작업 디렉터리 옆의 `.backup` 경로로 보관합니다. 복사·배치·nginx 검사·reload 블록에서 실패하면 이미 백업한 항목을 복구하고 중단합니다. 이후 HTTP 확인 실패는 자동 원복하지 않습니다. 여러 서버 전체를 일괄 원복하지 않으며 앞서 성공한 서버는 유지됩니다. 백업과 진단용 작업 폴더는 자동 삭제하지 않습니다.

## 패키지 준비와 Java 11

신규 서비스 구축을 위한 흐름이며, 준비된 서버에 기존 패키지와 파일이 있을 수 있습니다. 설치된 패키지는 rpm으로 조회하고 누락된 것만 dnf install로 설치합니다. 기존 nginx 패키지를 재설치하지 않으며 설정·정적 파일은 apply 단계에서 교체합니다. 누락 패키지 설치 과정에서 의존성 패키지가 추가되거나 갱신될 수 있습니다.

기본 설치 목록은 rsync, curl, acl, java-11-openjdk-headless이며 nginx role을 선택하면 nginx도 포함합니다. JAR 실행용 Java 11 런타임입니다. 컴파일 도구가 필요하면 bootstrap_packages에 java-11-openjdk-devel을 추가하세요. java_home은 /usr/lib/jvm/jre-11-openjdk이며 공통 서비스의 종료·시작·확인 명령에 JAVA_HOME과 PATH를 전달합니다. 시스템 전체 기본 Java는 변경하지 않습니다. 스크립트 내부에서 Java 경로를 직접 고정했다면 스크립트도 확인해야 합니다.

SSH 접속 계정, su 가능한 관리자 계정과 sudo 권한, 호환되는 Python 및 계정 간 Ansible 임시 파일 접근에 필요한 ACL 설정은 미리 준비해야 합니다. 필요한 서비스 소유자·그룹도 자동 생성하지 않습니다. 실제 systemd 서버에서는 설치 단계가 nginx를 enable --now로 준비합니다. Docker 실습은 entrypoint가 nginx를 실행합니다. 공통 서비스의 부팅 시 자동 실행 등록은 포함하지 않습니다.

사전 검사는 원본 폴더·스크립트 접근, Rocky 8 여부, 서비스 계정·그룹, 대상 파일 시스템 여유 공간을 확인합니다. minimum_free_bytes는 기본 1 GiB의 하한선이며 실제 파일 크기를 계산한 용량 보장은 아닙니다. 백업과 수집본 크기에 맞춰 조정하세요. 실습 source에는 네 서비스의 모의 프로세스와 start.sh·stop.sh·check.sh, 복사 전용 deploy.sh가 준비됩니다. nginx만 연습하려면 enabled_roles를 [nginx]로 지정하세요.

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
├─ preflight.yml / install.yml # 사전 검사와 패키지 준비
├─ tasks/                      # 공통 사전 검사 작업
├─ fetch.yml / upload.yml / apply.yml
├─ vars/
│  ├─ environment.yml           # role 선택, 공통 경로, nginx 경로·검증 주소
│  └─ services.yml              # Loki·Alloy·Scouter·node exporter·deploy 목록
└─ roles/
   ├─ nginx/
   │  ├─ defaults/main.yml
   │  └─ tasks/main.yml, fetch.yml, upload.yml, apply.yml
   └─ common_services/
      ├─ defaults/main.yml
      └─ tasks/main.yml, fetch.yml, upload.yml, apply.yml
```

상위의 setup.yml, fetch.yml, upload.yml, apply.yml은 현재 사용하는 진입 플레이북입니다. 대상 서버와 단계, 비밀번호 입력을 담당하며 role이 실제 작업을 수행합니다.

반영 명령의 공통 sudo 옵션은 `vars/execution.yml`에서 관리합니다. 개별 작업은 `sudo_root_argv + ["cp", ...]`처럼 실제 명령만 덧붙입니다. 서비스 실행 계정·Java 환경·작업 폴더 설정은 `roles/common_services/defaults/main.yml`의 `service_command_prefix`를 종료·시작·확인 명령에서 재사용합니다.

nginx는 `restore-directory.yml`로 설정·정적 파일의 복구 절차를 공유하고, `validate-reload.yml`로 새 설정과 복구한 설정 모두 동일하게 검사 후 reload합니다. 계정 전환과 비밀번호 숨김은 이를 호출하는 apply 블록에서 상속합니다.

common_services의 main.yml이 서비스 목록을 반복하면서 해당 단계 파일을 직접 호출합니다. 중간 호출 전용 파일 없이 main → fetch/upload/apply로 실행됩니다.

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

`services.yml`에는 /home/deploy 아래의 loki, alloy, scouter, node_exporter, deploy 폴더를 가정한 예시 다섯 개가 들어 있습니다. Docker source에는 이 경로에 실습 파일을 생성합니다. 실제 서버에 적용할 때는 경로와 제외 목록을 확인하세요. Loki·Alloy·Scouter·node exporter는 기존 폴더의 `./stop.sh`로 종료하고 새 폴더의 `./start.sh`로 시작합니다. 두 스크립트에 실행 권한이 필요합니다. deploy 항목은 파일만 배치합니다. 네 실습 서비스의 check_argv는 ./check.sh로 설정되어 HTTP 응답과 프로세스를 확인합니다. 실제 제품에 적용할 때는 정상 확인 명령을 맞춰야 합니다. 공통 서비스를 건너뛰려면 common_services: []로 바꾸거나 environment.yml의 enabled_roles를 [nginx]로 지정합니다. 아래도 설명용 예시입니다.

```yaml
common_services:
  - name: alloy
    path: /home/deploy/alloy
    owner: alloy
    group: alloy
    excludes: ["logs/", "data/"]
    start_user: alloy
    stop_argv: ["./stop.sh"]
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

공통 서비스는 기존 폴더가 있으면 그 폴더의 stop.sh가 성공한 뒤 폴더 전체를 작업 경로의 previous로 옮겨 백업합니다. 준비한 수집본으로 최종 폴더를 통째로 교체하므로 원본에서 사라진 파일이나 제외한 로그·데이터는 새 폴더에 남지 않습니다. 기존 내용은 백업에 보관합니다. stop.sh는 이미 중지된 경우에도 성공하도록 작성해야 하며, start.sh는 서비스를 시작한 뒤 종료되어야 합니다. 종료 명령이 실패하면 교체하지 않습니다. 교체·시작·검증 실패 시 자동 원복이나 재기동을 하지 않고 작업·백업 경로를 알립니다. 해당 서비스가 중지된 상태일 수 있으므로 경로를 확인한 뒤 수동 복구합니다. nginx는 기존 검사·원복 동작을 유지합니다.

일반 파일의 위치만 바뀌면 변수 파일만 수정하면 됩니다. Loki와 Alloy, Scouter, node exporter는 각 서비스마다 role이나 fetch 파일을 추가하지 않고 목록에 항목을 추가합니다.

## 공통 서비스 실습 원본

source 이미지 빌드 시 `/home/deploy/loki`, `alloy`, `scouter`, `node_exporter`에 동일한 실습용 HTTP 프로그램과 start.sh·stop.sh·check.sh를 만듭니다. 실제 Loki·Alloy·Scouter·node exporter 바이너리가 아니며, 파일 수집·전체 교체·계정별 실행·정상 확인을 연습하기 위한 모의 서비스입니다. source에서는 파일을 제공하고, setup.yml을 실행하면 target과 target2에서 기동합니다.

각 서비스의 service.json에 이름과 포트가 있습니다. 포트는 순서대로 19101~19104이며 각 컨테이너의 127.0.0.1에만 바인딩합니다. logs에는 실행 로그와 PID가 생기고 수집에서 제외됩니다. 원본의 logs/source-only.log가 수집본에 없는지도 확인할 수 있습니다. `/home/deploy/deploy/deploy.sh`는 복사만 하며 자동 실행하지 않습니다.

전체 실습 후 다음 명령으로 target을 확인할 수 있습니다. target2도 같은 방식입니다.

```sh
docker-compose exec control ssh deploy@target /home/deploy/loki/check.sh
docker-compose exec control ssh deploy@target /home/deploy/alloy/check.sh
docker-compose exec control ssh deploy@target /home/deploy/scouter/check.sh
docker-compose exec control ssh deploy@target /home/deploy/node_exporter/check.sh
```

두 번째 setup.yml 실행에서는 기존 서비스의 stop.sh → 기존 폴더 백업 → 새 수집본 배치 → start.sh → check.sh 순서를 연습할 수 있습니다. 실습용 스크립트는 이미 시작되었거나 중지된 경우에도 성공합니다. 실제 서비스의 프로토콜·Java 호환성·운영 설정은 이 모의 프로세스로 검증하지 않습니다.

## 중지와 실습 범위

`docker-compose stop`과 `start`는 컨테이너 내부 작업을 유지합니다. `down`이나 컨테이너 재생성은 내부 실습 변경을 초기화합니다. Mac의 workspace 및 .lab은 유지됩니다.

Ubuntu 실습 당시 설정과 업로드 파일은 `.lab/pre-rocky-*`에 백업했습니다. 이전 수집본은 Rocky에 그대로 적용하지 않도록 백업으로 옮겼습니다. 새 환경에서는 수집부터 다시 진행하세요.

일반 Docker 컨테이너이므로 systemd, 부팅 시 서비스 실행, 실제 SELinux 정책 및 파일 컨텍스트는 이 실습으로 검증하지 않습니다. 실제 Rocky 서버에서는 이 항목을 추가 검증해야 합니다. 현재 Mac 실습은 ARM64이며 운영 서버의 CPU 아키텍처·nginx 버전·모듈도 별도로 확인해야 합니다. CentOS에서 수집한 설정을 Rocky에 그대로 적용할 수 있다고 보장하지 않습니다.
