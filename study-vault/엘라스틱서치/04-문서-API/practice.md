# 04. 문서 API - 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch3 §3.5 / 엘라스틱서치바이블 Ch4 §4.1, §4.2, §8.1
> 태그: #index-api #get-api #update-api #delete-api #bulk-api #reindex #optimistic-concurrency

---

## 기초 (40%)

### Q1. Index API - PUT vs POST 차이

`PUT movie/_doc/1`과 `POST movie/_doc`의 동작 차이를 설명하라. 각각 어떤 경우에 사용하는가?

<details>
<summary>정답</summary>

**PUT movie/_doc/1**
- `_id`를 직접 지정해 색인한다.
- 해당 인덱스에 같은 `_id`를 가진 문서가 이미 존재하면 새 문서로 덮어씌운다.
- `_id`를 미리 알고 있거나, 멱등한 색인이 필요할 때 사용한다.

**POST movie/_doc**
- `_id`를 지정하지 않는다. 엘라스틱서치가 UUID 형태로 `_id`를 랜덤하게 생성한다.
- 항상 새 문서가 생성된다. 같은 요청을 반복해도 중복 문서가 계속 생성된다.
- `_id`를 클라이언트가 관리하지 않아도 될 때 사용한다.

**추가**: `PUT movie/_create/1`은 `_id`를 지정하면서 새 문서 생성만 허용한다. 같은 `_id` 문서가 이미 있으면 409 에러를 반환한다.
</details>

---

### Q2. Get API - 조회와 검색의 차이

Get API가 검색 API와 다른 결정적 차이점 두 가지를 설명하라.

<details>
<summary>정답</summary>

**1. refresh 없이 최신 데이터 확인 가능**
조회 API는 translog에서도 데이터를 읽어올 수 있기 때문에 색인 직후 refresh 단계가 완료되지 않아도 변경된 내용을 확인할 수 있다. 검색 API는 refresh 단계 이후에야 새로 색인된 문서를 찾을 수 있다.

**2. 역색인을 사용하지 않음**
Get API는 고유한 `_id`로 직접 문서를 찾는다. 역색인을 거치지 않으므로 정확한 `_id`를 알고 있을 때 검색 API보다 더 빠르고 확실하다.

**실무 설계 함의**: 색인 직후 결과를 확인해야 하는 비즈니스 요건이 있을 때, refresh 옵션을 사용한 색인 대신 조회 API를 활용하도록 서비스를 설계하는 것이 전체 클러스터 성능에 유리하다.
</details>

---

### Q3. Update API - 동작 방식

Update API의 내부 동작 단계를 설명하라. 왜 `_source`가 비활성화된 경우 Update API를 사용할 수 없는가?

<details>
<summary>정답</summary>

**내부 동작 3단계**:
1. 기존 문서의 `_source`를 읽어들인다.
2. `doc`에 기술한 부분 업데이트 내용을 기존 `_source`에 합친다.
3. 합쳐진 새 문서를 재색인(reindex)한다.

**`_source` 비활성화 시 Update API 불가 이유**:
업데이트 API는 1단계에서 반드시 기존 문서의 `_source`를 읽어야 한다. `_source`를 비활성화하면 문서를 저장할 때 원본 JSON을 저장하지 않으므로, 업데이트 API가 기존 내용을 읽어올 방법이 없다. 따라서 Update API를 사용할 수 없게 된다.

문서 전체를 교체해야 할 경우에는 Update API 대신 Index API(`PUT /_doc/{id}`)를 사용하면 된다.
</details>

---

### Q4. Bulk API - NDJSON 형식

다음 Bulk API 요청을 해석하라. 각 줄이 어떤 작업을 수행하는지 설명하라.

```
POST _bulk
{"index": {"_index": "orders", "_id": "101"}}
{"product": "keyboard", "qty": 2}
{"delete": {"_index": "orders", "_id": "88"}}
{"update": {"_index": "orders", "_id": "50"}}
{"doc": {"qty": 5}}
{"create": {"_index": "orders", "_id": "102"}}
{"product": "mouse", "qty": 1}
```

<details>
<summary>정답</summary>

1. `{"index": ...}` + `{"product": ...}`: `orders` 인덱스에 `_id=101`로 문서를 색인한다. `_id=101` 문서가 이미 있으면 덮어씌운다.

