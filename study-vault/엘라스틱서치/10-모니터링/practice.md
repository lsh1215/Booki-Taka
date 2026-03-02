# 엘라스틱서치 모니터링 - 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch11 / 엘라스틱서치바이블 Ch7
> 태그: #monitoring #cluster-health #cat-api #jvm #gc #thread-pool #metricbeat

---

## 기초 (40%)

### Q1. 클러스터 Health 상태 세 가지를 설명하라

클러스터의 `status` 필드가 가질 수 있는 세 가지 값과 각각의 의미, 그리고 서비스에 미치는 영향을 설명하시오.

<details>
<summary>정답 보기</summary>

| 상태 | 의미 | 서비스 영향 |
|------|------|------------|
| **green** | 모든 프라이머리 샤드와 레플리카 샤드가 정상적으로 할당되어 동작 중 | 없음. 완전 정상 |
| **yellow** | 프라이머리 샤드는 정상 할당됐으나 일부 레플리카 샤드가 할당되지 못한 상태 | 서비스는 가능하나 장애 발생 시 즉각 복구 불가. green이 될 때까지 모니터링 필요 |
| **red** | 일부 프라이머리 샤드가 할당되지 못한 상태 | 해당 샤드의 데이터를 검색/색인 불가. 즉각 원인 파악 및 복구 필요 |

- yellow는 단일 노드 클러스터에서 레플리카를 1 이상으로 설정했을 때 자주 발생한다. 레플리카를 할당할 다른 노드가 없기 때문이다.
- red 상태 발생 시 `_cat/shards?h=index,shard,prirep,state,unassigned.reason` 으로 어느 샤드가 미할당인지, 이유는 무엇인지 확인한다.

</details>

---

### Q2. `_cluster/health` API의 주요 응답 필드를 설명하라

다음 응답에서 각 필드가 의미하는 바를 설명하시오.

```json
{
  "number_of_nodes": 4,
  "number_of_data_nodes": 3,
  "active_primary_shards": 55,
  "active_shards": 110,
  "relocating_shards": 2,
  "initializing_shards": 0,
  "unassigned_shards": 0
}
```

<details>
<summary>정답 보기</summary>

| 필드 | 설명 |
|------|------|
| `number_of_nodes: 4` | 클러스터를 구성하는 전체 노드 수는 4개 |
| `number_of_data_nodes: 3` | 그 중 데이터 노드는 3개 (나머지 1개는 마스터 전용 등) |
| `active_primary_shards: 55` | 현재 동작 중인 프라이머리 샤드 수 55개 |
| `active_shards: 110` | 동작 중인 전체 샤드 수 110개 (프라이머리 55개 + 레플리카 55개, 레플리케이션 팩터 1) |
| `relocating_shards: 2` | 현재 다른 노드로 이동(Relocation) 중인 샤드가 2개. 노드 추가/제거 시 발생하며 완료 후 0이 됨 |
| `initializing_shards: 0` | 초기화 중인 샤드 없음. 오래 지속되면 문제 가능성 |
| `unassigned_shards: 0` | 미할당 샤드 없음. 0이 아니면 yellow 또는 red 상태 |

</details>

---

### Q3. Health 체크에서 `level` 파라미터를 사용하는 경우를 설명하라

`_cluster/health`에 `level` 파라미터를 사용하는 세 가지 값과 각각의 사용 시점을 설명하시오.

<details>
<summary>정답 보기</summary>

| 값 | API | 사용 시점 |
|----|-----|-----------|
| 기본값 (미지정) | `GET /_cluster/health` | 클러스터 전체 상태만 빠르게 확인할 때. 가장 가볍다 |
| `indices` | `GET /_cluster/health?level=indices` | 클러스터가 yellow/red일 때 어떤 인덱스에 문제가 있는지 파악할 때 |
| `shards` | `GET /_cluster/health?level=shards` | 특정 인덱스의 어떤 샤드에 문제가 있는지 정확히 찾을 때 |

특정 인덱스만 대상으로 할 수도 있다:
```
GET /_cluster/health/movie?level=shards
```
이는 멀티테넌시 구조에서 서비스별 인덱스를 독립적으로 Health 체크할 때 유용하다.

