# 엘라스틱서치 Study Vault

## 학습 지도

```
[사전 지식]
    │
    ▼
01-핵심-아키텍처 ──────────────────────────────────────────┐
(역색인 / 샤드 / 세그먼트 / NRT)                            │
    │                                                       │
    ├──────────────┐                                        │
    ▼              ▼                                        │
02-인덱스-설계  03-분석기                                    │
(매핑 / 필드타입) (애널라이저 / Nori)                         │
    │              │                                        │
    ▼              ▼                                        │
04-문서-API ─────────────────────────┐                      │
(Index / Get / Update / Bulk)        │                      │
    │                                │                      │
    ▼                                ▼                      │
05-검색-쿼리                       06-집계                   │
(Query DSL / BM25)                 (Metric / Bucket)        │
    │                                │                      │
    ▼                                ▼                      │
07-고급-검색 ────────────────────────┘                      │
(Highlight / Suggest / Scroll)                              │
    │                                                       │
    ▼                                                       │
08-클러스터-구성 ◄──────────────────────────────────────────┘
(Node Role / Split-brain / Security)
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
09-운영-전략   10-모니터링    11-장애-대응
(ILM / Alias)  (Cat API / JVM) (Unassigned / OOM)
    │              │              │
    └──────────────┴──────────────┘
                   │
                   ▼
            12-성능-최적화
            (JVM / Heap / G1GC)
                   │
                   ▼
            13-내부-동작
            (Query→Fetch / Checkpoint / Cache)
```

---

## 토픽 목록

| # | 토픽 | 핵심 개념 수 | 연습 문제 수 | 난이도 | 태그 |
|---|------|:-----------:|:-----------:|--------|------|
| 01 | [핵심 아키텍처](./01-핵심-아키텍처/concepts.md) | 8 | 11 | ★★☆ | #elasticsearch #lucene #inverted-index #shard |
| 02 | [인덱스 설계](./02-인덱스-설계/concepts.md) | 7 | 11 | ★★☆ | #mapping #field-type #template #routing |
| 03 | [분석기](./03-분석기/concepts.md) | 51 | 10 | ★★☆ | #analyzer #tokenizer #nori #ngram |
| 04 | [문서 API](./04-문서-API/concepts.md) | 49 | 10 | ★★☆ | #index-api #bulk-api #reindex #concurrency |
| 05 | [검색 쿼리](./05-검색-쿼리/concepts.md) | 39 | 10 | ★★★ | #query-dsl #bool #bm25 #scoring |
| 06 | [집계](./06-집계/concepts.md) | 27 | 12 | ★★★ | #aggregation #metric #bucket #pipeline |
| 07 | [고급 검색](./07-고급-검색/concepts.md) | 5 | 12 | ★★★ | #highlight #suggest #scroll #search-template |
| 08 | [클러스터 구성](./08-클러스터-구성/concepts.md) | 26 | 10 | ★★★ | #cluster #node-role #split-brain #tls |
| 09 | [운영 전략](./09-운영-전략/concepts.md) | 43 | 10 | ★★★ | #alias #rollover #ilm #data-stream #snapshot |
| 10 | [모니터링](./10-모니터링/concepts.md) | 35 | 10 | ★★☆ | #monitoring #cat-api #jvm #thread-pool |
| 11 | [장애 대응](./11-장애-대응/concepts.md) | 46 | 11 | ★★★ | #fault-tolerance #unassigned-shard #circuit-breaker |
| 12 | [성능 최적화](./12-성능-최적화/concepts.md) | 50 | 10 | ★★★ | #jvm #heap #g1gc #vm-max-map-count |
| 13 | [내부 동작](./13-내부-동작/concepts.md) | 32 | 12 | ★★★ | #lucene #query-phase #fetch-phase #cache |

**합계:** 개념 418개 / 연습 문제 139문제

---

## 권장 학습 순서

### 1단계: 기초 원리 (01 → 02 → 03)
역색인과 루씬 구조를 먼저 이해해야 이후 모든 개념의 "왜"가 보인다.

### 2단계: 읽기/쓰기 API (04 → 05 → 06)
문서를 넣고 꺼내는 핵심 인터페이스. 특히 04(쓰기)와 05(읽기)는 가장 자주 쓰인다.

### 3단계: 심화 검색과 집계 (07)
실무 기능의 90%는 여기서 해결된다.

### 4단계: 운영 지식 (08 → 09 → 10 → 11 → 12)
장애를 경험하기 전에 먼저 읽어두면 좋다.

### 5단계: 내부 동작 (13)
최적화와 트러블슈팅의 근거를 제공한다. 다른 토픽을 모두 읽은 후 읽으면 맥락이 연결된다.

---

## 약점 영역

_(학습 후 각 토픽 practice.md의 정답을 맞추지 못한 문제를 여기 기록한다)_

| 토픽 | 틀린 문제 | 날짜 | 재학습 완료 |
|------|---------|------|------------|
| - | - | - | - |

---

## 참고

- **출처**: 엘라스틱서치 실무가이드 (권택한 외 5인, 위키북스, 2022) / 엘라스틱서치바이블 (이동현, 위키북스, 2023)
- **생성일**: 2026-03-03
- **관련 스킬**: `/study`로 특정 토픽 깊이 파기, `/lab elasticsearch`로 실습 환경 구축
