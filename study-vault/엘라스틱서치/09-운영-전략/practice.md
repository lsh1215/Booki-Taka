# 09 - 운영 전략: 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch12 / 엘라스틱서치바이블 Ch6
> 태그: #alias #rollover #ilm #data-stream #snapshot #shard-strategy #rolling-restart

총 10문제 | 기초 4문제 (40%) | 응용 4문제 (40%) | 심화 2문제 (20%)

---

## 기초 (40%)

### 문제 1
운영 중인 인덱스 `service-data-v1`에 대해 alias `service-data`를 설정하고, 이후 새 인덱스 `service-data-v2`로 무중단 전환하려 한다. 다음 빈칸에 들어갈 올바른 API 요청을 작성하라.

```
# 1단계: service-data-v1에 alias 지정
POST _aliases
{
  "actions": [
    { ___(A)___ }
  ]
}

# 2단계: v2 생성 후 alias를 v2로 전환
POST _aliases
{
  "actions": [
    { ___(B)___ },  // v1 제거
    { ___(C)___ }   // v2 추가
  ]
}
```

<details>
<summary>정답 보기</summary>

**(A) v1에 alias 추가:**
```json
{
  "add": {
    "index": "service-data-v1",
    "alias": "service-data"
  }
}
```

**(B) v1에서 alias 제거:**
```json
{
  "remove": {
    "index": "service-data-v1",
    "alias": "service-data"
  }
}
```

**(C) v2에 alias 추가:**
```json
{
  "add": {
    "index": "service-data-v2",
    "alias": "service-data"
  }
}
```

핵심: `actions` 배열에 remove와 add를 원자적으로 실행하면 다운타임 없이 alias가 전환된다.
</details>

---

### 문제 2
롤링 리스타트를 수행하기 위한 절차를 올바른 순서로 나열하라.

```
(A) POST _flush
(B) GET _cat/health?v  // green 상태 대기
(C) PUT _cluster/settings { "transient": { "cluster.routing.allocation.enable": "primaries" } }
(D) 노드 프로세스를 종료하고 재기동
(E) PUT _cluster/settings { "transient": { "cluster.routing.allocation.enable": "all" } }
```

<details>
<summary>정답 보기</summary>

**올바른 순서: C → A → D → E → B**

1. **(C) 샤드 할당 비활성화**: 노드 재기동 시 불필요한 복제본 샤드 재생성 방지
2. **(A) flush 수행**: translog를 비워 재기동 후 샤드 복구 시간 단축 (필수는 아니나 권장)
3. **(D) 노드 재기동**: 기존 프로세스 완전 종료 확인 후 기동
4. **(E) 샤드 할당 활성화**: 재기동 완료 후 다시 all로 복원
5. **(B) green 상태 대기**: green이 되면 다음 노드 재기동

green 확인 후 다음 노드에 대해 C → A → D → E → B를 반복한다.
</details>

---

### 문제 3
다음 중 데이터 스트림과 alias 기반 구성의 차이점으로 올바르지 않은 것을 고르라.

```
(A) 데이터 스트림은 반드시 인덱스 템플릿과 연계해서 생성해야 한다.
(B) 데이터 스트림에서는 문서 업데이트가 불가능하다.
(C) 데이터 스트림은 @timestamp 필드를 포함하지 않아도 된다.
(D) 데이터 스트림의 뒷받침 인덱스 이름은 고정된 패턴을 따른다.
(E) 데이터 스트림은 롤오버 시 새 인덱스 이름을 직접 지정할 수 없다.
```

<details>
<summary>정답 보기</summary>

**(C)가 틀린 설명이다.**

데이터 스트림은 반드시 `@timestamp` 필드(`date` 또는 `date_nanos` 타입)가 포함된 문서만을 취급한다.

나머지 보기는 모두 올바른 설명:
- (A) 인덱스 템플릿 연계 필수
- (B) 문서 추가만 가능, 업데이트는 `update_by_query` 사용
- (D) 뒷받침 인덱스 이름 패턴: `.ds-<데이터 스트림 이름>-<yyyy.MM.dd>-<000001>`
- (E) 롤오버 시 이름 직접 지정 불가
</details>

---

### 문제 4
ILM의 각 페이즈에서 수행할 수 있는 액션을 연결하라.

```
페이즈          | 액션
----------------|----------------------------
(A) hot         | (1) migrate (데이터 티어 이동)
(B) warm        | (2) 롤오버
(C) cold        | (3) 스냅샷 대기 후 삭제
(D) delete      | (4) shrink (샤드 개수 줄이기)
```

<details>
<summary>정답 보기</summary>