2. `{"delete": ...}`: `orders` 인덱스에서 `_id=88`인 문서를 삭제한다. `delete`는 추가 본문 줄이 필요 없다.

3. `{"update": ...}` + `{"doc": ...}`: `orders` 인덱스의 `_id=50` 문서에서 `qty` 필드를 5로 부분 업데이트한다.

4. `{"create": ...}` + `{"product": ...}`: `orders` 인덱스에 `_id=102`로 문서를 생성한다. `_id=102` 문서가 이미 존재하면 409 에러로 실패한다 (`index`와 달리 덮어쓰지 않는다).

**주의**: 전체 응답 상태 코드가 200이더라도 세부 요청 중 일부가 실패할 수 있다. 반드시 응답 내 각 항목의 `status` 필드를 확인해야 한다.
</details>

---

## 응용 (40%)

### Q5. detect_noop 이해

뷰 카운터 서비스가 있다. `POST views_index/_update/doc1 {"doc": {"count": 1000}}`을 호출했을 때, 문서의 현재 `count` 값이 이미 1000이라면 어떤 일이 발생하는가? 이 동작이 왜 성능에 유리한가? 언제 이 동작을 비활성화해야 하는가?

<details>
<summary>정답</summary>

**발생하는 일**:
`detect_noop`이 기본값 `true`이므로, 엘라스틱서치는 업데이트 수행 전 변경 내용이 기존 문서와 실질적으로 다른지 비교한다. `count` 값이 이미 1000으로 동일하므로 noop(no operation)으로 판단하여 실제 재색인 쓰기 작업을 수행하지 않는다. 응답의 `result` 필드에 `"noop"`이 반환된다.

**성능 유리한 이유**:
`_source`를 읽어들이는 작업은 detect_noop 여부와 상관없이 항상 수행된다. 이미 읽어온 데이터를 비교하는 비용은 불필요한 디스크 쓰기 비용보다 훨씬 저렴하다. 따라서 noop 요청이 많은 환경에서 디스크 I/O를 크게 줄일 수 있다.

**비활성화해야 하는 경우**:
- 서비스나 데이터 특성상 noop 업데이트가 발생할 가능성이 아예 없는 경우 (불필요한 비교 비용 제거).
- 커스텀 플러그인에 `IndexingOperationListener` 같은 리스너를 달아 색인 전후에 특정 동작을 수행해야 할 때, noop 처리되면 리스너의 `preIndex`/`postIndex`가 호출되지 않으므로 의도치 않은 동작이 발생할 수 있다. 이 경우 `detect_noop=false`로 지정해야 한다.
</details>

---

### Q6. Delete By Query vs Delete API

다음 두 가지 상황에서 각각 어떤 삭제 API를 사용해야 하는지, 그 이유를 설명하라.

**상황 A**: 특정 문서의 `_id`가 `"order-12345"`임을 알고 있고, 해당 문서 하나만 즉시 삭제해야 한다.

**상황 B**: `status` 필드가 `"cancelled"` 인 주문 문서들을 일괄 삭제해야 한다. 대상 문서가 수천 건이다.

<details>
<summary>정답</summary>

**상황 A: Delete API**
```http
DELETE orders/_doc/order-12345
```
`_id`를 정확히 알고 있으므로 단건 Delete API가 가장 직접적이고 효율적이다. Delete By Query를 사용하면 검색 후 삭제하는 불필요한 단계가 추가된다.

**상황 B: Delete By Query API**
```http
POST orders/_delete_by_query
{
  "query": {
    "term": {"status": "cancelled"}
  }
}
```
`_id`를 모르는 상태에서 조건 기반으로 다수의 문서를 삭제해야 한다. Delete API는 `_id` 단위로만 동작하므로, 먼저 검색을 수행한 뒤 그 결과를 삭제하는 Delete By Query가 적합하다.

**추가 고려사항 (상황 B)**:
- 대량 삭제가 운영 서비스에 영향을 줄 수 있다면 `requests_per_second`로 스로틀링을 적용한다.
- 수십 시간이 걸릴 작업이라면 `wait_for_completion=false`와 Tasks API를 조합한다.
- 작업 중 실패가 발생해도 이미 삭제된 문서는 롤백되지 않는다는 점을 고려한다.
</details>

