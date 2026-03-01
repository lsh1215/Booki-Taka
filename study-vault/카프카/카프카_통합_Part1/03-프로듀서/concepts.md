# 프로듀서

> 출처: 카프카 핵심 가이드 Ch3·Ch8, 실전카프카 Ch3·Ch5, 아파치 카프카 애플리케이션 프로그래밍 Ch3
> 태그: #producer #serializer #partitioner #acks #batch #compression #idempotent #transaction

## 이 토픽의 근본 문제

데이터를 카프카에 안정적이고 효율적으로 전달하려면 어떤 설계가 필요한가

단순하게 생각하면 "메시지 하나 보낼 때마다 네트워크 콜"이면 될 것 같지만, 이 방식은 처리량이 극도로 낮다. 반면 너무 배치를 크게 모으면 지연이 늘어난다. 안정성과 효율성 사이의 긴장이 프로듀서 설계 전반을 관통한다.

---

## 전체 구조

```
Application (메인 스레드)
    │
    │ producer.send(ProducerRecord)
    ▼
┌─────────────────────────────────────────────────────────┐
│                    KafkaProducer                        │
│                                                         │
│  ┌──────────────┐    ┌──────────────┐                  │
│  │  Serializer  │───▶│  Partitioner │                  │
│  │  (Key/Value) │    │  (파티션 결정) │                  │
│  └──────────────┘    └──────┬───────┘                  │
│                             │                           │
│                             ▼                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │           RecordAccumulator (buffer.memory)      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐        │   │
│  │  │ topic-A / part0 │  │ topic-A / part1 │  ...   │   │
│  │  │ [batch: 16KB]   │  │ [batch: 16KB]   │        │   │
│  │  └─────────────────┘  └─────────────────┘        │   │
│  └──────────────────────────────────────────────────┘   │
│                             │                           │
│                     ┌───────▼──────┐                   │
│                     │    Sender    │  ← 별도 스레드      │
│                     │  (I/O 루프)  │                   │
│                     └───────┬──────┘                   │
└─────────────────────────────┼───────────────────────────┘
                              │ ProduceRequest
                              ▼
                    ┌──────────────────┐
                    │      Broker      │
                    │  (리더 파티션)    │
                    └──────────────────┘
                              │ acks 응답
                              ▼
                    Callback / Future 완료
```

---

## 핵심 개념

### 1. 프로듀서 내부 설계 (Producer Design)

**왜 이런 구조인가**

메시지를 하나씩 동기적으로 전송하면 네트워크 RTT가 매 메시지마다 발생한다. 초당 수만 건 처리 시 대부분의 시간을 대기에 쓴다. 카프카 프로듀서는 이를 **비동기 배치 구조**로 해결한다.

**두 스레드 분리**

- 메인 스레드: `send()` 호출 → 직렬화 → 파티션 결정 → RecordAccumulator에 추가하고 즉시 반환
- Sender 스레드: 백그라운드에서 RecordAccumulator를 폴링해 브로커로 전송, 응답 처리

두 스레드는 RecordAccumulator를 통해 느슨하게 결합된다. 메인 스레드는 네트워크 I/O와 무관하게 빠르게 진행된다.

**RecordAccumulator**

- 토픽-파티션 단위로 `Deque<ProducerBatch>`를 유지
- 각 배치는 `batch.size`(기본 16KB) 채우거나 `linger.ms` 경과 시 Sender로 이동
- 전체 메모리 한도: `buffer.memory`(기본 32MB). 초과 시 `send()`가 `max.block.ms`만큼 블로킹, 이후 `TimeoutException`

**없으면 어떻게 되나**

메시지마다 TCP 왕복 → 브로커 초당 수천 건 처리 불가 → 처리량 1/100 이하로 저하

---

### 2. 시리얼라이저 (Serializer)

**왜 필요한가**

브로커는 바이트 배열만 저장한다. 자바 객체 → 바이트 배열 변환은 프로듀서 책임이다.

