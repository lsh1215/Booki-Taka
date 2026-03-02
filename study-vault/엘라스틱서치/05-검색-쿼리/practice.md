# 05. 검색 쿼리 — 실전 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch4 / 엘라스틱서치바이블 Ch4
> 태그: #query-dsl #match #term #bool #range #pagination #scoring #bm25

---

## 구성

- 기초 (40%): Q1 ~ Q4
- 응용 (40%): Q5 ~ Q8
- 심화 (20%): Q9 ~ Q10

---

## 기초

### Q1. URI 검색 vs Request Body 검색

다음 URI 검색 쿼리를 Request Body 방식으로 변환하라.

```
POST movie_search/_search?q=movieNmEn:Family
```

<details>
<summary>정답</summary>

```json
POST movie_search/_search
{
  "query": {
    "query_string": {
      "default_field": "movieNmEn",
      "query": "Family"
    }
  }
}
```

**핵심 포인트:**
- URI 검색의 `q=필드:검색어` 는 Request Body의 `query_string.default_field + query` 로 표현
- URI 검색은 엘라스틱서치의 모든 검색 옵션을 사용할 수 없으므로 실무에서는 Request Body 방식을 사용해야 한다

</details>

---

### Q2. term vs match 선택

다음 두 쿼리의 동작 차이를 설명하고, 각각 어떤 상황에서 사용해야 하는지 서술하라.

```json
// 쿼리 A
{ "query": { "match": { "title": "Hello World" } } }

// 쿼리 B
{ "query": { "term": { "category": "Hello World" } } }
```

<details>
<summary>정답</summary>

**쿼리 A (match):**
- `title` 필드가 `text` 타입이면 "Hello World"를 애널라이저로 분석하여 "hello", "world" 두 개의 토큰으로 분리
- 역색인에서 각 텀을 검색하며, 기본 동작은 **OR 조건** (두 텀 중 하나라도 포함된 문서 반환)
- **사용 상황:** 자연어 전문 검색(full-text search)이 필요할 때, text 타입 필드 검색

**쿼리 B (term):**
- "Hello World"를 하나의 텀으로 처리하여 분석하지 않고 정확히 일치하는 값 검색
- keyword 타입 필드에서는 직관적으로 동작, text 타입에서는 역색인의 단일 텀과만 매칭
- **사용 상황:** keyword 타입 필드의 정확한 값 검색 (상태 코드, 카테고리, 태그 등)

**핵심 규칙:** text 타입 → match, keyword 타입 → term

</details>

---

### Q3. range 쿼리 작성

`prdtYear` 필드에서 2015년부터 2020년까지(양쪽 포함)의 영화를 검색하는 range 쿼리를 작성하라.

<details>
<summary>정답</summary>

```json
POST movie_search/_search
{
  "query": {
    "range": {
      "prdtYear": {
        "gte": "2015",
        "lte": "2020"
      }
    }
  }
}
```

**연산자 정리:**
| 연산자 | 의미 | 경곗값 포함 |
|---|---|---|
| `gt` | greater than (초과) | 포함 안 함 |
| `lt` | less than (미만) | 포함 안 함 |
| `gte` | greater than or equal to (이상) | 포함 |
| `lte` | less than or equal to (이하) | 포함 |

**주의:** 문자열 필드를 대상으로 한 range 쿼리는 부하가 큰 쿼리로 분류된다.

</details>

---

### Q4. match_all과 Query DSL 구조

다음 Query DSL 요청의 각 파라미터가 의미하는 바를 설명하라.

```json
POST movie_search/_search
{
  "size": 5,
  "from": 10,
  "timeout": "2s",
  "_source": ["movieNm", "prdtYear"],
  "query": {
    "match_all": {}
  },
  "sort": {
    "prdtYear": { "order": "desc" }
  }
}
```

<details>
<summary>정답</summary>

| 파라미터 | 설명 |
|---|---|
| `"size": 5` | 반환할 결과 개수를 5개로 지정 (기본값 10) |
| `"from": 10` | 11번째 문서부터 결과를 반환 (페이지 3의 시작, 0부터 카운트) |
| `"timeout": "2s"` | 2초 안에 응답받지 못한 경우 그 시점까지의 결과만 반환 |
| `"_source": [...]` | 응답에서 `movieNm`과 `prdtYear` 필드만 포함 (네트워크 비용 절감) |
| `"query": { "match_all": {} }` | 인덱스의 모든 문서를 매칭 |
| `"sort": {...}` | `prdtYear` 필드 기준 내림차순 정렬 |

**동작:** prdtYear 내림차순으로 정렬된 전체 문서 중 11~15번째 문서의 movieNm, prdtYear 필드만 반환

</details>

---

## 응용

### Q5. bool 쿼리 작성

