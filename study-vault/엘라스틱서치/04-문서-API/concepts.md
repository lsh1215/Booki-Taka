# 04. 문서 API (Document API)

> 출처: 엘라스틱서치 실무가이드 Ch3 §3.5 / 엘라스틱서치바이블 Ch4 §4.1, §4.2, §8.1
> 태그: #index-api #get-api #update-api #delete-api #bulk-api #reindex #optimistic-concurrency

---

## 개념 지도

```
Document API
├── 단건 문서 API
│   ├── Index API        - 색인 (생성/덮어쓰기)
│   ├── Get API          - 조회
│   ├── Update API       - 부분 업데이트 / 스크립트 업데이트
│   └── Delete API       - 삭제
└── 복수 문서 API
    ├── Bulk API              - 배치 색인/업데이트/삭제
    ├── Multi Get API         - 배치 조회
    ├── Update By Query API   - 조건부 일괄 업데이트
    ├── Delete By Query API   - 조건부 일괄 삭제
    └── Reindex API           - 인덱스 간 문서 복사
```

관련 개념 링크: [인덱스 설계](../02-인덱스-설계/concepts.md) | [핵심 아키텍처](../01-핵심-아키텍처/concepts.md)

---

## 1. Index API

### 정의
특정 인덱스에 JSON 문서를 색인(추가/덮어쓰기)하는 API. 엘라스틱서치 문서 관리의 기본 진입점이다.

### 왜 필요한가
루씬 세그먼트는 불변이기 때문에 "수정"이 존재하지 않는다. 모든 쓰기는 새 문서를 색인하는 형태로 이뤄진다. Index API는 이 쓰기 진입점을 표준화된 REST 인터페이스로 제공한다.

### 동작 원리

```http
# _id를 직접 지정 (PUT): 기존 문서가 있으면 덮어씌운다
PUT [인덱스]/_doc/[_id]
{ "field": "value" }

# _id를 자동 생성 (POST): 항상 새 문서 생성, UUID 형태로 _id 부여
POST [인덱스]/_doc
{ "field": "value" }

# _create: 새 문서 생성만 허용. 같은 _id 문서가 있으면 409 에러
PUT [인덱스]/_create/[_id]
{ "field": "value" }
```

응답에는 `_index`, `_id`, `_version`, `result` (`created`/`updated`), `_seq_no`, `_primary_term`, `_shards` 가 포함된다.

#### op_type 파라미터
`PUT [인덱스]/_doc/1?op_type=create` 형태로 지정하면, 동일한 _id 문서가 이미 존재할 경우 색인을 실패시킨다. 멱등하게 "최초 생성" 의미를 강제할 때 사용한다.

#### refresh 파라미터
| 값 | 동작 |
|---|---|
| `true` | 색인 직후 샤드를 즉시 refresh하고 응답 반환 |
| `wait_for` | refresh될 때까지 대기 후 응답 반환 (refresh를 직접 유발하지 않음) |
| `false` (기본) | refresh 관련 동작 없음 |

> 주의: `true`나 `wait_for`는 너무 많은 작은 세그먼트를 생성해 성능을 저하시킨다. 대량 색인이 필요하면 Bulk API를 사용하고, 색인 직후 결과를 확인해야 하면 검색 API 대신 조회 API를 활용하도록 설계하는 것이 바람직하다. (바이블 §4.1.1)

#### 버전 관리
색인된 모든 문서는 `_version` 값을 가진다. 최초 1, 이후 업데이트/삭제마다 1씩 증가한다.

### 설계 트레이드오프
- `PUT /_doc/{id}` 는 idempotent하지 않다. 같은 요청을 반복하면 덮어쓰기가 발생한다.
- 진정한 "생성만" 의미가 필요하면 `_create` 엔드포인트를 사용해야 한다.
- 대량 색인 시 단건 Index API 반복은 HTTP 오버헤드가 매우 크다. Bulk API를 사용해야 한다.

### 관련 개념
- Bulk API, Refresh, 세그먼트, Translog, 낙관적 동시성 제어

---

## 2. Get API

### 정의
인덱스에서 특정 `_id`를 가진 문서 단건을 직접 조회하는 API.

