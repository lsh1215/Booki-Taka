# 13. 내부 동작 — 개념 정리

> 출처: 엘라스틱서치 실무가이드 Ch9 (p.452-486) / 엘라스틱서치바이블 Ch8 (p.367-410)
> 태그: #lucene #query-phase #fetch-phase #primary-replica-sync #checkpoint #cache #bm25-scoring

---

## 관련 개념 링크
- 아키텍처 전체 그림: `../01-핵심-아키텍처/concepts.md`
- 검색 쿼리 활용: `../05-검색-쿼리/concepts.md`
- 클러스터 구성과 운영: `../08-클러스터-구성/concepts.md`

---

## 1. 루씬 인덱스 vs ES 인덱스 vs 샤드 관계

### 정의
- **루씬(Lucene)**: ES가 내부적으로 사용하는 검색 라이브러리. `IndexWriter`(색인)와 `IndexSearcher`(검색) 두 클래스가 핵심이다.
- **루씬 인덱스**: IndexWriter + IndexSearcher를 합친 단일 검색엔진 인스턴스. 내부에 다수의 세그먼트를 보유한다.
- **ES 샤드**: 루씬 인덱스를 확장한 ES의 가장 작은 검색 단위. "장애 복구 기능을 가진 작은 루씬 기반 단일 검색 서버".
- **ES 인덱스**: 물리적으로 분산된 ES 샤드를 논리적으로 하나의 데이터로 바라보는 추상화 레이어.

### 왜 필요한가
루씬 인덱스는 단일 머신 리소스의 한계를 벗어날 수 없다. ES는 샤드라는 단위로 루씬을 확장해 여러 노드에 데이터를 분산 저장함으로써 이 한계를 극복했다.

### 동작 원리 — 계층 구조

```
ES 인덱스  (논리적 단일 뷰)
  └── ES 샤드 1   (물리적 노드 A, 루씬 인덱스)
        └── 세그먼트, 세그먼트, ...
  └── ES 샤드 2   (물리적 노드 B, 루씬 인덱스)
        └── 세그먼트, 세그먼트, ...
```

- **세그먼트**: 루씬 내부 자료구조. 역색인 구조. 한번 생성되면 수정 불가(불변성).
- **루씬 인덱스**: 자기가 가진 세그먼트 내에서만 검색 가능.
- **ES 샤드**: 다수의 샤드가 협력해 존재하는 모든 세그먼트를 논리적으로 통합해 검색.

### 설계 트레이드오프
- 루씬의 불변성 덕분에 동시성 문제가 없고 시스템 캐시를 적극 활용 가능하지만, 수정 시 세그먼트를 다시 만들어야 한다.
- 샤드 개수는 인덱스 생성 시 결정되며 **운영 중 변경 불가** (루씬 세그먼트 불변성 때문). 변경하려면 Reindex API로 재색인해야 한다. 단, 레플리카 샤드 수는 운영 중 변경 가능.

---

## 2. 세그먼트 불변성(Immutability)과 Flush/Commit/Merge

### 정의
세그먼트는 한번 디스크에 저장되면 수정이 불가능하다. 이 특성을 **불변성**이라고 한다.

### 왜 필요한가
불변성은 다음 장점을 제공한다:
- 잠금(Lock) 없이 동시성 문제 회피
- OS 커널 시스템 캐시를 적극 활용 (캐시 수명이 길어짐)
- 높은 캐시 적중률 유지
- CPU/메모리 I/O 리소스 절감

### 동작 원리 — 삭제/수정 처리

수정 불가이므로:
- **수정(Update)**: 기존 데이터를 삭제 표시 → 변경된 데이터를 새 세그먼트로 추가.
- **삭제(Delete)**: 각 문서마다 삭제 여부를 표시하는 **비트 배열**을 내부적으로 관리. 삭제 요청 시 비트만 flip. 실제 물리 삭제는 Merge 시 수행.

### 루씬 Flush / Commit / Merge

