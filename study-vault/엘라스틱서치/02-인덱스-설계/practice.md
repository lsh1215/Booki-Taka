# 인덱스 설계 연습 문제

> 난이도: ★ 기초 / ★★ 응용 / ★★★ 심화

---

## 문제 1 ★

엘라스틱서치에서 인덱스 생성 후 변경할 수 없는 설정 하나와 변경 가능한 설정 두 가지를 각각 고르시오.

<details>
<summary>정답 보기</summary>

**변경 불가**: `number_of_shards`

샤드 수는 데이터가 저장되는 물리적 분산 단위이며, 이미 색인된 데이터가 특정 샤드에 분산되어 있으므로 사후 변경이 불가능하다. 변경이 필요하면 인덱스를 삭제하고 새로 만들거나 reindex API를 사용해야 한다.

**변경 가능**:
- `number_of_replicas`: 복제본 수는 운영 중에도 `PUT /index/_settings`로 변경 가능.
- `refresh_interval`: 색인 후 검색에 노출되는 주기도 운영 중 변경 가능. `-1`로 설정하면 자동 refresh 비활성화.

</details>

---

## 문제 2 ★

다음 두 매핑을 보고 각각 어떤 필드에 적합한지 설명하고, `"Hello, World!"` 값이 색인됐을 때 `"hello"` 검색어로 히트 여부를 판단하시오.

```json
{ "fieldA": { "type": "text" } }
{ "fieldB": { "type": "keyword" } }
```

<details>
<summary>정답 보기</summary>

**fieldA (text 타입)**:
- 적합한 필드: 영화 제목, 상품 설명, 본문처럼 전문 검색이 필요한 자연어 필드.
- 색인 과정: `"Hello, World!"` → standard 애널라이저 → `hello`, `world` 두 개의 텀으로 분리 후 역색인 구성.
- `"hello"` 검색 → **히트**. match 쿼리는 검색 질의어도 동일한 애널라이저로 분석하므로 `hello` 텀이 역색인에서 발견된다.

**fieldB (keyword 타입)**:
- 적합한 필드: 상태 코드, 카테고리명, 영화 장르처럼 정확한 값으로 필터링·집계·정렬이 필요한 필드.
- 색인 과정: `"Hello, World!"` → 노멀라이저(기본: 없음) → `"Hello, World!"` 단일 텀 그대로 역색인 구성.
- `"hello"` 검색 → **미스**. `"Hello, World!"` 전체 문자열로만 검색 가능.

</details>

---

## 문제 3 ★

아래 상황에서 동적 매핑을 사용했을 때 발생하는 문제를 설명하시오.

```json
// 첫 번째 문서
{ "movieCd": "20173732", "movieNm": "살아남은 아이" }

// 두 번째 문서
{ "movieCd": 20180001, "movieNm": "기생충" }
```

<details>
<summary>정답 보기</summary>

첫 번째 문서의 `movieCd` 값은 `"20173732"` (문자열)이므로 동적 매핑이 `text` 또는 `keyword` 타입으로 매핑한다.

두 번째 문서의 `movieCd`는 `20180001` (숫자)이다. 이미 문자열 타입으로 매핑된 필드에 숫자가 들어오면 **색인에 실패**한다.

반대로 첫 번째 문서의 `movieCd`가 숫자라면 `integer`나 `long`으로 매핑된다. 이후 문자열이 들어오면 역시 색인 실패한다.

핵심: **한 번 생성된 매핑의 타입은 변경할 수 없다.** 실무에서는 명시적 매핑을 사용해야 한다.

</details>

---

## 문제 4 ★

`refresh_interval`을 명시적으로 설정하지 않았을 때 엘라스틱서치의 기본 동작을 설명하시오. 또한 대용량 배치 색인 시 이 설정을 어떻게 변경하는 것이 유리한가?

<details>
<summary>정답 보기</summary>

**기본 동작**:
- 매 1초마다 refresh를 수행하지만, 마지막 검색 쿼리 수신 후 30초가 지나도록 검색이 없으면 다음 검색 요청이 올 때까지 refresh를 수행하지 않는다. (`index.search.idle.after` 설정으로 30초를 변경 가능)

**대용량 배치 색인 최적화**:
- `refresh_interval: -1` 로 설정하면 자동 refresh를 완전히 비활성화하여 쓰기 성능을 극대화할 수 있다.
- 색인 완료 후 수동으로 `POST /index/_refresh`를 호출하거나 `refresh_interval`을 원래 값으로 복원한다.
- 마찬가지로 `number_of_replicas: 0` 으로 설정해 복제 비용을 줄이고, 작업 후 복원하는 패턴도 함께 사용한다.

