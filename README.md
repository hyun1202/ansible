# Ansible 첫 실습

이 프로젝트는 Ubuntu 24.04 컨테이너 네 개(제어 노드 1대, 신규 대상 노드 2대, 운영 서버 역할 1대)로 구성됩니다.

- `control`: Ansible Core 2.19.14를 실행하는 제어 노드
- `target`: SSH와 Python이 준비된 대상 노드. 접속 계정은 sudo 권한이 없는 `deploy`입니다.
- `target2`: 두 번째 대상 노드. `target`과 같은 구성이고, 서버 호스트 키는 별도로 사용합니다.
- `source`: nginx가 실행 중인 운영 서버 역할의 실습 컨테이너. rsync로 설정을 읽어 오는 용도이며, 배포용 inventory에는 포함하지 않습니다.

Compose 프로젝트 이름은 `ansible-study`입니다. 호스트 포트는 공개하지 않고, 네 컨테이너는 프로젝트 전용 네트워크에서 통신합니다. 실제 운영 서버의 인증 정보는 사용하지 않습니다. 패키지 설치를 위한 외부 인터넷 연결은 가능합니다.

## 시작하기

이 Mac에서는 Compose가 `docker-compose` 명령으로 설치되어 있습니다. 아래 명령은 이 README가 있는 폴더에서 실행합니다.

```sh
./init.sh
docker-compose up -d --build
docker-compose ps
```

다른 컴퓨터에서 Compose 플러그인을 쓰는 경우 `docker-compose`를 `docker compose`로 바꾸면 됩니다. 현재 환경의 Docker context는 `colima`입니다.

## 1단계: 접속 확인

```sh
docker-compose exec control ansible lab -m ansible.builtin.ping
```

`target`과 `target2` 모두 `SUCCESS`와 `"ping": "pong"`이 나오면 성공입니다. 이 ping은 ICMP ping이 아니라 SSH로 연결해서 대상의 Python에서 Ansible 모듈을 실행하는 검사입니다.

- `control`: 명령을 실행할 컨테이너
- `ansible`: Ansible 실행 명령
- `lab`: inventory.ini의 대상 그룹
- `-m ansible.builtin.ping`: 실행할 모듈

한 대만 확인하려면 `lab` 대신 `target` 또는 `target2`를 지정합니다.

## 운영 서버 역할의 source에서 최신 설정 수집

신규 구축을 시작할 때마다 source의 현재 `/etc/nginx/`를 rsync로 control에 가져옵니다.

`fetch-nginx.yml` 플레이북의 `ansible.posix.synchronize` 모듈이 rsync를 실행합니다. `mode: pull`은 source → control 방향이며 별도 쉘 스크립트는 필요하지 않습니다. 필요한 컬렉션은 control 이미지에 설치됩니다.

```sh
docker-compose exec control ansible-playbook -i inventory-source.ini fetch-nginx.yml
```

수집 결과는 항상 Mac의 `workspace/collected/nginx/`에 저장됩니다. 수집 시작 시 기존 `.complete` 표시를 지우고, 성공했을 때만 다시 만듭니다. rsync의 `delete: true`는 원본에서 사라진 파일을 이 로컬 수집 폴더에서도 제거합니다. source 파일은 삭제하거나 변경하지 않으며 심볼릭 링크를 보존합니다. 수집과 업로드는 동시에 실행하지 말고 순서대로 진행합니다. 수집 중 원본 파일이 바뀌면 한 시점의 일관된 설정이 아닐 수 있으므로, 실제 구축에서는 설정 변경이 없는 시점에 수집합니다.

예제 설정은 source의 `/etc/nginx/sites-available/legacy-app.conf`입니다. source에서 nginx를 실행하는 데 사용합니다. 로컬 `source/legacy-app.conf`는 컨테이너 초기 구성용이고, rsync는 실행 중인 source 내부의 파일을 읽습니다.

