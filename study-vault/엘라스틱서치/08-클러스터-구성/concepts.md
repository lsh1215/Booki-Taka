# 08. 클러스터 구성 — 핵심 개념

> 출처: 엘라스틱서치 실무가이드 Ch12 (클러스터 운영 노하우) / 엘라스틱서치바이블 Ch5 (서비스 환경에 클러스터 구성)
> 태그: #cluster #node-role #master #data-node #coordinating-node #split-brain #security #tls

관련 개념: [핵심 아키텍처](../01-핵심-아키텍처/concepts.md)

---

## 1. 노드 역할 (Node Roles)

### 정의
엘라스틱서치 클러스터 내에서 각 노드가 담당하는 작업 범위. `node.roles` 설정으로 지정하며, 역할을 0개 이상 조합할 수 있다.

### 왜 필요한가
- 클러스터 규모가 작을 때는 모든 노드가 동일한 역할(Single Node 모드)로 동작해도 무방하다
- 규모가 커질수록 역할 분리 없이 운영하면 처리 속도, 메모리 관리 측면에서 큰 손해를 본다
- 각 역할을 전용 노드에서 처리해야 장애 격리와 성능 최적화가 가능하다

### 주요 노드 역할 종류

#### 마스터 후보 노드 (master-eligible node)
```yaml
node.roles: [ master ]
```
- `master` 역할을 지정하면 마스터 후보 노드가 된다
- 마스터 후보 노드 중 선거를 통해 **마스터 노드**가 선출된다
- 마스터 노드: 인덱스 생성/삭제, 어떤 샤드를 어느 노드에 할당할지 등 클러스터 관리 담당
- 구버전(7.9 미만): `node.master: true/false`로 설정

#### 데이터 노드 (data node)
```yaml
node.roles: [ data ]
```
- 실제 데이터를 보관하는 노드
- CRUD, 검색, 집계와 같이 데이터 관련 작업 수행
- 대용량 스토리지와 고성능 CPU/메모리 필요
- 구버전: `node.data: true/false`로 설정

#### 인제스트 노드 (ingest node)
```yaml
node.roles: [ ingest ]
```
- 데이터가 색인되기 전에 전처리를 수행하는 인제스트 파이프라인을 실행
- 크롤러 개발 없이 간단한 포맷 변경, 유효성 검증 등 전처리 가능
- 구버전: `node.ingest: true/false`로 설정

#### 조정 전용 노드 (coordinating-only node)
```yaml
node.roles: []  # 빈 배열 = 조정 전용
```
- 모든 노드는 기본적으로 조정(coordinating) 역할을 수행한다
- **조정 역할**: 클라이언트 요청을 받아 다른 데이터 노드에 요청을 분배하고, 결과를 취합해 최종 응답을 반환
- 조정 역할만 수행하는 노드를 **조정 전용 노드**라 부른다
- 각 데이터 노드에서 작업한 결과를 취합하는 작업은 생각보다 큰 부하를 줄 수 있다
- 구버전: `node.master: false`, `node.data: false`, `node.ingest: false`, `search.remote.connect: false`

#### 원격 클러스터 클라이언트 노드
```yaml
node.roles: [ remote_cluster_client ]
```
- 다른 엘라스틱서치 클러스터에 클라이언트로 접속 가능
- 키바나 스택 모니터링, 클러스터 간 검색(cross-cluster search) 기능에 사용

#### 데이터 티어 노드 (data tier node)
```yaml
node.roles: [ data_hot ]    # 최신 데이터, 고성능 서버
node.roles: [ data_warm ]   # 중간 단계 데이터
node.roles: [ data_cold ]   # 오래된 데이터
node.roles: [ data_frozen ] # 거의 접근 안 하는 데이터
node.roles: [ data_content ] # 컨텐츠 데이터
```
- `data` 역할 대신 성능별로 hot-warm-cold-frozen 티어로 구분
- 사양이 크게 차이나는 서버 자원을 활용해야 하는 경우에 유용
- 단, 최신/오래된 데이터 접근 패턴이 명확히 구분될 때만 도입 권장

### 설계 트레이드오프
| 구성 | 장점 | 단점 |
|------|------|------|
| Single Node (모든 역할 겸임) | 장비 절약, 간단한 관리 | 규모 확장 시 비효율, 장애 전파 위험 |
| 마스터/데이터 분리 | 장애 격리, 안정성 향상 | 장비 추가 필요 |
| 조정 전용 노드 추가 | 집계/검색 부하 분리 | 마스터 노드 관리 부담 증가 |
| 데이터 티어 구조 | 비용 최적화 | 복잡한 운영, 추가 샤드 이동 비용 |

---

## 2. 마스터 선출 메커니즘

