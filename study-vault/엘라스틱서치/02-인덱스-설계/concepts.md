# 인덱스 설계

> 출처: 엘라스틱서치 실무가이드 Ch3 (매핑 API, 메타 필드, 필드 데이터 타입) / 엘라스틱서치바이블 Ch3 (인덱스 설정, 매핑과 필드 타입, 템플릿, 라우팅)
> 태그: #index #mapping #field-type #template #routing #analyzer #doc-values #fielddata

## 이 토픽의 근본 문제

"어떤 필드에 어떤 타입을 얼마나 많은 샤드로 저장하고, 누가 어느 샤드에 접근할지를 색인 전에 결정해야 한다 — 한 번 정한 것은 바꿀 수 없다."

## 전체 구조

```
PUT /my_index
{
  "settings": {                     ← 1. 인덱스 설정
    "number_of_shards": 3,          ← 변경 불가
    "number_of_replicas": 1,        ← 변경 가능
    "refresh_interval": "1s"        ← 변경 가능
  },
  "mappings": {                     ← 2. 매핑 (스키마)
    "properties": {
      "title":   { "type": "text"    },   ← 전문검색
      "code":    { "type": "keyword" },   ← 정확일치/집계/정렬
      "count":   { "type": "integer" },
      "created": { "type": "date"    },
      "location":{ "type": "geo_point" },
      "spec":    { "type": "nested"  }    ← 독립적 객체 배열
    }
  }
}

색인 시 라우팅 결정:
  shard = hash(routing_value) % number_of_shards
  └ routing_value 기본값: _id
  └ 커스텀: ?routing=user_id

인덱스 템플릿: 인덱스 이름 패턴 매칭 → 자동 설정 적용
  _index_template (7.8+)
    └── composed_of: [컴포넌트 템플릿 A, 컴포넌트 템플릿 B]
  _template (레거시)
```

---

## 핵심 개념

### 인덱스 설정 (Index Settings)

**정의**: 인덱스 생성 시 지정하는 물리적 구성 — 샤드 수, 복제본 수, refresh 주기 등.

**왜 필요한가**: `number_of_shards`는 생성 후 변경이 불가능하다. 잘못 설정하면 데이터를 삭제하고 재색인하는 수밖에 없다. 복제본 수와 refresh_interval은 이후 변경 가능.

**핵심 파라미터**:

| 파라미터 | 기본값 | 변경 가능 | 역할 |
|---|---|---|---|
| `number_of_shards` | 1 | 불가 | 데이터를 몇 개 조각으로 분산할지 |
| `number_of_replicas` | 1 | 가능 | 각 샤드의 복제본 수 (0이면 복제 없음) |
| `refresh_interval` | 1s (암묵적) | 가능 | 색인 후 검색에 노출되기까지의 주기 |

**`refresh_interval` 세부 동작** (바이블 Ch3):
- 명시적으로 설정하지 않으면 기본 1초마다 refresh 수행
- 단, 마지막 검색 쿼리가 30초 이상 없으면 다음 검색 요청이 올 때까지 refresh 중단 (배치 색인 시 성능 이점)
- `null`로 설정하면 "명시 안 한 상태"로 복귀
- `-1`로 설정하면 주기적 refresh 완전 비활성화

**`number_of_replicas = 0` 활용**: 대용량 초기 데이터 마이그레이션 시 일시적으로 복제본을 없애 쓰기 성능을 높인다. 작업 후 원복 필요.

**설계 트레이드오프**:
- 샤드 수 많음 → 병렬 처리 증가 / 오버헤드 증가, 노드당 샤드 수 관리 필요
- 복제본 많음 → 읽기 성능·가용성 향상 / 디스크 사용량 증가, 쓰기 비용 증가
- refresh 짧음 → 색인 직후 검색 가능 / 더 잦은 세그먼트 병합, 쓰기 성능 저하