</details>

---

### Q4. `_nodes/stats`에서 스레드풀을 모니터링할 때 가장 중요한 두 필드는?

스레드풀 통계에서 어떤 두 필드를 집중 모니터링해야 하는지, 그 이유와 함께 설명하시오.

<details>
<summary>정답 보기</summary>

**`queue`와 `rejected`**

**queue (대기열)**:
- 현재 스레드풀에서 처리를 기다리고 있는 요청의 수
- queue가 지속적으로 증가한다면 현재 처리 용량보다 더 많은 요청이 들어오고 있다는 과부하 신호
- 임계값을 넘어서면 rejected로 이어진다

**rejected (거부)**:
- 대기열이 가득 차서 처리를 거부한 요청 수 (누적)
- 0이 아니면 실제로 요청이 유실되고 있다는 것이므로 즉시 대응 필요
- 클라이언트에게는 EsRejectedExecutionException이 반환된다

**확인 방법**:
```
GET /_nodes/stats/thread_pool
GET /_cat/thread_pool?v
```

**대응**:
- rejected 발생 시 스레드풀 size를 무조건 늘리는 것은 부작용이 있다
- 근본 해결책: 색인/검색 요청 속도 조절(throttling) 또는 노드 추가

</details>

---

## 응용 (40%)

### Q5. JVM 힙 사용률 75%인 노드에서 Old GC가 1분에 5회 발생하고 있다. 어떻게 판단하고 어떤 조치를 취할 것인가?

<details>
<summary>정답 보기</summary>

**상황 판단**:

힙 사용률 75%는 경계 수준이고, Old GC가 1분에 5회는 매우 높다. Old GC(Full GC)는 Stop-The-World를 유발하므로 클러스터가 주기적으로 응답 불가 상태가 될 수 있다.

**원인 분석**:
1. 힙 크기 부족: 현재 데이터 볼륨에 비해 힙이 작다
2. fielddata 과다 사용: text 필드에 집계를 수행하는 쿼리가 fielddata를 많이 생성
3. 세그먼트 수 과다: 너무 많은 세그먼트가 메모리를 점유
4. 메모리 누수: 특정 쿼리나 집계가 메모리를 많이 사용

**확인 방법**:
```
# JVM 상세 확인
GET /_nodes/stats/jvm

# fielddata 사용량 확인
GET /_nodes/stats/indices/fielddata

# 서킷 브레이커 tripped 여부 확인
GET /_nodes/stats/breaker
```

**조치 방안**:
1. 즉시: 불필요한 fielddata 캐시 지우기 → `POST /_cache/clear?fielddata=true`
2. 단기: 힙 크기 증설 (최대 물리 메모리의 50%, 31GB 초과 금지)
3. 중장기: fielddata 대신 `keyword` 필드 + doc_values 사용으로 쿼리 최적화

</details>

---

### Q6. Cat API와 `_cluster` REST API의 차이점과 각각의 적절한 사용 시나리오를 설명하라

<details>
<summary>정답 보기</summary>

**차이점**:

| 구분 | Cat API | REST API (`_cluster`) |
|------|---------|----------------------|
| 출력 형식 | 텍스트, 탭 구분 테이블 | JSON |
| 사용 목적 | 콘솔에서 사람이 직접 읽기 | 프로그램으로 파싱하여 활용 |
| 가독성 | 높음 (콘솔 친화적) | 낮음 (구조적이나 장황) |
| 파싱 편의성 | 낮음 | 높음 |

**Cat API 사용 시나리오**:
```bash
# 운영 중 긴급하게 클러스터 상태 확인
curl -X GET "localhost:9200/_cat/health?v"

# 어느 샤드가 UNASSIGNED인지 빠르게 파악
GET /_cat/shards?v&h=index,shard,prirep,state,unassigned.reason

# 노드별 디스크 사용량 확인
GET /_cat/allocation?v
```

**REST API 사용 시나리오**:
```python
# Python으로 힙 사용률 주기적 수집 및 알림
import requests
response = requests.get("http://localhost:9200/_nodes/stats/jvm")
data = response.json()
for node_id, node in data["nodes"].items():
    heap_percent = node["jvm"]["mem"]["heap_used_percent"]
    if heap_percent > 80:
        send_alert(f"Node {node['name']}: heap {heap_percent}%")
```

