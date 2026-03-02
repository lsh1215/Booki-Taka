# 엘라스틱서치 빠른 참조표

> 실무에서 손이 자주 가는 API, 설정값, 패턴 모음.
> 개념 배경은 각 토픽 concepts.md 참조.

---

## 핵심 용어

| 용어 | 정의 | 관련 토픽 |
|------|------|---------|
| Index | 도큐먼트의 논리적 컨테이너. RDBMS의 테이블에 대응 | [01](./01-핵심-아키텍처/concepts.md) |
| Shard | 인덱스를 분산 저장하는 루씬 인스턴스 단위. Primary / Replica로 구분 | [01](./01-핵심-아키텍처/concepts.md) |
| Segment | 루씬이 디스크에 쓰는 불변(immutable) 파일 단위. 병합(merge)으로 줄어듦 | [01](./01-핵심-아키텍처/concepts.md), [13](./13-내부-동작/concepts.md) |
| Translog | 세그먼트 flush 전 데이터 유실 방지용 WAL(Write-Ahead Log) | [01](./01-핵심-아키텍처/concepts.md) |
| Mapping | 필드 이름과 데이터 타입의 스키마 정의 | [02](./02-인덱스-설계/concepts.md) |
| Analyzer | 텍스트를 토큰으로 분해하는 파이프라인 (캐릭터 필터 → 토크나이저 → 토큰 필터) | [03](./03-분석기/concepts.md) |
| Alias | 하나 이상의 인덱스를 가리키는 가상 이름. 무중단 전환에 사용 | [09](./09-운영-전략/concepts.md) |
| ILM | Index Lifecycle Management. 핫→웜→콜드→삭제 자동 관리 | [09](./09-운영-전략/concepts.md) |
| Rollover | alias 기반으로 조건(크기/문서 수/기간) 충족 시 새 인덱스로 전환 | [09](./09-운영-전략/concepts.md) |
| Circuit Breaker | 메모리 과부하를 JVM OOM 전에 차단하는 안전장치 | [11](./11-장애-대응/concepts.md) |
| doc_values | 집계·정렬용으로 열 지향(column-oriented) 구조로 디스크에 저장. 기본 활성화 | [02](./02-인덱스-설계/concepts.md) |
| fielddata | text 필드의 집계를 위해 힙에 올리는 구조. 메모리 소모 큼. 기본 비활성화 | [02](./02-인덱스-설계/concepts.md) |
| BM25 | ES 기본 유사도 알고리즘. TF-IDF 개선형 (TF 포화, 필드 길이 정규화) | [05](./05-검색-쿼리/concepts.md), [13](./13-내부-동작/concepts.md) |
| Refresh | 메모리 버퍼 → 파일 시스템 캐시 이동. 검색 가능 상태로 전환. 기본 1초 | [01](./01-핵심-아키텍처/concepts.md) |
| Flush | 파일 시스템 캐시 → 디스크 기록 + translog 초기화. fsync 발생 | [01](./01-핵심-아키텍처/concepts.md) |

---

## 클러스터 상태 확인

```bash
# 클러스터 전체 Health
GET _cluster/health
GET _cluster/health?level=shards

# 클러스터 상세 설정 조회
GET _cluster/settings?include_defaults=true

# 동적 설정 변경
PUT _cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.enable": "all"
  }
}
```

---

## Cat API 주요 명령어

```bash
# 노드 목록 (역할, 힙 사용량 포함)
GET _cat/nodes?v&h=name,node.role,heap.percent,heap.current,heap.max,cpu,load_1m

# 인덱스 목록 (크기, 문서 수)
GET _cat/indices?v&s=store.size:desc

# 샤드 상태 (UNASSIGNED 확인)
GET _cat/shards?v&h=index,shard,prirep,state,unassigned.reason

# 디스크 사용량
GET _cat/allocation?v

# 세그먼트 현황
GET _cat/segments?v

# 보류 중인 태스크
GET _cat/pending_tasks?v

# 스레드 풀 상태
GET _cat/thread_pool?v&h=name,active,queue,rejected,completed
```

