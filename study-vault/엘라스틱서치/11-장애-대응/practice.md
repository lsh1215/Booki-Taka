# 11. 장애 대응 - 연습 문제

> 출처: 엘라스틱서치바이블 Ch7 / 엘라스틱서치 실무가이드 Ch11-12
> 태그: #fault-tolerance #unassigned-shard #circuit-breaker #disk-full #gc #recovery

---

## 기초 (40%)

### Q1. 장애 발생 직후 클러스터 상태를 확인하기 위한 API 두 가지와 각각 확인하는 주요 정보를 나열하세요.

<details>
<summary>정답 보기</summary>

**`GET _cat/health`**
- 클러스터 전체 상태 (green / yellow / red)
- 미할당 샤드(unassigned_shards) 수
- 현재 클러스터에 합류된 노드 수

**`GET _cat/nodes`**
- 어떤 노드가 클러스터에서 빠졌는지
- 마스터 노드가 제대로 선출되어 있는지
- 각 노드별 평균 부하, 힙 사용량, 메모리 사용량, CPU 사용량

디스크 사용량은 각 노드에서 직접 `df` 명령어로 확인하거나 `GET _nodes/stats`의 `fs` 항목으로 확인.

</details>

---

### Q2. 장애 발생 시 샤드 할당을 즉시 비활성화해야 하는 이유를 설명하세요.

<details>
<summary>정답 보기</summary>

노드 하나가 클러스터에서 빠지면 그 노드가 가지고 있던 샤드의 복제본 수가 줄어든다. ES는 `number_of_replicas` 설정을 맞추기 위해 다른 노드에 새 복제본 샤드를 할당하고 데이터를 복사하는 작업을 수행한다.

장애 상황에서 가뜩이나 노드가 줄어 부하가 높은데 복제본 샤드 할당/복사 작업까지 더해지면:
- 다른 노드에도 과부하 발생 → 추가로 클러스터에서 이탈
- 이탈된 노드의 샤드도 재할당 → 연쇄 장애

이 도미노를 막기 위해 샤드 할당을 한시라도 빠르게 비활성화해야 한다.

```json
PUT _cluster/settings
{
  "transient": {
    "cluster.routing.allocation.enable": "primaries"
  }
}
```

</details>

---

### Q3. 디스크 풀 상황에서 인덱스에 워터마크가 설정되면 어떤 작업이 제한되고, 어떻게 해제하는지 설명하세요.

<details>
<summary>정답 보기</summary>

**제한**: `index.blocks.read_only_allow_delete: true` 상태가 되어 **읽기와 삭제만 가능**, 색인(쓰기) 요청은 모두 거부된다.

**기준**: 디스크 사용량 95% 초과 시 워터마크 설정.

**해제 방법**:
- 7.4 버전 이상: 디스크에 여유가 생기면 자동 해제
- 7.4 버전 이하 또는 자동 해제 안 된 경우: 수동 해제 필요

```json
PUT [인덱스 이름]/_settings
{
  "index": {
    "blocks": {
      "read_only_allow_delete": false
    }
  }
}
```

`null`로 설정하면 설정 항목 자체가 사라지고, `false`로 설정하면 워터마크가 붙었던 인덱스를 나중에 구분할 수 있다. 와일드카드(`my-index-*`)로 일괄 해제 가능.

</details>

---

### Q4. 서킷 브레이커의 종류 4가지와 기본 임계치를 나열하세요.

<details>
<summary>정답 보기</summary>

| 종류 | 설정 키 | 기본 임계치 |
|---|---|---|
| 필드 데이터 서킷 브레이커 | `indices.breaker.fielddata.limit` | 힙의 40% |
| 요청 서킷 브레이커 | `indices.breaker.request.limit` | 힙의 60% |
| 실행 중 요청 서킷 브레이커 | `network.breaker.inflight_requests.limit` | 힙의 100% |
| 부모 서킷 브레이커 | `indices.breaker.total.limit` | 힙의 95% (실제 메모리 체크 활성 시) |

+ 스크립트 컴파일 서킷 브레이커 (`script.max_compilations_rate`): 기본값 75/5m (메모리 기반이 아닌 횟수 기반).

</details>

---

### Q5. 댕글링 인덱스(Dangling Index)란 무엇이고, 가장 흔한 발생 시나리오는 무엇인가요?

<details>
<summary>정답 보기</summary>

**정의**: 노드의 로컬 데이터 디렉토리에는 샤드 데이터가 있는데, 클러스터의 메타데이터에는 해당 인덱스 정보가 없는 상태. 노드가 클러스터에 합류할 때 이 불일치를 감지하면 댕글링 인덱스로 취급한다.