| 작업 | 설명 |
|------|------|
| **Flush** | 인메모리 버퍼 → 세그먼트 생성 → `write()` 함수로 OS 커널 시스템 캐시에 기록. 검색 가능해짐. 물리 디스크 보장 없음. |
| **Commit** | `fsync()` 함수 호출로 시스템 캐시 → 물리 디스크 동기화. 비용이 크다. |
| **Merge** | 다수의 세그먼트를 하나로 합침. Commit 동반 필수. 삭제된 데이터의 물리 삭제도 이때 수행. 검색 성능 향상. |

> **주의**: `write()` 함수는 OS 커널 캐시에만 기록하므로, 서버 전원이 갑자기 꺼지면 데이터가 유실될 수 있다. `fsync()`인 Commit이 언젠가는 반드시 필요하다.

### ES에서의 용어 대응

| 루씬 | ES |
|------|-----|
| Flush | **Refresh** |
| Commit | **Flush** |
| Merge | **Optimize API / Force Merge API** |

---

## 3. ES의 Refresh, Flush, Translog

### Refresh (= 루씬 Flush)
- 인메모리 버퍼 → 세그먼트 생성 → 검색 가능.
- 기본 주기: **1초**. 이 때문에 ES가 NRT(Near Real-Time) 검색을 제공.
- 대량 색인 시: `refresh_interval: "-1"` 로 비활성화 → 색인 완료 후 재활성화 권장.

### Flush (= 루씬 Commit + Translog 정리)
- 루씬 Commit(fsync)을 수행하고 Translog에서 완료된 내역을 삭제.
- 기본 주기: **5초** 또는 Translog가 일정 크기 이상일 때.

### Translog — ES만의 고가용성 메커니즘

```
[색인 요청]
  1. Translog에 먼저 기록
  2. 루씬 인메모리 버퍼로 전달
  3. Refresh → 세그먼트 생성 → 검색 가능
  4. Flush → 루씬 Commit → Translog 내역 삭제
```

- **목적**: 루씬 Commit 전 장애 발생 시, Translog로 데이터 복구.
- **장애 시나리오 1**: Commit 도중 장애 → Commit 롤백 → 샤드 재시작 시 Translog 재실행으로 복구.
- **장애 시나리오 2**: Commit 중 새 색인 요청 → 루씬 버퍼 대신 Translog에 임시 저장 → 다음 Commit 시 반영. 검색 시 Translog에서 임시 저장분 먼저 확인.
- **주의**: Translog가 클수록 복구 시간이 길어진다. 적절한 Flush 주기로 Translog 크기를 관리해야 한다.

---

## 4. 쓰기 작업 분산 처리 — Primary-Replica 동기화

### 동작 원리

```
[쓰기 요청 흐름]
클라이언트
  → 조정 노드 (라우팅으로 대상 샤드 결정)
    → 주(Primary) 샤드 (실제 색인 수행)
      → 모든 복제본(Replica) 샤드로 복제
        → 모든 복제본 반영 완료 후 클라이언트에 응답
```

- 주 샤드에서 색인 완료 후 모든 복제본 샤드에도 복제.
- 레플리카가 많을수록 색인 성능 저하. 읽기 분산과 색인 성능의 트레이드오프.

### 동시성 제어 — `_seq_no`와 `_primary_term`

| 메타데이터 | 설명 |
|-----------|------|
| `_seq_no` | 각 주 샤드마다 독립적으로 관리하는 시퀀스 번호. 매 작업마다 1씩 증가. **더 작은 seq_no를 가진 복제 요청이 나중에 오면 무시** → 순서 역전 방지. |
| `_primary_term` | 주 샤드가 새로 선출될 때마다 1씩 증가. 이전 주 샤드의 작업과 새 주 샤드의 작업을 구분. |
| `_version` | 문서 버전. 기본값(internal)은 ES가 자동 부여. `external` 타입은 클라이언트가 직접 지정. |

**낙관적 동시성 제어(Optimistic Concurrency Control)**:
```
PUT my_index/_doc/1?if_primary_term=1&if_seq_no=3
```
→ 현재 문서의 `_primary_term=1`, `_seq_no=3`일 때만 색인 수행.

