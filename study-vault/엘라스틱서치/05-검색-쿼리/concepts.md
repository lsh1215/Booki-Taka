# 05. 검색 쿼리 — 핵심 개념

> 출처: 엘라스틱서치 실무가이드 Ch4 / 엘라스틱서치바이블 Ch4
> 태그: #query-dsl #match #term #bool #range #pagination #scoring #bm25

---

## 목차

1. [URI 검색 vs Request Body 검색](#1-uri-검색-vs-request-body-검색)
2. [Query Context vs Filter Context](#2-query-context-vs-filter-context)
3. [Query DSL 구조](#3-query-dsl-구조)
4. [주요 쿼리](#4-주요-쿼리)
   - 4.1 match_all
   - 4.2 match
   - 4.3 multi_match
   - 4.4 term / terms
   - 4.5 range
   - 4.6 bool
   - 4.7 prefix / wildcard / regexp
   - 4.8 exists
   - 4.9 nested
   - 4.10 constant_score
5. [검색 결과 정렬](#5-검색-결과-정렬)
6. [페이지네이션](#6-페이지네이션)
7. [\_source 필드 제어](#7-_source-필드-제어)
8. [관련도 점수 (BM25)](#8-관련도-점수-bm25)

---

## 1. URI 검색 vs Request Body 검색

### 정의

엘라스틱서치 검색 API는 질의를 표현하는 방식을 두 가지로 제공한다.

- **URI 검색**: HTTP GET 요청의 URL 파라미터에 `key=value` 형태로 질의를 전달하는 방식. 루씬에서 사용하던 전통적인 방식.
- **Request Body 검색**: HTTP 요청 Body에 JSON 형태로 질의를 기술하는 방식. 엘라스틱서치 Query DSL을 활용한다.

### 왜 필요한가

검색 도구가 다양한 검색 조건을 유연하게 표현할 수 있어야 하는데, URI 방식은 파라미터 표현의 한계로 복잡한 질의 작성이 불가능하다. Request Body 방식은 JSON 구조를 통해 엘라스틱서치의 모든 검색 옵션을 활용할 수 있다.

### 동작 원리

**URI 검색**
```
POST movie_search/_search?q=movieNmEn:Family
# 파라미터: q, df, analyzer, analyze_wildcard, default_operator, _source, sort, from, size
```

복잡한 URI 검색 예:
```
POST movie_search/_search?q=movieNmEn:* AND prdtYear:2017&analyze_wildcard=true&from=0&size=5&sort=_score:desc,movieCd:asc&_source_includes=movieCd,movieNm,movieNmEn,typeNm
```

**Request Body 검색**
```json
POST movie_search/_search
{
  "query": {
    "query_string": {
      "default_field": "movieNmEn",
      "query": "Family"
    }
  },
  "from": 0,
  "size": 5,
  "sort": [
    { "_score": { "order": "desc" } },
    { "movieCd": { "order": "asc" } }
  ],
  "_source": ["movieCd", "movieNm", "movieNmEn", "typeNm"]
}
```

### 설계 트레이드오프

| 항목 | URI 검색 | Request Body 검색 |
|---|---|---|
| 사용 편의성 | 간단한 조회에 편리 | JSON 구조 학습 필요 |
| 표현력 | 제한적 | 엘라스틱서치 전체 기능 활용 가능 |
| 가독성 | 길어질수록 급격히 저하 | JSON 구조로 명확 |
| 적합한 상황 | 빠른 테스트, 간단한 조회 | 실무 서비스 환경 |

> 실무에서는 Request Body 방식을 사용해야 한다. URI 검색은 엘라스틱서치의 모든 검색 옵션을 사용할 수 없다.

**바이블 추가 설명:** 요청 본문과 `q` 매개변수가 동시 지정된 경우 `q` 매개변수가 우선 작동한다. 두 방법을 혼용할 수는 없다.

### 관련 개념
- [Query DSL 구조](#3-query-dsl-구조)
- `../03-분석기/concepts.md` — 검색 시점 분석기 동작

---

## 2. Query Context vs Filter Context

### 정의

엘라스틱서치 쿼리를 작성할 때 하위 질의는 두 가지 문맥(context)으로 동작한다.

- **Query Context (쿼리 문맥)**: 문서가 질의어와 얼마나 잘 매치되는지 유사도 점수를 계산하는 검색 과정
- **Filter Context (필터 문맥)**: 질의 조건을 만족하는지 여부만 참/거짓으로 판별하는 검색 과정

### 왜 필요한가

모든 질의에 점수 계산을 수행하면 불필요한 CPU 비용이 발생한다. 예를 들어 "상태가 활성화인 문서"를 필터링하는 조건에는 관련도 점수가 의미 없다. Filter Context를 쓰면 점수 계산 비용을 아끼고 캐시도 활용할 수 있다.

### 동작 원리

**Query Context 특성**
- 루씬 레벨에서 분석 과정을 거쳐야 하므로 상대적으로 느림
- 결과가 캐싱되지 않음 (매 요청마다 계산)
- `bool`의 `must`, `should` 조건절이 해당
- 예: "Harry Potter" 같은 문장 분석

```json
POST movie_search/_search
{
  "query": {
    "match": {
      "movieNm": "기묘한 가족"
    }
  }
}
```

**Filter Context 특성**
- Yes/No로 단순 판별 가능 → 엘라스틱서치 레벨에서 처리, 상대적으로 빠름
- 자주 사용되는 필터 결과는 내부적으로 캐싱
- `bool`의 `filter`, `must_not` 조건절이 해당
- 예: "create_year" 필드의 값이 2018년인지 여부

```json
POST movie_search/_search
{
  "query": {
    "bool": {
      "match_all": {},
      "filter": {
        "term": {
          "repGenreNm": "다큐멘터리"
        }
      }
    }
  }
}
```

### 설계 트레이드오프

| 항목 | Query Context | Filter Context |
|---|---|---|
| 질의 개념 | 문서가 질의어와 얼마나 잘 매치되는가 | 질의 조건을 만족하는가 |
| 점수 | 계산함 | 계산하지 않음 |
| 성능 | 상대적으로 느림 | 상대적으로 빠름 |
| 캐시 | 쿼리 캐시 활용 불가 | 쿼리 캐시 활용 가능 |
| 해당 절 | `bool`의 `must`, `should` / `match`, `term` 등 | `bool`의 `filter`, `must_not` / `exists`, `range`, `constant_score` 등 |

> **조건을 만족하는지 여부만 중요하고 랭킹에 영향을 줄 필요 없는 조건은 반드시 필터 문맥으로 검색해야 성능상 유리하다.**

**바이블 추가 설명 (쿼리 수행 순서):** `must`, `filter`, `must_not`, `should` 사이에서 어떤 쿼리가 먼저 수행된다는 규칙은 없다. 엘라스틱서치는 내부적으로 쿼리를 루씬의 여러 쿼리로 쪼갠 뒤 비용 추정을 통해 유리할 것으로 생각되는 부분을 먼저 수행한다.

### 관련 개념
- [bool 쿼리](#46-bool)
- [constant_score](#410-constant_score)
- `../01-핵심-아키텍처/concepts.md` — 역색인 구조, 샤드 레벨 처리

---

## 3. Query DSL 구조

### 정의

Query DSL(Domain Specific Language)은 엘라스틱서치가 제공하는 JSON 기반의 쿼리 전용 언어다. Request Body 검색 시 사용하며 여러 개의 질의를 조합하거나 질의 결과에 대해 다시 검색하는 등 강력한 검색이 가능하다.

### 요청 JSON 기본 구조

```json
{
  "size": 10,          // 반환할 결과 개수 (기본값 10)
  "from": 0,           // 몇 번째 문서부터 가져올지 (기본값 0)
  "timeout": "1s",     // 타임아웃 (기본값 무한대)
  "_source": {},       // 검색 시 필요한 필드만 출력
  "query": {},         // 검색 조건문
  "aggs": {},          // 통계 및 집계
  "sort": {}           // 결과 정렬 조건
}
```

### 응답 JSON 기본 구조

```json
{
  "took": 1,           // 쿼리 실행 시간 (ms)
  "timed_out": false,  // 쿼리 시간 초과 여부
  "_shards": {
    "total": 5,        // 전체 샤드 개수
    "successful": 5,   // 응답 성공 샤드
    "failed": 0        // 실패 샤드
  },
  "hits": {
    "total": 10,       // 매칭된 문서 전체 개수
    "max_score": 1.0,  // 가장 높은 스코어
    "hits": []         // 각 문서 정보와 스코어
  }
}
```

### 동작 원리

쿼리가 요청되면 엘라스틱서치는 JSON 파싱 → 문법 검증 → 검색 수행 → JSON 형식 응답의 흐름으로 처리한다. 파싱 실패 시 `json_parse_exception` 에러가 반환된다.

### 관련 개념
- `../01-핵심-아키텍처/concepts.md` — 샤드, 레플리카, 검색 브로드캐스트

---

## 4. 주요 쿼리

### 4.1 match_all

**정의:** 파라미터 없이 색인에 저장된 모든 문서를 검색하는 가장 단순한 쿼리다. `query` 부분을 비워 두면 기본값으로 지정된다.

```json
POST movie_search/_search
{
  "query": {
    "match_all": {}
  }
}
```

**사용처:** 색인에 저장된 문서 전체 확인. 집계(aggs)와 함께 사용할 때 기본 쿼리로 활용.

---

### 4.2 match

**정의:** 지정한 필드의 내용이 질의어와 매치되는 문서를 찾는 쿼리. 필드가 `text` 타입이라면 필드의 값도 질의어도 모두 애널라이저로 분석된다.

**동작 원리:** 질의어가 형태소 분석되어 여러 토큰으로 분리되고, 각 토큰을 역색인에서 검색한다. 기본 동작은 **OR 조건**이다.

```json
POST movie_search/_search
{
  "query": {
    "match": {
      "movieNm": "그대 장미"
    }
  }
}
// "그대" OR "장미" 로 분석되어 두 텀 중 하나라도 포함된 문서 반환
```

**AND 조건으로 변경:**
```json
{
  "query": {
    "match": {
      "movieNm": {
        "query": "자전차왕 엄복동",
        "operator": "and"
      }
    }
  }
}
```

**minimum_should_match:** OR 연산 시 최소 몇 개 이상의 텀이 매칭되어야 하는지 지정
```json
{
  "query": {
    "match": {
      "movieNm": {
        "query": "자전차왕 엄복동",
        "minimum_should_match": 2
      }
    }
  }
}
```

**fuzziness:** 레벤슈타인 편집 거리 알고리즘 기반 유사 검색. 알파벳에 유용하며 오타 교정에 활용.
```json
{
  "query": {
    "match": {
      "movieNmEn": {
        "query": "Fli High",
        "fuzziness": 1
      }
    }
  }
}
// "Fly High" 검색 가능
```

---

### 4.3 multi_match

**정의:** Match Query와 동일하지만 단일 필드가 아닌 여러 개의 필드를 대상으로 검색한다.

```json
POST movie_search/_search
{
  "query": {
    "multi_match": {
      "query": "가족",
      "fields": ["movieNm", "movieNmEn"]
    }
  }
}
```

**boost를 활용한 필드 가중치:**
```json
{
  "query": {
    "multi_match": {
      "query": "Fly",
      "fields": ["movieNm^3", "movieNmEn"]
    }
  }
}
// movieNm 필드에서 매치되면 스코어에 3을 곱함
```

---

### 4.4 term / terms

**정의:**
- `term`: 지정한 필드의 값이 질의어와 **정확히 일치**하는 문서를 찾는 쿼리. 별도의 분석 작업을 수행하지 않는다.
- `terms`: term과 동일하나 질의어를 여러 개 지정 가능. 하나 이상 일치하면 검색 결과에 포함.

**왜 필요한가:** `match` 쿼리는 텍스트를 분석하기 때문에 keyword 타입 필드에는 적합하지 않다. keyword 데이터 타입을 정확히 검색하려면 `term`을 사용해야 한다.

**동작 원리 (바이블):**
- `keyword` 타입 필드: 필드 값도 질의어도 같은 노멀라이저 처리를 거치므로 직관적으로 사용 가능
- `text` 타입 필드: 질의어는 노멀라이저 처리를 거치지만, 필드 값은 애널라이저로 분석한 역색인을 이용. 분석 결과 단일 텀이 생성됐고 그 값이 완전히 같은 경우에만 매칭

```json
POST movie_search/_search
{
  "query": {
    "term": {
      "genreAlt": "코미디"
    }
  }
}
```

```json
{
  "query": {
    "terms": {
      "fieldName": ["hello", "world"]
    }
  }
}
```

> **주의:** 영문의 경우 대소문자가 다르면 검색되지 않는다.

---

### 4.5 range

**정의:** 지정한 필드의 값이 특정 범위 내에 있는 문서를 찾는 쿼리.

**범위 연산자:**
| 연산자 | 의미 |
|---|---|
| `gt` | greater than (초과) |
| `lt` | less than (미만) |
| `gte` | greater than or equal to (이상) |
| `lte` | less than or equal to (이하) |

```json
POST movie_search/_search
{
  "query": {
    "range": {
      "prdtYear": {
        "gte": "2016",
        "lte": "2017"
      }
    }
  }
}
```

**date 타입 날짜 계산식:**
```json
{
  "query": {
    "range": {
      "dateField": {
        "gte": "2019-01-15T00:00:00.000Z||+36h/d",
        "lte": "now-3h/d"
      }
    }
  }
}
// now: 현재 시각, ||: 날짜 문자열 마지막에 붙여 계산식 파싱
// +/-: 더하거나 빼는 연산, /: 버림 연산 (예: /d = 날짜 단위 이하 버림)
```

> **주의:** 문자열 필드를 대상으로 한 range 쿼리는 부하가 큰 쿼리로 분류된다. `search.allow_expensive_queries: false` 설정으로 차단 가능.

---

### 4.6 bool

**정의:** 여러 쿼리를 조합하여 검색하는 복합 쿼리(Compound Query). `must`, `must_not`, `filter`, `should` 4가지 조건절을 사용한다.

**왜 필요한가:** 관계형 데이터베이스의 WHERE절에서 AND/OR/NOT을 조합하는 것처럼, 엘라스틱서치에서도 여러 조건을 복합적으로 조합해야 하는 경우가 있다.

**조건절 비교 (실무가이드):**
| Elasticsearch | SQL | 설명 |
|---|---|---|
| `must: [필드]` | `AND 컬럼 == 조건` | 반드시 조건에 만족하는 문서만 검색 |
| `must_not: [필드]` | `AND 컬럼 != 조건` | 조건을 만족하지 않는 문서 검색 |
| `should: [필드]` | `OR 컬럼 = 조건` | 여러 조건 중 하나 이상을 만족하는 문서 검색 |
| `filter: [필드]` | `컬럼 IN (조건)` | 조건을 포함하는 문서 출력, 스코어 정렬 없음 |

**Query Context vs Filter Context:**
- `must`, `should` → **Query Context** (점수 계산 O)
- `filter`, `must_not` → **Filter Context** (점수 계산 X, 캐시 활용)

```json
POST movie_search/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "repGenreNm": "코미디" } },
        { "match": { "repNationNm": "한국" } }
      ],
      "must_not": [
        { "match": { "typeNm": "단편" } }
      ],
      "should": [
        { "match": { "field4": "elasticsearch" } }
      ],
      "filter": [
        { "term": { "field3": true } }
      ],
      "minimum_should_match": 1
    }
  }
}
```

> `minimum_should_match` 기본값은 1이며, 이 값이 1이라면 `should`는 OR 조건과 같다.

---

### 4.7 prefix / wildcard / regexp

**prefix:**
- 필드의 값이 지정한 질의어로 시작하는 문서를 찾는 쿼리
- 역색인된 텀을 스캔하여 일치하는 텀 탐색

```json
POST movie_search/_search
{
  "query": {
    "prefix": {
      "movieNm": "자전차"
    }
  }
}
```

서비스 호출 용도로 사용하려면 매핑에 `index_prefixes` 설정으로 미리 색인:
```json
"prefixField": {
  "type": "text",
  "index_prefixes": {
    "min_chars": 3,
    "max_chars": 5
  }
}
```

**wildcard:**
- 와일드카드와 일치하는 구문을 찾는 쿼리. 입력된 검색어는 형태소 분석이 이루어지지 않음
- `*`: 문자의 길이와 상관없이 일치하는 모든 문서
- `?`: 지정된 위치의 한 글자가 다른 경우의 문서

```json
{
  "query": {
    "wildcard": {
      "typeNm": "장?"
    }
  }
}
```

> **경고:** 와일드카드 검색은 매우 무겁고 위험하다. 와일드카드 문자가 앞에 오는 쿼리(`*ello`)는 색인된 전체 term을 가지고 검색해야 하므로 클러스터 전체를 다운시킬 수도 있다. `search.allow_expensive_queries: false`로 차단 가능.

---

### 4.8 exists

**정의:** 지정한 필드를 포함한(null이 아닌 값이 있는) 문서를 검색한다.

```json
{
  "query": {
    "exists": {
      "field": "fieldName"
    }
  }
}
```

**필드가 없거나 null인 문서를 찾으려면** `bool.must_not`과 조합:
```json
{
  "query": {
    "bool": {
      "must_not": {
        "exists": {
          "field": "fieldName"
        }
      }
    }
  }
}
```

---

### 4.9 nested

**정의:** Nested 데이터 타입의 필드를 검색할 때 사용하는 쿼리. 분산 시스템에서 SQL의 JOIN과 유사한 기능을 수행한다.

**왜 필요한가:** 문서 내부에 다른 문서(Child)가 존재하는 구조에서 Child 필드 조건으로 Parent 문서를 찾아야 할 때 사용한다.

**매핑 설정:**
```json
PUT movie_nested
{
  "mappings": {
    "_doc": {
      "properties": {
        "repGenreNm": { "type": "keyword" },
        "companies": {
          "type": "nested",
          "properties": {
            "companyCd": { "type": "keyword" },
            "companyNm": { "type": "keyword" }
          }
        }
      }
    }
  }
}
```

**Nested Query:**
```json
GET movie_nested/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "repGenreNm": "멜로/로맨스" } },
        {
          "nested": {
            "path": "companies",
            "query": {
              "bool": {
                "must": [
                  { "term": { "companies.companyCd": "20173401" } }
                ]
              }
            }
          }
        }
      ]
    }
  }
}
```

> **주의:** 엘라스틱서치는 성능상의 이유로 Parent 문서와 Child 문서를 동일한 샤드에 저장한다. 특정 Parent에 포함된 Child 문서가 비정상적으로 커지면 샤드 크기 분배 문제가 발생할 수 있다.

---

### 4.10 constant_score

**정의:** 하위 `filter` 부분에 지정한 쿼리를 필터 문맥에서 검색하는 쿼리. 매치된 문서의 유사도 점수는 일괄적으로 1로 지정된다.

**왜 필요한가:** 특정 조건을 만족하는 문서를 동일한 점수로 처리하고 싶을 때 사용. 점수 계산이 불필요한 쿼리를 명시적으로 필터 문맥으로 실행한다.

```json
GET [인덱스 이름]/_search
{
  "query": {
    "constant_score": {
      "filter": {
        "term": {
          "fieldName": "hello"
        }
      }
    }
  }
}
```

---

## 5. 검색 결과 정렬

### 정의

`sort` 파라미터를 사용해 검색 결과를 특정 기준으로 정렬한다. 기본 정렬은 `_score` 내림차순이다.

### 동작 원리

```json
POST movie_search/_search
{
  "query": {
    "term": { "repNationNm": "한국" }
  },
  "sort": {
    "prdtYear": { "order": "asc" }
  }
}
```

**다중 정렬:** 정렬 기준이 동일한 경우 추가 정렬 기준 적용
```json
{
  "sort": [
    { "prdtYear": { "order": "asc" } },
    { "_score": { "order": "desc" } }
  ]
}
```

### 정렬 가능 타입과 불가 타입

| 정렬 가능 | 정렬 불가 |
|---|---|
| 숫자 타입, date, boolean, keyword | text 타입 (fielddata=true 설정 시 가능하나 권장하지 않음) |

**특수 정렬 기준:**
- `_score`: 유사도 점수 기준 정렬
- `_doc`: 문서 번호 순서 정렬 (정렬 순서 무관, scroll API와 함께 많이 사용)

> **성능 팁 (바이블):** 정렬 수행 중에는 필드의 값이 메모리에 올라간다. 정렬 대상 필드는 메모리를 적게 차지하는 `integer`, `short`, `float` 등의 타입으로 설계하는 것이 좋다. 또한 정렬 옵션에 `_score`가 포함되지 않은 경우 엘라스틱서치는 유사도 점수를 계산하지 않는다.

---

## 6. 페이지네이션

### 정의

검색 결과를 나누어 제공하는 기법. 엘라스틱서치는 세 가지 방식을 제공한다.

### 6.1 from / size

**기본 사용:**
```json
{
  "from": 0,
  "size": 5,
  "query": { ... }
}
```

**문제점:**
1. **성능 이슈:** 엘라스틱서치는 특정 문서만 선택적으로 읽는 것이 아니라 모든 데이터를 읽은 후 필터링하여 제공. 페이지 번호가 높아질수록 쿼리 비용이 증가. 예를 들어 2페이지(from=5, size=5)를 요청하면 내부적으로 상위 10건의 문서를 읽어야 한다.
2. **일관성 이슈:** 이전 페이지 검색과 다음 페이지 검색 사이에 새로운 문서가 색인되거나 삭제될 수 있어 중복/누락 발생 가능.

> `from + size`의 합이 기본값 **1만**을 넘어서는 검색은 거부된다. `index.max_result_window` 설정으로 변경 가능하나 권장하지 않는다.

### 6.2 scroll

**정의:** 검색 조건에 매칭되는 전체 문서를 모두 순회해야 할 때 적합한 방식. 검색 문맥(search context)이 유지되어 중복/누락이 발생하지 않는다.

```json
# 첫 번째 검색 (검색 문맥 유지 시간 지정)
GET [인덱스]/_search?scroll=1m
{
  "size": 1000,
  "sort": ["_doc"],  // scroll 성능 최적화
  "query": { ... }
}

# 이후 검색 (scroll_id 사용)
GET _search/scroll
{
  "scroll_id": "FGluY2xlZGV...",
  "scroll": "1m"
}

# 사용 후 명시적 삭제
DELETE _search/scroll
{
  "scroll_id": "FGluY2xlZGV..."
}
```

> **주의:** scroll은 서비스에서 지속적으로 호출하는 것을 의도하고 만들어진 기능이 아니다. 주로 대량의 데이터를 다른 스토리지로 이전하거나 덤프하는 용도로 사용한다.

### 6.3 search_after

**정의:** 서비스에서 사용자가 검색 결과를 요청하고 페이지네이션을 제공하는 용도에 가장 적합한 방식. `sort`를 지정해야 하며 동점 제거(tiebreaker)용 필드가 필요하다.

```json
# 첫 번째 검색
GET kibana_sample_data_ecommerce/_search
{
  "size": 20,
  "query": { "term": { "currency": { "value": "EUR" } } },
  "sort": [
    { "order-date": "desc" },
    { "order-id": "asc" }  // 동점 제거용
  ]
}

# 응답의 마지막 문서 sort 값을 search_after에 넣어 다음 페이지 요청
GET kibana_sample_data_ecommerce/_search
{
  "size": 20,
  "query": { ... },
  "search_after": [1674333590000, "591924"],
  "sort": [
    { "order-date": "desc" },
    { "order-id": "asc" }
  ]
}
```

> `_id` 필드는 `doc_values`가 꺼져 있어 정렬 시 많은 메모리를 사용하므로 동점 제거용으로 사용하지 말 것. `_id` 값과 동일한 값을 별도 필드에 저장해 사용하는 편이 낫다.

**point in time (PIT) API와 조합:** 인덱스 상태를 특정 시점으로 고정하여 일관된 페이지네이션 제공
```json
POST kibana_sample_data_ecommerce/_pit?keep_alive=1m
# -> pit id 반환

GET _search
{
  "size": 20,
  "pit": { "id": "697qAwEca...", "keep_alive": "1m" },
  "sort": [ { "order_date": "desc" } ]
  // pit 사용 시 인덱스 이름 지정 불필요
  // sort 필드 지정 시 _shard_doc 동점 제거 필드 자동 추가
}
```

**세 가지 방식 비교:**

| 방식 | 적합한 상황 | 성능 | 일관성 |
|---|---|---|---|
| from/size | 간단한 페이지네이션, 소규모 | 페이지 뒤로 갈수록 저하 | 낮음 (중복/누락 가능) |
| scroll | 전체 문서 순회, 데이터 이전/덤프 | 검색 문맥 유지 비용 | 높음 (문맥 유지) |
| search_after | 서비스 페이지네이션 | 높음 | PIT 조합 시 높음 |

---

## 7. \_source 필드 제어

### 정의

검색 결과에서 반환할 필드를 선택적으로 지정하는 옵션. 기본값은 모든 필드를 포함한다.

### 왜 필요한가

필요하지 않은 필드를 제외하면 네트워크 사용량을 줄여 응답 속도를 높일 수 있다.

```json
POST movie_search/_search
{
  "_source": ["movieNm"],
  "query": {
    "term": { "repNationNm": "한국" }
  }
}
```

**URI 검색에서는** `_source_includes` 파라미터 사용:
```
?_source_includes=movieCd,movieNm,movieNmEn
```

---

## 8. 관련도 점수 (BM25)

### 정의

엘라스틱서치는 루씬의 BM25(Best Match 25) 알고리즘을 기반으로 검색 결과의 관련도 점수(relevance score)를 계산한다. BM25는 TF-IDF의 개선 버전이다.

### 왜 필요한가

검색 결과를 단순히 일치 여부로만 나열하면 품질이 낮다. 어떤 문서가 질의어와 얼마나 관련이 있는지 수치화하여 랭킹을 결정해야 최상위 결과를 정확하게 제공할 수 있다.

### 동작 원리

**TF-IDF 기본 개념:**
- **TF (Term Frequency, 텀 빈도):** 특정 텀이 문서 내에 얼마나 자주 등장하는가. 많이 등장할수록 관련성이 높다고 판단.
- **IDF (Inverse Document Frequency, 역문서 빈도):** 전체 문서에서 특정 텀이 얼마나 흔하게 등장하는가. 드물게 등장할수록 구별 능력이 높아 점수가 높다.

**BM25가 TF-IDF를 개선한 점:**
- TF가 증가할수록 점수가 무한정 높아지는 문제(TF saturation)를 조정 파라미터 `k1`으로 완화
- 문서 길이에 따른 정규화를 파라미터 `b`로 조정 (긴 문서는 자연히 TF가 높아지므로 불리하지 않게 보정)

**샤드 레벨 계산 (실무가이드 설명):**
- 엘라스틱서치는 기본적으로 각 샤드 레벨에서 점수 계산을 끝낸다 (`query_then_fetch`)
- 샤드 수가 적을 때 점수 계산이 약간 부정확할 수 있음
- `dfs_query_then_fetch`로 검색하면 모든 샤드의 정보를 모아 글로벌하게 계산하여 정확도 향상, 성능 저하

**Explain API로 점수 계산 확인:**
```json
POST movie_search/_doc/8/_explain
{
  "query": {
    "term": { "prdtYear": 2017 }
  }
}

# 결과 예시
{
  "matched": true,
  "explanation": {
    "value": 1.0,
    "description": "prdtYear:[2017 TO 2017]",
    "details": [...]
  }
}
```

**bool 쿼리에서 점수 디버깅:**
```json
GET my_index3/_search?explain=true
{
  "query": {
    "bool": {
      "must": [
        { "term": { "field1": { "value": "hello" } } },
        { "term": { "field2": { "value": "world" } } }
      ]
    }
  }
}
// 응답의 _explanation에서 각 하위 쿼리 점수 계산 과정 확인 가능
```

> **explain 주의사항:** explain 옵션을 사용하면 내부적으로 쿼리를 덜 최적화해 수행하므로 일반 검색보다 성능이 하락한다. 서비스에서 일상적으로 사용하지 말고 디버깅 용도로만 사용할 것.

### 설계 트레이드오프

| 상황 | 권장 방식 |
|---|---|
| 랭킹이 중요한 검색 | Query Context (`must`, `should`) |
| 조건 필터링만 필요 | Filter Context (`filter`, `must_not`) |
| 점수 계산 정확도 우선 | `dfs_query_then_fetch` |
| 검색 성능 우선 | `query_then_fetch` (기본값) |
| 특정 필드 점수 강조 | `boost` 파라미터 또는 `multi_match` 필드 가중치 |

### 관련 개념
- `../01-핵심-아키텍처/concepts.md` — 역색인, 샤드 구조
- `../03-분석기/concepts.md` — 토크나이저, 텀 생성 과정
- [Query Context vs Filter Context](#2-query-context-vs-filter-context)

---

*최종 업데이트: 2026-03-03*
