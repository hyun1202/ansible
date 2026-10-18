# Ansible 신규 서버 구축 실습

원본 서버에서 nginx 설정·정적 파일·서비스 폴더를 수집해 Rocky Linux 8 대상 두 대에 배포합니다. 파일 전송과 공통 서비스에는 SSH 키 계정을, nginx와 패키지 설치에는 실행 시 입력한 개발자 계정을 사용합니다. su 전환은 사용하지 않습니다.

| 서버 | 키 계정 | 역할 |
| --- | --- | --- |
| control | — | Ansible Core 2.19.14, rsync 실행 및 수집본 보관 |
| source | ansible | nginx 설정·정적 파일·공통 서비스 원본 |
| target, target2 | deploy | 신규 구축 대상 |

source와 target은 Rocky 8, control은 Ubuntu 24.04입니다. Ansible 실행용 Python은 Rocky에 설치한 Python 3.9입니다. 원본은 Rocky로 제한하지 않지만 SSH·Python·rsync 등 연결 조건이 맞아야 합니다.

## 접속과 권한

| 작업 | 접속 방식 | 권한 |
| --- | --- | --- |
| nginx 원본 사본 준비·정리 | 입력한 개발자 계정 + SSH 비밀번호 | Ansible become으로 sudo |
| rsync 수집·업로드 | inventory의 일반 계정 + SSH 키 | sudo 없음 |
| nginx 최종 반영 | 입력한 개발자 계정 + SSH 비밀번호 | Ansible become으로 sudo |
| common_services 백업·교체·실행 | deploy + SSH 키 | sudo 없음 |
| 패키지 설치·최초 폴더 준비 | 입력한 개발자 계정 + SSH 비밀번호 | Ansible become으로 sudo |

개발자 계정은 서버에 직접 SSH 접속할 수 있고 sudo 권한이 있어야 합니다. 실습에서는 개발자 예시로 adminuser를 사용하며, source와 target 모두 같은 `.lab/adminuser_password`를 사용합니다. 실제 서버에서는 본인 계정을 입력합니다. 원본과 대상 접속 정보는 별도로 받습니다.

```sh
# 실습용 비밀번호 확인 (실제 운영 비밀번호를 이 파일에 저장하지 마세요)
cat .lab/adminuser_password
```

실습 SSH 설정에서 ansible/deploy는 키 전용이고 adminuser만 비밀번호 SSH를 허용합니다. root SSH 로그인은 막혀 있습니다. 키와 비밀번호는 `.lab/`에 보관하며 Git과 이미지 빌드에서 제외합니다.

## 경로

```text
원본 /etc/nginx/                 → /srv/ansible-staging/source-임의값/nginx/
원본 /usr/share/nginx/html/      → /srv/ansible-staging/source-임의값/static/
                                         ↓ 키 계정 rsync pull
control /workspace/collected/nginx/ + static/
                                         ↓ 키 계정 rsync push
대상 /srv/ansible-staging/upload/nginx/ + static/
                                         ↓ 개발자 SSH + sudo
대상 /etc/nginx/ + /usr/share/nginx/html/
```

원본 임시 사본은 일반 전송 계정만 접근하도록 0700으로 제한합니다. 원본 파일의 소유권·권한은 변경하지 않습니다. 수집 후 `always` 작업으로 이번 사본을 지우며, 수집 실패 시에도 정리합니다. 강제 종료·연결 단절로 정리 자체가 실행되지 못하면 수동 정리가 필요할 수 있습니다.

`/etc/nginx/SSL_2026` 안의 실제 인증서·개인키도 함께 수집합니다. 외부 경로를 가리키는 심볼릭 링크는 링크만 보존하므로 실제 대상 파일은 별도로 준비해야 합니다. 원본을 복사하는 동안 변경이 발생하면 한 시점의 일관된 백업을 보장하지 않습니다. 설정 변경·인증서 갱신과 겹치지 않게 수집하고 사본을 위한 원본 디스크 공간도 확보하세요.

control 수집본은 한 벌만 유지합니다. rsync의 delete는 수집본과 업로드용 폴더에만 적용하며 운영 원본을 삭제하지 않습니다. collected, 대상 staging, 백업에는 개인키가 포함될 수 있으므로 접근 권한을 유지하고 Git에 올리지 마세요. Mac의 workspace가 control의 /workspace에 연결됩니다.

## 시작과 실행

```sh
./init.sh
docker-compose up -d --build
docker-compose exec control ansible lab -m ansible.builtin.ping
```

이 Mac의 Compose 실행 파일은 `/opt/homebrew/bin/docker-compose`입니다. Compose 프로젝트는 ansible-study이며 외부 포트는 열지 않습니다. 다른 프로젝트의 컨테이너는 건드리지 않습니다.