다음 조건을 만족하는 bool 쿼리를 작성하라.
- 대표 장르(`repGenreNm`)가 반드시 "액션"이어야 한다
- 제작 국가(`repNationNm`)에 "한국"이 포함되어야 한다
- 영화 타입(`typeNm`)이 "단편"이면 제외한다
- 배우 이름(`actor`)에 "이병헌" 또는 "최민식"이 있으면 우선순위를 높인다

<details>
<summary>정답</summary>

```json
POST movie_search/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "repGenreNm": "액션" } },
        { "match": { "repNationNm": "한국" } }
      ],
      "must_not": [
        { "match": { "typeNm": "단편" } }
      ],
      "should": [
        { "match": { "actor": "이병헌" } },
        { "match": { "actor": "최민식" } }
      ],
      "minimum_should_match": 0
    }
  }
}
```

**핵심 포인트:**
- `must`: AND 조건, **Query Context** (점수 계산 O)
- `must_not`: NOT 조건, **Filter Context** (점수 계산 X)
- `should`: OR 조건, **Query Context**로 매칭 시 점수 가산
- `minimum_should_match: 0` 이면 should는 선택적 가중치 역할만 함 (must만으로도 결과에 포함)
- 성능 최적화: `repGenreNm` 조건을 `must` 대신 `filter`로 이동하면 점수 계산 불필요 → 성능 향상

</details>

---

### Q6. Query Context vs Filter Context 최적화

다음 쿼리는 동일한 결과를 반환하지만 성능 차이가 있다. 어떤 쿼리가 더 성능이 좋은지, 그 이유를 설명하라.

```json
// 쿼리 A
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "elasticsearch" } },
        { "term": { "status": "published" } },
        { "range": { "date": { "gte": "2020-01-01" } } }
      ]
    }
  }
}

// 쿼리 B
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "elasticsearch" } }
      ],
      "filter": [
        { "term": { "status": "published" } },
        { "range": { "date": { "gte": "2020-01-01" } } }
      ]
    }
  }
}
```

<details>
<summary>정답</summary>

**쿼리 B가 더 성능이 좋다.**

**이유:**
1. **점수 계산 비용 절감:** 쿼리 A에서 `term`과 `range` 조건도 Query Context로 실행되어 불필요한 유사도 점수를 계산한다. 쿼리 B에서는 `filter` 절로 이동하여 Filter Context로 실행되므로 점수 계산을 하지 않는다.

2. **캐시 활용:** Filter Context로 실행된 쿼리 결과는 엘라스틱서치가 내부적으로 캐싱한다. 동일한 `status: published`, `date >= 2020-01-01` 조건이 반복 요청될 때 캐시에서 빠르게 결과를 반환할 수 있다.

3. **처리 레벨:** Query Context는 루씬 레벨에서 분석 과정이 필요하여 상대적으로 느리고, Filter Context는 엘라스틱서치 레벨에서 처리하여 빠르다.

**원칙:** `status`, `date` 처럼 Yes/No로 판단할 수 있는 조건, 랭킹에 영향을 줄 필요 없는 조건은 `filter` 절에 넣어야 한다.

</details>

---

### Q7. 페이지네이션 방식 선택

다음 세 가지 시나리오에서 각각 어떤 페이지네이션 방식(`from/size`, `scroll`, `search_after`)을 사용해야 하는지 이유와 함께 설명하라.

1. 사용자가 검색 결과 1페이지 → 2페이지 → 3페이지로 넘기는 서비스 API
2. 1억 건의 로그 데이터를 외부 스토리지로 전체 이전하는 배치 작업
3. 10페이지 이하의 간단한 관리자 목록 조회

<details>
<summary>정답</summary>

**시나리오 1 → search_after**
- 서비스에서 사용자가 검색 결과를 요청하고 페이지네이션을 제공하는 용도에 가장 적합
- 성능 부담이 상대적으로 낮고 본격적인 페이지네이션 가능
- PIT(point in time) API와 조합하면 인덱스 상태를 고정하여 일관된 결과 제공
- sort 필드를 지정하고 동점 제거(tiebreaker)용 필드 필수

**시나리오 2 → scroll**
- 검색 조건에 매칭되는 전체 문서를 모두 순회해야 할 때 적합
- 검색 문맥(search context)이 유지되어 중복/누락 없이 전체 문서 순회 가능
- 정렬 순서가 상관없으므로 `sort: ["_doc"]` 지정으로 성능 최적화
- 대량 데이터 이전/덤프에 최적

**시나리오 3 → from/size**
- 10페이지 이하의 소규모 조회는 from/size로 충분
- 구현이 가장 단순
- 단, from+size 합이 10,000을 넘지 않아야 하며 페이지 깊이가 깊어질수록 성능 저하 발생

</details>

---

### Q8. multi_match와 boost 조합

영화 검색 서비스에서 "장군"이라는 키워드로 검색할 때, 한글 제목(`movieNm`) 매칭에 3배 가중치를 주고 영문 제목(`movieNmEn`)도 함께 검색하는 쿼리를 작성하라. 또한 제작 연도가 2010년 이후인 조건을 성능 최적화를 고려하여 추가하라.