**내장 시리얼라이저**

| 클래스 | 대상 타입 |
|--------|-----------|
| `StringSerializer` | String |
| `IntegerSerializer` | Integer |
| `ByteArraySerializer` | byte[] |
| `LongSerializer` | Long |

**커스텀 시리얼라이저**

`org.apache.kafka.common.serialization.Serializer<T>` 인터페이스 구현. 하지만 **비권장**. 스키마가 바뀌면 프로듀서와 컨슈머를 동시에 변경해야 하고 버전 관리가 어렵다.

**권장 방식: 스키마 레지스트리 활용**

```
Avro / Protobuf / JSON Schema
        │
        ▼
Schema Registry (스키마 저장/조회)
        │
   ─────┼─────
   │         │
Producer   Consumer
(스키마 ID  (스키마 ID로
  포함 전송)  스키마 조회 후 역직렬화)
```

- **Avro**: 스키마 진화(Schema Evolution) 지원. 하위/상위 호환 가능
- **Protobuf**: 필드 번호 기반. 언어 중립적
- 스키마 레지스트리 없이 커스텀 → 필드 추가·삭제 시 하드코딩된 역직렬화 코드 전체 수정 필요

**트레이드오프**

| 방식 | 장점 | 단점 |
|------|------|------|
| 커스텀 직렬화 | 의존성 없음, 구현 단순 | 스키마 진화 어려움, 버전 관리 수동 |
| Avro + Schema Registry | 스키마 진화, 타입 안전 | 레지스트리 인프라 필요 |
| JSON | 사람이 읽기 쉬움 | 크기 크고 타입 안전성 낮음 |

---

### 3. 파티셔너 (Partitioner)

**역할**

`ProducerRecord`가 어느 파티션으로 가야 하는지 결정한다. 직접 파티션 번호를 지정하면 파티셔너를 거치지 않는다.

**기본 동작 (DefaultPartitioner / UniformStickyPartitioner)**

```
키가 있는 경우:
  partition = murmur2(key) % numPartitions
  → 같은 키는 항상 같은 파티션 (순서 보장)

키가 없는 경우 (Kafka 2.4+ 스티키 파티셔닝):
  현재 배치가 채워질 때까지 같은 파티션에 메시지 축적
  → 배치 가득 차거나 linger.ms 경과 시 다음 파티션으로 전환
  (이전: 라운드로빈 → 배치마다 파티션이 달라 배치 크기가 작았음)
```

**스티키 파티셔닝이 왜 더 나은가**

라운드로빈은 메시지 n개를 n개 파티션에 분산 → 파티션당 배치 크기 = 1. 스티키는 같은 파티션에 모아서 하나의 큰 배치로 전송 → 브로커 요청 수 감소, 배치 압축률 향상.

**커스텀 파티셔너**

```java
public class PriorityPartitioner implements Partitioner {
    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        // VIP 고객은 파티션 0번 고정
        if (key != null && key.toString().startsWith("VIP")) return 0;
        return (Math.abs(Utils.murmur2(keyBytes)) % (cluster.partitionCountForTopic(topic) - 1)) + 1;
    }
}
```

**트레이드오프**

| 전략 | 장점 | 단점 |
|------|------|------|
| 키 기반 해시 | 파티션 내 순서 보장 | 특정 키 집중 시 핫스팟 파티션 |
| 스티키 | 높은 처리량, 배치 효율 | 파티션 분포 일시적 불균형 |
| 라운드로빈 | 균등 분산 | 배치 크기 작아 효율 낮음 |
| 커스텀 | 비즈니스 요건 직접 반영 | 파티션 수 변경 시 재배치 로직 주의 |