서버 목록은 `workspace/inventory.ini` 하나입니다. config_sources는 원본, lab은 대상이며 플레이북의 hosts가 실행 그룹을 선택합니다. 개발자 접속은 같은 서버 주소에 실행 중 메모리의 별칭을 만들어 사용하므로 inventory 파일에 개인 계정이나 비밀번호를 적지 않습니다.

```sh
# 전체: 인증 입력 → 사전 검사 → 설치 → 수집 → 업로드 → 반영
docker-compose exec control ansible-playbook setup.yml

# 필요한 단계만 따로 실행
docker-compose exec control ansible-playbook preflight.yml
docker-compose exec control ansible-playbook install.yml
docker-compose exec control ansible-playbook fetch.yml
docker-compose exec control ansible-playbook upload.yml
docker-compose exec control ansible-playbook apply.yml
```

setup은 원본·대상의 개발자 계정명, SSH 비밀번호, sudo 비밀번호를 각각 한 번 입력받아 후속 단계에서 재사용합니다. fetch 단독은 원본 정보만, install 단독은 대상 정보만, nginx를 포함한 apply 단독은 대상 정보만 받습니다. common_services만 선택한 apply에는 개발자 인증이 필요 없습니다. preflight와 upload는 키 계정으로만 실행합니다.

입력은 대화형 터미널에서 실행하세요. 비밀번호를 파일에 자동 저장하거나 fact cache에 기록하지 않습니다. 인증 값과 동적 연결 정보는 no_log로 숨깁니다. 다음 ansible-playbook 실행에서는 다시 입력합니다. 비대화형 실행 시에는 Vault 등으로 source_admin_user/source_admin_ssh_password/source_admin_sudo_password와 admin_user/admin_ssh_password/admin_sudo_password를 제공할 수 있습니다. 비밀번호를 명령행에 직접 적지 마세요.

`apply.yml --limit target`으로 한 대만 먼저 반영할 수 있습니다. 수집·업로드·반영은 순서대로 실행하고 동시에 실행하지 않습니다. fetch는 시작 시 완료 표시를 제거하고 수집과 원본 사본 정리가 모두 성공한 뒤 다시 생성합니다. upload는 완료 표시가 있어야 진행합니다.

## 변수와 role

```text
workspace/
├─ setup.yml
├─ preflight.yml / install.yml / fetch.yml / upload.yml / apply.yml
├─ inventory.ini
├─ vars/
│  ├─ environment.yml          # 경로·Java·검사 설정
│  └─ services.yml             # 공통 서비스 목록
├─ tasks/                     # 인증 입력·개발자 연결·사전 검사
└─ roles/
   ├─ nginx/                  # 인증서 포함 설정·정적 파일
   └─ common_services/        # 키 계정이 관리하는 서비스
```

role의 main.yml은 deployment_phase에 해당하는 fetch/upload/apply.yml을 호출합니다. common_services는 services.yml의 목록을 반복합니다. validate.yml은 이름 중복·경로·명령 목록 형식 같은 변수 오류를 검사합니다.

- enabled_roles: 실행할 role. nginx만 연습하려면 `[nginx]`.
- collection_root: control의 수집본 경로.
- source_staging_root: 원본 임시 사본 상위 경로, 기본 `/srv/ansible-staging`.
- staging_root: 대상 업로드 경로, 기본 `/srv/ansible-staging/upload`.
- nginx_config_dir / nginx_static_dir: 대상 설정·정적 파일 경로.
- nginx_source_config_dir / nginx_source_static_dir: 수집할 원본 경로.
- nginx_source_use_sudo: true이면 개발자 계정으로 수집 사본 준비. false이면 원본 키 계정으로 직접 읽으며 원본 인증 입력은 생략.
- java_home: 기본 `/usr/lib/jvm/jre-11-openjdk`.
- minimum_free_bytes: 대상 파일 시스템의 최소 여유 공간. 기본 1 GiB이며 실제 수집본·백업 용량 보장은 아님.

## 설치와 반영

install은 누락된 rsync·curl·acl·Java 11 런타임 및 선택한 nginx를 설치합니다. Rocky 8의 시스템 DNF 바인딩은 Python 3.6용이므로 Ansible용 Python 3.9에서는 rpm/dnf CLI를 사용하고, root 권한은 Ansible become이 처리합니다. 다른 파일 작업은 file/copy/tempfile 모듈을 사용합니다. 기존 패키지를 강제로 재설치하지 않지만 의존성 해결 과정에서 패키지가 추가·갱신될 수 있습니다.

