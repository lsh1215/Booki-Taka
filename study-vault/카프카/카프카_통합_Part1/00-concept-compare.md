# Kafka Part 1 - 헷갈리는 개념 비교

> 아키텍처, 토픽/파티션, 프로듀서, 컨슈머 영역에서 자주 혼동되는 개념 쌍 정리

---

## acks=0 vs acks=1 vs acks=all

### 구조적 차이

| 구분 | acks=0 | acks=1 | acks=all |
|------|--------|--------|----------|
| 풀려는 문제 | 최대 처리량, 유실 감수 | 처리량과 내구성의 균형 | 데이터 유실 없는 강한 내구성 |
| 동작 원리 | 브로커 응답 대기 없이 즉시 반환 | Leader가 로컬에 기록하면 ack 반환 | Leader + 모든 ISR Follower 기록 후 ack 반환 |
| 사용 시점 | 로그/메트릭 등 유실 허용 가능한 데이터 | 일반적인 비즈니스 이벤트 | 결제, 주문 등 유실 절대 불가 데이터 |
| 트레이드오프 | 처리량 최대, 메시지 유실 위험 | Leader 장애 시 유실 가능 | 처리량 감소, 지연 증가 |

### 왜 헷갈리는가

세 설정 모두 "Producer가 브로커에 메시지를 보낸다"는 동일한 흐름 위에 있으며, 단순히 숫자(0, 1, all)로 표현되어 내부 동작 차이가 직관적으로 드러나지 않는다. acks=1이 기본값이라 "기본이 안전한 것 아닌가"라고 오해하기 쉽다.

### 핵심 구분 기준

"몇 개의 브로커가 쓰기를 확인해야 ack를 주는가" - acks 숫자는 응답을 기다리는 브로커의 수다.

### 관련 개념