| 페이즈 | 가능한 액션 | 정답 연결 |
|---|---|---|
| hot (A) | 롤오버, 읽기 전용, 세그먼트 병합(롤오버 함께), shrink(롤오버 함께) | **A - (2)** |
| warm (B) | 읽기 전용, 세그먼트 병합, shrink, 할당, migrate, 인덱스 우선순위 변경 | **B - (4)** |
| cold (C) | 읽기 전용, 할당, migrate, 인덱스 우선순위 변경 | **C - (1)** |
| delete (D) | 스냅샷 대기, 삭제 | **D - (3)** |

추가 포인트:
- 롤오버는 **hot 페이즈에서만** 수행 가능
- migrate는 **warm, cold** 페이즈에서 수행 가능 (같은 페이즈에 할당 액션 없으면 자동 추가)
- 스냅샷 대기는 **delete 페이즈에서만** 수행 가능 (ILM + SLM 연동)
</details>

---

## 응용 (40%)

### 문제 5
다음 롤오버 설정에서 오류를 찾고 수정하라.

```json
// 인덱스 생성
PUT my-logs

// alias 설정
POST _aliases
{
  "actions": [
    {
      "add": {
        "index": "my-logs",
        "alias": "logs-alias",
        "is_write_index": true
      }
    }
  ]
}

// 롤오버 시도
POST logs-alias/_rollover
```

<details>
<summary>정답 보기</summary>

**오류: 인덱스 이름이 롤오버 이름 패턴을 따르지 않는다.**

롤오버를 수행할 alias 내 `is_write_index: true` 인덱스의 이름은 반드시 `.*-\d+$` 패턴을 따라야 한다.

- `my-logs` → **롤오버 불가** (숫자 접미사 없음)
- `my-logs-000001` → **롤오버 가능** (롤오버 시 `my-logs-000002` 자동 생성)

**수정 방법:**
```
PUT my-logs-000001
POST _aliases
{
  "actions": [
    {
      "add": {
        "index": "my-logs-000001",
        "alias": "logs-alias",
        "is_write_index": true
      }
    }
  ]
}
POST logs-alias/_rollover
```

예외: `POST [alias]/_rollover/[새 인덱스 이름]`처럼 새 인덱스 이름을 직접 지정하면 기존 인덱스와 새 인덱스 모두 패턴 규칙 불필요. 단, 이 경우 alias만 대상으로 지정 가능 (데이터 스트림 불가).
</details>

---

### 문제 6
아래 시나리오에서 shrink 대신 reindex를 선택해야 하는 이유를 설명하고, reindex + alias를 활용한 무중단 마이그레이션 절차를 작성하라.

**시나리오:** `product-index` 인덱스가 샤드 8개로 운영 중인데, 데이터가 적어져 샤드 2개로 줄이고 싶다. 현재 서비스 중이며 중단 없이 처리해야 한다.

<details>
<summary>정답 보기</summary>

**shrink 대신 reindex를 선택해야 하는 이유:**

shrink는 다음 제약이 있다:
1. `index.blocks.write: true` - 읽기 전용 상태여야 함 (운영 중 쓰기 불가)
2. 한 노드가 로컬에 모든 샤드를 보유하고 있어야 함
3. 클러스터 상태가 green이어야 함
4. 새 인덱스의 샤드 개수는 원본의 약수여야 함

운영 중인 인덱스는 쓰기가 계속 발생하므로 shrink 적용이 어렵다. reindex는 이러한 제약 없이 안전하게 수행 가능하다.

**reindex + alias 무중단 마이그레이션 절차:**

```
# 1. 기존 인덱스에 alias 설정 (미리 설정되어 있지 않다면)
POST _aliases
{
  "actions": [{ "add": { "index": "product-index", "alias": "product" } }]
}

# 2. 새 인덱스 생성 (샤드 2개)
PUT product-index-v2
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1
  }
}

# 3. reindex 실행 (비동기로 진행 중에도 서비스 계속)
POST _reindex?wait_for_completion=false
{
  "source": { "index": "product-index" },
  "dest": { "index": "product-index-v2" }
}

# 4. reindex 완료 후 alias를 v2로 전환 (원자적)
POST _aliases
{
  "actions": [
    { "remove": { "index": "product-index", "alias": "product" } },
    { "add": { "index": "product-index-v2", "alias": "product" } }
  ]
}

# 5. 구 인덱스 삭제 (확인 후)
DELETE product-index
```

포인트: 서비스는 항상 `product` alias를 바라보므로 alias 전환 시점에 무중단으로 전환된다.
</details>

---

### 문제 7
스냅샷 저장소에 스냅샷이 300개 이상 쌓였을 때 발생할 수 있는 문제와 해결 방법을 설명하라.

<details>
<summary>정답 보기</summary>

