# 컨슈머

> 출처: 카프카 핵심 가이드 Ch4, 실전카프카 Ch3·Ch6, 아파치 카프카 애플리케이션 프로그래밍 Ch3
> 태그: #consumer #consumer-group #rebalance #offset-commit #polling #partition-assignment #coordinator

## 이 토픽의 근본 문제

대규모 데이터를 여러 소비자가 협력하여 처리하면서, 장애 시에도 데이터를 빠뜨리거나 중복 처리하지 않으려면 어떻게 해야 하는가

---

## 전체 구조

```
Kafka Cluster
┌─────────────────────────────────────────────────────┐
│  Topic: orders (4 partitions)                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Part 0  │ │  Part 1  │ │  Part 2  │ │ Part 3 │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
│       │             │            │            │      │
│  Group Coordinator (Broker)                         │
│  - __consumer_offsets 파티션 리더                    │
│  - heartbeat 모니터링, 리밸런스 트리거               │
└───────┬─────────────┬────────────┬────────────┬─────┘
        │             │            │            │
   ─────────────────────────────────────────────────
   Consumer Group: "order-processor" (group.id)
   ┌────────────┐        ┌────────────┐
   │ Consumer1  │        │ Consumer2  │
   │ [Part0,1]  │        │ [Part2,3]  │
   └────────────┘        └────────────┘

   다른 그룹: "order-analytics" → 같은 토픽을 독립 소비
```

---

## 1. 컨슈머 그룹 (Consumer Group)

### 정의

같은 `group.id`를 공유하는 컨슈머들의 논리적 묶음. 카프카가 메시지를 분산 처리하는 핵심 단위.

### 왜 필요한가

단일 컨슈머는 처리 속도에 한계가 있다. 여러 컨슈머가 같은 토픽을 읽으면 중복 소비가 발생한다. 컨슈머 그룹은 파티션 단위로 독점 할당하여 중복 없이 병렬 처리를 가능하게 한다.

### 동작 원리

- 각 파티션은 그룹 내 **하나의 컨슈머에만** 할당
- 파티션 수 > 컨슈머 수: 일부 컨슈머가 여러 파티션 담당
- 파티션 수 < 컨슈머 수: 초과 컨슈머는 유휴(idle) 상태
- 다른 `group.id` → 같은 파티션을 독립적으로 소비 (pub/sub 패턴 구현)

```
파티션 4개, 컨슈머 2개:         파티션 2개, 컨슈머 4개:
┌─────────────────────┐        ┌─────────────────────┐
│ C1: [P0, P1]        │        │ C1: [P0]            │
│ C2: [P2, P3]        │        │ C2: [P1]            │
└─────────────────────┘        │ C3: [] (유휴)        │
                               │ C4: [] (유휴)        │
                               └─────────────────────┘
```

### 설계 트레이드오프

| 선택 | 장점 | 단점 |
|------|------|------|
| 컨슈머 수 = 파티션 수 | 최대 병렬성, 1:1 할당 | 스케일아웃 한계 |
| 컨슈머 수 < 파티션 수 | 유연한 확장 여지 | 일부 컨슈머 과부하 |
| 컨슈머 수 > 파티션 수 | 빠른 장애 복구 대기 | 자원 낭비 |