### 투표 구성원 (Voting Configuration)
- 마스터 후보 노드 중 일부 혹은 전체로 구성된 부분 집합
- 마스터 선출, 클러스터 상태 저장 등 의사결정에 참여
- **과반 이상의 결정**으로 중요한 의사결정을 수행
- 일반적으로 마스터 후보 노드 전체와 동일한 집합

### 투표 구성원 자동 조정 (7 버전 이상)
- 새 마스터 후보 노드가 클러스터에 참여하면 투표 구성원에 추가하려 한다
- 마스터 후보 노드가 떠나면 투표 구성원에서 제거하려 한다
- 마스터 후보 노드 수를 줄이려면 한 대씩 천천히 제거해야 한다 (동시에 절반 이상 멈추면 의사결정 불가)

### 홀수 대 권장 이유
- 투표 구성원 조정 개념이 없는 7 버전 미만: split brain 방지를 위해 minimum_master_nodes를 과반으로 지정해야 했음
  - 4대 준비 시 minimum_master_nodes=3이므로 결국 1대 실패만 허용 → 3대 준비와 동일
- 7 버전 이상: 엘라스틱서치가 투표 구성원을 홀수로 유지하기 위해 마스터 후보 노드 하나를 투표 구성원에서 빼 둠
- 따라서 **홀수 대를 준비하는 것이 비용 대비 효용성이 좋다**

### 구버전 클러스터 설정 (7 버전 미만)
```yaml
discovery.zen.minimum_master_nodes: 2  # (마스터 후보 노드 수/2) + 1
```
- 런타임 변경도 가능:
```json
PUT _cluster/settings
{
  "transient": {
    "discovery.zen.minimum_master_nodes": 3
  }
}
```

### 신버전 클러스터 설정 (7 버전 이상)
```yaml
discovery.seed_hosts: ["10.0.0.1", "some-host-name.net"]
cluster.initial_master_nodes: ["test-es-node01", "test-es-node02", "test-es-node03"]
```

---

## 3. Split Brain 문제와 방지

### 정의
마스터 노드가 둘 이상으로 포개져서 발생하는 클러스터 분리 문제.

### 발생 시나리오
1. 마스터 노드에 장애 발생
2. 대기 중인 마스터 후보 노드들이 투표 시작 직전에 **네트워크 단절** 발생
3. 각 후보 노드가 "나 혼자 남았다"고 판단하고 각자 마스터로 선출
4. 클러스터 안에 마스터가 2개 이상 존재하게 됨
5. 데이터 노드가 두 그룹으로 분리
6. 샤드가 마구 복구되며 클러스터 전체 데이터 정합성 붕괴

### 왜 치명적인가
- 데이터 유실, 중복, 불일치 발생
- 강제로 마스터를 하나로 변경해도 완벽한 데이터 복구 불가능
- 현실에서도 충분히 발생 가능한 시나리오 (네트워크 순간 단절)

### 방지 방법

#### 7 버전 미만: minimum_master_nodes 설정
```yaml
# elasticsearch.yml
discovery.zen.minimum_master_nodes: 2  # 마스터 3대인 경우
```
- 공식: `(마스터 후보 노드 수 / 2) + 1`
- 반드시 과반 이상으로 지정해야 split brain 방지 가능

#### 7 버전 이상: 투표 구성원 자동 조정
- `discovery.zen.minimum_master_nodes` 설정 자체가 없어짐
- 엘라스틱서치가 투표 구성원을 자동으로 관리
- split brain이 원천적으로 일어나지 않는 구조

---

## 4. 클러스터 구성 전략

### 마스터 후보 노드와 데이터 노드를 분리해야 하는 이유

**분리하지 않을 경우의 문제:**
- 무거운 쿼리로 데이터 노드에 hang이 걸리거나 다운되면 마스터 역할도 정상 수행 불가
- 데이터 노드 하나의 장애가 클러스터 전체 장애로 번짐
- 마스터 노드가 완전히 다운되지 않고 프로세스만 살아 있으면 새 마스터 선출도 안 됨

**분리 시 이점:**
- 데이터 노드 하나가 죽어도 마스터는 정상 동작
- 마스터가 주 샤드 없어진 샤드의 복제본을 새 주 샤드로 변경, 자연스러운 복구
- 롤링 리스타트 시 불필요한 샤드 복구나 마스터 재선출 방지

**마스터 후보 노드 사양:**
- 데이터 노드보다 상대적으로 낮은 사양 서버 사용 가능
- 디스크나 메모리를 많이 쓰지 않음
- 가상 서버 사용 가능 (단, 마스터 후보 노드들이 같은 물리 장비에 배정되지 않도록 주의)