---

### Q7. Reindex 시나리오

`orders_v1` 인덱스를 운영 중인데 다음 두 가지 변경이 필요하다:
1. `product_name` 필드의 타입을 `text`에서 `keyword`로 변경
2. 샤드 수를 3개에서 5개로 늘리기

각 변경을 어떻게 수행해야 하는가? 서비스 중단 없이 전환하려면 어떤 전략이 필요한가?

<details>
<summary>정답</summary>

**변경이 어려운 이유**:
엘라스틱서치는 인덱스 생성 후 매핑 타입 변경(text → keyword)과 샤드 수 변경을 허용하지 않는다. 반드시 새 인덱스를 만들어 데이터를 복사해야 한다.

**Reindex 절차**:

1. 새 매핑과 설정으로 `orders_v2` 인덱스 생성:
```http
PUT orders_v2
{
  "settings": {"number_of_shards": 5},
  "mappings": {
    "properties": {
      "product_name": {"type": "keyword"}
    }
  }
}
```

2. Reindex로 데이터 복사:
```http
POST _reindex
{
  "source": {"index": "orders_v1"},
  "dest":   {"index": "orders_v2"}
}
```

3. Reindex 완료 후 별칭(alias) 전환:
```http
POST _aliases
{
  "actions": [
    {"remove": {"index": "orders_v1", "alias": "orders"}},
    {"add":    {"index": "orders_v2", "alias": "orders"}}
  ]
}
```

**서비스 중단 없는 전환 전략 (alias 활용)**:
- 처음부터 서비스에서 인덱스 이름 대신 alias(`orders`)를 사용하도록 설계한다.
- Reindex 진행 중에는 기존 `orders_v1`이 alias를 통해 계속 서비스된다.
- Reindex 완료 후 alias를 원자적으로 전환한다. 전환은 즉각적이며 서비스 중단이 없다.
- Reindex 완료 후 `orders_v1`을 삭제해 스토리지를 정리한다.
</details>

---

### Q8. Update By Query 스로틀링

운영 중인 대용량 인덱스(문서 1억 건)에서 `category` 필드가 `"A"`인 모든 문서의 `priority` 값을 1에서 2로 일괄 수정해야 한다. 서비스 중단 없이 안전하게 수행하기 위해 고려해야 할 사항과 실제 요청 예시를 작성하라.

<details>
<summary>정답</summary>

**고려 사항**:

1. **스로틀링 적용**: 대량 작업이 운영 트래픽에 영향을 주지 않도록 `requests_per_second`를 제한한다.
2. **비동기 처리**: 수십 시간짜리 작업은 HTTP 클라이언트 타임아웃 문제가 있으므로 `wait_for_completion=false`로 비동기 처리한다.
3. **작업 관리**: Tasks API로 진행 상황을 주기적으로 모니터링한다.
4. **중단 대비**: 서비스 트래픽이 급증하면 스로틀링을 동적으로 낮추거나 작업을 취소할 수 있어야 한다.
5. **재개 전략**: 작업 중단 시 이미 수정된 문서는 롤백되지 않으므로, 재시작할 때 `priority`가 아직 1인 문서만 대상으로 하는 조건으로 재실행한다.

**요청 예시**:

```http
POST my_index/_update_by_query?wait_for_completion=false&scroll_size=1000&scroll=1m&requests_per_second=500
{
  "script": {
    "source": "ctx._source.priority = 2",
    "lang": "painless"
  },
  "query": {
    "bool": {
      "must": [
        {"term": {"category": "A"}},
        {"term": {"priority": 1}}
      ]
    }
  }
}
```

**응답에서 task_id 확인 후 모니터링**:
```http
GET _tasks/[task_id]
```

**트래픽 급증 시 스로틀링 동적 낮추기**:
```http
POST _update_by_query/[task_id]/_rethrottle?requests_per_second=100
```

**긴급 취소**:
```http
POST _tasks/[task_id]/_cancel
```
</details>

---

## 심화 (20%)

### Q9. 낙관적 동시성 제어 - 시나리오 분석

클라이언트 A와 클라이언트 B가 동시에 같은 문서 `product/_doc/1` (현재 `stock: 10`)을 읽고 재고를 감소시키는 업데이트를 시도한다.