이후 단계는 수집본 확인 → 신규 서버별 값 조정 → target/target2에 nginx 설치 및 설정 배치 → 설정 검사 및 실행입니다. 한 번 구축할 때는 같은 수집본으로 두 신규 서버를 구성합니다. 수집과 일반 계정 업로드는 플레이북으로 준비되어 있고, 최종 복사·검사·reload는 직접 실습합니다.

## 파일과 작업 위치

Mac의 `workspace/` 폴더가 control의 `/workspace`에 연결됩니다. 플레이북은 Mac에서 작성하고 control 안에서 실행하면 됩니다.

- `workspace/inventory.ini`: 대상 서버 목록
- `workspace/inventory-source.ini`: 설정 수집 전용 source 목록
- `workspace/fetch-nginx.yml`: 최신 nginx 설정 수집 플레이북
- `workspace/ansible.cfg`: 접속과 실행 기본 설정
- `.lab/`: 이 실습만을 위한 SSH 키와 대상 서버의 공개키. Git에 넣거나 공유하지 않습니다.

SSH 대상 서버의 공개키를 미리 등록해서 호스트 키 검증을 유지합니다. 신규 타겟에는 `deploy`만 SSH 접속할 수 있습니다. `adminuser`는 `su` 전환용 계정이며 비밀번호를 입력해야 sudo를 사용할 수 있습니다. source의 수집 계정은 기존 `ansible`입니다.

## 컨테이너 쉘

```sh
docker-compose exec control bash
docker-compose exec --user deploy target bash
docker-compose exec --user deploy target2 bash
```

## 중지와 재시작

```sh
docker-compose stop
docker-compose start
```

`stop`/`start`는 대상 서버 안에서 실습한 파일을 유지합니다. `docker-compose down`은 이 프로젝트의 컨테이너와 네트워크를 삭제하므로 target 내부의 실습 변경은 사라집니다. Mac의 workspace와 .lab은 남습니다. 이미 만들어진 환경은 보통 `start`로 다시 시작하세요.

## 실습 범위

파일·권한·계정·패키지·설정 템플릿·nginx 설정 검사 등을 실습합니다. 일반 컨테이너이므로 systemd, OS 재부팅, 부팅 시 서비스 자동 시작의 최종 검증은 실제 신규 Linux 서버에서 진행합니다. Apple Silicon에서는 ARM64로 실행되므로 이후 바이너리 설치 시 아키텍처를 확인합니다.

수집 폴더는 하나만 유지합니다. 완료 표시 갱신 작업은 매번 changed가 나올 수 있습니다. 업로드 플레이북은 같은 설정이 이미 타겟에 있으면 파일을 다시 변경하지 않습니다. 이전 방식의 `workspace/snapshots/`는 더 이상 사용하지 않습니다.

## 직접 실습: 수집 → 업로드 → 계정 전환 → 복사 → 검사 → reload

타겟 두 대에는 nginx가 미리 설치·실행되어 있습니다. 초기 HTTP 응답은 `new target: before deployment`입니다. 이번 실습에서는 `/etc/nginx/` 디렉터리 전체를 수집·업로드·교체합니다. nginx.conf, sites-available, sites-enabled, conf.d, snippets 등을 포함하고 심볼릭 링크도 보존합니다. 이 경로 밖의 인증서·웹 콘텐츠·모듈 파일 등은 별도 준비가 필요하며 이 실습 설정은 해당 추가 파일을 요구하지 않습니다.

### 1. 실습용 관리자 비밀번호 확인 (Mac)

```sh
cd /Users/hyun/Study/ansible
cat .lab/adminuser_password
```

이 파일은 실습 환경 전용이며 Git에 포함되지 않습니다. 두 타겟의 `adminuser`가 같은 실습 비밀번호를 사용합니다. 컨테이너 시작 시 이 파일의 값으로 설정되므로 컨테이너 안에서 바꾼 비밀번호는 재시작 시 초기화됩니다. 실제 운영 비밀번호를 이 파일에 넣지 마세요.