### 서버 자원별 구성 전략

#### 최소 구성 (장비 3대)
- 3대 모두 마스터 후보 + 데이터 역할 겸임
- 소규모 서비스에 적합, 1대 장애까지 서비스 유지 가능

#### 장비 4~5대
- 3대: 마스터 후보 + 데이터 겸임
- 나머지 1~2대: 데이터 전용

#### 장비 6~7대
- 마스터 후보와 데이터 노드 완전 분리 가능
- 일반적으로 분리가 서비스 안정성 면에서 유리

#### 서버 자원이 굉장히 많이 필요한 경우 (물리 서버 200대 이상)
- 먼저 용도나 중요도별로 클러스터를 더 잘게 쪼갤 수 있는지 검토
- 클러스터당 마스터 노드는 한 대만 선출된다는 한계 인식
- 클러스터 간 검색(cross-cluster search), 로드 밸런싱, 데이터 샤딩 전략 고려

### 조정 전용 노드 사용 시점

**도입 이유:**
- 집계 작업의 결과 취합은 큰 메모리 부하를 줌
- 키바나가 무리한 집계 요청 날리는 상황을 격리하기 위해
- 조정 전용 노드를 내리면 최악의 장애 확산을 막을 수 있음

**읽기/쓰기 분리 전략:**
- 읽기 전용 조정 노드 + 쓰기 전용 조정 노드를 분리
- 샤드 복구 중 쓰기 조정 노드를 내리면 복구 속도 향상 (주/복제 샤드 차이 방지)

**설정:**
```yaml
node.roles: []  # 빈 배열 = 조정 전용 노드
```

**유의사항:**
- 조정 전용 노드가 너무 많아지면 마스터 노드의 관리 부담 증가
- 데이터를 들고 있지 않으므로 부담 없이 kill 가능

### 한 서버에 여러 프로세스 띄우기

**조건:** 128GB 이상 메모리 서버에서 약 32GB 힙 프로세스 여러 개 운영 시 고려

**필수 설정:**
```yaml
cluster.routing.allocation.same_shard.host: true  # 기본값 false
```
- 같은 서버에 주 샤드와 복제본 샤드가 몰리지 않도록

**주의사항:**
- 마스터 후보 역할 프로세스는 다중화 금지 (클러스터 안정성 저하)
- `cluster.name` 동일, `node.name` 다르게, 포트/경로 분리 필요
- CPU, 파일 디스크립터, mmap, 네트워크 자원 공유 리스크 고려

---

## 5. 부트스트랩 체크 (Bootstrap Checks)

### 정의
엘라스틱서치 노드가 최초 실행 시 동작 환경을 검사하는 과정. 문제 발견 시 강제 종료.

### 개발 모드 vs 운영 모드
- **개발 모드**: IP 주소가 루프백(localhost)으로 설정된 경우. 부트스트랩 체크 무시.
- **운영 모드**: IP 주소가 실제 주소로 설정된 경우. 부트스트랩 체크 필수.
- 강제 적용: JVM 옵션 `-Des.enforce.bootstrap.checks=true`

### 주요 체크 단계
1. **힙 크기 체크**: Xms == Xmx 인지 확인 (Memory Lock과도 연관)
2. **파일 디스크립터 체크**: 루씬의 역색인 파일 처리를 위한 충분한 FD 수 확인
3. **메모리 락 체크**: 힙 메모리 Memory Lock 여부 (GC 중 swap-out 방지)
4. **최대 스레드 수 체크**: 최소 4096개 이상 스레드 생성 가능 여부
5. **최대 가상 메모리 크기 체크**: mmap 사용을 위해 unlimited 필요
6. **최대 파일 크기 체크**: 세그먼트/Translog 파일 크기 무제한 필요
7. **mmap 카운트 체크**: 최대 262,144개 메모리맵 영역 필요 (`vm.max_map_count`)
8. **Client JVM 체크**: Server JVM으로 실행 여부
9. **Serial GC 사용 여부 체크**: 대용량 힙에서 Serial GC는 금지
10. **시스템 콜 필터 체크**: seccomp 기반 샌드박스 설치 여부
11. **OnError/OnOutOfMemoryError 체크**: 시스템 콜 필터 사용 시 해당 옵션 금지
12. **Early-access 체크**: 테스트 버전 JVM 사용 금지
13. **G1GC 체크**: 자바 8에서 G1GC 사용 시 JDK 8u40 이후 버전 확인
14. **All Permission 체크**: `java.security.AllPermission` 적용 금지

---

## 6. 보안 기능

### 보안 적용 단계

#### 1단계: 보안 기능 미적용
```yaml
xpack.security.enabled: false
```
- 완전히 통제된 인트라넷 + 법적 이슈 없는 데이터 + 접근 제어 가능 시에만 허용