1. 클라이언트 A가 문서를 읽는다. 응답: `"_seq_no": 5, "_primary_term": 1`
2. 클라이언트 B가 같은 문서를 읽는다. 응답: `"_seq_no": 5, "_primary_term": 1`
3. 클라이언트 A가 `stock: 9`로 업데이트한다 (`if_seq_no=5&if_primary_term=1`). 성공.
4. 클라이언트 B가 `stock: 9`로 업데이트를 시도한다 (`if_seq_no=5&if_primary_term=1`).

4단계에서 무슨 일이 발생하는가? 클라이언트 B는 어떻게 처리해야 하는가?

<details>
<summary>정답</summary>

**4단계 발생 내용**:
클라이언트 A의 성공으로 인해 문서의 `_seq_no`가 5에서 6으로 증가했다. 클라이언트 B는 `if_seq_no=5`를 지정했지만 현재 문서의 `_seq_no`는 6이므로 조건이 일치하지 않는다. 엘라스틱서치는 409 Conflict 에러와 함께 `version_conflict_engine_exception`을 반환한다.

이로써 클라이언트 B가 "자신이 확인한 stock=10" 상태를 기반으로 "stock=9"로 덮어쓰는 것이 방지된다. 실제로 A가 이미 9로 변경했는데, B가 다시 9로 쓰면 올바른 감소가 일어나지 않는다 (재고가 두 번 감소해야 8이 되어야 함).

**클라이언트 B의 처리 방법**:
1. 409 에러를 감지한다.
2. 문서를 다시 조회해 최신 `_seq_no`, `_primary_term`, `stock` 값을 읽는다.
3. 읽어온 최신 상태를 기반으로 업데이트 내용을 재계산한다 (`stock: 현재값 - 1`).
4. 새로 읽어온 `_seq_no`, `_primary_term`으로 업데이트를 재시도한다.
5. 충돌이 다시 발생하면 설정한 최대 재시도 횟수까지 반복한다.

이것이 낙관적 동시성 제어의 특징이다: 잠금 없이 동작하여 성능이 좋지만, 충돌 시 클라이언트가 재시도 로직을 직접 구현해야 한다. 충돌 빈도가 매우 높다면 비관적 잠금(pessimistic locking) 전략이 오히려 더 효율적일 수 있다.
</details>

---

### Q10. Bulk API 작업 순서 보장

다음 Bulk API 요청에서 작업 순서가 보장되는 경우와 보장되지 않는 경우를 구분하고, 그 이유를 설명하라.

```
POST _bulk
{"create": {"_index": "items", "_id": "1"}}
{"name": "A"}
{"update": {"_index": "items", "_id": "1"}}
{"doc": {"name": "B"}}
{"create": {"_index": "items", "_id": "2"}}
{"name": "C"}
{"delete": {"_index": "items", "_id": "1"}}
```

<details>
<summary>정답</summary>

**작업 순서가 보장되는 경우**:
`_id=1`에 대한 3개의 작업 (create → update → delete)은 순서가 보장된다. 이유는 이 3개의 요청이 모두 동일한 `_index=items` + `_id=1` 조합을 가지기 때문에, 조정 노드는 이를 모두 동일한 주 샤드로 라우팅한다. 같은 주 샤드로 전달된 요청은 Bulk API에 기술된 순서대로 처리된다.

**작업 순서가 보장되지 않는 경우**:
`_id=1`에 대한 요청들과 `_id=2`에 대한 요청(`create C`) 사이의 상대적 순서는 보장되지 않는다. `_id=2` 요청은 `_id=1` 요청과 다른 주 샤드로 라우팅될 수 있으며, 조정 노드에서 각 샤드로 넘어간 요청은 독자적으로 수행된다.

**실무 의미**:
이 예에서 `create _id=1` → `update _id=1` 순서는 보장되므로 안전하다. `create` 이전에 `update`가 실행될 위험이 없다. 그러나 서로 다른 `_id`/라우팅을 가진 작업 간의 실행 순서를 가정한 로직은 Bulk API에서 신뢰할 수 없다.
</details>

---

*최소 8문제 완료. 기초 4문제 (40%) / 응용 4문제 (40%) / 심화 2문제 (20%)*