---

## 인덱스 관련

```bash
# 인덱스 생성
PUT my-index
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "1s"
  },
  "mappings": {
    "properties": {
      "title": { "type": "text", "analyzer": "nori" },
      "created_at": { "type": "date" },
      "status": { "type": "keyword" }
    }
  }
}

# 인덱스 삭제
DELETE my-index

# 인덱스 설정 변경 (동적 변경 가능한 항목만)
PUT my-index/_settings
{
  "number_of_replicas": 2,
  "refresh_interval": "30s"
}

# Alias 생성 및 전환 (무중단 인덱스 교체)
POST _aliases
{
  "actions": [
    { "remove": { "index": "my-index-v1", "alias": "my-index" } },
    { "add":    { "index": "my-index-v2", "alias": "my-index", "is_write_index": true } }
  ]
}

# Rollover (alias 기반 자동 전환)
POST my-alias/_rollover
{
  "conditions": {
    "max_age":  "7d",
    "max_docs": 1000000,
    "max_size": "50gb"
  }
}

# Reindex (인덱스 간 데이터 복사)
POST _reindex
{
  "source": { "index": "my-index-v1" },
  "dest":   { "index": "my-index-v2" }
}

# Force merge (세그먼트 병합 — 더 이상 쓰지 않는 인덱스에만)
POST my-index/_forcemerge?max_num_segments=1
```

---

## 검색 기본 패턴

```bash
# match 검색 (분석기 적용)
GET my-index/_search
{
  "query": {
    "match": {
      "title": "엘라스틱서치 검색"
    }
  }
}

# term 검색 (분석기 미적용 — keyword 필드용)
GET my-index/_search
{
  "query": {
    "term": { "status": "active" }
  }
}

# bool 복합 쿼리
GET my-index/_search
{
  "query": {
    "bool": {
      "must":   [{ "match": { "title": "kafka" } }],
      "filter": [{ "range": { "created_at": { "gte": "now-7d" } } }],
      "must_not": [{ "term": { "status": "deleted" } }]
    }
  }
}

# 페이지네이션 — from/size (10,000건 이하)
GET my-index/_search
{
  "from": 0, "size": 10,
  "query": { "match_all": {} }
}

# 페이지네이션 — search_after (대용량)
GET my-index/_search
{
  "size": 100,
  "sort": [{ "created_at": "asc" }, { "_id": "asc" }],
  "search_after": ["2024-01-01T00:00:00Z", "doc-id-xyz"]
}

# scroll (배치 처리용 — 7.10 이후 search_after+PIT 권장)
POST my-index/_search?scroll=1m
{
  "size": 1000,
  "query": { "match_all": {} }
}
POST _search/scroll
{
  "scroll": "1m",
  "scroll_id": "DXF1ZXJ5..."
}
```

---

## 집계 기본 패턴

```bash
# 메트릭 집계 (평균, 최대, 최소, 합계)
GET my-index/_search
{
  "size": 0,
  "aggs": {
    "avg_price":  { "avg":   { "field": "price" } },
    "max_price":  { "max":   { "field": "price" } },
    "total_sale": { "sum":   { "field": "amount" } },
    "unique_users": { "cardinality": { "field": "user_id" } }
  }
}

# 버킷 집계 + 서브 집계
GET my-index/_search
{
  "size": 0,
  "aggs": {
    "by_category": {
      "terms": { "field": "category", "size": 10 },
      "aggs": {
        "avg_price": { "avg": { "field": "price" } }
      }
    }
  }
}

# date_histogram
GET my-index/_search
{
  "size": 0,
  "aggs": {
    "sales_over_time": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "1d"
      }
    }
  }
}
```

---

## 샤드 관련 설정값

