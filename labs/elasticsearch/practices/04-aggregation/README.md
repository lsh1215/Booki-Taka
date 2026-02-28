# 04. 집계 (Aggregation)

## 실습 목적

Elasticsearch 집계 API를 통해 데이터를 다양한 관점에서 분석하는 방법을 익힌다.
SQL의 GROUP BY, COUNT, SUM, AVG와 같은 기능을 ES에서 어떻게 표현하는지 이해하고,
중첩 집계(Nested Aggregation)로 복잡한 분석 쿼리를 구성하는 방법을 학습한다.

---

## 관련 챕터

- 엘라스틱서치 바이블: 8장 (집계)
- Elasticsearch 실무 가이드: 7장 (집계)

---

## 실습 절차

```
bash 00-setup-data.sh    # 집계 실습용 주문 데이터 로딩 (먼저 실행 필수!)
bash 01-metric-aggs.sh   # 메트릭 집계
bash 02-bucket-aggs.sh   # 버킷 집계
bash 03-pipeline-aggs.sh # 파이프라인 집계
bash 04-nested-aggs.sh   # 중첩 집계
```

---

## 샘플 데이터 구조

이커머스 주문 데이터 약 200건

| 필드 | 타입 | 설명 |
|------|------|------|
| order_id | keyword | 주문 ID |
| customer_name | keyword | 고객명 |
| product | keyword | 상품명 |
| category | keyword | 카테고리 |
| price | integer | 단가 |
| quantity | integer | 수량 |
| order_date | date | 주문일 |
| region | keyword | 지역 |
| payment_method | keyword | 결제 방법 |

---

## 관찰 포인트

### 01-metric-aggs.sh
- `stats` 집계는 어떤 값들을 한번에 반환하는가
- `cardinality`는 정확한 값인가, 근사값인가? 왜?
- `percentiles`로 P95, P99를 파악하는 실무적 의미

### 02-bucket-aggs.sh
- `terms` 집계의 `size`를 늘리면 정확도가 올라가지만 성능에 영향을 준다
- `date_histogram`의 `calendar_interval` vs `fixed_interval` 차이
- `histogram`의 `min_doc_count: 0`으로 빈 버킷 포함하기

### 03-pipeline-aggs.sh
- 파이프라인 집계는 다른 집계의 결과를 입력으로 사용한다
- `derivative`로 전월 대비 증감 계산하기
- `cumulative_sum`으로 누적 합계 만들기

### 04-nested-aggs.sh
- 버킷 안에 메트릭 집계를 넣으면 SQL의 GROUP BY + 집계 함수와 같다
- `top_hits`로 각 버킷의 대표 문서 가져오기
- 집계 결과를 `sort`로 정렬하는 방법

---

## 핵심 질문

1. 메트릭 집계와 버킷 집계의 차이는 무엇인가?
2. `terms` 집계 결과에서 `doc_count_error_upper_bound`와 `sum_other_doc_count`는 무엇을 의미하는가?
3. `cardinality` 집계가 정확하지 않은 이유는 무엇인가? 정확도를 높이는 방법은?
4. 파이프라인 집계는 일반 집계와 어떤 점이 다른가?
5. `filter` 쿼리와 `filter` 집계의 차이는 무엇인가?