- [프로듀서 acks](./03-프로듀서/concepts.md#4-acks-설정)
- [ISR (In-Sync Replicas)](./02-토픽과-파티션/concepts.md#isr-in-sync-replicas)
- [min.insync.replicas](./03-프로듀서/concepts.md#4-acks-설정)

---

## Eager Rebalance vs Cooperative Rebalance

### 구조적 차이

| 구분 | Eager Rebalance | Cooperative Rebalance |
|------|-----------------|----------------------|
| 풀려는 문제 | 단순하고 일관된 파티션 재할당 | 재할당 중 처리 중단 최소화 |
| 동작 원리 | 모든 컨슈머가 파티션을 반납 → 일시 정지 → 전체 재할당 | 필요한 파티션만 단계적으로 이전, 나머지는 계속 소비 |
| 사용 시점 | 단순 구현, 짧은 중단 허용 환경 | 대규모 컨슈머 그룹, 고가용성 요구 환경 |
| 트레이드오프 | 구현 단순, 전체 Stop-The-World 발생 | 복잡도 높음, 재할당 완료까지 다소 오래 걸릴 수 있음 |

### 왜 헷갈리는가

둘 다 "리밸런싱"이라는 같은 이름으로 불리며, 결과적으로 파티션이 컨슈머에 재배분된다는 최종 결과가 동일하다. 차이는 그 과정에서 얼마나 처리를 중단하느냐에 있다.

### 핵심 구분 기준

Eager는 "전부 내려놓고 다시 나눈다", Cooperative는 "필요한 것만 골라 옮긴다" - 재할당 범위와 중단 시간이 다르다.

### 관련 개념

- [컨슈머 리밸런싱](./04-컨슈머/concepts.md#2-리밸런스-rebalance)
- [Partition Assignor](./04-컨슈머/concepts.md#6-파티션-할당-전략-partition-assignment-strategy)
- [group.protocol](./04-컨슈머/concepts.md#3-그룹-코디네이터-group-coordinator)

---

## commitSync vs commitAsync

### 구조적 차이

| 구분 | commitSync | commitAsync |
|------|------------|-------------|
| 풀려는 문제 | 오프셋 커밋 실패 시 재시도로 정확한 커밋 보장 | 처리량 최대화, 커밋 지연 최소화 |
| 동작 원리 | 브로커 응답 올 때까지 블로킹, 실패 시 자동 재시도 | 비동기로 커밋 요청 후 즉시 반환, 콜백으로 결과 처리 |
| 사용 시점 | 정확한 오프셋 관리가 필요한 경우, 종료 직전 마지막 커밋 | 일반적인 메시지 처리 루프 내 |
| 트레이드오프 | 처리량 감소, 블로킹으로 지연 발생 | 처리량 높음, 실패 시 중복 발생 가능 |

### 왜 헷갈리는가

두 메서드 모두 "오프셋을 커밋한다"는 동일한 목적을 갖고, 보통 같은 오프셋을 커밋한다. Sync/Async라는 이름만 보면 단순히 속도 차이처럼 보이지만, 실패 처리 방식과 중복 발생 가능성이 근본적으로 다르다.

### 핵심 구분 기준

commitSync는 "성공을 확인하고 진행", commitAsync는 "일단 진행하고 나중에 확인" - 안정성 vs 처리량의 트레이드오프다.

### 관련 개념

- [오프셋 커밋](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit)
- [At-Least-Once 전달](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit)
- [enable.auto.commit](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit)

---

## 로그 삭제(Retention) vs 로그 압착(Compaction)

### 구조적 차이

| 구분 | 로그 삭제 (Retention) | 로그 압착 (Compaction) |
|------|----------------------|----------------------|
| 풀려는 문제 | 디스크 공간 관리, 오래된 데이터 정리 | 키 기준 최신 상태만 유지, 이벤트 소싱/CDC |
| 동작 원리 | 시간(retention.ms) 또는 크기(retention.bytes) 기준으로 오래된 세그먼트 삭제 | 동일 키의 이전 메시지를 삭제하고 최신 값만 보존 |
| 사용 시점 | 시계열 로그, 이벤트 스트림 (최신 N일치 데이터만 필요) | 사용자 프로필, 설정값, 변경 이력 (최신 상태가 중요) |
| 트레이드오프 | 단순하고 예측 가능, 오래된 데이터 복구 불가 | 키별 최신 값 보장, 처리 부하 및 복잡도 증가 |

### 왜 헷갈리는가

둘 다 "카프카 토픽의 데이터를 줄인다"는 결과를 낳으며, 둘 다 토픽 설정으로 제어한다. "cleanup.policy"라는 하나의 설정값에서 선택하는 옵션이라 혼동하기 쉽다.

### 핵심 구분 기준

Retention은 "시간/크기 기준으로 전체 삭제", Compaction은 "키 기준으로 중복 제거" - 삭제 단위와 보존 기준이 다르다.

### 관련 개념

- [토픽 설정](./02-토픽과-파티션/concepts.md#토픽-topic)
- [cleanup.policy](./02-토픽과-파티션/concepts.md#로그-압착-log-compaction)
- [Log Segment](./02-토픽과-파티션/concepts.md#세그먼트-segment)

---

## ZooKeeper vs KRaft

### 구조적 차이

| 구분 | ZooKeeper | KRaft |
|------|-----------|-------|
| 풀려는 문제 | 분산 시스템 메타데이터 및 리더 선출 외부 위임 | 카프카 자체에서 메타데이터 관리, ZooKeeper 의존성 제거 |
| 동작 원리 | 별도 ZooKeeper 앙상블이 브로커 메타데이터, 컨트롤러 선출 담당 | 브로커 중 일부가 KRaft Controller 역할을 겸임, Raft 합의 알고리즘 사용 |
| 사용 시점 | Kafka 2.x 이하 (레거시), 기존 운영 환경 유지 | Kafka 3.3+ 프로덕션, 신규 클러스터 구축 |
| 트레이드오프 | 성숙한 생태계, 별도 ZooKeeper 운영 비용 및 복잡도 | 운영 단순화, 확장성 향상 - 아직 일부 기능 제한 |

### 왜 헷갈리는가

둘 다 "카프카 클러스터의 메타데이터를 관리한다"는 동일한 역할을 한다. "ZooKeeper 없이 카프카가 되냐"는 의문에서 시작해, KRaft가 ZooKeeper를 대체하는 것인지 보완하는 것인지 혼동한다.

### 핵심 구분 기준

ZooKeeper는 "외부 의존 시스템", KRaft는 "카프카 내장 메타데이터 관리" - 아키텍처 단순화의 방향이다.

### 관련 개념

- [카프카 아키텍처](./01-핵심-아키텍처/concepts.md#브로커-broker)
- [Controller](./01-핵심-아키텍처/concepts.md#컨트롤러-controller)
- [Broker 메타데이터](./01-핵심-아키텍처/concepts.md#분산-시스템-설계)

---

## Leader vs Follower (Replica)

### 구조적 차이

| 구분 | Leader Replica | Follower Replica |
|------|---------------|-----------------|
| 풀려는 문제 | 모든 읽기/쓰기의 단일 진입점 제공 | 데이터 복제로 내구성 및 장애 복구 보장 |
| 동작 원리 | Producer/Consumer 요청을 직접 처리, LEO와 HW 관리 | Leader로부터 Fetch 요청으로 데이터 복제, ISR 유지 |
| 사용 시점 | 항상 활성 상태로 요청 처리 | 평시에는 복제만 수행, Leader 장애 시 새 Leader로 승격 |
| 트레이드오프 | 단일 Leader로 일관성 보장, Leader 브로커에 부하 집중 | 부하 분산(복제), 평시 직접 서비스하지 않음 |

### 왜 헷갈리는가

"레플리카"라는 이름 때문에 둘 다 동등한 역할을 한다고 오해한다. 또한 Follower도 데이터를 갖고 있어서 "왜 읽기를 못 하지?"라는 의문이 생긴다. (Kafka 2.4+의 Follower Fetching 기능으로 일부 읽기 가능)

### 핵심 구분 기준

Leader는 "서비스하는 복제본", Follower는 "대기하는 복제본" - 요청 처리 여부가 다르다.

### 관련 개념

- [파티션 복제](./02-토픽과-파티션/concepts.md#리플리케이션-replication)
- [ISR (In-Sync Replicas)](./02-토픽과-파티션/concepts.md#isr-in-sync-replicas)
- [HW / LEO](./02-토픽과-파티션/concepts.md#오프셋-offset)

---

## At-Most-Once vs At-Least-Once vs Exactly-Once

### 구조적 차이

| 구분 | At-Most-Once | At-Least-Once | Exactly-Once |
|------|-------------|--------------|--------------|
| 풀려는 문제 | 처리 지연 없이 최대 처리량 | 유실 없는 메시지 전달 | 유실도 중복도 없는 정확한 전달 |
| 동작 원리 | 커밋 후 처리 (실패해도 재시도 없음) | 처리 후 커밋 (실패 시 재소비로 중복 가능) | 트랜잭션/멱등성으로 중복 방지 |
| 사용 시점 | 로그/메트릭 등 일부 유실 허용 | 일반 이벤트 처리, 중복 허용 또는 멱등성 보장된 소비자 | 결제, 재고 등 정확성 필수 |
| 트레이드오프 | 구현 단순, 메시지 유실 위험 | 구현 단순, 중복 처리 위험 | 정확성 보장, 성능 비용 및 구현 복잡도 |

### 왜 헷갈리는가

"Exactly-Once가 있으면 항상 그걸 쓰면 되지 않나"라는 직관과 달리, 성능 비용과 구현 복잡도가 크다. 또한 At-Least-Once와 Exactly-Once는 응용 레이어의 멱등성 처리에 따라 사실상 동일하게 동작할 수 있어 경계가 모호하게 느껴진다.

### 핵심 구분 기준

유실(Loss)과 중복(Duplicate) 중 무엇을 허용하느냐 - At-Most-Once는 유실 허용, At-Least-Once는 중복 허용, Exactly-Once는 둘 다 불허.

### 관련 개념

- [프로듀서 멱등성](./03-프로듀서/concepts.md#6-멱등적-프로듀서-idempotent-producer)
- [트랜잭션 API](./03-프로듀서/concepts.md#7-트랜잭션-transaction)
- [오프셋 커밋 전략](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit)

---

## RangeAssignor vs RoundRobinAssignor vs StickyAssignor vs CooperativeStickyAssignor

### 구조적 차이

| 구분 | RangeAssignor | RoundRobinAssignor | StickyAssignor | CooperativeStickyAssignor |
|------|--------------|-------------------|----------------|--------------------------|
| 풀려는 문제 | 토픽별 연속 파티션 범위 할당 | 전체 파티션 균등 분배 | 균등 분배 + 재할당 최소화 | 균등 분배 + 재할당 최소화 + Stop-The-World 제거 |
| 동작 원리 | 토픽별로 파티션을 정렬 후 컨슈머에 범위로 배분 | 모든 파티션을 섞어 컨슈머에 순환 배분 | 기존 할당 최대한 유지하며 균형 조정 | Sticky 방식으로 재할당하되 Cooperative 프로토콜 사용 |
| 사용 시점 | 여러 토픽을 같은 컨슈머가 처리해야 할 때 | 여러 토픽의 균등한 부하 분산 | 잦은 리밸런싱 환경 | Kafka 2.4+, 중단 없는 리밸런싱 필요 |
| 트레이드오프 | 토픽 수가 많으면 불균형 발생 | 단순 균등 분배, 리밸런싱 시 기존 할당 무시 | 균등+안정성, Eager 방식이라 중단 발생 | 가장 이상적이지만 구현 복잡, 신규 기능 |

### 왜 헷갈리는가

네 가지 모두 "파티션을 컨슈머에 할당한다"는 동일한 목적이며, 이름이 비슷하거나(Sticky vs CooperativeSticky) 두 가지 축(균등성 vs 안정성, Eager vs Cooperative)이 교차하여 혼동이 생긴다.

### 핵심 구분 기준

균등성(Range vs RoundRobin)과 안정성(Sticky 여부), 리밸런스 방식(Eager vs Cooperative) - 세 축으로 구분한다.

### 관련 개념

- [Partition Assignor](./04-컨슈머/concepts.md#6-파티션-할당-전략-partition-assignment-strategy)
- [Eager vs Cooperative Rebalance](#eager-rebalance-vs-cooperative-rebalance)
- [컨슈머 그룹](./04-컨슈머/concepts.md#1-컨슈머-그룹-consumer-group)

---

## HW (High Watermark) vs LEO (Log End Offset)

### 구조적 차이

| 구분 | HW (High Watermark) | LEO (Log End Offset) |
|------|--------------------|--------------------|
| 풀려는 문제 | 컨슈머가 안전하게 읽을 수 있는 경계 표시 | 각 레플리카의 최신 쓰기 위치 추적 |
| 동작 원리 | 모든 ISR 레플리카가 복제 완료한 오프셋 중 최솟값 | 각 레플리카에 마지막으로 기록된 메시지의 다음 오프셋 |
| 사용 시점 | 컨슈머 읽기 경계 (HW 이전만 읽기 가능) | 레플리카 복제 진행 상황 모니터링, ISR 판별 |
| 트레이드오프 | 일관성 보장 (아직 복제 안 된 데이터 노출 방지), 읽기 가능 범위 제한 | 가장 최신 데이터 위치, 컨슈머에 직접 노출 불가 |

### 왜 헷갈리는가

둘 다 "오프셋"이라는 단위를 사용하며, 같은 파티션 내에서 같은 숫자 범위를 다룬다. HW는 항상 LEO 이하이며, Leader의 HW와 LEO가 동일한 순간이 존재해 "왜 두 개가 필요한가"라는 의문이 생긴다.

### 핵심 구분 기준

LEO는 "쓰기가 도달한 곳", HW는 "읽기가 허용된 곳" - 복제 완료 여부가 기준이다.

### 관련 개념

- [파티션 복제](./02-토픽과-파티션/concepts.md#리플리케이션-replication)
- [ISR (In-Sync Replicas)](./02-토픽과-파티션/concepts.md#isr-in-sync-replicas)
- [Leader vs Follower Replica](#leader-vs-follower-replica)

---

*최종 업데이트: 2026-03-01*