### 왜 필요한가
검색 API는 refresh 이후에만 결과가 반영되지만, 조회 API는 translog에서도 데이터를 읽어올 수 있기 때문에 색인 직후에도 최신 내용을 확인할 수 있다. 역색인을 사용하지 않으므로 정확한 `_id`를 알고 있을 때 더 빠르고 확실하다.

### 동작 원리

```http
# 기본 조회: 메타데이터 + _source 반환
GET [인덱스]/_doc/[_id]

# 본문만 조회
GET [인덱스]/_source/[_id]
```

`_doc` 사용 시 `_index`, `_id`, `_version`, `_seq_no`, `_primary_term`, `found`, `_source` 가 포함된 응답이 반환된다.

#### 특정 필드만 조회
`_source_includes`와 `_source_excludes` 옵션으로 반환할 필드를 필터링할 수 있다. 와일드카드(`*`) 사용 가능.

```http
# p로 시작하는 필드와 views 필드만 포함
GET my_index2/_doc/1?_source_includes=p*,views

# 모든 필드에서 public 필드 제외
GET my_index2/_doc/1?_source_excludes=public

# 두 옵션 조합: p* 및 views에서 public 제외
GET my_index2/_doc/1?_source_includes=p*,views&_source_excludes=public
```

#### _source 비활성화 주의
매핑에서 `_source`를 비활성화하면 Update API를 사용할 수 없다. Update API는 내부적으로 `_source`를 읽어들인 뒤 업데이트를 수행하기 때문이다. (바이블 §4.1.3)

### 설계 트레이드오프
- 조회 API는 refresh 없이도 최신 데이터를 확인할 수 있다. 색인 후 즉시 결과를 확인해야 한다면 검색 API보다 조회 API를 활용하는 설계가 검색 성능에 유리하다.
- `_source`를 완전히 비활성화하면 조회 API의 일부 기능과 Update API를 사용할 수 없게 된다.

### 관련 개념
- `_source` 메타 필드, Translog, Update API

---

## 3. Update API

### 정의
지정한 문서 하나를 부분 업데이트(partial update)하거나 스크립트를 통해 동적으로 수정하는 API.

### 왜 필요한가
루씬 세그먼트는 불변이므로 "수정"은 기존 문서를 삭제하고 새 문서를 색인하는 형태로 이뤄진다. Update API는 이 과정을 자동화하면서, 변경된 필드만 지정하는 부분 업데이트를 편리하게 제공한다. 전체 문서 내용을 클라이언트가 들고 있지 않아도 된다.

### 동작 원리

```http
POST [인덱스]/_update/[_id]
```

내부 동작: 기존 문서의 `_source`를 읽어들임 → 업데이트 내용을 합침 → 새 문서로 재색인. 이 때문에 `_source`가 비활성화된 경우 Update API는 사용 불가.

#### doc을 이용한 부분 업데이트
```json
POST update_test/_update/1
{
  "doc": {
    "views": 36,
    "updated": "2019-01-23T17:00:01.567Z"
  }
}
```
기존 문서에 없는 필드를 `doc`에 기술하면 새 필드로 추가된다.

#### detect_noop
업데이트 전 실질적 변경 여부를 검사한다. 변경 사항이 없으면 (`noop`) 쓰기 작업을 수행하지 않는다. 기본값 `true`. 불필요한 디스크 I/O를 줄인다.

```json
POST update_test/_update/1
{
  "doc": { "views": 36 },
  "detect_noop": false
}
```

#### doc_as_upsert
기존 문서가 없을 때 새 문서를 생성하는 upsert 동작을 활성화한다. 기본값 `false`.

```json
POST update_test/_update/2
{
  "doc": { "views": 36 },
  "doc_as_upsert": true
}
```

#### script를 이용한 업데이트
painless 스크립트 언어를 사용해 조건 분기나 수치 증감 등 동적 업데이트가 가능하다. `doc`과 `script`를 동시에 기술하면 `script`만 적용된다.

```json
POST update_test/_update/1
{
  "script": {
    "source": "ctx._source.views += params.amount",
    "lang": "painless",
    "params": { "amount": 1 },
    "scripted_upsert": false
  }
}
```

스크립트에서 접근 가능한 컨텍스트 정보:

| 이름 | 내용 |
|---|---|
| `params` | 요청에서 지정한 params Map (읽기 전용) |
| `ctx._source` | 문서의 _source를 Map으로 반환 (변경 가능) |
| `ctx.op` | 작업 종류: `"index"`, `"none"`, `"delete"` |
| `ctx._now` | 현재 타임스탬프 (밀리초, 읽기 전용) |
| `ctx._index`, `ctx._id`, `ctx._type`, `ctx._routing`, `ctx._version` | 메타데이터 (읽기 전용) |

### 설계 트레이드오프
- Update API는 내부적으로 read → merge → reindex 3단계를 거친다. 사실상 색인 비용이 발생한다.
- 전체 문서를 교체하려면 Update API 대신 Index API(`PUT /_doc/{id}`)를 사용하는 것이 더 간단하다.
- `detect_noop`은 기본적으로 활성화하는 것이 좋다. 그러나 커스텀 플러그인에 `IndexingOperationListener`를 달 경우, noop 처리되면 리스너가 실행되지 않아 예상치 못한 동작이 발생할 수 있다. (바이블 §4.1.3)
- script 업데이트는 painless 사용을 공식 권장한다.

### 관련 개념
- `_source`, Translog, Bulk API, Update By Query, painless

---

## 4. Delete API

### 정의
지정한 인덱스에서 특정 `_id`의 문서 단건을 삭제하는 API.

### 왜 필요한가
루씬에서 삭제는 즉시 물리적으로 제거되지 않고 삭제 표시(tombstone)를 남긴다. 나중에 세그먼트 병합 시 실제로 제거된다. Delete API는 이 삭제 표시를 REST 인터페이스로 제공한다.

### 동작 원리

```http
DELETE [인덱스]/_doc/[_id]
```

성공 시 응답의 `result` 필드가 `"deleted"`이며 `_version`이 1 증가한다.

인덱스 전체 삭제는 `DELETE [인덱스]`로 호출한다. 인덱스가 삭제되면 포함된 모든 문서가 삭제되고 복구할 수 없으므로 주의가 필요하다.

### 설계 트레이드오프
- `DELETE [인덱스]/_doc/[_id]`와 `DELETE [인덱스]`는 형태가 유사해서 실수하기 쉽다. 뒷부분을 빠뜨리면 인덱스 전체가 삭제된다.
- 실무에서는 즉시 삭제보다 삭제 플래그(`is_deleted`)를 올려두고 Delete By Query로 일괄 처리하는 패턴이 일반적이다. (바이블 §4.2.4)

### 관련 개념
- Delete By Query, 세그먼트 병합, Reindex API

---

## 5. Delete By Query API

### 정의
검색 쿼리로 조건에 맞는 문서를 먼저 찾아낸 뒤, 해당 문서들을 일괄 삭제하는 API.

### 왜 필요한가
단건 Delete API는 `_id`를 알고 있어야 한다. 특정 필드 조건에 해당하는 문서를 일괄 삭제해야 할 때 Delete By Query를 사용한다. 서비스에서 오래된 데이터를 주기적으로 정리하거나, 삭제 플래그가 올라간 데이터를 배치로 처리할 때 유용하다.

### 동작 원리

```http
POST [인덱스]/_delete_by_query
{
  "query": {
    "term": { "status": "deleted" }
  }
}
```

내부 동작: 검색 쿼리로 대상 문서 스냅샷 생성 → 각 문서에 삭제 수행. 작업 도중 문서가 변경되면 버전 충돌(`version_conflicts`)이 발생한다.

- `conflicts=abort` (기본): 충돌 발견 시 작업 중단
- `conflicts=proceed`: 충돌을 무시하고 다음 문서로 진행

### 설계 트레이드오프
- Update By Query와 마찬가지로: 스로틀링(`requests_per_second`), 슬라이싱(`slices`), 비동기 실행(`wait_for_completion=false`), Tasks API 관리 모두 동일하게 적용된다.
- 작업 중 실패가 발생해도 이미 삭제된 문서는 롤백되지 않는다.
- 날짜 기반 인덱스(`web-log-20210110`) 패턴을 사용하면 Delete By Query 없이 인덱스째 삭제가 가능해 훨씬 효율적이다.

### 관련 개념
- Update By Query, Tasks API, 인덱스 명명 전략

---

## 6. Bulk API

### 정의
여러 색인/업데이트/삭제 작업을 한 번의 HTTP 요청에 묶어 배치 처리하는 API.