</details>

---

## 문제 5 ★★

다음 매핑에서 `spec` 필드를 `object` 타입이 아닌 `nested` 타입으로 지정해야 하는 이유를 설명하고, 해당 타입을 검색할 때 주의사항을 서술하시오.

```json
{
  "spec": [
    { "cores": 4, "memory": 128 },
    { "cores": 6, "memory": 64  }
  ]
}
```
쿼리 조건: `cores=6` AND `memory=128` 인 문서는 없어야 한다.

<details>
<summary>정답 보기</summary>

**object 타입의 문제**:
object 타입으로 배열을 저장하면 각 객체의 필드가 평탄화(flatten)된다.
```
spec.cores = [4, 6]
spec.memory = [128, 64]
```
이 상태에서 `cores=6 AND memory=128` 쿼리를 실행하면 **히트**된다. `cores` 배열에 6이 있고 `memory` 배열에 128이 있기 때문이다. 객체 간 관계가 사라진다.

**nested 타입의 동작**:
각 배열 원소를 루씬 내부에서 별도의 숨겨진 문서로 저장한다. `{ cores:6, memory:128 }` 인 원소가 없으므로 `cores=6 AND memory=128` 쿼리는 **미스**된다.

**주의사항**:
1. nested 타입은 일반 `bool` 쿼리로 검색할 수 없다. 반드시 `nested` 쿼리로 감싸야 한다.
   ```json
   { "nested": { "path": "spec", "query": { "bool": { ... } } } }
   ```
2. 내부적으로 숨겨진 문서를 생성하므로 object보다 성능 비용이 크다.
3. 인덱스당 nested 타입 최대 50개, 문서당 nested 객체 최대 10,000개 제한이 있다.

</details>

---

## 문제 6 ★★

다음 요구사항에 맞게 인덱스 매핑을 설계하시오.

- 인덱스명: `article_search`
- 필드:
  - `title`: 한국어 전문 검색 대상, 정렬도 필요
  - `status`: 필터링 및 집계 대상 (`published`, `draft` 등 고정 값)
  - `view_count`: 집계 (평균, 합계) 대상
  - `published_at`: 날짜 범위 검색 대상
  - `author_id`: 집계 및 정확 일치 필터링
- 초기 샤드 3개, 복제본 1개

<details>
<summary>정답 보기</summary>

```json
PUT /article_search
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "standard",
        "fields": {
          "keyword": { "type": "keyword" }
        }
      },
      "status": {
        "type": "keyword"
      },
      "view_count": {
        "type": "long"
      },
      "published_at": {
        "type": "date"
      },
      "author_id": {
        "type": "keyword"
      }
    }
  }
}
```

**설계 이유**:
- `title`: text로 전문 검색을 지원하되, 정렬에는 분석되지 않은 원문이 필요하므로 `keyword` 서브필드(멀티필드)를 추가한다. 한국어 형태소 분석이 필요하다면 `standard` 대신 `nori` 같은 한국어 분석기로 교체한다.
- `status`: 정해진 값만 가지는 카테고리형 필드는 `keyword`. 집계·필터링 모두 가능.
- `view_count`: 숫자 집계(avg, sum)를 위해 numeric 타입. `doc_values`가 기본 활성화되어 효율적 집계 가능.
- `published_at`: 날짜 범위 쿼리를 위해 `date` 타입.
- `author_id`: 집계·필터링 대상이므로 `keyword`. text로 분석이 불필요.

</details>

---

## 문제 7 ★★

다음 두 시나리오에서 라우팅 설정이 검색 성능에 어떤 영향을 미치는지 설명하고, 라우팅을 잘못 설계했을 때 발생할 수 있는 문제를 두 가지 서술하시오.

- 시나리오 A: 5개 샤드, 라우팅 미지정
- 시나리오 B: 5개 샤드, `login_id`를 라우팅 값으로 지정

<details>
<summary>정답 보기</summary>

**성능 비교**:

시나리오 A: 검색 시 5개 샤드 전체에 요청이 분산된다. 응답의 `_shards.total = 5`. 데이터가 많을수록 모든 샤드의 처리 비용이 누적된다.

시나리오 B: 특정 `login_id`의 댓글을 검색할 때 `?routing=login_id`를 지정하면 해당 사용자의 문서가 있는 단일 샤드에만 요청이 간다. 응답의 `_shards.total = 1`. 데이터 규모가 클수록 성능 차이가 극명해진다.