| 항목 | 권장값 / 기준 | 설명 |
|------|-------------|------|
| 샤드당 크기 | 10GB ~ 50GB | 너무 작으면 오버헤드, 너무 크면 복구 느림 |
| 힙당 최대 샤드 수 | 20개 이하 | `_cat/nodes`로 확인. 힙 1GB당 20개 기준 |
| `cluster.max_shards_per_node` | 1000 (기본) | 7.x 이후 기본값. 필요 시 늘릴 수 있으나 남용 금지 |
| Primary Shard 수 | 인덱스 생성 시 고정 | 이후 변경 불가. Reindex 또는 Split/Shrink로 조정 |
| Replica Shard 수 | 동적 변경 가능 | `PUT index/_settings { "number_of_replicas": N }` |

---

## JVM 및 OS 설정

| 항목 | 권장값 | 이유 |
|------|-------|------|
| JVM Heap 크기 | 전체 RAM의 50%, 최대 32GB | 32GB 초과 시 Compressed OOP 비활성화되어 역효과 |
| `-Xms` = `-Xmx` | 동일하게 설정 | 런타임 힙 확장으로 인한 STW 방지 |
| `vm.max_map_count` | 262144 | `sysctl -w vm.max_map_count=262144` |
| `ulimit -n` (열린 파일 수) | 65536 이상 | 세그먼트 파일 수 증가 대응 |
| swap | 비활성화 | `swapoff -a` + `bootstrap.memory_lock: true` |
| GC | G1GC (기본) | ZGC는 대용량 힙에서 유리하나 ES 권장 기본은 G1GC |

---

## 장애 대응 주요 API

```bash
# UNASSIGNED 샤드 확인
GET _cat/shards?v&h=index,shard,prirep,state,unassigned.reason&s=state

# 샤드 강제 재할당 (reroute)
POST _cluster/reroute
{
  "commands": [{
    "allocate_empty_primary": {
      "index": "my-index",
      "shard": 0,
      "node": "node-1",
      "accept_data_loss": true
    }
  }]
}

# 디스크 읽기전용 해제 (disk flood stage 해제)
PUT my-index/_settings
{
  "index.blocks.read_only_allow_delete": null
}

# 클러스터 전체 읽기전용 해제
PUT _cluster/settings
{
  "persistent": {
    "cluster.blocks.read_only_allow_delete": null
  }
}

# 샤드 할당 임시 중지 / 재개
PUT _cluster/settings
{
  "transient": {
    "cluster.routing.allocation.enable": "none"
  }
}
PUT _cluster/settings
{
  "transient": {
    "cluster.routing.allocation.enable": "all"
  }
}

# Circuit Breaker 상태 확인
GET _nodes/stats/breaker

# 노드 Hot Threads 확인
GET _nodes/hot_threads

# 느린 쿼리 로그 임시 활성화
PUT my-index/_settings
{
  "index.search.slowlog.threshold.query.warn": "1s",
  "index.search.slowlog.threshold.query.info": "500ms"
}

# Pending Tasks 확인
GET _cluster/pending_tasks

# Task 목록 확인 (장시간 실행 중인 작업)
GET _tasks?detailed=true&actions=*reindex*
```

---

## 스냅샷 (백업/복구)

```bash
# 저장소 등록
PUT _snapshot/my-repo
{
  "type": "fs",
  "settings": { "location": "/mnt/backup/elasticsearch" }
}

# 스냅샷 생성
PUT _snapshot/my-repo/snapshot-2024-01-01
{
  "indices": "my-index-*",
  "ignore_unavailable": true
}

# 스냅샷 목록 확인
GET _snapshot/my-repo/_all

# 특정 인덱스 복구
POST _snapshot/my-repo/snapshot-2024-01-01/_restore
{
  "indices": "my-index",
  "rename_pattern": "(.+)",
  "rename_replacement": "restored-$1"
}
```