### 왜 필요한가
단건 문서 API를 반복 호출하면 HTTP 요청마다 오버헤드가 발생한다. 실제 서비스에서 대량 색인이 필요한 경우 단건 API를 반복하는 것보다 Bulk API를 사용하면 성능이 월등히 향상된다.

### 동작 원리

Bulk API는 다른 API와 달리 요청 본문을 **NDJSON** 형태(줄바꿈 구분 JSON)로 작성한다. `Content-Type: application/x-ndjson`을 사용해야 하며, 마지막 줄도 반드시 줄바꿈(`\n`)으로 끝나야 한다.

```http
POST _bulk
{"index": {"_index": "movie_test", "_id": "1"}}
{"title": "살아남은 아이"}
{"index": {"_index": "movie_test", "_id": "2"}}
{"title": "해리포터와 비밀의 방"}
{"delete": {"_index": "movie_test", "_id": "3"}}
{"update": {"_index": "movie_test", "_id": "1"}}
{"doc": {"movieNmEn": "Last Child"}}
```

각 요청의 크기는 1줄 또는 2줄이다:
- `index`, `create`: 다음 줄에 색인할 문서 본문이 온다
- `update`: 다음 줄에 `doc` 또는 `script`가 온다
- `delete`: 추가 줄이 필요 없다

`index`와 `create`의 차이:
- `index`: 동일 `_id` 문서가 있으면 덮어씌운다
- `create`: 새 문서 생성만 허용. 기존 문서가 있으면 실패

```http
# 인덱스를 URL에 지정하면 세부 요청에서 _index 생략 가능
POST [인덱스]/_bulk
```

#### 작업 순서 보장
Bulk API의 세부 요청은 반드시 요청 순서대로 수행된다는 보장이 없다. 단, 완전히 동일한 `_index + _id + routing` 조합을 가진 요청은 동일한 주 샤드로 전달되므로 기술된 순서대로 처리된다. (바이블 §4.2.1)

#### 응답 처리 주의
전체 응답 상태 코드가 200이더라도 세부 요청 중 일부가 실패할 수 있다. 반드시 응답 내 각 세부 항목의 `status` 필드를 확인해야 한다.

#### 성능 고려사항
- 단건 API 반복보다 Bulk API가 훨씬 빠르다.
- 요청 하나에 몇 개를 묶는 것이 최적인지는 데이터 크기와 환경에 따라 다르다. 실험을 통해 결정해야 한다.
- HTTP 요청을 chunked로 보내면 성능이 떨어진다. 피해야 한다.
- 실패가 발생해도 이미 처리된 작업은 롤백되지 않는다.

### 설계 트레이드오프
- 실시간성이 필요 없는 대량 색인은 Bulk API를 기본으로 사용해야 한다.
- 한 배치에 너무 많은 요청을 담으면 오히려 메모리 부담이 커진다. 적절한 배치 크기를 찾아야 한다.

### 관련 개념
- Multi Get API, Index API, Update API, refresh

---

## 7. Multi Get API

### 정의
여러 `_id`를 한 번에 지정해 복수 문서를 한 번의 요청으로 조회하는 API.

### 왜 필요한가
단건 조회 API를 반복 호출하는 것보다 성능이 좋다. 서비스에서 특정 ID 목록의 문서를 한꺼번에 가져와야 할 때 사용한다.

### 동작 원리

```http
GET _mget
{
  "docs": [
    {"_index": "bulk_test", "_id": "1"},
    {"_index": "bulk_test", "_id": "4", "routing": "a"},
    {
      "_index": "my_index2", "_id": "1",
      "_source": {"include": ["p*"], "exclude": ["point"]}
    }
  ]
}

# 인덱스를 URL에 지정하면 ids 형태로 간단하게 사용 가능
GET bulk_test/_mget
{
  "ids": ["1", "3"]
}
```

응답은 요청 순서대로 각 문서의 내용을 모아 단일 응답으로 반환한다.

### 관련 개념
- Bulk API, Get API

---

## 8. Update By Query API

### 정의
검색 쿼리로 조건에 맞는 문서를 먼저 찾아낸 뒤, 스크립트를 사용해 해당 문서들을 일괄 업데이트하는 API.

### 왜 필요한가
데이터 마이그레이션, 잘못 입력된 데이터 일괄 수정 등 관리 목적의 일괄 업데이트에 주로 사용된다. 단건 Update API와 달리 `_id`를 모르는 상태에서 조건 기반으로 대량의 문서를 업데이트할 수 있다.