**잘못된 라우팅 설계의 문제**:

1. **샤드 불균형(Hot Shard)**: 특정 값이 너무 많은 문서를 가지면 해당 샤드에 데이터가 쏠린다. 일부 샤드만 과부하가 걸린다.

2. **_id 고유성 파괴**: 라우팅 값이 다르면 같은 인덱스 내에서 동일한 `_id`를 가진 문서가 서로 다른 샤드에 중복 존재할 수 있다. 라우팅 값 없이 단건 조회를 하면 잘못된 샤드를 대상으로 조회하여 문서를 찾지 못하는 현상이 발생한다.

**방어 방법**: 인덱스 매핑에 `"_routing": { "required": true }` 설정으로 라우팅 값을 강제화한다.

</details>

---

## 문제 8 ★★

인덱스 템플릿과 컴포넌트 템플릿의 관계를 설명하고, 아래 요구사항을 컴포넌트 템플릿 방식으로 구성하시오.

요구사항:
- 로그 인덱스(`logs-*`): `timestamp` 필드(date), 샤드 2개, 복제본 1개
- 메트릭 인덱스(`metrics-*`): `timestamp` 필드(date), 샤드 5개, 복제본 1개
- 두 인덱스 모두 `timestamp` 매핑은 동일하게 재사용

<details>
<summary>정답 보기</summary>

**인덱스 템플릿 vs 컴포넌트 템플릿**:
- 인덱스 템플릿: 인덱스 이름 패턴에 설정을 직접 담는 최종 템플릿.
- 컴포넌트 템플릿: 설정의 재사용 가능한 블록. 여러 인덱스 템플릿에서 `composed_of`로 가져다 쓴다.

**구성**:

```json
// 공통 매핑 컴포넌트
PUT _component_template/common_timestamp
{
  "template": {
    "mappings": {
      "properties": {
        "timestamp": { "type": "date" }
      }
    }
  }
}

// 로그용 샤드 설정 컴포넌트
PUT _component_template/log_shard_settings
{
  "template": {
    "settings": {
      "number_of_shards": 2,
      "number_of_replicas": 1
    }
  }
}

// 메트릭용 샤드 설정 컴포넌트
PUT _component_template/metric_shard_settings
{
  "template": {
    "settings": {
      "number_of_shards": 5,
      "number_of_replicas": 1
    }
  }
}

// 로그 인덱스 템플릿
PUT _index_template/logs_template
{
  "index_patterns": ["logs-*"],
  "priority": 10,
  "composed_of": ["common_timestamp", "log_shard_settings"]
}

// 메트릭 인덱스 템플릿
PUT _index_template/metrics_template
{
  "index_patterns": ["metrics-*"],
  "priority": 10,
  "composed_of": ["common_timestamp", "metric_shard_settings"]
}
```

**주의**: 엘라스틱서치 7.9+에는 `logs-*-*`와 `metrics-*-*` 패턴으로 priority 100인 빌트인 템플릿이 존재한다. 커스텀 템플릿을 우선 적용하려면 priority를 101 이상으로 설정해야 한다.

</details>

---

## 문제 9 ★★★

아래 두 가지 매핑 파라미터의 차이를 설명하고, text 필드에서 집계를 수행해야 하는 상황에서의 권장 접근법을 서술하시오.

- `doc_values`
- `fielddata`

<details>
<summary>정답 보기</summary>

**doc_values**:
- 디스크 기반 컬럼 지향 자료 구조. text, annotated_text를 제외한 거의 모든 타입에서 기본 활성화.
- 파일 시스템 캐시를 활용하므로 메모리 부담이 낮다.
- 정렬·집계·스크립트 작업 시 "문서 → 값" 방향 조회를 위해 사용.

**fielddata**:
- text 타입 전용 메모리(힙) 기반 캐시. 기본 비활성화.
- 활성화 시 역색인 전체를 힙에 올리므로 OOM 위험이 크다.
- 메모리에 올라오는 내용은 이미 분석된 토큰(텀)이므로 원본 값이 아닌 분석 결과로 집계된다.

**text 필드 집계가 필요한 상황에서의 권장 접근법**:

1. **멀티필드(권장)**: text 필드에 keyword 서브필드를 추가한다. keyword 서브필드는 doc_values가 기본 활성화되어 있으므로 집계·정렬이 효율적이다.
   ```json
   "content": {
     "type": "text",
     "fields": { "keyword": { "type": "keyword" } }
   }
   ```
   집계는 `content.keyword`를 대상으로 수행.