### 2. source의 최신 설정 수집 (Mac)

```sh
/opt/homebrew/bin/docker-compose exec control ansible-playbook -i inventory-source.ini fetch-nginx.yml
```

항상 `/workspace/collected/nginx/`에 수집되므로 다음 단계에서 경로를 입력할 필요가 없습니다.

### 3. 타겟 두 대의 deploy 폴더에 업로드 (Mac)

```sh
/opt/homebrew/bin/docker-compose exec control ansible-playbook upload-nginx.yml
```

공통 수집 폴더의 nginx 디렉터리 전체를 rsync로 두 서버의 `/home/deploy/staging/nginx/`에 업로드합니다. 원본 수집본에 없는 파일은 이 임시 nginx 폴더에서도 제거합니다. sudo는 사용하지 않고, 실행 중인 `/etc/nginx/` 설정도 아직 바뀌지 않습니다. 업로드가 성공한 뒤 최종 복사를 진행하며, 복사 중에는 업로드를 다시 실행하지 않습니다.

### 4. target에 SSH 접속하고 계정 전환 (Mac에서 시작)

```sh
/opt/homebrew/bin/docker-compose exec control ssh deploy@target
```

이후 명령은 target 안에서 실행합니다.

```sh
whoami
ls -la /home/deploy/staging/nginx/
cat /home/deploy/staging/nginx/nginx.conf
su - adminuser
whoami
```

`su` 비밀번호에는 앞서 확인한 실습용 관리자 비밀번호를 입력합니다. 입력 중 문자가 표시되지 않는 것이 정상입니다.

### 5. 디렉터리 전체를 sudo로 복사하고 기존 설정 교체 (target의 adminuser)

```sh
nginx_stage=$(sudo mktemp -d /etc/nginx-stage.XXXXXX)
sudo cp -a --no-preserve=ownership /home/deploy/staging/nginx "$nginx_stage/"
```

위 복사가 성공한 것을 확인한 뒤 아래 명령을 한 줄씩 실행합니다. 실패하면 다음 단계로 넘어가지 않습니다.

```sh
nginx_backup="${nginx_stage}.backup"
sudo mv /etc/nginx "$nginx_backup"
sudo mv "$nginx_stage/nginx" /etc/nginx
sudo rmdir "$nginx_stage"
```

sudo가 비밀번호를 물으면 같은 adminuser 비밀번호를 입력합니다. `cp -a`는 디렉터리와 링크를 보존하고, `--no-preserve=ownership`은 deploy의 소유권을 넘기지 않아 새 파일이 root 소유로 생성되게 합니다. 기존 디렉터리를 백업 위치로 이동한 뒤 새 디렉터리를 배치하므로 예전 설정 파일이 섞이지 않습니다. 같은 셸에서 `nginx_backup` 값을 유지한 채 검사와 복구를 진행하세요. 교체 후에도 nginx는 reload 전까지 메모리에 읽어 둔 기존 설정으로 실행됩니다.

### 6. 설정 검사에 성공한 경우에만 reload (target의 adminuser)

```sh
sudo nginx -t && sudo nginx -s reload
python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1').read().decode())"
```

응답이 `legacy nginx configuration v1`이면 원본 서버에서 수집한 설정이 반영된 것입니다. 검사에 실패하면 reload하지 말고 오류를 수정하거나 아래처럼 복원합니다.

```sh
sudo mv /etc/nginx "${nginx_backup}.failed"
sudo mv "$nginx_backup" /etc/nginx
sudo nginx -t
```

`exit` 두 번으로 adminuser와 SSH 세션에서 나온 뒤, `ssh deploy@target2`로 두 번째 타겟에 같은 과정을 연습할 수 있습니다. 일반 Docker 컨테이너이므로 이번에는 systemctl 대신 nginx 명령을 사용합니다.