### 동작 원리

```http
POST [인덱스]/_update_by_query
{
  "script": {
    "source": "ctx._source.field1 = ctx._source.field1 + '-' + ctx._id",
    "lang": "painless"
  },
  "query": {
    "exists": {"field": "field1"}
  }
}
```

- `doc`을 이용한 업데이트를 지원하지 않는다. `script`를 통한 업데이트만 지원한다.
- 스크립트 문맥에서 `ctx._now`는 사용할 수 없다.
- 작업 도중 문서 변경으로 버전 충돌 발생 시 `conflicts=abort`(기본) 또는 `conflicts=proceed`로 제어.

#### 스로틀링
대량 관리 작업이 서비스에 영향을 주지 않도록 속도를 제한하는 기능.

```http
POST [인덱스]/_update_by_query?scroll_size=1000&scroll=1m&requests_per_second=500
```

- `scroll_size`: 한 번의 스크롤에 처리할 문서 수 (기본 1000)
- `scroll`: 검색 컨텍스트 유지 시간 (한 배치 처리에 충분한 시간)
- `requests_per_second`: 초당 처리 건수 제한 (기본 -1: 무제한)

#### 비동기 처리
```http
POST [인덱스]/_update_by_query?wait_for_completion=false
```
작업을 task로 등록하고 즉시 task ID를 반환. Tasks API로 진행 상황 확인/취소/스로틀링 동적 변경 가능.

```http
# 상태 조회
GET _tasks/[task_id]

# 취소
POST _tasks/[task_id]/_cancel

# 스로틀링 동적 변경
POST _update_by_query/[task_id]/_rethrottle?requests_per_second=[새 값]
```

#### 슬라이싱
업데이트 성능을 최대화하기 위해 작업을 병렬로 분할 실행.

```http
POST [인덱스]/_update_by_query?slices=auto
```

`slices=auto`는 인덱스의 주 샤드 수를 기준으로 슬라이스를 나눈다. 슬라이스 수가 주 샤드 수를 초과하면 성능이 급감할 수 있다.

### 설계 트레이드오프
- Update By Query 작업이 중단되어도 이미 업데이트된 문서는 롤백되지 않는다. 재시작 시 조건을 잘 설계해야 한다.
- 대형 서비스에서 수십 시간짜리 일괄 작업은 `wait_for_completion=false`와 Tasks API를 함께 사용해야 한다.
- 트래픽이 급증하면 스로틀링을 동적으로 낮추거나 작업을 취소한 뒤 나중에 재개하는 전략을 고려해야 한다.

### 관련 개념
- Delete By Query, Tasks API, painless, Bulk API

---

## 9. Reindex API

### 정의
한 인덱스의 문서를 다른 인덱스로 복사하는 API.

### 왜 필요한가
인덱스 매핑이나 설정은 한번 생성하면 변경이 불가능하다(예: 샤드 수). 매핑 변경, 데이터 정제, 인덱스 재구성이 필요할 때 Reindex API를 사용해 새 인덱스로 데이터를 옮긴다.

### 동작 원리

```http
POST _reindex
{
  "source": {"index": "movie_dynamic"},
  "dest":   {"index": "movie_dynamic_new"}
}
```

`source`에 쿼리를 포함시켜 특정 문서만 복사할 수 있다.

```http
POST _reindex
{
  "source": {
    "index": "movie_dynamic",
    "query": {
      "term": {"title.keyword": "프렌즈: 몬스터성의비밀"}
    }
  },
  "dest": {"index": "movie_dynamic_new"}
}
```

정렬 순서를 지정해 복사할 수도 있다.

```http
POST _reindex
{
  "size": 10000,
  "source": {
    "index": "movie_dynamic",
    "sort": {"counter": "desc"}
  },
  "dest": {"index": "movie_dynamic_new"}
}
```

- 기본적으로 1,000건 단위로 스크롤을 수행한다.
- `size`를 늘리면 전체 속도를 향상시킬 수 있다.
- 실무에서는 alias를 함께 사용해, reindex 완료 후 alias를 새 인덱스로 교체하는 Zero Downtime Reindex 패턴을 사용한다. (바이블 §6.3.7)