### 장애 시 복구 과정 — 체크포인트

**로컬 체크포인트**: 각 샤드가 seq_no 기준으로 빠짐없이 순차적으로 완료한 마지막 번호.
- 예: seq_no 1,2,3,5,7을 완료 → 로컬 체크포인트 = 3 (4번이 빠졌으므로)

**글로벌 체크포인트**: 주 샤드가 모든 복제본의 로컬 체크포인트를 비교해 **가장 낮은 값**으로 결정. 그 번호까지는 모든 샤드에 반영 완료를 의미.

```
복구 시 동작:
  1. 주 샤드와 복구 대상 샤드의 글로벌 체크포인트 비교
  2. 같으면 추가 복구 불필요
  3. 다르면 체크포인트 이후 작업만 재처리 (세그먼트 전체 복사보다 효율적)
```

**샤드 이력 보존(Shard History Retention Leases)**: 논리적 삭제로 최근 삭제 문서를 보존해 작업 재처리에 활용. 기본 보존 기간: `index.soft_deletes.retention_lease.period` = **12시간**. 만료 후 복구는 세그먼트 파일 통째로 복사.

---

## 5. 읽기 작업 분산 처리

### 동작 원리

```
[읽기 요청 흐름]
클라이언트
  → 조정 노드
    → 주 또는 복제본 샤드 (라운드로빈 또는 adaptive replica selection)
      → 로컬 읽기 수행
        → 조정 노드로 결과 반환
          → 클라이언트 응답
```

- 읽기는 주/복제본 구분 없이 분산. 색인이 완료됐지만 특정 복제본에는 아직 반영 안 된 데이터를 읽을 수도 있다.

### Adaptive Replica Selection

- **기본 동작**: `preference` 미지정 시 adaptive replica selection 활성화. 이전 응답 속도, 검색 소요 시간, 현재 검색 스레드 풀 상황 등을 고려해 **가장 빠르게 응답할 것으로 예상되는 노드** 선택.
- **비활성화**: `cluster.routing.use_adaptive_replica_selection: false` → 랜덤 선택.
- **`preference` 매개변수**: `_local`, `_only_local`, `_only_nodes:<id>`, `_prefer_nodes:<id>`, `_shards:<n>` 등으로 수동 제어 가능.

---

## 6. 검색 동작 상세 — Query Phase와 Fetch Phase

### 전체 흐름 개괄

```
클라이언트
  → TransportSearchAction (조정 노드)
      [CanMatchPreFilterSearchPhase] (128개+ 샤드 등 특정 조건 시 수행)
      → 각 샤드로 Query 요청 분산 전송
          → [QueryPhase] (각 샤드)
              루씬 IndexSearcher로 매칭 문서 수집 + 유사도 점수 계산
              상위 docId 목록 반환
  → [FetchSearchPhase] (조정 노드)
      Query Phase 결과 병합 → fetch 대상 문서 확정 → 각 샤드로 fetch 요청
          → [FetchPhase] (각 샤드)
              요청받은 문서의 실제 내용(_source 등) 읽어 반환
  → [ExpandSearchPhase] (조정 노드)
      field collapse 처리 (필요 시)
  → 최종 응답 생성
```

### Query Phase 상세
- 각 샤드에서 루씬 `IndexSearcher.search(query, collector)` 호출.
- **Query → Weight → Scorer → DocIdSetIterator** 순서로 매칭 문서 순회.
- Collector가 DocIdSetIterator를 순회하며 유사도 점수 계산 후 상위 문서 수집.
- 반환값: 매칭된 상위 문서의 **docId 목록 + 유사도 점수** (문서 내용 아님).

### Fetch Phase 상세
- 조정 노드가 Query Phase 결과를 병합해 최종 상위 N개 문서 확정.
- 해당 문서를 보유한 샤드에 fetch 요청.
- 각 샤드의 FetchPhase가 실제 문서 내용(`_source`, score 등) 읽어 반환.
- FetchSubPhase: `FetchSourcePhase`(source 읽기), `FetchScorePhase`(점수 재계산), `ExplainPhase`(explain 모드) 등이 하위 작업으로 수행.