<details>
<summary>정답</summary>

```json
POST movie_search/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "multi_match": {
            "query": "장군",
            "fields": ["movieNm^3", "movieNmEn"]
          }
        }
      ],
      "filter": [
        {
          "range": {
            "prdtYear": {
              "gte": "2010"
            }
          }
        }
      ]
    }
  }
}
```

**핵심 포인트:**
- `movieNm^3`: movieNm 필드에서 매칭되면 스코어에 3을 곱하여 한글 제목 우선
- `multi_match`: 여러 필드를 동시에 검색
- 제작 연도 조건은 랭킹과 무관하므로 `filter` 절에 넣어 Filter Context로 처리 → 점수 계산 없음, 캐시 활용

</details>

---

## 심화

### Q9. 페이지네이션의 deep pagination 문제

from/size 페이지네이션에서 발생하는 "deep pagination" 문제를 설명하고, 엘라스틱서치가 이를 어떻게 처리하는지, 그리고 이 문제를 해결하는 방법을 서술하라.

<details>
<summary>정답</summary>

**deep pagination 문제:**

엘라스틱서치는 관계형 데이터베이스와 다르게 페이징된 해당 문서만 선택적으로 가져오는 것이 아니라 모든 데이터를 읽어야 한다. 예를 들어 5건씩 페이징할 때 2페이지(from=5, size=5)를 요청하면 내부적으로 상위 10건의 문서를 읽은 후 마지막에 결과의 일부를 잘라내서 반환하는 구조다.

**두 가지 문제:**
1. **성능 이슈:** from 값이 올라갈수록 더 많은 문서를 읽어야 하므로 CPU와 메모리 사용량이 증가, 장애 유발 가능
2. **일관성 이슈:** 이전 페이지와 다음 페이지 검색 사이에 새로운 문서가 색인되거나 삭제될 수 있어 특정 문서의 중복/누락 발생 가능

**엘라스틱서치의 처리 방식:**
- 기본적으로 `from + size`의 합이 **10,000**을 넘어서는 검색은 수행 거부
- `index.max_result_window` 설정으로 변경 가능하나 권장하지 않음

**해결 방법:**
1. **scroll**: 전체 문서를 순회해야 할 때. 검색 문맥을 유지하여 중복/누락 없이 순회 가능. 단, 서비스 성 지속 호출에는 부적합.
2. **search_after**: 서비스 페이지네이션용. 이전 페이지의 마지막 문서 sort 값을 기준으로 다음 페이지 요청. PIT API와 조합하면 인덱스 상태 고정으로 일관성 보장.

</details>

---

### Q10. 스코어 계산과 BM25

다음 상황에서 문서 A, B, C 중 어떤 문서가 가장 높은 스코어를 받을지 예측하고, BM25 알고리즘 관점에서 그 이유를 설명하라.

검색어: "elasticsearch"

- **문서 A (길이: 100단어):** "elasticsearch"가 5번 등장
- **문서 B (길이: 10단어):** "elasticsearch"가 2번 등장
- **문서 C (길이: 1000단어):** "elasticsearch"가 5번 등장

전체 인덱스에 "elasticsearch"라는 단어는 드물게 등장한다고 가정.

<details>
<summary>정답</summary>

**예상 스코어 순서: 문서 B > 문서 A > 문서 C**

**BM25 관점에서의 분석:**

**IDF (Inverse Document Frequency):**
- "elasticsearch"가 인덱스 전체에서 드물게 등장 → IDF 값이 높음
- 세 문서 모두 동일한 IDF를 공유 (인덱스 전체 통계 기준)

**TF (Term Frequency) + 포화 처리:**
- TF-IDF의 문제: TF가 증가할수록 점수가 무한정 증가
- BM25는 `k1` 파라미터로 TF 포화를 조정 → TF가 어느 수준 이상 증가해도 점수 증가가 둔화됨
- 따라서 문서 A(TF=5/100)와 문서 C(TF=5/1000)의 TF 원시 값은 같지만...

**문서 길이 정규화 (BM25의 핵심):**
- BM25는 `b` 파라미터로 문서 길이에 따른 정규화 수행
- 긴 문서(C)는 자연히 텀이 많이 등장할 확률이 높으므로 길이로 나누어 보정
- 문서 B (10단어에서 2번 등장) = 높은 밀도 → 가장 높은 관련도
- 문서 A (100단어에서 5번 등장) = 중간 밀도
- 문서 C (1000단어에서 5번 등장) = 낮은 밀도 → 가장 낮은 관련도

**실무 활용:**
- 디버깅 시 `explain=true` 또는 `_explain` API로 각 문서의 점수 계산 과정 확인 가능
- 단, explain 사용 시 쿼리 최적화가 덜 되어 성능 저하 발생 → 디버깅 용도로만 사용

</details>

---

*최종 업데이트: 2026-03-03*