### 설계 트레이드오프
- Reindex는 운영 중인 인덱스 변경의 유일한 방법이다. 대용량 인덱스는 reindex 시간이 매우 길어질 수 있다.
- alias를 활용하면 reindex 완료 전까지 기존 인덱스를 서비스에서 사용하다가 원자적으로 전환할 수 있다.

### 관련 개념
- alias, 인덱스 설정, 샤드, Update By Query

---

## 10. 낙관적 동시성 제어 (Optimistic Concurrency Control)

### 정의
분산 환경에서 여러 클라이언트가 동일 문서를 동시에 수정할 때 발생하는 충돌을 감지하고 제어하는 메커니즘. 잠금(lock) 없이 메타데이터 비교로 충돌을 처리한다.

### 왜 필요한가
엘라스틱서치는 주 샤드에서 변경된 내용을 복제본 샤드로 복제할 때, 분산 네트워크 특성상 요청이 역전되어 도착할 수 있다. 이를 방지하지 않으면 나중에 온 이전 버전 요청이 최신 데이터를 덮어쓰는 현상이 발생한다.

### 동작 원리

#### `_seq_no`와 `_primary_term`
- `_seq_no`: 각 주 샤드마다 관리되는 시퀀스 번호. 매 쓰기 작업마다 1씩 증가.
- `_primary_term`: 주 샤드가 새로 지정될 때마다 1씩 증가.

엘라스틱서치는 `_seq_no`를 역전시키는 변경을 허용하지 않는다. 복제본 샤드에 요청이 역순으로 도착해도, 더 큰 `_seq_no`를 가진 문서가 이미 반영되어 있다면 이전 요청을 무시한다. (바이블 §8.1.1)

#### 클라이언트 측 동시성 제어
클라이언트가 문서를 읽을 때 확인한 `_seq_no`와 `_primary_term` 값을 업데이트 요청에 포함시키면, 그 순간과 완전히 동일한 상태인 경우에만 업데이트가 수행된다.

```http
PUT concurrency_test/_doc/1?if_primary_term=1&if_seq_no=1
{
  "views": 3
}
```

같은 문서를 두 클라이언트가 동시에 읽고 수정하려 할 때, 먼저 성공한 클라이언트가 `_seq_no`를 변경하므로 나중 클라이언트의 요청은 409 에러를 반환한다.

#### `_version`과의 차이
`_version`도 동시성 제어에 사용 가능하지만 `_seq_no`/`_primary_term` 방식을 권장한다.

| 항목 | `_seq_no` + `_primary_term` | `_version` |
|---|---|---|
| 관리 주체 | 엘라스틱서치 (주 샤드 단위) | 엘라스틱서치 또는 클라이언트 |
| 클라이언트 지정 | 불가 | `version_type=external` 시 가능 |
| 복제 순서 보장 | 복제본 간 역전 방지 | 문서 단위 버전만 관리 |

`version_type=external`로 지정하면 클라이언트가 직접 버전 값을 지정해 색인할 수 있다. 외부 스토리지의 버전을 동기화할 때 활용한다. 현재 버전보다 높은 값으로만 색인 가능.

### 설계 트레이드오프
- 낙관적 동시성 제어는 잠금이 없어 성능이 좋지만, 충돌 시 클라이언트가 재시도 로직을 직접 구현해야 한다.
- `if_seq_no` + `if_primary_term`을 사용하면 "내가 읽은 상태 그대로일 때만 수정"이라는 CAS(Compare-And-Swap) 패턴을 구현할 수 있다.

### 관련 개념
- `_seq_no`, `_primary_term`, `_version`, 복제본 샤드, 주 샤드, Index API

---

## 문서 파라미터 요약

> 출처: 엘라스틱서치 실무가이드 §3.5.1

Document API에서 공통으로 사용할 수 있는 주요 파라미터:

| 파라미터 | 설명 |
|---|---|
| `op_type` | `create`로 지정하면 새 문서 생성만 허용 (동일 _id 존재 시 실패) |
| `timeout` | 대기 최대 시간 지정 (기본 1분) |
| `refresh` | `true` / `wait_for` / `false` (기본) |
| `routing` | 커스텀 라우팅 값 지정 |
| `if_seq_no` | 낙관적 동시성 제어: 지정한 _seq_no와 일치할 때만 작업 수행 |
| `if_primary_term` | 낙관적 동시성 제어: 지정한 _primary_term과 일치할 때만 작업 수행 |