> 관련: [acks 설정](#4-acks-설정), [배치 처리](#5-배치-처리와-압축)

---

### 4. acks 설정

**왜 중요한가**

프로듀서가 "성공"으로 간주하는 기준을 정한다. 이 기준이 내구성(durability)과 지연(latency) 사이의 핵심 트레이드오프를 결정한다.

**세 가지 수준**

```
acks=0
  Producer → Broker (응답 안 기다림)
  처리량 최대, 유실 위험 최대
  용도: 로그, 메트릭 등 일부 유실 허용 데이터

acks=1
  Producer → Leader ✓ → (팔로워는 아직 복제 안됨)
  리더가 쓰기 확인 직후 장애 → 메시지 유실 가능
  기본값 (Kafka 2.x까지)

acks=all (또는 acks=-1)
  Producer → Leader ✓ → Follower1 ✓ → Follower2 ✓
  모든 ISR(In-Sync Replica) 복제 완료 후 ack
  가장 안전, 지연 증가
  Kafka 3.0부터 기본값
```

**min.insync.replicas와 결합**

`acks=all`만으로는 ISR이 1개(리더만)인 경우에도 성공 응답이 가능하다. 진정한 내구성 보장을 위해:

```
min.insync.replicas=2  (브로커/토픽 설정)
acks=all               (프로듀서 설정)

→ ISR이 최소 2개 있어야 쓰기 허용
→ ISR < 2이면 프로듀서에 NotEnoughReplicasException 반환
```

**트레이드오프 요약**

| acks | 지연 | 처리량 | 내구성 |
|------|------|--------|--------|
| 0 | 최소 | 최대 | 최저 (유실 가능) |
| 1 | 중간 | 높음 | 중간 (리더 장애 시 유실) |
| all | 최대 | 낮음 | 최고 (ISR 모두 복제) |

> 관련: [멱등적 프로듀서](#6-멱등적-프로듀서-idempotent-producer), [트랜잭션](#7-트랜잭션-transaction)

---

### 5. 배치 처리와 압축

**왜 배치인가**

네트워크 요청 오버헤드(TCP 헤더, 요청 처리 비용)는 고정 비용이다. 메시지를 묶어 보내면 같은 비용으로 더 많은 데이터를 전송할 수 있다.

**핵심 설정**

```
batch.size (기본 16384 bytes = 16KB)
  파티션별 배치의 최대 크기
  배치가 이 크기에 도달하면 즉시 Sender로 전달
  → 크게 할수록 처리량 증가, but 메모리 사용 증가

linger.ms (기본 0ms)
  배치를 채우기 위해 기다리는 최대 시간
  0이면 배치에 메시지 있는 즉시 전송 (배치 효과 감소)
  → 올리면 지연 증가하지만 배치 크기 증가 → 처리량 향상

compression.type (기본 none)
  none / gzip / snappy / lz4 / zstd
  배치 단위로 압축 적용

buffer.memory (기본 33554432 bytes = 32MB)
  RecordAccumulator 전체 크기 한도
  가득 차면 send()가 max.block.ms만큼 블로킹
  이후 TimeoutException 발생
```

**압축 알고리즘 비교**

| 알고리즘 | 압축률 | 속도 | CPU 사용 | 권장 용도 |
|----------|--------|------|----------|-----------|
| gzip | 높음 | 느림 | 높음 | 스토리지 절약 우선 |
| snappy | 중간 | 빠름 | 낮음 | 범용, 균형 |
| lz4 | 중간 | 매우 빠름 | 낮음 | 처리량 우선 |
| zstd | 높음 | 빠름 | 중간 | 현대적 권장 |

**배치+압축 시너지**

같은 종류의 메시지가 배치에 모이면 압축률이 극적으로 높아진다. JSON 메시지 100개를 개별 압축하는 것보다 배치로 묶어 한 번에 압축하면 중복 패턴(필드명 등)이 압축 사전에 반영되어 훨씬 높은 압축률을 달성한다.

**트레이드오프**

```
batch.size 크게 + linger.ms 높게
  → 처리량 최대화
  → but 지연 증가 (메시지가 배치에 쌓이는 시간 대기)
  → but 메모리 사용 증가

압축 활성화
  → 네트워크 대역폭 절약
  → 브로커 디스크 절약
  → but CPU 비용 추가 (인코딩/디코딩)
```

> 관련: [파티셔너 - 스티키 파티셔닝](#3-파티셔너-partitioner)

---

### 6. 멱등적 프로듀서 (Idempotent Producer)

**문제: 재시도로 인한 중복**

```
Producer → Broker: 메시지 M (시퀀스 5)
Broker: 저장 성공
네트워크 오류 → ack 유실
Producer: ack 못 받음 → 재시도
Producer → Broker: 메시지 M (시퀀스 5) 재전송
Broker: 저장 성공 → 메시지 중복 저장!
```

**해결: PID + 시퀀스 번호**

```java
// 활성화
props.put("enable.idempotence", true);
// Kafka 3.0부터 기본값
```

```
프로듀서 시작 시:
  브로커로부터 PID(Producer ID) 할당받음

메시지 전송 시:
  각 메시지에 (PID, 파티션, SequenceNumber) 부착
  시퀀스 번호는 파티션별로 0부터 단조 증가

브로커 수신 시:
  (PID, 파티션)별 마지막 시퀀스 번호 추적
  이미 본 시퀀스 번호 → 조용히 무시 (중복 제거)
  시퀀스 번호 Gap → OutOfOrderSequenceException (재전송 요청)
```

**순서 보장과 max.in.flight.requests.per.connection**

멱등성 비활성화 시 재시도가 순서를 뒤집을 수 있어 보수적으로 `max.in.flight.requests.per.connection=1`을 권장했다. 멱등성 활성화 시 브로커가 시퀀스 번호로 순서를 재조정하므로 **5까지 허용**되어 처리량도 함께 향상된다.

**한계**

- 프로듀서 재시작 → 새 PID 할당 → 이전 세션과 연속성 없음
- 즉, 프로듀서 **프로세스 재시작 간** 정확히 한 번은 보장하지 못함
- 이를 위해 → [트랜잭션](#7-트랜잭션-transaction) 사용

**트레이드오프**

- 오버헤드: 시퀀스 번호 추가, 브로커 메모리에서 (PID, 파티션) 상태 유지
- 이점: 네트워크 재전송 시나리오에서 중복 없음
- 주의: `acks=all`, `retries > 0` 자동 강제 적용됨

---

### 7. 트랜잭션 (Transaction)

**문제: 여러 파티션에 원자적 쓰기**

Kafka Streams의 "읽고-처리하고-쓰기" 패턴을 생각해보자. 처리 결과를 여러 토픽에 쓰다가 중간에 실패하면 일부만 쓰인 상태가 된다. 멱등적 프로듀서는 파티션 내 중복만 제거한다. 여러 파티션에 걸친 원자성은 트랜잭션이 필요하다.

**트랜잭션 코디네이터와 상태 로그**

```
Transaction Coordinator (브로커 역할 겸임)
        │
        ▼
__transaction_state (내부 토픽, 50개 파티션)
  트랜잭션 상태 영구 저장:
  ONGOING / PREPARE_COMMIT / COMPLETE_COMMIT
  PREPARE_ABORT / COMPLETE_ABORT
```

**transactional.id와 에포크**

```java
props.put("transactional.id", "my-transactional-producer-1");
```

- 같은 `transactional.id`로 재시작 시: 코디네이터가 이전 프로듀서를 펜스(fencing)
- 이전 프로듀서는 동일 ID로 새 에포크(epoch) 부여 → 구 프로듀서의 요청 거부
- 좀비 프로듀서 문제 해결

**2단계 커밋 (2-Phase Commit) 흐름**

```
1. producer.initTransactions()
   → 코디네이터로부터 PID + 에포크 할당

2. producer.beginTransaction()
   → 로컬 상태만 변경 (네트워크 없음)

3. producer.send(record1)  // topic-A, partition-0
   producer.send(record2)  // topic-B, partition-1
   → 코디네이터에 파티션 등록

4a. producer.commitTransaction()
    → Phase 1: 코디네이터에 PREPARE_COMMIT 기록
    → Phase 2: 각 파티션에 트랜잭션 마커(커밋 마커) 기록
    → COMPLETE_COMMIT 기록

4b. producer.abortTransaction()
    → PREPARE_ABORT → 각 파티션에 어보트 마커 → COMPLETE_ABORT
```

**컨슈머 측 설정**

```java
props.put("isolation.level", "read_committed");
// 기본값: read_uncommitted
```

- `read_uncommitted`: 진행 중인 트랜잭션 메시지도 읽음 (미완료 쓰기 노출)
- `read_committed`: 커밋 마커까지 확인된 메시지만 읽음

**트레이드오프**

| 항목 | 내용 |
|------|------|
| 보장 | 여러 파티션에 EOS(Exactly-Once Semantics) |
| 지연 | 트랜잭션 마커 쓰기 왕복 추가 |
| 처리량 | 트랜잭션당 코디네이터 왕복 → 낮은 TPS |
| 복잡도 | 에러 처리, 재시작 로직 복잡 |
| 용도 | Kafka Streams, 금융 트랜잭션, 정확히 한 번 필수 파이프라인 |

> 관련: [멱등적 프로듀서](#6-멱등적-프로듀서-idempotent-producer), [acks=all](#4-acks-설정)

---

### 8. 메시지 전달 시간 설정

**타임아웃 계층 구조**

```
send() 호출
  │
  ├─ max.block.ms (기본 60,000ms)
  │   버퍼 가득 차거나 메타데이터 못 얻을 때 블로킹 한도
  │
  └─ delivery.timeout.ms (기본 120,000ms)
      전체 전달 시도 한도 (재시도 포함)
      │
      ├─ linger.ms (배치 대기 시간)
      │
      └─ 요청 전송 루프
          │
          ├─ request.timeout.ms (기본 30,000ms)
          │   개별 요청 응답 대기 한도
          │
          └─ retry.backoff.ms (기본 100ms)
              재시도 간 대기 시간
```

**retries 설정**

- 기본값: `Integer.MAX_VALUE` (멱등성 활성화 시 자동)
- `delivery.timeout.ms` 내에서 재시도
- 재시도 가능한 오류: `LEADER_NOT_AVAILABLE`, `NOT_ENOUGH_REPLICAS` 등
- 재시도 불가 오류: `INVALID_TOPIC`, `MESSAGE_TOO_LARGE` 등 → 즉시 실패

**실전 설정 예시**

```java
// 높은 처리량, 일부 지연 허용
props.put("batch.size", 65536);          // 64KB
props.put("linger.ms", 20);
props.put("compression.type", "lz4");
props.put("buffer.memory", 67108864);    // 64MB

// 낮은 지연 우선
props.put("batch.size", 16384);          // 16KB
props.put("linger.ms", 0);
props.put("acks", "1");

// 높은 내구성 우선
props.put("acks", "all");
props.put("enable.idempotence", "true");
props.put("max.in.flight.requests.per.connection", "5");
```

---

## 개념 간 연결 관계

```
[시리얼라이저] ──────────────────────────────────────────┐
                                                         │
[파티셔너] ──── 파티션 결정 ────┐                        │
                               ▼                         ▼
                    [RecordAccumulator]           프로듀서 파이프라인
                    batch.size / linger.ms
                               │
                               ▼
                         [Sender 스레드]
                               │
               ┌───────────────┼───────────────┐
               │               │               │
           acks=0           acks=1          acks=all
           (유실 가능)    (리더만 확인)    (ISR 전체 확인)
                                               │
                                    [min.insync.replicas]
                                               │
                               ┌───────────────┘
                               │
                    [멱등적 프로듀서]
                    PID + SequenceNumber
                    재전송 중복 제거
                               │
                               ▼
                      [트랜잭션]
                    여러 파티션 원자적 쓰기
                    EOS 완성
```