실무에서는 운영자의 콘솔 작업에는 Cat API, 모니터링 시스템 자동화에는 REST API를 사용한다.

</details>

---

### Q7. 다음 상황에서 어떤 API를 사용해 원인을 파악할 것인가?

**상황**: 특정 인덱스에 대한 검색 응답 시간이 갑자기 평소의 3배로 늘어났다.

순서대로 확인해야 할 API와 각 단계에서 확인할 내용을 설명하시오.

<details>
<summary>정답 보기</summary>

**1단계: 클러스터 전체 Health 확인**
```
GET /_cluster/health
```
- status가 green인지 확인
- relocating_shards, unassigned_shards 값 확인

**2단계: 노드 스레드풀 확인**
```
GET /_nodes/stats/thread_pool
```
또는
```
GET /_cat/thread_pool?v
```
- `search` 스레드풀의 queue, rejected 값 확인
- 대기열이 쌓여있으면 과부하 상태

**3단계: JVM 상태 확인**
```
GET /_nodes/stats/jvm
```
- heap_used_percent 75% 이상인 노드 확인
- gc.collectors.old.collection_count 증가 여부 확인
- GC 압박으로 STW가 빈번하면 검색 응답 지연 발생

**4단계: 인덱스 통계 확인**
```
GET /{인덱스명}/_stats
```
- `search.query_time_in_millis / search.query_total` 로 평균 검색 시간 계산
- `merges.current` 확인 (활발한 병합 중이면 I/O 경쟁으로 검색 지연 가능)

**5단계: 노드 별 OS/FS 확인**
```
GET /_nodes/stats/os,fs
```
- CPU 사용률, 메모리 사용률 확인
- 디스크 I/O 통계 확인 (`io_stats`)

**결론**: 이 순서로 병목이 되는 지점을 좁혀가며 원인을 파악한다. JVM GC 압박, 스레드풀 과부하, 세그먼트 병합, 디스크 I/O 포화가 주요 원인이다.

</details>

---

### Q8. 메트릭비트 모니터링 아키텍처를 설계할 때 프로덕션 클러스터와 모니터링 클러스터를 분리해야 하는 이유는?

<details>
<summary>정답 보기</summary>

**핵심 이유: 모니터링의 독립성 보장**

모니터링 데이터를 프로덕션 클러스터 자체에 저장하면 다음 문제가 발생한다:

1. **장애 시 모니터링 불가**: 프로덕션 클러스터가 장애로 다운되면 모니터링 데이터도 같이 사라진다. 장애의 원인을 파악해야 할 때 정작 필요한 데이터를 볼 수 없다.

2. **리소스 경쟁**: 모니터링 데이터 색인이 프로덕션 서비스와 자원(CPU, 메모리, 디스크 I/O)을 경쟁하게 된다. 고부하 상황에서 모니터링이 장애를 악화시킬 수 있다.

3. **노이즈**: 모니터링 색인 작업이 통계 지표에 포함되어 실제 서비스 지표 분석이 어려워진다.

**권장 아키텍처**:
```
[프로덕션 ES 클러스터] → [Metricbeat] → [모니터링 전용 ES 클러스터 + Kibana]
```

모니터링 클러스터는 서비스 규모가 작으면 소규모로 구성해도 된다. 단, Kibana 알럿 기능을 사용하려면 모니터링 클러스터 노드에 `remote_cluster_client` 역할을 추가하고 TLS와 기본 인증이 설정되어 있어야 한다.

</details>

---

## 심화 (20%)

### Q9. 서킷 브레이커(Circuit Breaker)의 작동 원리와 종류를 설명하고, `tripped` 값이 증가하는 상황에서의 대응 방법을 서술하라

<details>
<summary>정답 보기</summary>

**작동 원리**:

엘라스틱서치는 과도한 요청이 들어왔을 때 노드가 다운되는 것보다 요청을 거부하는 정책을 선택한다. 서킷 브레이커는 요청이 얼마만큼의 메모리를 사용할지 예상하는 방법과 현재 실제 메모리 사용량을 체크하는 방법을 사용해 임계값 초과 시 요청을 사전 차단한다.

