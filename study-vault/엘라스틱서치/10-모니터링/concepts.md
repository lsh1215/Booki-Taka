# 엘라스틱서치 모니터링 - 핵심 개념

> 출처: 엘라스틱서치 실무가이드 Ch11 / 엘라스틱서치바이블 Ch7
> 태그: #monitoring #cluster-health #cat-api #jvm #gc #thread-pool #metricbeat

---

## 목차
1. [클러스터 Health 체크](#1-클러스터-health-체크)
2. [물리적 클러스터 상태 조회](#2-물리적-클러스터-상태-조회)
3. [클러스터 레벨 실시간 모니터링](#3-클러스터-레벨-실시간-모니터링)
4. [노드 레벨 실시간 모니터링](#4-노드-레벨-실시간-모니터링)
5. [인덱스 레벨 실시간 모니터링](#5-인덱스-레벨-실시간-모니터링)
6. [Cat API](#6-cat-api)
7. [주요 모니터링 지표](#7-주요-모니터링-지표)
8. [메트릭비트를 이용한 지표 수집](#8-메트릭비트를-이용한-지표-수집)

---

## 1. 클러스터 Health 체크

### 정의
`_cluster/health` API를 이용해 클러스터의 현재 상태를 실시간으로 확인하는 방법. 클러스터 상태를 간단한 형태로 요약해서 제공한다.

### 왜 필요한가
클러스터에 `_cluster/health`를 일정 주기로 요청하면 이상 유무를 즉시 알 수 있다. 간단히 사용할 수 있으면서도 빠른 장애 대응이 가능하기 때문에 대부분의 시스템에서 필수적으로 사용한다.

### 동작 원리

#### status 필드의 세 가지 상태

| 상태 | 의미 | 서비스 영향 |
|------|------|------------|
| **green** | 모든 샤드(프라이머리 + 레플리카)가 정상 할당 | 없음 |
| **yellow** | 프라이머리 샤드는 정상이나 일부 레플리카 샤드가 미할당 | 서비스 가능하나 장애 즉시 복구 불가 |
| **red** | 일부 프라이머리 샤드가 미할당 | 일부 데이터 검색/색인 불가 |

#### 클러스터 레벨 Health 체크
```
GET /_cluster/health

{
  "cluster_name": "javacafe-es",
  "status": "green",
  "timed_out": false,
  "number_of_nodes": 4,
  "number_of_data_nodes": 3,
  "active_primary_shards": 55,
  "active_shards": 110,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 0,
  "delayed_unassigned_shards": 0,
  "number_of_pending_tasks": 0,
  "number_of_in_flight_fetch": 0,
  "active_shards_percent_as_number": 100
}
```

주요 속성:
- `active_primary_shards`: 동작 중인 프라이머리 샤드 수
- `active_shards`: 동작 중인 전체 샤드 수
- `relocating_shards`: 복구를 위해 Relocation 중인 샤드 수 (평상시 0)
- `initializing_shards`: 초기화 중인 샤드 수 (오래 지속되면 문제)
- `unassigned_shards`: 할당되지 않은 샤드 수 (평상시 0)

#### 인덱스 레벨 Health 체크
```
GET /_cluster/health?level=indices
```
모든 인덱스의 상태 정보를 포함해서 결과를 리턴한다. 문제가 발생했을 때 어떤 인덱스에서 발생했는지 찾기 쉽다.

#### 샤드 레벨 Health 체크
```
GET /_cluster/health?level=shards
```
인덱스 내부의 개별 샤드 단위까지 상태 정보를 제공한다.

#### 특정 인덱스 Health 체크
```
GET /_cluster/health/movie
GET /_cluster/health/movie?level=indices
GET /_cluster/health/movie?level=shards
```
멀티테넌시 구조에서 특정 인덱스만을 대상으로 Health 체크할 때 유용하다.

### 설계 트레이드오프
- Health 체크는 요약 정보만 제공한다. 상세한 원인 분석은 stats API나 Cat API를 함께 사용해야 한다.
- yellow는 서비스에 지장이 없으나 장애 복구 능력이 떨어진 상태다. green이 될 때까지 모니터링해야 한다.

### 관련 개념
- [클러스터 구성](../08-클러스터-구성/concepts.md) - 샤드 할당, 레플리카 개념
- `_cluster/state` - 더 상세한 물리 상태 조회

---

## 2. 물리적 클러스터 상태 조회

### 정의
`_cluster/state`와 `_nodes` API를 이용해 클러스터와 노드의 환경설정 및 물리적 상태를 확인하는 방법.

### 왜 필요한가
클러스터가 실제로 어떤 설정을 가지고 동작하는지, 각 노드가 어떻게 구성되어 있는지를 런타임에 확인할 수 있다. elasticsearch.yml 수정 후 반영 여부 확인, JVM 설정 확인, 플러그인 설치 여부 확인 등에 활용된다.

### 동작 원리

#### 클러스터 물리 상태 조회 (`_cluster/state`)
```
GET /_cluster/state
```
클러스터 구성의 기반이 되는 metadata 정보, routing table 정보, Restore/Snapshot 정보 등을 한눈에 확인할 수 있다.

#### 노드 물리 상태 조회 (`_nodes`)
```
GET /_nodes                      # 전체 노드
GET /_nodes/10.0.0.1,10.0.0.2   # 특정 IP로 조회
GET /_nodes/{node_id}            # 특정 노드 ID
GET /_nodes/_local               # API 요청을 받은 노드만
```

노드 정보에서 확인 가능한 항목:
- **Settings**: elasticsearch.yml에 설정된 기본 설정사항 (설정 변경 반영 여부 확인용)
- **OS**: 노드가 실행된 운영체제 정보 (CPU 수, OS 종류)
- **Process**: Memory Lock 수행 여부, PID 정보
- **JVM**: 힙 설정, GC 수집기, JVM 인수들
- **Thread Pool**: 스레드풀 종류별 min/max/queue_size 설정
- **Transport/HTTP**: 바인딩된 포트 정보
- **Plugins/Modules**: 설치된 플러그인 목록

### 설계 트레이드오프
- `_cluster/state`는 매우 큰 응답을 반환할 수 있어 실시간 모니터링보다는 진단 목적으로 사용한다.
- `filter_path` 파라미터로 필요한 정보만 필터링할 수 있다.

---

## 3. 클러스터 레벨 실시간 모니터링

### 정의
`_cluster/stats` API를 이용해 클러스터 전체에서 통계를 집계하는 방법. 노드의 역할, OS 정보, 메모리 사용량, CPU 사용량 등 다양한 지표를 제공한다.

### 왜 필요한가
클러스터 전반의 상태를 한눈에 파악할 수 있다. 클러스터에 어떤 노드가 몇 개 있는지, 전체 메모리/디스크 사용량은 얼마인지, 색인된 문서 수는 얼마인지 등을 빠르게 확인할 수 있다.

### 동작 원리
```
GET /_cluster/stats
```

응답 구조는 크게 `indices`와 `nodes` 두 섹션으로 구성된다.

#### indices 섹션 주요 지표

| 필드 | 설명 |
|------|------|
| `count` | 클러스터에 존재하는 인덱스 수 |
| `shards.total` / `shards.primaries` | 전체/프라이머리 샤드 수 |
| `docs.count` | 클러스터에 색인된 전체 문서 수 |
| `store.size_in_bytes` | 색인된 문서가 차지하는 디스크 크기 |
| `fielddata.memory_size_in_bytes` | fielddata에 사용 중인 메모리 크기 |
| `query_cache` | 검색 결과 캐시 히트/미스 횟수 |
| `segments.count` | 루씬 세그먼트 수 및 메모리 사용량 |

#### nodes 섹션 주요 지표

| 필드 | 설명 |
|------|------|
| `count.total` / `count.data` / `count.master` | 전체/데이터/마스터 노드 수 |
| `os.mem.used_percent` | 전체 노드의 메모리 사용률 |
| `process.cpu.percent` | CPU 사용률 |
| `jvm.mem.heap_used_in_bytes` | JVM 힙 사용량 |
| `fs.total_in_bytes` / `fs.available_in_bytes` | 전체/가용 디스크 크기 |

### 설계 트레이드오프
- 클러스터 통계는 집계된 값으로 개별 노드의 정확한 상태를 파악하기 어렵다. 문제 발생 시에는 노드 레벨 통계를 함께 확인해야 한다.

---

## 4. 노드 레벨 실시간 모니터링

### 정의
`_nodes/stats` API를 이용해 개별 노드의 상세 통계 정보를 확인하는 방법. 클러스터 통계보다 훨씬 더 많은 정보가 노드별로 제공된다.

### 왜 필요한가
문제가 발생한 경우 개별 노드를 비교해 실제로 문제가 발생한 노드를 찾아야 한다. 클러스터 레벨의 통계로는 특정 노드의 문제를 찾기 어렵다.

### 동작 원리
```
GET /_nodes/stats
```

노드 통계에서 확인 가능한 섹션:

#### indices (인덱스 통계)
해당 노드가 가진 인덱스의 통계 정보.

| 항목 | 설명 |
|------|------|
| `docs.count` | 노드가 가진 문서 수 |
| `store.size_in_bytes` | 디스크 사용량 |
| `indexing.index_total` | 색인된 문서 수 (누적) |
| `indexing.index_time_in_millis` | 색인에 소요된 시간 (누적) |
| `search.query_total` | 검색 쿼리 수 (누적) |
| `search.query_time_in_millis` | 검색에 소요된 시간 (누적) |
| `merges` | 세그먼트 병합 통계 |
| `refresh` | Refresh 작업 통계 |
| `flush` | Flush 작업 통계 |
| `fielddata.memory_size_in_bytes` | fielddata 메모리 |
| `segments.count` | 세그먼트 수 및 메모리 |
| `translog.size_in_bytes` | Translog 파일 크기 |

#### jvm (JVM 통계) - 핵심 모니터링 대상
```json
"jvm": {
  "mem": {
    "heap_used_in_bytes": 1524976032,
    "heap_used_percent": 71,
    "heap_committed_in_bytes": 2136051072,
    "heap_max_in_bytes": 2130051072,
    "pools": {
      "young": { "used_in_bytes": 96443840, "max_in_bytes": 139591680 },
      "survivor": { "used_in_bytes": 181632 },
      "old": { "used_in_bytes": 1428350560, "max_in_bytes": 1973026816 }
    }
  },
  "gc": {
    "collectors": {
      "young": { "collection_count": 4698, "collection_time_in_millis": 114725 },
      "old": { "collection_count": 2, "collection_time_in_millis": 180 }
    }
  }
}
```

JVM 주요 지표:
- `heap_used_percent`: 힙 사용률 (75% 이상이면 주의)
- `gc.collectors.young.collection_count`: Young GC 발생 횟수
- `gc.collectors.young.collection_time_in_millis`: Young GC 소요 시간
- `gc.collectors.old.collection_count`: Old GC(Full GC) 발생 횟수 - 적을수록 좋다
- `gc.collectors.old.collection_time_in_millis`: Old GC 소요 시간 - 길면 STW 발생

#### thread_pool (스레드풀 통계) - 핵심 모니터링 대상
```json
"thread_pool": {
  "bulk": {
    "threads": 2,
    "queue": 0,
    "active": 0,
    "rejected": 0,
    "largest": 2,
    "completed": 9457
  },
  "search": { ... },
  "index": { ... }
}
```

스레드풀 주요 필드:
| 필드 | 설명 | 주의 기준 |
|------|------|-----------|
| `threads` | 현재 스레드 수 | |
| `queue` | 대기 중인 요청 수 | 증가 추세면 과부하 신호 |
| `active` | 현재 처리 중인 요청 수 | |
| `rejected` | 거부된 요청 수 | 0이 아니면 심각한 문제 |

주요 스레드풀 종류:
- `bulk`: bulk 요청 처리
- `search`: 검색/카운트/추천 처리
- `index`: 색인 처리
- `get`: GET 요청 처리
- `refresh`: Refresh 요청 처리
- `flush`: Flush 요청 처리
- `management`: Cat API/Stat API 등 관리용 요청 처리

#### os (운영체제 통계)
- `cpu.percent`: CPU 사용률
- `mem.used_percent`: 메모리 사용률
- `swap.used_in_bytes`: 스왑 사용량 (0이 이상적)
- `cgroup`: Linux cgroup 리소스 제한 정보

#### fs (파일시스템 통계)
- `total.total_in_bytes` / `total.available_in_bytes`: 디스크 전체/가용 크기
- `io_stats`: 읽기/쓰기 작업량

#### process (프로세스 정보)
- `open_file_descriptors`: 현재 열린 파일 디스크립터 수
- `max_file_descriptors`: 최대 허용 파일 디스크립터 수 (권장값 65536 이상)

#### breakers (서킷 브레이커)
서킷 브레이커 상태. `tripped` 값이 증가하면 OOM 위험이 있음을 의미한다.

| 브레이커 | 기본 제한 | 설명 |
|----------|-----------|------|
| `parent` | 힙의 70% (실제 메모리 체크 시 95%) | 전체 부모 서킷 브레이커 |
| `request` | 힙의 60% | 요청당 집계 연산 제한 |
| `fielddata` | 힙의 60% | fielddata 캐시 제한 |
| `in_flight_requests` | 힙의 100% | transport/HTTP 수신 데이터 제한 |
| `accounting` | 힙의 100% | 루씬 세그먼트 등 해제 안 되는 메모리 |

### 설계 트레이드오프
- 노드 레벨 통계는 물리적 노드 기준으로 집계된다. 논리적 인덱스 단위 분석은 인덱스 통계를 별도로 확인해야 한다.

---

## 5. 인덱스 레벨 실시간 모니터링

### 정의
`/{index}/_stats` API를 이용해 특정 인덱스의 통계 정보를 확인하는 방법. 인덱스는 여러 노드에 걸쳐 존재하는 논리적 개념이므로, 노드 통계와 다른 관점의 정보를 제공한다.

### 왜 필요한가
노드 통계는 물리적 장애 대응에 유용하고, 인덱스 통계는 특정 인덱스의 색인/검색 성능을 분석하는 데 유용하다. 두 가지를 조합하면 클러스터를 물리적 및 논리적 측면에서 복합적으로 파악할 수 있다.

### 동작 원리
```
GET /_stats           # 전체 인덱스
GET /movie/_stats     # 특정 인덱스
```

응답 구조:
- `_all`: 모든 인덱스의 통계값 합산
- `indices.{인덱스명}.primaries`: 프라이머리 샤드 기준 통계
- `indices.{인덱스명}.total`: 프라이머리 + 레플리카 통계 합산

주요 지표는 노드 통계의 `indices` 섹션과 동일하나, 데이터가 인덱스 레벨로 집계된다.

---

## 6. Cat API

### 정의
리눅스 콘솔에서 클러스터를 모니터링하기 위한 특수 API. 리눅스의 `cat` 명령어에 영감을 받아 개발되었으며, JSON이 아닌 콘솔 친화적인 텍스트 형태로 결과를 출력한다.

### 왜 필요한가
`_cluster` API는 JSON으로 결과를 제공하기 때문에 콘솔에서 직접 읽기 불편하다. 리눅스 환경에서 운영 중에 빠르게 상태를 확인할 때 Cat API가 훨씬 편리하다.

### 동작 원리

#### Cat API 특징
- `_cluster` API와 대부분 동일한 정보를 제공
- 출력이 컬럼 형태로 사람이 읽기 쉬운 포맷
- 다양한 파라미터로 출력 커스터마이징 가능
  - `?v`: 헤더(컬럼명) 포함
  - `?help`: 사용 가능한 컬럼 목록
  - `?h=col1,col2`: 특정 컬럼만 출력
  - `?s=col`: 특정 컬럼 기준 정렬

#### 주요 Cat API 목록

| API | 설명 |
|-----|------|
| `GET /_cat/health` | 클러스터 Health 상태 확인 |
| `GET /_cat/nodes` | 노드 목록 및 상태 |
| `GET /_cat/indices` | 인덱스 목록 및 상태 |
| `GET /_cat/shards` | 샤드 목록 및 할당 상태 |
| `GET /_cat/allocation` | 노드별 샤드 할당 현황 및 디스크 사용량 |
| `GET /_cat/master` | 마스터 노드 정보 |
| `GET /_cat/pending_tasks` | 대기 중인 클러스터 태스크 |
| `GET /_cat/recovery` | 복구 중인 샤드 상태 |
| `GET /_cat/thread_pool` | 스레드풀 통계 |
| `GET /_cat/count` | 문서 수 |
| `GET /_cat/segments` | 루씬 세그먼트 정보 |

#### 사용 예시
```bash
# 헤더 포함하여 Health 확인
GET /_cat/health?v

# 인덱스 목록 (health, status, docs.count, store.size 컬럼만)
GET /_cat/indices?v&h=health,status,index,docs.count,store.size

# 샤드 상태 확인 (UNASSIGNED 필터링)
GET /_cat/shards?v&h=index,shard,prirep,state,unassigned.reason
```

### 설계 트레이드오프
- Cat API는 사람이 읽기 위한 포맷이므로 프로그램 파싱에는 `_cluster` API의 JSON 포맷이 더 적합하다.
- 실시간 모니터링 스크립트 작성 시 둘을 용도에 맞게 구분해서 사용한다.

### 관련 개념
- [성능 최적화](../12-성능-최적화/concepts.md) - 성능 지표와 연계

---

## 7. 주요 모니터링 지표

### JVM Heap 사용률

**정의**: JVM이 사용 중인 힙 메모리의 비율 (`heap_used_percent`).

**왜 중요한가**: 힙이 가득 차면 GC가 빈번하게 발생하고, 서킷 브레이커가 발동하거나 최악의 경우 OutOfMemoryError로 노드가 다운될 수 있다.

**확인 방법**:
```
GET /_nodes/stats/jvm
```

**판단 기준**:
- 정상: 75% 미만
- 주의: 75~85%
- 위험: 85% 이상 (GC 압박, 서킷 브레이커 발동 위험)

---

### GC 횟수/시간

**정의**: JVM의 가비지 컬렉션 발생 횟수와 소요 시간.

**왜 중요한가**: Old GC(Full GC)가 발생하면 엘라스틱서치 프로세스가 일시적으로 멈추는 STW(Stop The World)가 발생한다. 이 시간이 길어지면 클러스터 전체에 영향을 미친다.

**확인 방법**: `_nodes/stats` 응답의 `jvm.gc.collectors` 섹션.

**판단 기준**:
- Young GC: 빈번하게 발생해도 시간이 짧으면 정상
- Old GC: 횟수 자체가 적어야 한다. 빈번하거나 소요 시간이 길면 힙 증설 또는 쿼리 최적화 검토 필요

---

### 인덱싱 속도 / 검색 속도

**정의**: 노드 또는 인덱스 단위로 측정되는 색인/검색 처리량과 지연 시간.

**확인 방법**: `_nodes/stats` 또는 `/{index}/_stats` 응답의 `indices.indexing`과 `indices.search` 섹션.

주요 지표:
- `indexing.index_total`: 총 색인 문서 수 (누적)
- `indexing.index_time_in_millis`: 색인 소요 총 시간 → 평균 색인 시간 = `index_time_in_millis / index_total`
- `search.query_total`: 총 쿼리 수 (누적)
- `search.query_time_in_millis`: 쿼리 소요 총 시간 → 평균 검색 지연 = `query_time_in_millis / query_total`

---

### 스레드풀 큐 / 거절 수

**정의**: 스레드풀의 대기열(queue)에 쌓인 요청 수와 처리를 거부한 요청 수.

**왜 중요한가**:
- `queue`가 증가하면 처리 능력보다 요청이 더 많이 들어오고 있다는 신호
- `rejected`가 0이 아니면 요청이 유실되고 있는 것이므로 즉시 대응 필요

**확인 방법**:
```
GET /_nodes/stats/thread_pool
GET /_cat/thread_pool?v
```

**대응 방법**: rejected가 발생하면 스레드풀 크기 조정보다는 색인/검색 요청 속도를 줄이거나 노드를 추가하는 것이 근본 해결책이다.

---

### 디스크 사용량

**정의**: 데이터 노드의 디스크 사용률.

**확인 방법**:
- `_nodes/stats/fs` 응답의 `fs.total.available_in_bytes`
- `GET /_cat/allocation?v`

**판단 기준**:
- 기본적으로 디스크 사용률 85%를 넘으면 샤드 할당이 중단된다 (`cluster.routing.allocation.disk.watermark.low`)
- 90%를 넘으면 기존 샤드도 다른 노드로 이동한다 (`high`)
- 95%를 넘으면 색인이 읽기 전용으로 전환된다 (`flood_stage`)

---

## 8. 메트릭비트를 이용한 지표 수집

### 정의
메트릭비트(Metricbeat)는 여러 서비스의 메트릭 데이터를 주기적으로 수집해 엘라스틱서치, 로그스태시, 카프카 등으로 전송하는 서비스다.

### 왜 필요한가
엘라스틱서치 Stats API를 직접 호출하는 것은 일회성이다. 시계열로 지표를 저장하고 시각화하려면 메트릭비트로 데이터를 수집해 별도 모니터링 클러스터에 저장해야 한다. Kibana의 Stack Monitoring 메뉴와 연동하면 편리하게 모니터링 대시보드를 구성할 수 있다.

### 동작 원리

#### 권장 아키텍처
```
[프로덕션 ES 클러스터]
    ↓ (메트릭 수집)
[메트릭비트]
    ↓ (전송)
[모니터링용 ES 클러스터 + Kibana]
    (Stack Monitoring 메뉴에서 확인)
```

프로덕션 클러스터와 모니터링 클러스터를 분리하는 것이 원칙이다. 같은 클러스터에 저장하면 모니터링 대상이 장애날 때 모니터링도 함께 불능이 된다.

#### 메트릭비트 설치 및 설정

설치:
```bash
wget https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-8.4.2-linux-x86_64.tar.gz
tar zxvf metricbeat-8.4.2-linux-x86_64.tar.gz
ln -s metricbeat-8.4.2-linux-x86_64 metricbeat
```

`metricbeat.yml` 기본 설정:
```yaml
output.elasticsearch:
  hosts: ["10.10.0.2:9200"]   # 모니터링용 클러스터 주소
```

보안 적용 시 추가 설정:
```yaml
output.elasticsearch:
  protocol: "https"
  username: "remote_monitoring_user"
  password: "my-monitoring-password-123"
  ssl:
    certificate_authorities: ["/path/to/monitoring_http_ca.crt"]
    verification_mode: "certificate"
```

#### 메트릭 수집 방법 두 가지
1. **클러스터 범위 수집** (권장): 한 개의 메트릭비트 인스턴스가 클러스터 전체 메트릭 수집
2. **노드 범위 수집**: 각 노드에 메트릭비트를 설치해 개별 노드 메트릭 수집

공식 문서는 전자를 권장한다. 마스터 후보가 아닌 노드 또는 별도 서버에 메트릭비트를 설치한다.

#### Kibana 알럿 (Alert)
Kibana의 Stack Monitoring에서 수집된 메트릭을 기반으로 임계값 초과 시 알림을 받을 수 있다. 알럿 기능을 사용하려면 모니터링용 클러스터 노드의 roles에 `remote_cluster_client`를 추가하고 TLS 설정이 완료되어 있어야 한다.

```yaml
# config/elasticsearch.yml (모니터링용 클러스터)
node.roles: ["master", "data", "ingest", "remote_cluster_client"]
```

### 설계 트레이드오프
- 모니터링 클러스터 별도 구축은 비용이 들지만 프로덕션 클러스터 장애 시에도 모니터링 데이터를 보존할 수 있다.
- 알럿 기능은 7.4.1 버전부터 무료로 사용 가능하다.

### 관련 개념
- Beats 계열 (Filebeat, Metricbeat, Packetbeat 등)
- Kibana Stack Monitoring
- [클러스터 구성](../08-클러스터-구성/concepts.md) - 노드 역할 설정