> 관련: [그룹 코디네이터](#3-그룹-코디네이터-group-coordinator), [리밸런스](#2-리밸런스-rebalance), [파티션 할당 전략](#6-파티션-할당-전략-partition-assignment-strategy)

---

## 2. 리밸런스 (Rebalance)

### 정의

컨슈머 그룹 내에서 파티션 할당을 재조정하는 과정.

### 왜 필요한가

컨슈머가 추가되거나 장애로 이탈하면 파티션 할당이 무효화된다. 리밸런스 없이는 특정 파티션의 메시지 소비가 중단된다.

### 트리거 조건

1. 컨슈머 그룹에 새 컨슈머 참가
2. 컨슈머가 명시적으로 이탈하거나 크래시
3. `session.timeout.ms` 내 heartbeat 미수신
4. `max.poll.interval.ms` 초과 (처리 지연)
5. 토픽 파티션 수 변경 (동적 파티션 추가 등)

### Eager 리밸런스 (기존 방식)

```
Phase 1: 모든 파티션 해제 (Stop-The-World)
  C1: [P0,P1] → []    C2: [P2,P3] → []
  ↓ 전체 컨슈머가 일시 중단
Phase 2: 재할당
  C1: [P0,P1,P2] → 처리 재개
  C2: [P3]       → 처리 재개
```

- 단순하고 구현이 명확
- 리밸런스 중 전체 소비 중단 (STW)

### Cooperative(Incremental) 리밸런스 (최신 방식)

```
Phase 1: 이동이 필요한 파티션만 해제
  C1: [P0,P1] 유지      C2: [P2,P3] → [P3] (P2만 해제)
  ↓ 해제된 파티션만 재할당
Phase 2: P2 → C1에 추가
  C1: [P0,P1,P2]        C2: [P3]
  나머지는 중단 없이 계속 처리
```

- 중단 최소화, 부분 중단만 발생
- 여러 라운드 필요, 구현 복잡
- `CooperativeStickyAssignor` 사용 필요

### 설계 트레이드오프

| 방식 | 중단 시간 | 구현 복잡도 | 적합한 상황 |
|------|-----------|-------------|-------------|
| Eager | STW (전체) | 단순 | 짧은 처리, 정확성 우선 |
| Cooperative | 최소 (부분) | 복잡 | 고처리량, 지연 민감 |

> 관련: [그룹 코디네이터](#3-그룹-코디네이터-group-coordinator), [폴링](#5-폴링-polling), [안전한 종료](#7-컨슈머-안전한-종료)

---

## 3. 그룹 코디네이터 (Group Coordinator)

### 정의

컨슈머 그룹의 생명주기를 관리하는 브로커 측 컴포넌트.

### 왜 필요한가

분산 환경에서 여러 컨슈머의 상태를 추적하고 일관된 파티션 할당을 보장하는 중앙 조율자가 필요하다.

### 동작 원리

```
코디네이터 결정 방법:
  hash(group.id) % __consumer_offsets 파티션 수
  → 해당 파티션의 리더 브로커 = 그룹 코디네이터

컨슈머 참가 흐름:
  Consumer → FindCoordinator 요청
           ← 코디네이터 브로커 주소
  Consumer → JoinGroup 요청 (최초 컨슈머 = 그룹 리더 선출)
  그룹 리더 → 파티션 할당 계획 수립 (AssignmentStrategy 사용)
  그룹 리더 → SyncGroup (할당 계획 전달)
  코디네이터 → 각 컨슈머에 할당 결과 전파
```

### 역할 분리

| 주체 | 역할 |
|------|------|
| 그룹 코디네이터 (브로커) | 멤버십 관리, heartbeat 수신, 리밸런스 트리거, 오프셋 저장 |
| 그룹 리더 (컨슈머) | 파티션 할당 계획 계산, SyncGroup으로 코디네이터에 전달 |

### Heartbeat

- 별도 heartbeat 스레드에서 `heartbeat.interval.ms`(기본 3초)마다 전송
- `session.timeout.ms`(기본 45초) 내 미수신 시 컨슈머 이탈 처리 → 리밸런스 트리거

> 관련: [컨슈머 그룹](#1-컨슈머-그룹-consumer-group), [리밸런스](#2-리밸런스-rebalance), [오프셋 커밋](#4-오프셋-커밋-offset-commit)

---

## 4. 오프셋 커밋 (Offset Commit)

### 정의

컨슈머가 특정 파티션에서 어디까지 메시지를 읽었는지 기록하는 행위.

### 왜 필요한가

컨슈머가 재시작되거나 다른 컨슈머로 파티션이 재할당될 때, 어디서부터 다시 읽을지 알 수 없으면 전체를 재처리하거나 일부를 유실한다.

### 저장 위치

```
__consumer_offsets 토픽 (내부 토픽, 기본 50개 파티션)
키: [group.id, topic, partition]
값: offset + metadata + timestamp
```

### 자동 커밋

```properties
enable.auto.commit=true      # 기본값
auto.commit.interval.ms=5000 # 기본 5초
```

- `poll()` 호출 시 인터벌이 지났으면 이전 poll에서 반환된 마지막 오프셋 커밋
- 중복 위험: 처리 중 크래시 시 미커밋 오프셋 재처리
- 유실 위험: 리밸런스 시점에 따라 처리 안 된 오프셋이 커밋될 수 있음

### 수동 커밋

```java
// 동기 커밋: commitSync()
// - 커밋 성공까지 블로킹, 실패 시 재시도
// - 처리량 저하, 안전성 우선
consumer.commitSync();

// 비동기 커밋: commitAsync()
// - 논블로킹, 콜백으로 결과 확인
// - 실패 시 자동 재시도 없음 (순서 보장 문제)
consumer.commitAsync((offsets, exception) -> {
    if (exception != null) {
        log.error("커밋 실패", exception);
    }
});

// 혼합 패턴: 평상시 비동기, 종료 시 동기
try {
    while (running) {
        records = consumer.poll(Duration.ofMillis(100));
        process(records);
        consumer.commitAsync();
    }
} finally {
    consumer.commitSync(); // 마지막은 동기로 보장
    consumer.close();
}
```

### 중복 vs 유실 시나리오

```
처리 후 커밋 (at-least-once):
  read → process → [crash] → restart → 재처리 → 중복 발생
  ↑ 일반적으로 선호, 비즈니스 로직에서 멱등성 보장

커밋 후 처리 (at-most-once):
  read → commit → [crash] → restart → 해당 메시지 유실
  ↑ 일부 로그 수집처럼 유실이 허용될 때
```

### 설계 트레이드오프

| 방식 | 처리량 | 안전성 | 중복 위험 |
|------|--------|--------|-----------|
| 자동 커밋 | 높음 | 낮음 | 중간 |
| 수동 동기 | 낮음 | 높음 | 낮음 |
| 수동 비동기 | 높음 | 중간 | 중간 |
| 혼합 | 높음 | 높음 | 낮음 |

> 관련: [폴링](#5-폴링-polling), [그룹 코디네이터](#3-그룹-코디네이터-group-coordinator)

---

## 5. 폴링 (Polling)

### 정의

`poll()` 메서드를 반복 호출하여 브로커로부터 레코드를 가져오는 메커니즘.

### 왜 필요한가

카프카는 push 방식이 아닌 pull 방식을 채택한다. 컨슈머가 자신의 처리 속도에 맞게 데이터를 가져올 수 있어 backpressure를 자연스럽게 처리한다.

### poll()이 하는 일

```
poll(Duration timeout) 호출 시:
  1. 브로커에서 레코드 fetch (fetch.min.bytes, fetch.max.wait.ms 기반)
  2. heartbeat 전송 (heartbeat 스레드와 별도)
  3. 리밸런스 처리 (ConsumerRebalanceListener 콜백 실행)
  4. 자동 커밋 인터벌 체크 및 커밋
  5. 레코드 반환
```

### 주요 설정

| 설정 | 기본값 | 역할 |
|------|--------|------|
| `max.poll.records` | 500 | 한 번 poll에서 반환할 최대 레코드 수 |
| `max.poll.interval.ms` | 300000 (5분) | poll() 호출 간 최대 허용 간격 |
| `fetch.min.bytes` | 1 | 브로커가 응답 전 최소 데이터 크기 |
| `fetch.max.wait.ms` | 500 | 최소 데이터 미충족 시 최대 대기 시간 |
| `fetch.max.bytes` | 52428800 (50MB) | 한 번 fetch에서 최대 데이터 크기 |

### max.poll.interval.ms 타임아웃

```
poll() → 처리 → poll() 호출 지연 > max.poll.interval.ms
  → 코디네이터: 컨슈머 이탈 판정 → 리밸런스 트리거
  → WakeupException은 발생하지 않음, 단지 그룹에서 제외됨

해결책:
  - max.poll.records 줄이기 (배치 크기 감소)
  - max.poll.interval.ms 늘리기 (무거운 처리 허용)
  - 처리 로직을 별도 스레드로 분리
```

### 설계 트레이드오프

| 설정 방향 | 장점 | 단점 |
|-----------|------|------|
| poll 자주 (짧은 timeout) | 낮은 지연, 빠른 heartbeat | CPU 사용 증가 |
| poll 드물게 (긴 timeout) | 큰 배치, 효율적 처리 | max.poll.interval.ms 위반 위험 |
| max.poll.records 크게 | 배치 효율 | 처리 시간 증가 |
| max.poll.records 작게 | 빠른 응답 | 처리량 감소 |

> 관련: [오프셋 커밋](#4-오프셋-커밋-offset-commit), [안전한 종료](#7-컨슈머-안전한-종료)

---

## 6. 파티션 할당 전략 (Partition Assignment Strategy)

### 정의

그룹 리더 컨슈머가 파티션을 각 컨슈머에 배분하는 알고리즘.

### 왜 필요한가

균등하지 않은 할당은 특정 컨슈머의 과부하와 다른 컨슈머의 유휴를 초래한다. 리밸런스 시 불필요한 파티션 이동은 처리 중단을 늘린다.

### 전략 비교

**RangeAssignor** (토픽별 범위 분할)

```
Topic A: P0,P1,P2  Topic B: P0,P1,P2  컨슈머: C1,C2

C1 ← [A:P0, A:P1, B:P0, B:P1]   (토픽마다 앞쪽을 C1이 가져감)
C2 ← [A:P2, B:P2]

→ 토픽 수가 많을수록 C1 편중 심화
```

**RoundRobinAssignor** (전체 파티션 라운드로빈)

```
전체 파티션: [A:P0, A:P1, A:P2, B:P0, B:P1, B:P2]

C1 ← [A:P0, A:P2, B:P1]
C2 ← [A:P1, B:P0, B:P2]

→ 균등하지만 리밸런스 시 파티션 이동 많음
```

**StickyAssignor** (기존 할당 유지 + 균등)

```
리밸런스 전: C1:[P0,P1], C2:[P2,P3]
C3 추가 → C1:[P0,P1], C2:[P2], C3:[P3]  ← 최소 이동

→ 이동 최소화하지만 계산 복잡
```

**CooperativeStickyAssignor**

- StickyAssignor + Cooperative 리밸런스 지원
- **현재 권장 기본값**: `[RangeAssignor, CooperativeStickyAssignor]`
- 점진적 마이그레이션 지원 (Eager → Cooperative)

### 설계 트레이드오프

| 전략 | 균등성 | 이동 최소화 | Cooperative 지원 |
|------|--------|-------------|-----------------|
| Range | 낮음 (토픽 많을수록) | 중간 | 미지원 |
| RoundRobin | 높음 | 낮음 | 미지원 |
| Sticky | 높음 | 높음 | 미지원 |
| CooperativeSticky | 높음 | 높음 | 지원 |

> 관련: [리밸런스](#2-리밸런스-rebalance), [컨슈머 그룹](#1-컨슈머-그룹-consumer-group)

---

## 7. 컨슈머 안전한 종료

### 정의

컨슈머를 즉시 종료하면서 그룹에 정상 이탈을 알려 리밸런스를 최소화하는 절차.

### 왜 필요한가

비정상 종료 시 코디네이터는 `session.timeout.ms`(기본 45초)까지 기다린 후 리밸런스를 시작한다. 그 시간 동안 해당 파티션 메시지는 소비되지 않는다.

### 동작 원리

```java
// ShutdownHook에서 호출
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    consumer.wakeup(); // poll()에서 WakeupException 발생시킴
}));

// 메인 루프
try {
    while (true) {
        ConsumerRecords<String, String> records =
            consumer.poll(Duration.ofMillis(100)); // WakeupException 발생
        process(records);
        consumer.commitSync();
    }
} catch (WakeupException e) {
    // 정상 종료 신호 - 무시
} finally {
    consumer.close(); // LeaveGroup 요청 → 즉시 리밸런스 트리거
}
```

```
정상 종료 흐름:
  consumer.wakeup() → WakeupException → consumer.close()
  → LeaveGroup 전송 → 코디네이터 즉시 리밸런스 시작
  → 대기 없이 파티션 재할당

비정상 종료 흐름:
  프로세스 크래시 → 코디네이터 heartbeat 타임아웃 대기 (최대 45초)
  → 그 동안 해당 파티션 메시지 처리 중단
```

> 관련: [폴링](#5-폴링-polling), [리밸런스](#2-리밸런스-rebalance)

---

## 8. 독립 실행 컨슈머 (Standalone Consumer)

### 정의

`subscribe()` 대신 `assign()`으로 파티션을 직접 지정하여 컨슈머 그룹에 참가하지 않는 방식.

### 왜 필요한가

특정 파티션의 특정 오프셋부터 정확히 읽어야 하거나, 리밸런스 없이 고정된 파티션을 처리해야 할 때 사용한다.

### 동작 원리

```java
// 직접 파티션 할당
List<PartitionInfo> partitionInfos =
    consumer.partitionsFor("my-topic");

List<TopicPartition> partitions = partitionInfos.stream()
    .map(p -> new TopicPartition(p.topic(), p.partition()))
    .collect(Collectors.toList());

consumer.assign(partitions); // 그룹 코디네이터 불참

// 특정 오프셋부터 읽기
consumer.seek(new TopicPartition("my-topic", 0), 1000L);
```

### 설계 트레이드오프

| 항목 | subscribe() (그룹) | assign() (독립) |
|------|--------------------|-----------------|
| 리밸런스 | 자동 | 없음 |
| 장애 복구 | 자동 | 수동 |
| 스케일아웃 | 자동 | 수동 |
| 오프셋 제어 | 그룹 관리 | 완전 제어 |
| 적합한 용도 | 일반 처리 | 데이터 복구, 특수 처리 |

> 관련: [컨슈머 그룹](#1-컨슈머-그룹-consumer-group), [오프셋 커밋](#4-오프셋-커밋-offset-commit)

---

## 핵심 설정 요약

| 설정 | 기본값 | 영향 |
|------|--------|------|
| `group.id` | - | 컨슈머 그룹 식별자 |
| `session.timeout.ms` | 45000 | heartbeat 타임아웃, 장애 감지 속도 |
| `heartbeat.interval.ms` | 3000 | heartbeat 전송 주기 (session.timeout의 1/3 권장) |
| `max.poll.interval.ms` | 300000 | 처리 지연 허용 한계 |
| `max.poll.records` | 500 | 배치 크기 |
| `enable.auto.commit` | true | 자동 오프셋 커밋 |
| `auto.commit.interval.ms` | 5000 | 자동 커밋 주기 |
| `auto.offset.reset` | latest | 초기 오프셋 없을 때 earliest/latest |
| `fetch.min.bytes` | 1 | 최소 fetch 크기 |
| `fetch.max.wait.ms` | 500 | fetch 최대 대기 시간 |
| `partition.assignment.strategy` | [Range, CooperativeSticky] | 파티션 할당 전략 |