**가장 흔한 시나리오**:
1. 특정 노드가 클러스터에서 제외됨
2. 그 사이에 클러스터에서 해당 노드가 가진 인덱스들이 삭제됨
3. 해당 노드가 클러스터에 다시 합류
4. 클러스터 메타데이터에는 없는데 로컬에는 데이터가 남아있는 상태 → 댕글링 인덱스

이 시나리오는 의도적으로 삭제된 데이터이므로 대부분 큰 문제 없이 삭제하면 됨.

</details>

---

## 응용 (40%)

### Q6. 노드 한 대가 클러스터에서 이탈했습니다. `GET _cat/health` 응답은 빠른데 `GET _cat/nodes` 응답이 오랫동안 오지 않습니다. 무엇을 의심해야 하고 어떻게 대응해야 하나요?

<details>
<summary>정답 보기</summary>

**의심 상황**: 일부 노드가 GC로 인한 STW(Stop-The-World) 상태로 사실상 먹통이 된 상태. `_cat/health`는 마스터 노드가 응답 가능하지만 `_cat/nodes`는 모든 노드에서 정보를 수집해야 하므로 STW 상태 노드에서 응답이 안 오면 타임아웃이 날 때까지 기다리게 됨.

**대응 절차**:
1. STW가 예상되는 노드의 서버 로그와 GC 로그 확인
2. 재기동 여부 결정:
   - STW 상황이 심각하다고 판단되면 `kill -15`로 프로세스 종료
   - `ps`로 프로세스가 제대로 죽었는지 확인
   - `kill -15`에도 안 죽으면 즉시 `kill -9`
3. 재기동 후 샤드 할당 재활성화 및 복구 대기

**주의**: 의도적 롤링 리스타트와 달리 사전 flush 없이 바로 kill.

</details>

---

### Q7. 미할당 샤드가 있는데 샤드 할당이 더 이상 진행되지 않는 상황입니다. 원인을 파악하고 재할당하는 절차를 작성하세요.

<details>
<summary>정답 보기</summary>

**원인 파악**:
```json
GET _cluster/allocation/explain?pretty
{
  "index": "my-index",
  "shard": 0,
  "primary": false
}
```
응답의 `unassigned_info`와 `node_allocation_decisions`의 `deciders` 항목에서 구체적인 실패 원인 파악.

**가장 빈번한 원인 및 대응**:

| 원인 | 대응 |
|---|---|
| `max_retry` 소진 | `POST _cluster/reroute?retry_failed=true` (본문 비워둠) |
| 서킷 브레이커 작동 | 부하 감소 후 재할당 요청, 임시로 브레이커 임계치 완화 |
| too many open files | 부하 감소 후 재할당 요청 |

**재할당 요청**:
```
POST _cluster/reroute?retry_failed=true
```

서킷 브레이커로 실패하는 경우 서버 로그에 관련 예외 로그가 남으므로 재할당 요청 시 서버 로그 함께 확인.

</details>

---

### Q8. 장애 복구 중 날짜가 넘어가서 대량의 새 인덱스가 생성될 것으로 예상됩니다. 어떤 설정을 변경해야 하고, 왜 위험한지 설명하세요.

<details>
<summary>정답 보기</summary>

**위험한 이유**:
- 복구 중 재시작된 노드는 샤드 복구가 완료되지 않아 겉으로 보기에 "샤드가 적은 노드"로 판정됨
- `cluster.routing.allocation.balance.shard` 설정(기본 0.45)에 따라 ES는 샤드 균형을 맞추려 이 노드에 새 인덱스의 샤드를 몰아서 할당
- 이 노드에 데이터까지 들어오면 단독으로 모든 부하를 받다가 다시 죽을 수 있음

**대응 설정**:
```json
PUT _cluster/settings
{
  "transient": {
    "cluster.routing.allocation.balance.shard": 0
  }
}
```
샤드 균형을 무시하고 단순 순서 배정으로 변경.

**추가 조치**:
- 내일 생성될 인덱스를 미리 수동으로 분산하여 천천히 생성 (클러스터 부하 상황 봐가며)

**주의**: 비상 상황 처리 후 반드시 기본값(0.45)으로 복구. 0으로 유지하면 시간이 지날수록 특정 노드에 샤드가 쏠리는 현상 심화.

</details>

---

### Q9. 샤드 복구 속도를 높이기 위해 조정할 수 있는 설정 3가지와 그 역할을 설명하세요.