서킷 브레이커가 발동되면 클라이언트에게 `CircuitBreakingException`이 반환된다. 자동 재시도는 엘라스틱서치가 해주지 않으며 클라이언트의 책임이다.

**종류 (계층 구조)**:

```
parent (부모) - 실제 메모리 기준, 기본값 힙의 70% (실제 메모리 체크 시 95%)
├── fielddata  - fielddata 캐시 제한, 기본값 힙의 40%
├── request    - 요청당 집계 등 제한, 기본값 힙의 60%
├── in_flight_requests - transport/HTTP 수신 데이터, 기본값 힙의 100%
└── accounting - 루씬 세그먼트 등 해제 안 되는 메모리, 기본값 힙의 100%
```

> 엘라스틱서치 바이블에서는 fielddata 서킷 브레이커 기본값을 힙의 40%로 설명한다. 실무가이드 예시에서는 60%로 설정된 사례가 나오는데, 이는 동적으로 변경된 설정이다.

**tripped 증가 시 대응**:

1. **진단**: 어떤 브레이커가 tripped되고 있는지 확인
```
GET /_nodes/stats/breaker
```

2. **fielddata 브레이커 tripped 시**:
   - text 필드에 집계를 수행하는 쿼리 제거 또는 `keyword` 필드로 변경
   - fielddata 캐시 비우기: `POST /_cache/clear?fielddata=true`
   - 필요시 한시적으로 limit 상향 (근본 해결 아님):
   ```
   PUT /_cluster/settings
   {
     "transient": {
       "indices.breaker.fielddata.limit": "50%"
     }
   }
   ```

3. **request 브레이커 tripped 시**:
   - 무거운 집계 쿼리를 작은 단위로 분할
   - 집계 결과를 캐시하는 구조로 쿼리 최적화

4. **parent 브레이커 tripped 시**:
   - 힙 크기 증설 (최대 31GB)
   - 노드 추가
   - 7 버전 이상에서는 parent 브레이커가 실제 메모리를 체크하므로 안정성이 높다

</details>

---

### Q10. `_nodes/stats`의 `jvm.gc` 정보만으로 현재 엘라스틱서치 노드의 GC 압박 상태를 어떻게 정량적으로 판단할 수 있는가? 구체적인 계산 방법을 제시하라

<details>
<summary>정답 보기</summary>

**GC 통계의 특성**:

`_nodes/stats`의 GC 정보는 노드 시작 이후의 **누적값**이다. 따라서 현재 순간의 GC 압박을 보려면 짧은 시간 간격으로 두 번 호출해 증분값을 계산해야 한다.

**정량적 판단 방법**:

**1. GC 오버헤드 비율 계산**

t1 시점과 t2 시점의 값 차이:
```
old_gc_time_delta = old.collection_time_in_millis[t2] - old.collection_time_in_millis[t1]
elapsed_time = t2 - t1 (ms)
gc_overhead = old_gc_time_delta / elapsed_time * 100 (%)
```

- 5% 미만: 정상
- 5~10%: 주의 (GC 최적화 검토)
- 10% 이상: 위험 (JVM이 시간의 10% 이상을 GC에 소비)

JVM 자체적으로도 GC overhead가 98%를 초과하면 OutOfMemoryError를 발생시킨다.

**2. Old GC 빈도 계산**
```
old_gc_count_delta = old.collection_count[t2] - old.collection_count[t1]
old_gc_per_minute = old_gc_count_delta / (elapsed_time / 60000)
```

- 0회/분: 이상적
- 1~2회/분: 주의 (힙 설정 재검토)
- 3회 이상/분: 위험 (즉각 조치 필요)

**3. 힙 사용률과의 상관관계**

Old GC가 자주 발생하는데도 힙 사용률이 낮아지지 않는다면 (예: GC 후에도 85% 이상 유지) 메모리 누수나 fielddata 과다 적재를 의심한다.

**실무 팁**:
메트릭비트로 이 값들을 시계열로 저장해두면 Kibana에서 그래프로 추이를 확인할 수 있다. 단발성 확인보다 추세 모니터링이 훨씬 유효하다.

</details>