#### 2단계: TLS 부트스트랩 체크
- 운영 모드에서 노드 간 transport 통신에 TLS 미적용 시 기동 거부
- `discovery.type: single-node` 또는 `xpack.security.enabled: false`이면 체크 건너뜀

#### 3단계: 자동 보안 설정 (8 버전 이상)
1. `xpack.security.enabled` 설정 없이 단일 노드로 최초 기동
2. 전용 CA 자동 생성, CA로 서명된 인증서 자동 발급
3. transport/HTTP 레이어에 TLS 적용
4. `elastic` 계정 초기 비밀번호 출력
5. enrollment 토큰으로 추가 노드 합류 및 키바나 연결

**자동 생성 파일:**
```
config/certs/http.p12          # HTTP 레이어 TLS
config/certs/http_ca.crt       # HTTP CA 인증서
config/certs/transport.p12     # transport 레이어 TLS
```

#### 수동 보안 설정 (7 버전 또는 특수 상황)

**노드 간 transport TLS 수동 적용:**
```bash
# CA 생성
bin/elasticsearch-certutil ca

# 인증서 생성
bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12
```

```yaml
# elasticsearch.yml
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.client_authentication: required
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12
```

**verification_mode 설명:**
- `full`: 인증서 + 호스트 이름/IP 검증
- `certificate`: 인증서만 검증 (호스트 이름 미검증)
- `none`: 검증 없음 (디버깅 전용, 운영 환경 사용 금지)

**기본 인증 설정:**
```bash
# 8 버전 이상
bin/elasticsearch-reset-password --interactive -u elastic
bin/elasticsearch-reset-password --interactive -u kibana_system

# 7 버전 이하
bin/elasticsearch-setup-passwords interactive
```

**REST API에 TLS 적용:**
```yaml
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: http.p12
```

### TLS 검증 모드 비교

| 모드 | 인증서 검증 | 호스트 이름 검증 | 사용 상황 |
|------|------------|----------------|---------|
| full | O | O | 공인 CA 인증서 사용 시 |
| certificate | O | X | 자체 서명 인증서, 같은 인증서 모든 노드 공유 시 |
| none | X | X | 디버깅 전용 (운영 금지) |

### 역할 기반 접근 제어 (RBAC)
- 계정 + 역할 기반으로 인증, 권한 부여, 분리 기능 제공
- 역할에는 읽기, 쓰기, 모니터링, 스냅샷 등 세부 권한이 나뉨
- 키바나의 **스페이스(space)** 개념: 대시보드, 비주얼라이즈 등을 스페이스마다 독립 운영
- 키바나에서 Users/Roles UI로 계정 및 역할 관리 가능

### 주요 내부 계정
| 계정 | 역할 |
|------|------|
| `elastic` | 최고 관리자 권한 |
| `kibana_system` | 키바나가 엘라스틱서치와 통신할 때 사용 |
| `apm_system` | APM 시스템 |
| `logstash_system` | Logstash 시스템 |
| `remote_monitoring_user` | 메트릭비트 모니터링 데이터 수집 |

---

## 7. 주요 설정 파일 구조

### elasticsearch.yml 클러스터 구성 예시
```yaml
node.roles: [ master, data ]   # 노드 역할
cluster.name: my-es-cluster    # 클러스터 이름 (모든 노드 동일해야 함)
node.name: my-es-node01        # 노드 이름 (고유해야 함)

http.port: 9200-9300
transport.port: 9300-9400

path:
  logs: /path/to/elasticsearch/logs
  data:
    - /path/to/elasticsearch/data1
    - /path/to/elasticsearch/data2

network.host: 10.0.0.1
network.bind_host: 0.0.0.0     # 바인딩 주소 (L4 등이 있을 때 별도 지정)

discovery.seed_hosts: ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
cluster.initial_master_nodes: ["my-es-node01", "my-es-node02", "my-es-node03"]

xpack.security.enabled: false  # 보안 설정 완료 전까지 임시
```

### 포트 의미
- `http.port (9200)`: HTTP 통신 (REST API, 클라이언트 접근)
- `transport.port (9300)`: 노드 간 내부 통신

---

## 관련 개념 연결

- **샤드**: 데이터 노드에 분산 저장되는 단위 → [01-핵심-아키텍처/concepts.md](../01-핵심-아키텍처/concepts.md)
- **레플리카**: 데이터 노드 장애 시 복구 기반 → [01-핵심-아키텍처/concepts.md](../01-핵심-아키텍처/concepts.md)
- **데이터 티어**: hot-warm-cold-frozen 구조 → Ch6에서 상세 학습