**문제:**
엘라스틱서치의 스냅샷은 **증분 백업 방식**으로 동작한다. 스냅샷 작업을 시작할 때 저장소 내 다른 모든 스냅샷의 정보를 메모리로 올리는 선행 작업을 수행한다.

- 저장소에 스냅샷이 많을수록 이 선행 작업이 느려짐
- 스냅샷 작업을 비동기로 요청해도 이 선행 작업이 완료되어야 비동기 응답 반환
- **너무 무거운 저장소는 마스터 노드에 부담**

엘라스틱서치의 저장소당 최대 스냅샷 개수 기본값은 **500개**. 이 최댓값 설정을 올리는 것은 좋지 않다.

**해결 방법:**
1. **SLM 정책 설정**: `retention.max_count`를 적절히 제한 (예: 100개)
2. **저장소 분리**: 용도별로 여러 저장소를 나눠서 스냅샷 관리
   ```
   PUT _snapshot/daily-snapshots    # 일별 스냅샷용
   PUT _snapshot/weekly-snapshots   # 주별 스냅샷용
   ```
3. **오래된 스냅샷 수동 삭제**:
   ```
   DELETE _snapshot/[저장소 이름]/[스냅샷 이름]
   ```
   증분 백업이므로 다른 스냅샷에 영향 없는 파일만 삭제됨.
4. **SLM retention 스케줄 설정**: 만료된 스냅샷 자동 삭제 스케줄 지정
</details>

---

### 문제 8
다음 ILM 정책을 분석하고, 인덱스 생성 후 각 단계가 언제 수행되는지 시나리오를 작성하라.

```json
PUT _ilm/policy/my-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "8gb",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "3d",
        "actions": {
          "forcemerge": { "max_num_segments": 1 },
          "readonly": {}
        }
      },
      "cold": {
        "min_age": "7d",
        "actions": {
          "allocate": { "number_of_replicas": 0 }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "wait_for_snapshot": { "policy": "my-slm-policy" },
          "delete": {}
        }
      }
    }
  }
}
```

<details>
<summary>정답 보기</summary>

**시나리오 분석:**

**Day 0: 인덱스 생성 → hot 페이즈 진입**
- `min_age: "0ms"` → 즉시 hot 페이즈
- 롤오버 조건 감시 시작:
  - 조건 1: 주 샤드 크기가 8GB 초과
  - 조건 2: 인덱스 생성 후 1일 경과
- 두 조건 중 하나라도 만족하면 자동 롤오버 (새 인덱스 생성, 쓰기 대상 전환)

**Day 1 이후: 롤오버된 인덱스 → 여전히 hot 페이즈**
- hot 페이즈의 `min_age: "0ms"` 기준으로 롤오버된 인덱스도 즉시 hot 진입
- 단, warm 전환은 **인덱스 생성 후 3일** 기준

**Day 3: warm 페이즈 전환**
- `min_age: "3d"` 조건 충족 + hot 페이즈 액션 완료
- 수행 액션:
  - `forcemerge`: 세그먼트를 1개로 강제 병합 (검색 성능 향상, 리소스 절약)
  - `readonly`: 읽기 전용으로 변경
- warm 페이즈의 migrate 액션이 자동 추가되어 `data_warm` 티어 노드로 이동

**Day 7: cold 페이즈 전환**
- `min_age: "7d"` 조건 충족
- 수행 액션:
  - `allocate: { number_of_replicas: 0 }`: 복제본 샤드 0개로 줄임 (스토리지 절약)
- cold 티어 노드로 이동

**Day 30: delete 페이즈 전환**
- `min_age: "30d"` 조건 충족
- 수행 액션:
  - `wait_for_snapshot`: `my-slm-policy`에 의해 스냅샷 백업 완료될 때까지 대기
  - 백업 완료 후 `delete`: 인덱스 삭제

**중요 포인트:**
- ILM은 `indices.lifecycle.poll_interval` (기본 10분) 주기로 상태를 체크한다.
- yellow 상태(미할당 샤드)여도 다음 페이즈로 전환된다.
- delete 페이즈의 `wait_for_snapshot`은 SLM으로 찍은 스냅샷이 해당 인덱스를 포함해야 통과된다.
</details>

---

## 심화 (20%)

### 문제 9
다음 상황을 보고 샤드 개수 설계 문제를 진단하고 해결 방안을 제시하라.

**상황:**
- 클러스터: 데이터 노드 5대, 각 노드 힙 메모리 32GB
- 인덱스 수: 약 200개
- 인덱스당 샤드 수: primary 5개, replica 1개 → 인덱스당 10 샤드
- 전체 샤드 수: 200 × 10 = 2,000 샤드
- 증상: 클러스터가 느려지고 마스터 노드에 부하 집중

<details>
<summary>정답 보기</summary>

**문제 진단:**

