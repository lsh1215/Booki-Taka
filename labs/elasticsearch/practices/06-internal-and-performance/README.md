# 06. 내부 동작 & 성능 (Internal & Performance)

## 실습 목적

Elasticsearch의 내부 동작 원리를 직접 관찰하고, 성능 최적화 기법을 실습한다.
세그먼트 구조, refresh와 flush 동작, 캐시 메커니즘을 이해하면 운영 중 발생하는 성능 문제를 진단하고 해결하는 능력을 키울 수 있다.

---

## 관련 챕터

- 엘라스틱서치 바이블: 12장 (내부 동작), 13장 (성능 최적화)
- Elasticsearch 실무 가이드: 9장 (성능 튜닝)

---

## 실습 절차

```
bash 01-segments.sh         # 세그먼트 관찰
bash 02-refresh-flush.sh    # refresh와 flush 동작
bash 03-force-merge.sh      # Force merge 실습
bash 04-cache.sh            # 캐시 동작 관찰
bash 05-bulk-performance.sh # Bulk API 성능 테스트
```

---

## 관찰 포인트

### 01-segments.sh
- `_segments` API에서 `num_docs`, `deleted_docs`, `size_in_bytes` 관찰
- 문서를 삭제해도 세그먼트에서 즉시 제거되지 않는다 (삭제 마킹)
- 세그먼트 수가 많을수록 검색 성능이 저하되는 이유

### 02-refresh-flush.sh
- `refresh_interval: -1` 설정 후 색인한 문서가 검색되지 않는 이유
- `_refresh` API 호출 후 문서가 검색 가능해지는 시점
- flush와 refresh의 차이: flush는 translog를 비우고 Lucene 커밋

### 03-force-merge.sh
- force_merge 전후 세그먼트 수 변화 관찰
- `max_num_segments: 1` 설정의 의미
- force_merge의 부작용 (I/O 집중, 운영 중 주의)

### 04-cache.sh
- request cache: 집계 결과를 샤드 레벨에서 캐싱 (size=0 쿼리)
- query cache: 자주 사용되는 필터 결과를 비트셋으로 캐싱
- fielddata cache: text 필드의 메모리 내 집계 데이터
- `_nodes/stats`에서 cache hit/miss 비율 관찰

### 05-bulk-performance.sh
- 단건 vs 벌크 색인 성능 비교
- 벌크 배치 크기별 성능 차이 (100, 500, 1000건)
- refresh_interval과 replica 수가 색인 성능에 미치는 영향

---

## 핵심 질문

1. 세그먼트란 무엇인가? Lucene에서 검색은 어떻게 이루어지는가?
2. refresh와 flush의 차이를 translog와 연결해서 설명하라.
3. 대량 색인 시 refresh_interval을 -1로 설정하는 이유는?
4. request cache와 query cache의 차이는 무엇인가?
5. 검색 성능 저하 시 캐시 상태를 어떻게 진단하는가?
