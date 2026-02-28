# 03. 검색 & Query DSL

## 실습 목적

Elasticsearch Query DSL의 핵심 쿼리 타입을 직접 실행하면서 각 쿼리의 동작 방식과 차이를 이해한다.
특히 full-text 쿼리(match)와 term-level 쿼리(term)의 근본적인 차이를 파악하고, bool 쿼리로 복잡한 검색 조건을 조합하는 방법을 익힌다.

---

## 관련 챕터

- 엘라스틱서치 바이블: 6장 (검색), 7장 (Query DSL)
- Elasticsearch 실무 가이드: 5장 (검색 API), 6장 (Query DSL)

---

## 실습 절차

```
bash 00-setup-data.sh       # 샘플 데이터 로딩 (먼저 실행 필수!)
bash 01-match-query.sh      # Match, Multi Match Query
bash 02-term-query.sh       # Term, Terms Query
bash 03-bool-query.sh       # Bool Query
bash 04-range-query.sh      # Range Query
bash 05-prefix-exists.sh    # Prefix, Exists Query
bash 06-scoring.sh          # 스코어링 원리
bash 07-search-template.sh  # 검색 템플릿
```

---

## 샘플 데이터 구조

전자상거래 상품 데이터 약 100건

| 필드 | 타입 | 설명 |
|------|------|------|
| title | text | 상품명 (full-text 검색) |
| category | keyword | 카테고리 |
| price | integer | 가격 (원) |
| brand | keyword | 브랜드명 |
| description | text | 상품 설명 |
| created_at | date | 등록일 |
| in_stock | boolean | 재고 여부 |
| rating | float | 평점 (1.0 ~ 5.0) |
| tags | keyword | 태그 배열 |

---

## 관찰 포인트

### 01-match-query.sh
- `match` 쿼리는 검색어를 분석(analyze)하여 검색한다
- `match_phrase`는 단어 순서와 위치까지 고려한다
- `multi_match`의 `type` 옵션별 스코어링 차이

### 02-term-query.sh
- `term` 쿼리는 분석 없이 정확한 값으로 검색한다
- text 필드에 term 쿼리를 사용하면 안 되는 이유
- `terms` 쿼리의 OR 조건 동작

### 03-bool-query.sh
- `must`, `should`, `filter`, `must_not`의 차이
- `filter`는 스코어에 영향을 주지 않고 캐싱된다
- `minimum_should_match` 옵션

### 04-range-query.sh
- `gte`, `gt`, `lte`, `lt` 조합
- date 필드의 `now`, `now-7d/d` 등 날짜 수식

### 06-scoring.sh
- `_explain` API로 BM25 스코어 계산 과정 확인
- `boost` 파라미터로 특정 쿼리의 가중치 조정
- `function_score` 쿼리로 비즈니스 로직 반영

---

## 핵심 질문

1. `match` 쿼리와 `term` 쿼리의 근본적인 차이는 무엇인가?
2. bool 쿼리에서 `must`와 `filter`의 차이는 무엇인가? 언제 filter를 사용해야 하는가?
3. text 필드에 `term` 쿼리를 사용했을 때 검색이 안 되는 이유를 설명하라.
4. `_score` 값이 어떤 요소들로 계산되는지 설명하라.
5. 검색 결과의 relevancy(관련성)를 높이기 위한 방법에는 어떤 것들이 있는가?
