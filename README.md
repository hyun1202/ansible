# Ansible 첫 실습

이 프로젝트는 Ubuntu 24.04 컨테이너 네 개(제어 노드 1대, 신규 대상 노드 2대, 운영 서버 역할 1대)로 구성됩니다.

- `control`: Ansible Core 2.19.14를 실행하는 제어 노드
- `target`: SSH와 Python이 준비된 대상 노드. 접속 계정은 `ansible`입니다.
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

수집 결과는 Mac의 `workspace/snapshots/nginx-<UTC 시각>-<고유값>/nginx/`에 저장됩니다. 성공한 수집 폴더에는 `.complete` 파일이 생깁니다. 매번 새 폴더에 수집하므로 기존 수집본의 오래된 파일이 섞이지 않습니다. 심볼릭 링크를 보존하며 source의 설정은 변경하지 않습니다. 수집 중 원본 파일이 바뀌면 한 시점의 일관된 설정이 아닐 수 있으므로, 실제 구축에서는 설정 변경이 없는 시점에 수집합니다.

예제 설정은 source의 `/etc/nginx/sites-available/legacy-app.conf`입니다. source에서 nginx를 실행하는 데 사용합니다. 로컬 `source/legacy-app.conf`는 컨테이너 초기 구성용이고, rsync는 실행 중인 source 내부의 파일을 읽습니다.

이후 단계는 수집본 확인 → 신규 서버별 값 조정 → target/target2에 nginx 설치 및 설정 배치 → 설정 검사 및 실행입니다. 한 번 구축할 때는 같은 수집본으로 두 신규 서버를 구성합니다. 현재는 수집까지만 구현되어 있습니다.

## 파일과 작업 위치

Mac의 `workspace/` 폴더가 control의 `/workspace`에 연결됩니다. 플레이북은 Mac에서 작성하고 control 안에서 실행하면 됩니다.

- `workspace/inventory.ini`: 대상 서버 목록
- `workspace/inventory-source.ini`: 설정 수집 전용 source 목록
- `workspace/fetch-nginx.yml`: 최신 nginx 설정 수집 플레이북
- `workspace/ansible.cfg`: 접속과 실행 기본 설정
- `.lab/`: 이 실습만을 위한 SSH 키와 대상 서버의 공개키. Git에 넣거나 공유하지 않습니다.

SSH 대상 서버의 공개키를 미리 등록해서 호스트 키 검증을 유지합니다. 실습 대상의 `ansible` 계정은 컨테이너 안에서 비밀번호 없이 sudo를 사용할 수 있습니다.

## 컨테이너 쉘

```sh
docker-compose exec control bash
docker-compose exec --user ansible target bash
docker-compose exec --user ansible target2 bash
```

## 중지와 재시작

```sh
docker-compose stop
docker-compose start
```

`stop`/`start`는 대상 서버 안에서 실습한 파일을 유지합니다. `docker-compose down`은 이 프로젝트의 컨테이너와 네트워크를 삭제하므로 target 내부의 실습 변경은 사라집니다. Mac의 workspace와 .lab은 남습니다. 이미 만들어진 환경은 보통 `start`로 다시 시작하세요.

## 실습 범위

파일·권한·계정·패키지·설정 템플릿·nginx 설정 검사 등을 실습합니다. 일반 컨테이너이므로 systemd, OS 재부팅, 부팅 시 서비스 자동 시작의 최종 검증은 실제 신규 Linux 서버에서 진행합니다. Apple Silicon에서는 ARM64로 실행되므로 이후 바이너리 설치 시 아키텍처를 확인합니다.

수집 플레이북은 실행할 때마다 새 수집본을 만드므로 매번 `changed`가 발생합니다. 이후 신규 서버 구성 플레이북에서는 같은 수집본을 반복 적용해 멱등성을 확인합니다.