install은 staging과 없는 서비스 폴더를 지정한 소유자·그룹으로 준비합니다. 기존 서비스 폴더의 소유권은 강제로 바꾸지 않습니다. 계정과 그룹은 미리 존재해야 하며, 공통 서비스의 owner와 start_user는 키 접속 계정과 같아야 합니다. `/srv` 자체를 deploy 소유로 바꾸지 않습니다. 시스템 기본 Java는 바꾸지 않고 서비스 명령에 Java 11의 JAVA_HOME과 PATH를 전달합니다. 스크립트에 Java 경로를 직접 고정했다면 별도로 확인하세요.

nginx는 개발자 접속에 sudo become을 적용해 업로드 파일을 root 작업 폴더에 복사하고, 기존 설정·정적 파일을 백업한 뒤 디렉터리를 교체합니다. 이동에는 mv를 사용합니다. nginx -t 성공 후 reload하며, 반영 블록 실패 시 백업한 항목을 복구합니다. HTTP 확인은 그 블록 밖이므로 HTTP 확인 실패에는 자동 원복하지 않습니다. 실제 systemd 서버에서는 install이 nginx를 자동 시작하도록 준비하고, 컨테이너에서는 entrypoint가 실행합니다.

공통 서비스는 deploy 계정으로 현재 폴더의 stop.sh를 실행하고, 내용을 staging의 서비스 작업 폴더 안 previous에 백업합니다. 서비스 폴더의 상위 경로에 쓰기 권한이 없어도 동작하도록 서비스 디렉터리 자체는 유지하고 내부 파일·하위 폴더를 교체합니다. 따라서 제외한 기존 로그·데이터와 원본에 없는 파일은 새 서비스 폴더에 남지 않고 백업에만 남습니다. 교체 후 start.sh, check.sh 순서로 실행합니다. 실패 시 자동 원복·재기동하지 않고 백업 위치를 안내합니다. 백업과 대상 업로드 파일은 자동 삭제하지 않습니다.

## 공통 서비스 실습

서비스 경로의 `~`는 키 접속 계정인 deploy의 홈(`/home/deploy`)을 뜻합니다. 개발자 sudo 계정의 홈과 혼동하지 않도록 services.yml에는 절대 경로를 적습니다. 전송용 staging은 `/srv/ansible-staging`을 사용합니다.

source 이미지에는 `/home/deploy/loki`, `/home/deploy/alloy`, `/home/deploy/scouter`, `/home/deploy/node_exporter`와 `/home/deploy/deploy`가 준비됩니다. 앞의 네 서비스는 실제 제품 대신 가벼운 실습용 HTTP 프로세스이며 start.sh·stop.sh·check.sh를 제공합니다. 마지막 deploy.sh는 복사만 하고 자동 실행하지 않습니다.

각 서비스는 127.0.0.1의 19101~19104 포트를 사용합니다. logs에는 PID와 실행 로그가 생기고 수집에서 제외됩니다. 시작 스크립트는 실행 후 종료되어야 하며 종료 스크립트는 이미 중지된 경우에도 성공해야 합니다. 전체 실행을 다시 하면 종료·백업·교체·재시작을 연습할 수 있습니다.

```sh
docker-compose exec control ssh deploy@target /home/deploy/loki/check.sh
docker-compose exec control ssh deploy@target /home/deploy/alloy/check.sh
docker-compose exec control ssh deploy@target /home/deploy/scouter/check.sh
docker-compose exec control ssh deploy@target /home/deploy/node_exporter/check.sh
```

실제 서비스에 적용할 때는 services.yml의 경로, 제외 패턴, 시작·종료·검증 명령을 수정하세요. source_path를 지정하면 대상 path와 다른 원본 경로에서 수집할 수 있습니다. check_argv가 비어 있으면 정상 동작 검증은 생략합니다.

## 실습 범위

사전 검사는 원본 서비스 폴더·스크립트, 대상 Rocky 8 여부·계정·여유 공간을 확인합니다. 관리자 모드의 nginx 경로 접근은 fetch에서 확인하므로 preflight 성공만으로 개발자 SSH·sudo·인증서 접근까지 검증한 것은 아닙니다.

일반 Docker 컨테이너이므로 실제 systemd 동작, SELinux 정책·파일 컨텍스트, 공통 서비스의 부팅 시 자동 실행은 별도 검증이 필요합니다. Mac 실습은 ARM64이므로 실제 서버의 CPU 아키텍처·nginx 버전·모듈도 확인해야 합니다. 모의 서비스로 실제 제품의 설정이나 Java 호환성이 검증되지는 않습니다.

Compose stop/start는 컨테이너 내부 파일을 유지하지만 down 또는 재생성은 초기화할 수 있습니다. Mac의 workspace와 .lab은 유지됩니다. 이전 실습에서 /srv 아래에 만든 서비스 파일은 자동 삭제하지 않습니다.