2. **fielddata 활성화(비권장)**: 어쩔 수 없는 상황에서만 사용. 분석된 토큰 기준 집계이므로 원하는 결과가 아닐 수 있고 OOM 위험이 존재한다.
   ```json
   "content": { "type": "text", "fielddata": true }
   ```

결론: text 필드 집계가 필요하다면 설계 단계부터 멀티필드로 구성하는 것이 올바른 접근이다.

</details>

---

## 문제 10 ★★★

다음 동적 템플릿을 해석하고, `description_text` 필드와 `category_keyword` 필드가 각각 어떤 타입으로 매핑될지 설명하시오. 또한 `"match_mapping_type": "string"`이 `long`이나 `integer`와 다른 점을 설명하시오.

```json
"dynamic_templates": [
  {
    "my_text": {
      "match_mapping_type": "string",
      "match": "*_text",
      "mapping": { "type": "text" }
    }
  },
  {
    "my_keyword": {
      "match_mapping_type": "string",
      "match": "*_keyword",
      "mapping": { "type": "keyword" }
    }
  }
]
```

<details>
<summary>정답 보기</summary>

**매핑 결과**:
- `description_text`: 데이터 타입이 문자열(string)이고 필드명이 `*_text` 패턴에 매칭 → **text 타입**으로 자동 매핑.
- `category_keyword`: 데이터 타입이 문자열(string)이고 필드명이 `*_keyword` 패턴에 매칭 → **keyword 타입**으로 자동 매핑.

**`match_mapping_type: "string"` vs 숫자 타입**:
- 동적 템플릿의 `match_mapping_type`은 JSON 파서가 값을 파싱한 결과 타입을 기준으로 한다.
- JSON 파서는 정수를 모두 `long`으로, 부동소수점을 모두 `double`로 인식한다. `integer`나 `float`를 개별적으로 구분하지 않는다.
- 따라서 `match_mapping_type`에 지정할 수 있는 값은 JSON 파서 수준의 큰 범주: `boolean`, `double`, `long`, `string`, `object`, `date` 이다.
- 예를 들어 `match_mapping_type: "long"`을 지정하면 정수처럼 보이는 모든 값에 적용되며, `integer` 타입만 골라서 적용할 수는 없다.

**실무 활용**: 동적 매핑을 사용하되 문자열 필드가 기본적으로 text+keyword 멀티필드로 생성되는 것을 막고 싶을 때, 동적 템플릿으로 필드명 패턴에 따라 타입을 제어하는 것이 효과적이다.

</details>

---

## 문제 11 ★★★

`number_of_shards: 5`로 생성된 인덱스에서 `routing=user_A`로 색인한 문서가 2번 샤드에 저장됐다. 이후 아래 세 가지 방식으로 해당 문서를 조회할 때 각각의 결과를 예측하고 이유를 설명하시오.

1. `GET /index/_doc/1` (라우팅 없음)
2. `GET /index/_doc/1?routing=user_A`
3. `GET /index/_search` (전체 검색, 라우팅 없음)

<details>
<summary>정답 보기</summary>

**배경**: 문서는 `hash("user_A") % 5 = 2` → 2번 샤드에 저장됨.

**1. `GET /index/_doc/1` (라우팅 없음)**:
- 라우팅 기본값은 `_id` = `1`.
- `hash("1") % 5`의 결과가 2가 아닌 다른 샤드(예: 0번 샤드)로 요청이 간다.
- 0번 샤드에는 해당 문서가 없으므로 **404 Not Found** 또는 `"found": false` 응답.

**2. `GET /index/_doc/1?routing=user_A`**:
- `hash("user_A") % 5 = 2` → 정확히 2번 샤드로 요청.
- 해당 문서가 있으므로 **정상 조회 성공**.

**3. `GET /index/_search` (전체 검색, 라우팅 없음)**:
- 검색은 모든 샤드(5개)를 대상으로 수행.
- 2번 샤드도 검색 대상에 포함되므로 문서가 **검색 결과에 포함됨**.

**핵심**: 단건 조회(GET /_doc)는 라우팅 값으로 지정된 단일 샤드에만 요청하므로 색인 시와 동일한 라우팅 값을 반드시 지정해야 한다. 검색(_search)은 기본적으로 전체 샤드를 대상으로 하므로 라우팅 없이도 문서를 찾을 수 있지만 성능상 비효율적이다.

</details>