1. **과도한 샤드 개수**
   - 힙 1GB당 샤드 20개 가이드라인: 32GB × 20 = 노드당 640 샤드 이하
   - 실제: 2,000 샤드 ÷ 5 노드 = 노드당 400 샤드
   - 가이드라인 내이나 "빡빡한" 수준. 200개 인덱스면 각 인덱스 특성 고려 필요

2. **인덱스당 샤드 5개가 적절한가**
   - 작은 인덱스에 5 샤드는 과도함 (샤드가 지나치게 작아짐)
   - 큰 인덱스에 5 샤드로는 부족할 수 있음

3. **마스터 노드 부하**: 샤드가 많을수록 클러스터 상태 관리 비용이 마스터 노드에 집중

**해결 방안:**

1. **소형 인덱스의 샤드 수 감소**
   - 크기가 작은 인덱스는 `number_of_shards: 1` 또는 `2`로 설정
   - `GET _cat/shards?v&s=store:desc`로 인덱스별 크기 확인
   - 목표: 샤드 하나당 수 GB 내외

2. **ILM + 데이터 티어 구조 도입**
   - 오래된 인덱스는 cold 페이즈에서 복제본 0개로 설정 (전체 샤드 수 감소)
   - warm 페이즈에서 shrink로 샤드 수 축소

3. **시계열 인덱스 전략 도입**
   - 단일 대형 인덱스가 있다면 롤오버로 분할
   - 오래된 인덱스는 자연스럽게 삭제

4. **즉각적인 조치: reindex로 과도한 샤드 개수 인덱스 재생성**
   ```
   # 소형 인덱스들의 샤드 개수를 줄인 새 인덱스로 reindex
   # alias + reindex로 무중단 처리
   ```

5. **모니터링 기준 수립**
   ```
   GET _cat/allocation?v          # 노드별 샤드 수 확인
   GET _cat/shards?v&s=store:desc  # 인덱스별 샤드 크기 확인
   GET _cat/health?v              # 전체 샤드 수 확인
   ```
</details>

---

### 문제 10
엘라스틱서치 클러스터를 버전 5에서 버전 8로 업그레이드해야 한다. 직접 5→8 업그레이드가 불가한 이유와, 단계적 업그레이드 계획을 스냅샷 호환성 문제를 포함해 설명하라.

<details>
<summary>정답 보기</summary>

**직접 5→8 업그레이드가 불가한 이유:**

엘라스틱서치는 **메이저 버전이 둘 이상 차이나는 클러스터에서 생성된 인덱스에 대해 하위 호환을 지원하지 않는다.**

- 5버전 인덱스가 남아있는 상태에서 7버전으로 업그레이드하면 해당 인덱스가 제대로 인식되지 않아 문제 발생
- 따라서 **5 → 6 → 7 → 8 순서로 단계적 업그레이드** 필요

**단계적 업그레이드 계획:**

**사전 준비 단계 (버전 5에서 수행)**
1. `_cat/indices?v`로 5버전에서 생성된 오래된 인덱스 식별
2. 불필요한 인덱스 삭제
3. 필요한 오래된 인덱스는 reindex로 새 인덱스 생성 (alias로 서비스 무중단)
4. `_source` 활성화 상태 확인
5. 스냅샷 백업 수행

**5 → 6 업그레이드**
- 롤링 리스타트 방식: 샤드 할당 비활성화 → flush → 노드 업그레이드 → 할당 활성화 → green 대기
- 업그레이드 완료 후 5버전 인덱스 모두 삭제 또는 reindex

**6 → 7 업그레이드**
- 6버전 인덱스 중 오래된 것 정리
- 동일한 롤링 리스타트 방식

**7 → 8 업그레이드**
- 동일한 롤링 리스타트 방식

**스냅샷 호환성 문제:**
- 5버전에서 생성한 스냅샷을 7버전에서 복구 불가 (메이저 버전 둘 이상 차이)
- **해결책**: 오래된 스냅샷이 필요할 경우 6버전 임시 클러스터 세팅 후 복구
  ```
  # 6버전 임시 클러스터에 동일한 스냅샷 저장소 등록
  PUT _snapshot/old-repo { ... }

  # 5버전 스냅샷에서 인덱스 복구
  POST _snapshot/old-repo/snapshot_v5/_restore { ... }

  # 필요 작업 수행 후 7버전 이상 클러스터로 이전
  ```

**운영 전략 권장사항:**
- 시계열 인덱스 이름 전략 + ILM 도입으로 오래된 인덱스가 자동 삭제되는 구조 유지
- 이 경우 메이저 버전 업그레이드 시 구버전 인덱스 문제가 자연스럽게 줄어듦
- alias 설정을 사전에 해두어 언제든 reindex로 전환 가능하도록 준비
</details>