### DFS Query Phase (search_type=dfs_query_then_fetch)
- 모든 샤드로부터 텀 빈도(document frequency) 등 통계 데이터를 사전 수집.
- 이를 이용해 전역 유사도 점수 계산 → 정확도 향상 but 성능 저하.
- 기본값 `query_then_fetch`는 각 샤드가 로컬 통계로 점수 계산 → 샤드 간 점수 편차 가능.

---

## 7. 루씬 쿼리 매칭과 스코어링 과정

### 주요 클래스 역할

| 클래스 | 역할 |
|--------|------|
| `IndexSearcher` | 루씬 검색 담당. 내부에 여러 `LeafIndexReader`(세그먼트 단위 reader)를 보유. |
| `QueryBuilder` | ES 레벨 쿼리 → 루씬 `Query` 생성. |
| `Query` | 루씬 쿼리 추상클래스. `createWeight()`로 Weight 생성. `rewrite()`로 쿼리 최적화. |
| `Weight` | IndexSearcher 의존성 있는 작업 담당. `Scorer`, `BulkScorer` 생성. |
| `Scorer` | 유사도 점수 계산. `DocIdSetIterator`로 매칭 문서 순회. `score()`로 현재 문서 점수 반환. |
| `DocIdSetIterator` | 매칭 문서 ID를 순차적으로 순회. `advance(target)`으로 건너뛰기 최적화. |
| `TwoPhaseIterator` | 무거운 매치 판단을 간략 매치(후보 추리) + 정확 매치(최종 판정) 두 페이즈로 분리. |
| `Collector/LeafCollector` | 매칭 문서를 순회하며 수집. 유사도 점수 계산 여부에 따라 구현 다름. |

### conjunction(AND) 검색 최적화

- 각 하위 쿼리의 `DocIdSetIterator`를 cost(매칭 추정 문서 수) 순으로 정렬.
- cost가 가장 작은 DISI(leadl)부터 advance. lead2와 같은 문서를 가리킬 때까지 번갈아 advance.
- 모든 DISI가 같은 문서를 가리킬 때 → 모든 조건에 매칭된 문서.
- 핵심: AND 조건에서 한 DISI가 doc ID N을 가리키면 다른 DISI는 N 미만 문서를 건너뛸 수 있다.

### disjunction(OR) 검색 최적화

- 상위 K개 문서 수집 시, 현재 수집된 K번째 문서보다 점수 경쟁력 없는 문서/블록을 적극 건너뜀.
- `Scorer.setMinCompetitiveScore()`, `advanceShallow()` 등 활용.

### 쿼리 문맥 vs 필터 문맥
- 둘 다 DocIdSetIterator 생성 이후 Collector가 순회하며 수집.
- 필터 문맥은 유사도 점수(`score()`) 계산을 건너뜀 → 그 비용만큼 절약. 먼저 수행되는 것이 아니라 점수 계산을 생략하는 것.

---

## 8. 캐시 동작

### 8-1. 샤드 레벨 요청 캐시(Shard Request Cache)

- **수행 위치**: QueryPhase 진입 직전, SearchService의 `executeSearch` 메서드.
- **캐시 키**: ShardSearchRequest(인덱스 + 샤드 번호 + 검색 요청 본문) 직렬화값.
- **캐시 대상 값**: QueryPhase 수행 결과 전체 (매칭 상위 문서, 유사도 점수, 집계 결과 등). **FetchPhase 결과는 캐시 안 됨** (_source는 여전히 fetch 필요).
- **주요 캐시 조건**:
  - `search_type=query_then_fetch` + scroll 아님 + profile 아님
  - `requestCache=true` 명시하거나, 미명시 시 `index.requests.cache.enable=true`이고 **`size=0`** 인 경우
- **활용**: 주 목적은 `size=0` 집계 쿼리 캐싱. 하지만 자주 반복되는 일반 검색에도 `requestCache=true`로 명시해서 활용 가능.
- **무효화**: 인덱스 refresh 시 자동 무효화. `POST [인덱스]/_cache/clear?request=true` 수동 무효화.
- **캐시 크기**: 기본값 힙의 **1%**. `indices.requests.cache.size: 2%`로 조정.
- **적재 위치**: `IndicesService`의 `IndicesRequestCache` (노드와 생명주기 동일, 샤드 레벨로 관리).

