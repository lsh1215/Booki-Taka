# Kafka Part 1 Quick Reference

> Part 1 핵심 내용 빠른 참조 시트
> 관련 토픽: [아키텍처](./01-핵심-아키텍처/concepts.md) | [토픽/파티션](./02-토픽과-파티션/concepts.md) | [프로듀서](./03-프로듀서/concepts.md) | [컨슈머](./04-컨슈머/concepts.md)

---

## 핵심 용어

| 용어 | 정의 | 관련 토픽 |
|------|------|-----------|
| **Broker** | 메시지를 저장하고 클라이언트 요청을 처리하는 Kafka 서버 단위. 하나의 JVM 프로세스 | [아키텍처](./01-핵심-아키텍처/concepts.md#브로커-broker) |
| **Cluster** | 여러 Broker가 모여 구성되는 Kafka 분산 시스템 단위 | [아키텍처](./01-핵심-아키텍처/concepts.md#클러스터-cluster) |
| **ZooKeeper** | Kafka 클러스터 메타데이터 관리 및 Controller 선출을 담당하던 외부 의존 시스템 (Kafka 3.x부터 KRaft로 대체) | [아키텍처](./01-핵심-아키텍처/concepts.md#주키퍼-zookeeper--kraft) |
| **KRaft** | ZooKeeper 없이 Kafka 자체적으로 메타데이터를 관리하는 Raft 기반 합의 프로토콜 (Kafka 3.3+ 기본) | [아키텍처](./01-핵심-아키텍처/concepts.md#주키퍼-zookeeper--kraft) |
| **Controller** | 파티션 Leader 선출, 브로커 장애 감지 등 클러스터 관리를 담당하는 특수 Broker | [아키텍처](./01-핵심-아키텍처/concepts.md#컨트롤러-controller) |
| **ISR (In-Sync Replicas)** | Leader와 동기화된 상태를 유지하는 Replica 집합. ISR 내 모든 복제본이 메시지를 받아야 커밋 가능 | [아키텍처](./01-핵심-아키텍처/concepts.md#분산-시스템-설계) |
| **Leader** | 파티션의 모든 읽기/쓰기 요청을 처리하는 주 복제본 | [아키텍처](./01-핵심-아키텍처/concepts.md#요청-처리-모델) |
| **Follower** | Leader를 복제하는 수동 복제본. Leader 장애 시 새로운 Leader로 승격 후보 | [아키텍처](./01-핵심-아키텍처/concepts.md#요청-처리-모델) |
| **Topic** | 메시지를 분류하는 논리적 채널. 하나 이상의 파티션으로 구성 | [토픽/파티션](./02-토픽과-파티션/concepts.md#토픽-topic) |
| **Partition** | Topic을 물리적으로 분할한 단위. 병렬 처리와 수평 확장의 핵심 | [토픽/파티션](./02-토픽과-파티션/concepts.md#파티션-partition) |
| **Offset** | 파티션 내 메시지의 고유한 순서 번호 (0부터 시작, 단조 증가) | [토픽/파티션](./02-토픽과-파티션/concepts.md#오프셋-offset) |
| **Segment** | 파티션 로그를 구성하는 물리적 파일 단위 (`.log`, `.index`, `.timeindex`) | [토픽/파티션](./02-토픽과-파티션/concepts.md#세그먼트-segment) |
| **Record** | Kafka에서 전송되는 메시지 단위. Key, Value, Timestamp, Headers로 구성 | [토픽/파티션](./02-토픽과-파티션/concepts.md#레코드-record) |
| **Replication Factor** | 파티션 복제본 수. `replication.factor=3`이면 1개의 Leader + 2개의 Follower | [토픽/파티션](./02-토픽과-파티션/concepts.md#리플리케이션-replication) |
| **Log Compaction** | 동일 Key의 오래된 메시지를 삭제하고 최신 값만 유지하는 로그 정리 정책 | [토픽/파티션](./02-토픽과-파티션/concepts.md#로그-압착-log-compaction) |
| **HW (High Watermark)** | ISR 내 모든 복제본이 복제 완료한 최대 Offset. 컨슈머는 HW 이하 메시지만 읽을 수 있음 | [토픽/파티션](./02-토픽과-파티션/concepts.md#isr-in-sync-replicas) |
| **LEO (Log End Offset)** | 파티션의 다음 메시지가 기록될 Offset (마지막 메시지 Offset + 1) | [토픽/파티션](./02-토픽과-파티션/concepts.md#오프셋-offset) |
| **Serializer** | Java 객체를 바이트 배열로 변환하는 컴포넌트. Key/Value 각각 설정 필요 | [프로듀서](./03-프로듀서/concepts.md#2-시리얼라이저-serializer) |
| **Partitioner** | 메시지를 어느 파티션으로 보낼지 결정하는 컴포넌트. Key 해시 또는 Round-Robin 방식 | [프로듀서](./03-프로듀서/concepts.md#3-파티셔너-partitioner) |
| **acks** | 프로듀서가 메시지 전송 완료를 판단하는 기준. `0` / `1` / `all(-1)` | [프로듀서](./03-프로듀서/concepts.md#4-acks-설정) |
| **RecordAccumulator** | 전송 전 배치로 묶기 위해 메시지를 임시 버퍼링하는 프로듀서 내부 큐 | [프로듀서](./03-프로듀서/concepts.md#1-프로듀서-내부-설계-producer-design) |
| **Batch** | RecordAccumulator에서 파티션별로 묶인 메시지 묶음. `batch.size`로 크기 제어 | [프로듀서](./03-프로듀서/concepts.md#5-배치-처리와-압축) |
| **Compression** | 배치 단위로 메시지를 압축하는 기능. `snappy`, `lz4`, `gzip`, `zstd` 지원 | [프로듀서](./03-프로듀서/concepts.md#5-배치-처리와-압축) |
| **Idempotent Producer** | `enable.idempotence=true`로 활성화. PID + Sequence Number로 중복 메시지 방지 | [프로듀서](./03-프로듀서/concepts.md#6-멱등적-프로듀서-idempotent-producer) |
| **Transaction** | 여러 파티션에 걸친 메시지를 원자적으로 쓰는 기능. `transactional.id` 설정 필요 | [프로듀서](./03-프로듀서/concepts.md#7-트랜잭션-transaction) |
| **linger.ms** | 배치가 꽉 차지 않아도 전송을 기다리는 최대 시간(ms). 처리량과 지연의 트레이드오프 | [프로듀서](./03-프로듀서/concepts.md#8-메시지-전달-시간-설정) |
| **buffer.memory** | RecordAccumulator의 전체 버퍼 크기(bytes). 기본 32MB | [프로듀서](./03-프로듀서/concepts.md#1-프로듀서-내부-설계-producer-design) |
| **Consumer Group** | 동일 `group.id`를 가진 컨슈머 집합. 하나의 파티션은 그룹 내 하나의 컨슈머만 할당 | [컨슈머](./04-컨슈머/concepts.md#1-컨슈머-그룹-consumer-group) |
| **Rebalance** | Consumer Group 내 파티션 할당을 재조정하는 과정. Eager(전체 중단) / Cooperative(점진적) | [컨슈머](./04-컨슈머/concepts.md#2-리밸런스-rebalance) |
| **Group Coordinator** | 특정 Broker에서 Consumer Group의 멤버십과 오프셋을 관리하는 역할 | [컨슈머](./04-컨슈머/concepts.md#3-그룹-코디네이터-group-coordinator) |
| **Offset Commit** | 컨슈머가 처리 완료한 메시지의 Offset을 `__consumer_offsets` 토픽에 기록하는 행위 | [컨슈머](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit) |
| **Polling** | 컨슈머가 `poll()` 호출로 브로커에서 메시지를 가져오는 방식. 주기적 호출 필수 | [컨슈머](./04-컨슈머/concepts.md#5-폴링-polling) |
| **Partition Assignment Strategy** | 파티션을 Consumer Group 멤버에게 분배하는 전략. Range / RoundRobin / Sticky / CooperativeSticky | [컨슈머](./04-컨슈머/concepts.md#6-파티션-할당-전략-partition-assignment-strategy) |
| **__consumer_offsets** | 각 Consumer Group의 Offset 정보를 저장하는 Kafka 내부 시스템 토픽 | [컨슈머](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit) |

---

## 주요 설정값

### Broker 설정

| 설정 | 설명 | 기본값 | 주의사항 |
|------|------|--------|----------|
| `log.retention.hours` | 로그 보관 기간(시간) | `168` (7일) | `log.retention.bytes`와 OR 조건으로 동작 |
| `log.segment.bytes` | 세그먼트 파일 최대 크기(bytes) | `1073741824` (1GB) | 작을수록 파일 수 증가, 클수록 정리 지연 |
| `num.partitions` | 자동 생성 토픽의 기본 파티션 수 | `1` | 프로덕션에서는 적절히 상향 (예: 6~12) |
| `default.replication.factor` | 자동 생성 토픽의 기본 복제 수 | `1` | 프로덕션에서 최소 `3` 권장 |
| `min.insync.replicas` | acks=all 시 최소 동기화 복제본 수 | `1` | `replication.factor - 1` 권장 (3개 클러스터 → 2) |

### Producer 설정

| 설정 | 설명 | 기본값 | 주의사항 |
|------|------|--------|----------|
| `acks` | 전송 확인 레벨 (`0`/`1`/`all`) | `1` | 안정성 필요 시 `all`, 처리량 우선 시 `1` 또는 `0` |
| `retries` | 전송 실패 시 재시도 횟수 | `2147483647` | `delivery.timeout.ms` 내에서 재시도 |
| `batch.size` | 배치 최대 크기(bytes) | `16384` (16KB) | 너무 크면 메모리 낭비, 작으면 배치 효과 감소 |
| `linger.ms` | 배치 전송 대기 시간(ms) | `0` | `5~100ms` 설정 시 처리량 향상, 지연 증가 |
| `buffer.memory` | 전체 버퍼 메모리(bytes) | `33554432` (32MB) | 초과 시 `max.block.ms` 동안 블로킹 후 예외 |
| `compression.type` | 압축 알고리즘 | `none` | `snappy`(균형) / `lz4`(빠름) / `gzip`(고압축) / `zstd`(추천) |
| `enable.idempotence` | 멱등성 프로듀서 활성화 | `true` (Kafka 3.0+) | `acks=all`, `retries>0`, `max.in.flight≤5` 자동 설정 |
| `max.in.flight.requests.per.connection` | 확인 없이 전송 가능한 최대 요청 수 | `5` | 멱등성 사용 시 최대 `5`, 순서 보장 시 `1` |

### Consumer 설정

| 설정 | 설명 | 기본값 | 주의사항 |
|------|------|--------|----------|
| `group.id` | Consumer Group 식별자 | `""` (없음) | 필수 설정. 같은 ID = 같은 그룹 |
| `auto.offset.reset` | 초기 또는 유효하지 않은 오프셋 처리 | `latest` | `earliest`(처음부터) / `latest`(최신부터) / `none`(예외) |
| `enable.auto.commit` | 오프셋 자동 커밋 활성화 | `true` | `false` 권장 (처리 완료 후 수동 커밋으로 정확성 보장) |
| `auto.commit.interval.ms` | 자동 커밋 주기(ms) | `5000` (5초) | `enable.auto.commit=true`일 때만 적용 |
| `max.poll.records` | `poll()` 호출당 최대 레코드 수 | `500` | 처리 시간이 길면 낮춰서 `max.poll.interval.ms` 초과 방지 |
| `max.poll.interval.ms` | `poll()` 호출 최대 간격(ms). 초과 시 그룹에서 제외 | `300000` (5분) | 처리 로직이 오래 걸리면 상향 조정 필요 |
| `session.timeout.ms` | Heartbeat 없을 때 컨슈머 장애 판단 시간(ms) | `45000` (45초) | `heartbeat.interval.ms`의 3배 이상으로 설정 |
| `heartbeat.interval.ms` | Coordinator에 Heartbeat 전송 주기(ms) | `3000` (3초) | `session.timeout.ms`의 1/3 이하 권장 |
| `partition.assignment.strategy` | 파티션 할당 전략 클래스 | `RangeAssignor` | `CooperativeStickyAssignor` 권장 (무중단 리밸런스) |

---

## 주요 CLI 명령어

### kafka-topics.sh

```bash
# 토픽 생성
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic my-topic \
  --partitions 3 \
  --replication-factor 2

# 토픽 목록 조회
kafka-topics.sh --bootstrap-server localhost:9092 --list

# 토픽 상세 정보 (파티션, 복제본, ISR 확인)
kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic my-topic

# 토픽 파티션 수 변경 (증가만 가능)
kafka-topics.sh --bootstrap-server localhost:9092 \
  --alter --topic my-topic --partitions 6

# 토픽 삭제
kafka-topics.sh --bootstrap-server localhost:9092 \
  --delete --topic my-topic
```

### kafka-console-producer.sh

```bash
# 기본 메시지 전송
kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic my-topic

# Key-Value 메시지 전송
kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic my-topic \
  --property key.separator=: \
  --property parse.key=true

# acks 설정과 함께 전송
kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic my-topic \
  --producer-property acks=all
```

### kafka-console-consumer.sh

```bash
# 최신 메시지부터 소비
kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic my-topic

# 처음부터 모든 메시지 소비
kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic my-topic --from-beginning

# Consumer Group 지정 + Key 출력
kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic my-topic \
  --group my-group \
  --property print.key=true \
  --property key.separator=" -> "

# 특정 파티션과 오프셋부터 소비
kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic my-topic \
  --partition 0 \
  --offset 100
```

### kafka-consumer-groups.sh

```bash
# Consumer Group 목록 조회
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# Consumer Group 상세 (오프셋, LAG 확인)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group my-group

# 오프셋 리셋 (처음부터)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group my-group --topic my-topic \
  --reset-offsets --to-earliest --execute

# 오프셋 리셋 (특정 오프셋으로)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group my-group --topic my-topic \
  --reset-offsets --to-offset 500 --execute

# Consumer Group 삭제
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --delete --group my-group
```

### 기타 유틸리티

```bash
# 브로커 설정 확인 (동적 설정 포함)
kafka-configs.sh --bootstrap-server localhost:9092 \
  --describe --broker 0

# 토픽 설정 변경 (보관 기간 조정)
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --entity-type topics --entity-name my-topic \
  --add-config retention.ms=86400000

# LAG 모니터링 (전체 그룹)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --all-groups
```

---

## 자주 쓰는 패턴

### Exactly-Once 패턴

멱등성 프로듀서 + 트랜잭션 프로듀서 + read_committed 컨슈머 조합.
관련 개념: [Idempotent Producer](./03-프로듀서/concepts.md#6-멱등적-프로듀서-idempotent-producer) | [Transaction](./03-프로듀서/concepts.md#7-트랜잭션-transaction)

```java
// Producer 설정
Properties producerProps = new Properties();
producerProps.put("bootstrap.servers", "localhost:9092");
producerProps.put("enable.idempotence", "true");       // 멱등성 활성화
producerProps.put("transactional.id", "my-tx-id");     // 트랜잭션 ID
producerProps.put("acks", "all");
producerProps.put("retries", Integer.MAX_VALUE);
producerProps.put("max.in.flight.requests.per.connection", "5");

KafkaProducer<String, String> producer = new KafkaProducer<>(producerProps);
producer.initTransactions();

try {
    producer.beginTransaction();
    producer.send(new ProducerRecord<>("output-topic", key, value));
    // 트랜잭션 내 오프셋 커밋 (consume-transform-produce 패턴)
    producer.sendOffsetsToTransaction(offsets, consumerGroupMetadata);
    producer.commitTransaction();
} catch (ProducerFencedException | OutOfOrderSequenceException e) {
    producer.close(); // 복구 불가 예외
} catch (KafkaException e) {
    producer.abortTransaction(); // 재시도 가능
}

// Consumer 설정 (커밋된 메시지만 읽기)
Properties consumerProps = new Properties();
consumerProps.put("isolation.level", "read_committed"); // 핵심 설정
consumerProps.put("enable.auto.commit", "false");
```

---

### At-Least-Once 패턴

acks=all + retries + commitSync 조합.
관련 개념: [acks](./03-프로듀서/concepts.md#4-acks-설정) | [Offset Commit](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit)

```java
// Producer 설정
Properties producerProps = new Properties();
producerProps.put("acks", "all");                // 모든 ISR 확인
producerProps.put("retries", Integer.MAX_VALUE); // 무한 재시도
producerProps.put("enable.idempotence", "true"); // 중복 방지 (권장)

// Consumer 설정
Properties consumerProps = new Properties();
consumerProps.put("enable.auto.commit", "false"); // 수동 커밋
consumerProps.put("auto.offset.reset", "earliest");

KafkaConsumer<String, String> consumer = new KafkaConsumer<>(consumerProps);
consumer.subscribe(List.of("my-topic"));

try {
    while (true) {
        ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
        for (ConsumerRecord<String, String> record : records) {
            process(record); // 처리 로직
        }
        consumer.commitSync(); // 처리 완료 후 동기 커밋 (At-Least-Once 보장)
    }
} finally {
    consumer.commitSync(); // 종료 전 최종 커밋
    consumer.close();
}
```

---

### High Throughput Producer 패턴

처리량 극대화를 위한 설정. 지연 시간 증가를 감수.
관련 개념: [Batch](./03-프로듀서/concepts.md#5-배치-처리와-압축) | [Compression](./03-프로듀서/concepts.md#5-배치-처리와-압축) | [linger.ms](./03-프로듀서/concepts.md#8-메시지-전달-시간-설정)

```java
Properties props = new Properties();
props.put("bootstrap.servers", "localhost:9092");

// 배치 크기 증가 (기본 16KB → 64KB)
props.put("batch.size", String.valueOf(64 * 1024));

// 배치 대기 시간 (더 많은 메시지를 배치로 묶음)
props.put("linger.ms", "20");

// 버퍼 메모리 증가
props.put("buffer.memory", String.valueOf(64 * 1024 * 1024)); // 64MB

// 압축으로 네트워크/디스크 부하 감소
props.put("compression.type", "snappy"); // 또는 "lz4", "zstd"

// acks=1로 처리량 우선 (내구성 약간 희생)
props.put("acks", "1");

// 병렬 전송 요청 수 증가
props.put("max.in.flight.requests.per.connection", "5");
```

---

### Safe Consumer 패턴 (commitSync in finally)

컨슈머 종료/예외 시에도 오프셋을 안전하게 커밋하는 패턴.
관련 개념: [Offset Commit](./04-컨슈머/concepts.md#4-오프셋-커밋-offset-commit) | [Rebalance](./04-컨슈머/concepts.md#2-리밸런스-rebalance)

```java
Properties props = new Properties();
props.put("group.id", "safe-consumer-group");
props.put("enable.auto.commit", "false");          // 수동 커밋
props.put("auto.offset.reset", "earliest");
props.put("max.poll.records", "100");              // 처리량 제어
props.put("max.poll.interval.ms", "300000");       // 처리 시간 여유
props.put("session.timeout.ms", "45000");
props.put("heartbeat.interval.ms", "15000");
// CooperativeSticky: 리밸런스 중 불필요한 파티션 중단 방지
props.put("partition.assignment.strategy",
    "org.apache.kafka.clients.consumer.CooperativeStickyAssignor");

KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);
consumer.subscribe(List.of("my-topic"));

try {
    while (running) {
        ConsumerRecords<String, String> records =
            consumer.poll(Duration.ofMillis(500));

        if (!records.isEmpty()) {
            for (ConsumerRecord<String, String> record : records) {
                try {
                    process(record);
                } catch (Exception e) {
                    // 개별 레코드 처리 실패 시 DLQ(Dead Letter Queue)로 전송
                    sendToDLQ(record, e);
                }
            }
            // 배치 처리 완료 후 커밋
            consumer.commitSync();
        }
    }
} catch (WakeupException e) {
    // shutdown() 에서 wakeup() 호출 시 정상 종료
    if (running) throw e;
} finally {
    try {
        consumer.commitSync(); // 종료 전 마지막 오프셋 커밋 (핵심)
    } finally {
        consumer.close();
    }
}
```

---

## 빠른 판단 기준

### acks 선택

```
acks=0  → 최고 처리량, 유실 허용 (로그, 메트릭 수집)
acks=1  → 균형 (기본값, 일반적인 용도)
acks=all → 최고 내구성, 처리량 감소 (금융, 주문 등 중요 데이터)
```

### 파티션 수 선택

```
파티션 수 = max(목표 처리량 / 브로커당 처리량, 컨슈머 수)
규칙: 나중에 늘릴 수 있지만 줄일 수 없음 → 처음부터 충분히 설정
Key 기반 순서 보장 필요 시 → 파티션 수 변경 금지
```

### Rebalance 전략 선택

```
Eager (Range, RoundRobin)     → 단순, 리밸런스 중 전체 중단 (Stop-the-World)
Cooperative (CooperativeSticky) → 복잡, 리밸런스 중 일부만 중단 (권장)
```

### 오프셋 커밋 전략 선택

```
자동 커밋   → 간단, At-Least-Once (처리 전 커밋 가능성)
commitSync  → 안전, 처리 완료 후 보장, 성능 약간 저하
commitAsync → 빠름, 실패 시 재시도 로직 필요
```
