#!/bin/bash
# 실습 02: acks 설정별 프로듀서 성능 비교
# Study Vault 참조: 03-프로듀서/concepts.md#4-acks-설정
#
# 목표: acks=0, acks=1, acks=all(=-1) 각 설정에서 처리량(throughput)과
#       지연시간(latency)의 트레이드오프를 kafka-producer-perf-test.sh로 측정한다.
#
# 사전 준비: broker-1, broker-2, broker-3 컨테이너가 실행 중이어야 한다.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

BROKER_CONTAINER="broker-1"
BOOTSTRAP_SERVER="broker-1:29092"
KAFKA_BIN="/opt/kafka/bin"
TOPIC_NAME="perf-test-acks"
NUM_RECORDS=10000
RECORD_SIZE=1024      # 1KB per message
THROUGHPUT=-1         # -1 = 최대 속도 (제한 없음)

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 02: acks 설정별 프로듀서 성능 비교${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  테스트 조건:"
echo -e "  - 메시지 수: ${NUM_RECORDS}건"
echo -e "  - 메시지 크기: ${RECORD_SIZE} bytes (1KB)"
echo -e "  - 처리량 제한: 없음 (최대 속도)"
echo ""

# ─────────────────────────────────────────────────────────
# STEP 1: 테스트 토픽 생성
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 1] 테스트 토픽 생성${NC}"
echo -e "  토픽명: ${TOPIC_NAME} | 파티션: 3 | 복제계수: 3"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --create \
    --topic ${TOPIC_NAME} \
    --partitions 3 \
    --replication-factor 3 \
    --if-not-exists

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 복제계수 3은 acks=all 실험에서 내구성 보장의 의미가 있다."
echo -e "  - min.insync.replicas는 기본값 1이다 (브로커 설정 확인 가능)."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 2: acks=0 성능 테스트
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 2] acks=0 테스트 - Fire & Forget${NC}"
echo -e "${CYAN}  브로커로부터 어떤 확인도 받지 않고 전송한다.${NC}"
echo -e "${RED}  데이터 유실 가능성이 있으나 가장 빠르다.${NC}"
echo ""

echo -e "  -- acks=0 결과 --"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-producer-perf-test.sh \
    --topic ${TOPIC_NAME} \
    --num-records ${NUM_RECORDS} \
    --record-size ${RECORD_SIZE} \
    --throughput ${THROUGHPUT} \
    --producer-props \
      bootstrap.servers=${BOOTSTRAP_SERVER} \
      acks=0

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - records/sec: 초당 처리 건수 (높을수록 좋다)"
echo -e "  - avg latency: 평균 지연시간 ms (낮을수록 좋다)"
echo -e "  - max latency: 최대 지연시간 ms"
echo -e "  - acks=0이므로 브로커가 받았는지 확인하지 않는다 → 가장 빠름"
echo -e "  - 사용 사례: 로그 집계, 메트릭 수집 등 일부 유실이 허용되는 경우"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 3: acks=1 성능 테스트
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 3] acks=1 테스트 - 리더 확인${NC}"
echo -e "${CYAN}  파티션 리더가 로컬 디스크에 쓴 후 ACK를 반환한다.${NC}"
echo -e "${CYAN}  리더 장애 시 팔로워에 복제되지 않은 메시지는 유실 가능하다.${NC}"
echo ""

echo -e "  -- acks=1 결과 --"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-producer-perf-test.sh \
    --topic ${TOPIC_NAME} \
    --num-records ${NUM_RECORDS} \
    --record-size ${RECORD_SIZE} \
    --throughput ${THROUGHPUT} \
    --producer-props \
      bootstrap.servers=${BOOTSTRAP_SERVER} \
      acks=1

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - acks=0 대비 처리량이 다소 감소하고 지연이 증가했는가?"
echo -e "  - 리더 1대에서만 ACK를 기다리므로 acks=all보다 빠르다."
echo -e "  - Kafka 프로듀서의 기본값은 acks=1이다 (버전에 따라 다름)."
echo -e "  - 사용 사례: 일반적인 비즈니스 이벤트 (약간의 유실을 허용)"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 4: acks=all 성능 테스트
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 4] acks=all (-1) 테스트 - 모든 ISR 확인${NC}"
echo -e "${CYAN}  모든 In-Sync Replica가 메시지를 수신한 후 ACK를 반환한다.${NC}"
echo -e "${CYAN}  가장 강한 내구성 보장. 가장 느리다.${NC}"
echo ""

echo -e "  -- acks=all 결과 --"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-producer-perf-test.sh \
    --topic ${TOPIC_NAME} \
    --num-records ${NUM_RECORDS} \
    --record-size ${RECORD_SIZE} \
    --throughput ${THROUGHPUT} \
    --producer-props \
      bootstrap.servers=${BOOTSTRAP_SERVER} \
      acks=all \
      min.insync.replicas=2

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - acks=0, acks=1 대비 처리량 감소폭을 기록해보자."
echo -e "  - min.insync.replicas=2: ISR 중 최소 2대가 확인해야 ACK 반환"
echo -e "  - acks=all + min.insync.replicas=1은 acks=1과 사실상 동일하다."
echo -e "  - 사용 사례: 금융 거래, 주문 처리 등 절대 유실이 없어야 하는 경우"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 5: 결과 요약 비교
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 5] 결과 비교 요약${NC}"
echo ""
echo -e "${CYAN}  ┌─────────────┬────────────────┬─────────────┬───────────────────────────────┐${NC}"
echo -e "${CYAN}  │ acks 설정   │ 처리량         │ 지연시간    │ 데이터 유실 가능성             │${NC}"
echo -e "${CYAN}  ├─────────────┼────────────────┼─────────────┼───────────────────────────────┤${NC}"
echo -e "${CYAN}  │ acks=0      │ 최고           │ 최저        │ 높음 (브로커 확인 없음)        │${NC}"
echo -e "${CYAN}  │ acks=1      │ 중간           │ 중간        │ 낮음 (리더 장애 시 유실 가능)  │${NC}"
echo -e "${CYAN}  │ acks=all    │ 최저           │ 최고        │ 매우 낮음 (ISR 전체 확인)      │${NC}"
echo -e "${CYAN}  └─────────────┴────────────────┴─────────────┴───────────────────────────────┘${NC}"
echo ""
echo -e "${YELLOW}[추가 실험 제안]${NC}"
echo -e "  1. --throughput 1000 으로 제한하면 지연시간 분포가 어떻게 달라지는가?"
echo -e "  2. linger.ms=5 를 추가하면 배치 처리가 활성화되어 처리량이 증가하는가?"
echo -e "  3. batch.size=65536 (64KB)로 변경하면 acks=all의 지연이 얼마나 줄어드는가?"
echo -e "  4. compression.type=snappy 추가 시 네트워크 I/O와 처리량 변화를 측정하라."
echo ""

# ─────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[CLEANUP] 테스트 토픽 삭제${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --delete \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 02 완료!${NC}"
echo -e "${GREEN}  다음 실습: 03-consumer-group-practice.sh${NC}"
echo -e "${GREEN}=====================================================${NC}"