**관련 개념**: [라우팅](#라우팅-routing), [샤드 아키텍처](../01-핵심-아키텍처/concepts.md)

---

### 동적 매핑 vs 명시적 매핑

**정의**: 엘라스틱서치는 스키마리스(schema-less)를 지원한다. 매핑을 정의하지 않고 문서를 색인하면 필드 타입을 자동으로 추론하여 매핑을 생성한다. 이를 동적 매핑(Dynamic Mapping)이라 한다.

**왜 명시적 매핑이 필요한가**:
1. 동적 매핑은 첫 번째 문서의 데이터 타입을 기준으로 필드 타입을 결정한다. 첫 문서에 숫자가 들어오면 숫자 타입으로 매핑되며, 이후 문자열이 들어오면 색인 실패한다.
2. 한 번 생성된 매핑의 타입은 변경할 수 없다. 변경하려면 인덱스를 삭제하고 재생성해야 한다.
3. 동적 매핑은 모든 문자열 필드를 text + keyword 멀티필드로 생성하여 스토리지를 낭비한다.
4. 한국어 등 언어별 형태소 분석기를 자동으로 지정할 수 없다.

**동적 매핑 비활성화 방법** (실무가이드 Ch2):
- 전체 비활성화: `elasticsearch.yml`에 `action.auto_create_index: false`
- 인덱스 단위: 매핑에 `"dynamic": false`

**명시적 매핑 예시**:
```json
PUT /movie_search
{
  "settings": { "number_of_shards": 5, "number_of_replicas": 1 },
  "mappings": {
    "properties": {
      "movieCd":    { "type": "keyword" },
      "movieNm":    { "type": "text", "analyzer": "standard" },
      "prdtYear":   { "type": "integer" },
      "openDt":     { "type": "integer" },
      "directors":  {
        "properties": { "peopleNm": { "type": "keyword" } }
      }
    }
  }
}
```

**설계 트레이드오프**:
- 동적 매핑: 빠른 초기 설계, 실수 위험 큼, 실무에서 거의 미사용
- 명시적 매핑: 초기 설계 비용 있음, 안정적 운영, 실무 표준

**관련 개념**: [필드 데이터 타입](#주요-필드-데이터-타입), [동적 템플릿](#인덱스-템플릿--컴포넌트-템플릿--동적-템플릿)

---

### 주요 필드 데이터 타입

**정의**: 엘라스틱서치는 문서의 각 필드에 적절한 데이터 타입을 지정함으로써 색인·검색 방식을 결정한다.

#### keyword vs text (가장 중요한 구분)

**왜 필요한가**: 동일한 문자열이라도 "전문 검색이 필요한가(text)" vs "정확히 일치하는 값으로 필터·집계·정렬이 필요한가(keyword)"에 따라 역색인 구조가 완전히 다르다.

**동작 원리**:

```
색인되는 값: "Hello, World!"

text 타입 (애널라이저 적용)
  └─ standard analyzer
  └─ 역색인: hello | world
  └─ "hello" 검색 → 히트

keyword 타입 (노멀라이저 적용)
  └─ (기본: 아무것도 안 함)
  └─ 역색인: "Hello, World!" (단일 텀)
  └─ "hello" 검색 → 미스
  └─ "Hello, World!" 정확 일치만 히트
```

**실용 규칙**:
| 용도 | 타입 |
|---|---|
| 제목, 본문, 설명 (전문 검색) | text |
| 코드, 상태값, 카테고리 (필터링·집계·정렬) | keyword |
| 둘 다 필요할 때 | 멀티필드 (text + keyword 서브필드) |

**멀티필드 예시** (실무가이드 Ch3):
```json
"movieComment": {
  "type": "text",
  "fields": {
    "keyword": { "type": "keyword" }
  }
}
```
이후 `movieComment` (전문검색), `movieComment.keyword` (집계/정렬) 로 각각 사용한다.

**관련 개념**: [doc_values vs fielddata](#매핑-파라미터-doc_values--fielddata--index--store)

---

#### Numeric 데이터 타입

**정의**: 정수 및 부동소수점 데이터를 저장하는 타입군. 데이터 크기에 맞는 타입을 선택해 색인·검색 효율을 높인다.

| 타입 | 설명 |
|---|---|
| `long` | 64비트 부호 있는 정수 |
| `integer` | 32비트 부호 있는 정수 |
| `short` | 16비트 부호 있는 정수 |
| `byte` | 8비트 부호 있는 정수 |
| `double` | 64비트 부동소수점 |
| `float` | 32비트 부동소수점 |
| `half_float` | 16비트 부동소수점 |

---

#### Date 데이터 타입

**정의**: 날짜/시간을 저장하는 타입. 내부적으로 UTC 밀리초 단위로 변환하여 저장한다.

**형식 지정**: 명시하지 않으면 기본 포맷 `"yyyy-MM-ddTHH:mm:ssZ"` 사용. 세 가지 표현 모두 내부에서 동일하게 처리된다:
- 문자열: `"2018-01-20"`, `"2018-04-20 10:50:00"`
- Long (밀리초): `1545699886797`

---

#### object vs nested

**정의**: JSON 계층 구조(중첩 객체)를 저장하는 타입.

**왜 필요한가**: object 타입으로 객체 배열을 저장하면 배열 내 각 객체의 필드가 평탄화(flatten)되어 저장된다. 그 결과 "어떤 객체의 어떤 필드"라는 관계가 사라져 의도치 않은 쿼리 결과가 발생한다.

**동작 원리**:
```
# object 타입 — 평탄화 문제
spec: [
  { cores: 4, memory: 128 },
  { cores: 6, memory: 64  }
]
→ 내부 저장: spec.cores=[4,6], spec.memory=[128,64]
→ "cores=6 AND memory=128" 쿼리 → 히트! (실제로는 같은 객체가 아닌데)

# nested 타입 — 각 객체를 루씬 내부 문서로 분리
→ "cores=6 AND memory=128" 쿼리 → 미스 (정확)
```

**nested 쿼리 필수**: nested 타입은 일반 쿼리가 아닌 전용 `nested` 쿼리로만 검색 가능하다.

**설계 트레이드오프**:
| | object | nested |
|---|---|---|
| 성능 | 가볍다 | 무겁다 (내부 숨겨진 문서 생성) |
| 검색 | 일반 쿼리 | 전용 nested 쿼리 필수 |
| 용도 | 배열 내 각 객체를 독립적으로 취급할 필요 없을 때 | 배열 내 각 객체를 독립적으로 취급해야 할 때 |

**nested 개수 제한** (바이블 Ch3):
- `index.mapping.nested_fields.limit`: 인덱스당 nested 타입 최대 수 (기본 50)
- `index.mapping.nested_objects.limit`: 한 문서당 nested 객체 최대 수 (기본 10000)
- 무리하게 높이면 OOM 위험

---

#### 그 외 특수 타입

| 타입 | 용도 |
|---|---|
| `geo_point` | 위도/경도 좌표 |
| `geo_shape` | 지도상의 점·선·도형 |
| `binary` | base64로 인코딩된 문자열 |
| `completion` | 자동완성 검색 전용 |
| `long_range`, `date_range`, `ip_range` | 범위 데이터 |

**관련 개념**: [매핑 파라미터](#매핑-파라미터-doc_values--fielddata--index--store)

---

### 매핑 파라미터 (doc_values / fielddata / index / store)

**정의**: 필드별로 색인·저장·집계 방식을 세밀하게 제어하는 파라미터.

#### doc_values

**정의**: 디스크 기반의 컬럼 지향 자료 구조. 정렬·집계·스크립트 작업을 효율적으로 수행하기 위해 파일 시스템 캐시를 활용한다.

**왜 필요한가**: 역색인은 "텀 → 문서"를 찾는 데 최적화되어 있다. 정렬·집계는 반대로 "문서 → 텀(값)"을 찾아야 한다. doc_values는 이 반대 방향 조회를 위한 별도 자료 구조다.

**지원 범위**: text, annotated_text를 제외한 거의 모든 타입 (keyword, numeric, date, boolean, geo_point 등). 기본값 true.

**비활성화**: 정렬·집계·스크립트에 사용하지 않을 필드는 false로 설정해 디스크를 절약할 수 있다.
```json
"notForSort": {
  "type": "keyword",
  "doc_values": false
}
```

#### fielddata

**정의**: text 타입 필드에서 정렬·집계·스크립트 작업이 필요할 때 사용하는 메모리 기반 캐시. 역색인 전체를 힙 메모리에 올린다.

**왜 필요한가**: text 타입은 doc_values를 사용할 수 없다. fielddata를 통해 text 필드에서도 집계 작업이 가능하다.

**문제점**: 역색인 전체를 메모리에 올리므로 힙을 순식간에 점유하여 OOM 위험. 또한 분석된 토큰(텀) 단위로 집계되므로 원본 값이 아닌 분석 결과를 기준으로 집계된다. **기본값 비활성화.**

**doc_values vs fielddata 비교**:
| | doc_values | fielddata |
|---|---|---|
| 적용 타입 | text 제외 대부분 | text, annotated_text |
| 동작 방식 | 디스크 기반, 파일 시스템 캐시 | 메모리(힙)에 역색인 전체 로드 |
| 기본값 | 활성화 | 비활성화 |
| OOM 위험 | 낮음 | 높음 |

#### index 파라미터

**정의**: 해당 필드를 역색인(검색 대상)으로 만들지 여부. 기본값 true.

**왜 필요한가**: 색인은 하되 검색 대상이 아닌 필드(예: 내부 처리용 메타데이터)는 false로 설정하면 색인 공간을 절약할 수 있다.

#### store 파라미터

**정의**: 필드 값을 `_source`와 별도로 저장할지 여부. 기본값 false.

**왜 필요한가**: `_source`를 비활성화하고 특정 필드만 별도 저장하는 특수 케이스에 사용.

**관련 개념**: [text vs keyword](#keyword-vs-text-가장-중요한-구분), [메타 필드](#메타-필드)

---

### 메타 필드

**정의**: 엘라스틱서치가 문서를 관리하기 위해 자동으로 생성하는 시스템 필드. 이름 앞에 `_`가 붙는다.

| 메타 필드 | 역할 |
|---|---|
| `_index` | 문서가 속한 인덱스 이름 |
| `_id` | 문서의 고유 식별 키. 인덱스 내에서 유일 (정확히는 샤드 단위로 고유성 보장) |
| `_source` | 색인 시 전달된 원본 JSON 문서 본문. reindex, 스크립트 작업에 활용 |
| `_routing` | 문서가 저장될 샤드를 결정하는 라우팅 값 |
| `_type` | 문서가 속한 매핑 타입 (ES 7.x 이후 `_doc`으로 고정) |
| `_uid` | `_type#_id` 조합. 내부용, 검색 시 노출 안 됨 |
| `_all` | 모든 필드 내용을 하나로 합친 메타 필드 (ES 6.0+ deprecated → `copy_to`로 대체) |

**`_source` 활용 예**: reindex 시 스크립트로 `ctx._source.fieldName` 형태로 원본 데이터에 접근·수정 가능.

**`_routing` 커스텀 예**:
```
PUT movie_routing/_doc/1?routing=ko
```
→ `hash("ko") % num_of_shards` 번 샤드에 저장.

**관련 개념**: [라우팅](#라우팅-routing)

---

### 인덱스 템플릿 / 컴포넌트 템플릿 / 동적 템플릿

**정의**: 인덱스를 생성할 때 사전에 정의한 설정(settings, mappings)을 자동으로 적용하는 기능.

**왜 필요한가**: 실무에서는 유사한 구조의 인덱스를 자주 새로 생성한다 (예: 날짜별 로그 인덱스). 매번 동일한 설정을 반복 입력하면 실수가 발생한다.

**인덱스 템플릿 (7.8+)**:
```json
PUT _index_template/my_template
{
  "index_patterns": ["pattern_test_index-*", "another_pattern_*"],
  "priority": 1,
  "template": {
    "settings": { "number_of_shards": 2, "number_of_replicas": 2 },
    "mappings": {
      "properties": { "myTextField": { "type": "text" } }
    }
  }
}
```
- `index_patterns`: 와일드카드로 패턴 매칭
- `priority`: 여러 템플릿이 매칭될 때 우선순위. 높을수록 우선.

**컴포넌트 템플릿**: 템플릿 간 중복되는 설정 조각을 재사용 가능한 블록으로 분리.
```json
PUT _component_template/timestamp_mappings
{ "template": { "mappings": { "properties": { "timestamp": { "type": "date" } } } } }

PUT _component_template/my_shard_settings
{ "template": { "settings": { "number_of_shards": 2, "number_of_replicas": 2 } } }

PUT _index_template/my_template2
{
  "index_patterns": ["timestamp_index-*"],
  "composed_of": ["timestamp_mappings", "my_shard_settings"]
}
```

**레거시 템플릿** (`_template`): 7.8 이전 방식. `_index_template` 대신 `_template` 사용. 우선순위가 낮아 인덱스 템플릿에 매칭되는 것이 없을 때만 적용된다.

**빌트인 인덱스 템플릿** (7.9+): `metrics-*-*`, `logs-*-*` 패턴에 priority 100으로 사전 정의됨. 해당 이름을 사용하려면 priority를 101 이상으로 설정한 커스텀 템플릿으로 덮어써야 한다.

**동적 템플릿**: 새 필드가 추가될 때 조건(데이터 타입·필드명 패턴)에 따라 매핑을 자동 생성하는 규칙. 매핑 내부에 정의 (`dynamic_templates` 키).

```json
"dynamic_templates": [
  { "my_text": {
      "match_mapping_type": "string",
      "match": "*_text",
      "mapping": { "type": "text" }
  }},
  { "my_keyword": {
      "match_mapping_type": "string",
      "match": "*_keyword",
      "mapping": { "type": "keyword" }
  }}
]
```
조건 키워드:
- `match_mapping_type`: JSON 파서가 감지한 타입 (boolean, double, long, string, object, date)
- `match` / `unmatch`: 필드 이름 패턴
- `path_match` / `path_unmatch`: 점 표기법 포함 전체 경로 매칭

**설계 트레이드오프**:
- 인덱스 템플릿: 인덱스 단위 자동화, 복잡한 설정 일관성 보장
- 컴포넌트 템플릿: 여러 템플릿 간 중복 제거, 관리 효율 향상
- 동적 템플릿: 사전 정의 없이 들어오는 새 필드에 유연하게 대응

**관련 개념**: [동적 매핑 vs 명시적 매핑](#동적-매핑-vs-명시적-매핑)

---

### 라우팅 (Routing)

**정의**: 문서가 저장될 샤드 번호를 결정하는 값. 색인·조회·업데이트·삭제·검색 모든 작업에 적용된다.

**동작 원리**:
```
shard_number = hash(routing_value) % number_of_primary_shards

기본값: routing_value = _id
커스텀: ?routing=user_id 또는 request body에 라우팅 지정
```

**왜 필요한가**: 라우팅을 지정하지 않으면 검색 시 모든 샤드를 대상으로 요청을 날린다. 관련 문서를 같은 샤드에 모아두면 검색 요청이 단일 샤드로만 가서 성능이 크게 향상된다.

```
라우팅 미지정: 5개 샤드 전체 검색 (_shards.total = 5)
라우팅 지정:   단일 샤드 검색 (_shards.total = 1)
```

**실무 패턴**: 특정 사용자가 작성한 문서를 자주 함께 조회한다면 사용자 ID를 라우팅 값으로 지정 → 같은 사용자의 문서가 같은 샤드에 모임 → 검색 성능 향상.

**주의점**:
1. 색인 시 라우팅 값을 지정했다면 조회·업데이트·삭제·검색에도 동일하게 지정해야 한다.
2. 라우팅 값이 다르면 같은 인덱스 내에서 동일한 `_id`를 가진 문서가 여러 샤드에 중복 존재할 수 있다. `_id` 고유성은 사용자 책임.
3. 문서 단건 조회(`GET /index/_doc/1`)는 샤드 하나를 지정해 수행하므로, 라우팅 값을 틀리게 지정하면 해당 문서가 있어도 "없음" 응답을 받을 수 있다.

**라우팅 필수화**: 인덱스 매핑에 아래와 같이 설정하면 라우팅 값 없는 요청이 실패한다.
```json
PUT my_index
{
  "mappings": {
    "_routing": { "required": true }
  }
}
```

**설계 트레이드오프**:
- 라우팅 지정: 검색 성능 대폭 향상 / 잘못 설계 시 샤드 불균형 (특정 샤드에 데이터 쏠림)
- 라우팅 미지정: 균일한 데이터 분산 / 모든 검색이 전체 샤드 대상

**관련 개념**: [인덱스 설정](#인덱스-설정-index-settings), [메타 필드 _routing](#메타-필드)