### 8-2. 노드 레벨 쿼리 캐시(Node Query Cache)

- **수행 위치**: QueryPhase에서 IndexSearcher의 `search()` 호출 시 `createWeight()` 단계. 유사도 점수 계산 불필요 쿼리는 `CachingWeightWrapper`로 래핑.
- **캐시 키**: `Query` 인스턴스 (equals/hashCode가 같은 쿼리여야 적중).
- **캐시 대상 값**: 쿼리에 매칭된 문서 목록을 나타내는 **비트 배열** (`DocIdSet`).
  - 매칭 문서 수가 전체의 1% 초과 시 `FixedBitSet` (밀도 높은 배열)
  - 그 미만은 `RoaringDocIdSet` (메모리 효율적)
- **주요 캐시 조건**:
  - 유사도 점수 계산 불필요 쿼리(필터 문맥)
  - 세그먼트에 **10,000개 이상** 문서 + **샤드 내 문서의 3% 이상** 보유한 세그먼트
  - 자주 수행되는 쿼리 (무거운 쿼리 2회, 그 외 4-5회 이상)
  - TermQuery, MatchAllDocsQuery, MatchNoDocsQuery 등 이미 빠른 쿼리는 캐시 제외
- **bool 쿼리 활용**: 필터 문맥 하위 쿼리만 별도로 캐시. 여러 다른 bool 쿼리에서 필터 문맥이 겹치면 부분적으로 캐시 혜택.
- **읽기 시 락**: 캐시 읽기에도 락 필요. 락 실패 시 캐시 건너뛰고 일반 검색 진행.
- **무효화**: 인덱스 refresh 시 자동 무효화. `POST [인덱스]/_cache/clear?query=true` 수동 무효화.
- **캐시 크기**: 기본값 힙의 **10%**. `indices.queries.cache.size: 5%`로 조정.
- **적재 위치**: `IndicesService`의 `IndicesQueryCache`의 `LRUQueryCache` (노드 레벨).

### 8-3. OS 레벨 페이지 캐시

- OS가 디스크에서 읽은 데이터를 메모리에 올려두고 재사용.
- ES는 페이지 캐시를 적극 활용하므로 **시스템 메모리의 절반 이상을 OS 캐시로 사용**하도록 설정 권장.

### 캐시 비교

| 구분 | 샤드 레벨 요청 캐시 | 노드 레벨 쿼리 캐시 |
|------|-------------------|-------------------|
| 수행 위치 | QueryPhase 진입 직전 | Weight 생성 시 |
| 캐시 키 | ShardSearchRequest | Query 인스턴스 |
| 캐시 값 | QueryPhase 수행 결과 전체 | 매칭 문서 비트 배열 |
| 주요 조건 | size=0 또는 requestCache=true | 필터 문맥 + 일정 빈도 이상 |
| 적재 위치 | IndicesRequestCache (샤드 레벨) | IndicesQueryCache (노드 레벨) |

---

## 9. 샤드 크기와 개수 설계

### 적절한 샤드 크기
- 공식 권장: **샤드 1개 = 최대 50GB** 이하.
- 샤드가 너무 크면 장애 복구 시 네트워크 비용 증가.
- 샤드가 너무 많으면 마스터 노드 부하 증가 (마스터는 모든 샤드 정보를 메모리에 보유).

### 샤드 수 제한
- 개별 인덱스: 최대 **1024개** 샤드 (초과 시 오류).
- 클러스터 전체: 특별한 제한 없음 (리소스 허용 범위 내).

### 레플리카 수 결정
- 레플리카가 많을수록 읽기 성능 향상, 색인 성능 저하.
- 초기 서비스: 레플리카 최소화 → 모니터링 후 탄력적으로 조정.
- 레플리카 수는 운영 중 언제든 변경 가능.