<details>
<summary>정답 보기</summary>

**1. `cluster.routing.allocation.node_concurrent_recoveries`**
- 역할: 노드 하나가 네트워크를 통해 동시에 수행하는 샤드 복구 작업 수 (복제본 샤드 복구)
- 기본값: 2
- 복제해 주는 수와 복제받는 수를 동시에 지정

```json
PUT _cluster/settings
{
  "transient": {
    "cluster.routing.allocation.node_concurrent_recoveries": 4
  }
}
```

**2. `cluster.routing.allocation.node_initial_primaries_recoveries`**
- 역할: 노드 하나가 동시에 복구하는 주 샤드 수 (로컬 디스크에서 복구, 네트워크 불필요)
- 기본값: 4
- 네트워크를 사용하지 않으므로 더 높은 값 설정 가능

```json
PUT _cluster/settings
{
  "transient": {
    "cluster.routing.allocation.node_initial_primaries_recoveries": 8
  }
}
```

**3. `indices.recovery.max_bytes_per_sec`**
- 역할: 노드당 복구에 사용할 네트워크 트래픽 속도 제한
- 기본값: 40MB (cold/frozen 티어는 40~250MB)
- 색인 작업을 완전히 차단한 상태라면 크게 올려도 무방

```json
PUT _cluster/settings
{
  "transient": {
    "indices.recovery.max_bytes_per_sec": "512mb"
  }
}
```

</details>

---

## 심화 (20%)

### Q10. 서비스 앞쪽에 메시지 큐(카프카)를 두고 ES에 색인하는 구조에서 멱등성 설계가 필요한 이유를 설명하고, 멱등한 `_id` 설계 방법을 제시하세요.

<details>
<summary>정답 보기</summary>

**멱등성이 필요한 이유**:

bulk API로 ES에 색인 중 클라이언트가 응답 받기 전 죽거나 타임아웃이 발생했을 때, ES가 실제로 데이터를 색인했는지 알 수 없다. 이때:

- **멱등하지 않은 설계**: 어디까지 성공했는지 추적해서 정확히 실패한 것만 재시도해야 함 → 매우 복잡
- **멱등한 설계**: 카프카 오프셋을 원하는 시간대로 되감아 다시 꺼내면서 재처리하면 됨 → 중복 색인해도 동일한 결과 보장

**멱등한 `_id` 설계**:

```
_id = {topic}-{partition}-{offset}
```

같은 메시지는 항상 같은 `_id`를 가지게 되어 중복 색인해도 동일한 문서로 덮어씀.

**주의 사항**:
- 카프카 클러스터를 다중화 구성한 경우, 같은 `{topic}-{partition}-{offset}` 조합이 서로 다른 메시지를 의미할 수 있음 → 이 방법이 적합하지 않을 수 있음
- 데이터 자체에 고유한 식별자가 있다면 그것을 사용하는 것이 더 안전

**추가 활용**:
- 매핑/샤드 수 변경 시: alias + reindex 수행 중 발생한 변경분을 오프셋을 되감아 추가 색인하면 깔끔하게 처리 가능

</details>

---

### Q11. 클러스터를 용도별로 분리해야 하는 이유를 장애 대응 관점에서 구체적으로 설명하세요.

<details>
<summary>정답 보기</summary>

**핵심 문제: 장애 전파와 대응 전략의 충돌**

같은 클러스터에 서로 다른 성질의 데이터(서비스 데이터 + 분석/BI 데이터)를 섞어 운영하면:

1. **장애 전파**: 키바나에서 분석 쿼리 → ES 과부하 → 서비스 장애로 이어짐
2. **대응 전략 선택 불가**: 중요하지 않은 데이터를 위한 과감한 방법(풀 리스타트, 데이터 삭제)을 쓸 수 없음

**분리 후 장점**:

| 클러스터 유형 | 특성 | 장애 대응 방식 |
|---|---|---|
| 서비스 데이터 (NoSQL) | 높은 중요도, 키바나 오픈 불필요 | 신중하고 보수적인 복구 |
| 로그 데이터 | 색인 순서 중요하지 않음 | 장애 후 bulk API 병렬 호출로 빠른 재처리 |
| BI/분석 | 낮은 중요도 | 풀 리스타트 + 문제 데이터 삭제 같은 과감한 방법 가능 |

**전체 장애 대응 시간 단축**: 중요도 구분이 없으면 과감한 방법을 선택할 수 없어 장애 처리 시간이 늘어나고, 중요한 서비스의 가용성도 그만큼 떨어짐.

</details>
