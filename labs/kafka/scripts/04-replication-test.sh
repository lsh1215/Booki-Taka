#!/bin/bash
# 실습 04: 리플리케이션과 ISR 동작 확인
# Study Vault 참조: 02-토픽과-파티션/concepts.md (ISR, 리플리케이션)
#
# 목표: 브로커 장애를 시뮬레이션하여 ISR 변화, 리더 선출,
#       min.insync.replicas와 acks=all의 상호작용을 관찰한다.
#
# 사전 준비:
#   - broker-1, broker-2, broker-3 컨테이너가 실행 중이어야 한다.
#   - docker 명령을 실행할 수 있어야 한다 (sudo 불필요 환경 권장).
#
# 경고: 이 스크립트는 broker-2 컨테이너를 일시적으로 중지한다.
#       테스트 환경에서만 실행하라.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

BROKER_CONTAINER="broker-1"
BROKER2_CONTAINER="broker-2"
BOOTSTRAP_SERVER="broker-1:29092"
KAFKA_BIN="/opt/kafka/bin"
TOPIC_NAME="replication-test-01"

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 04: 리플리케이션과 ISR 동작 확인${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "${RED}  [경고] 이 실습은 broker-2 컨테이너를 일시 중지한다.${NC}"
echo -e "${RED}         테스트 환경에서만 실행하라.${NC}"
echo ""
read -p "  계속하려면 Enter 키를 누르세요 (Ctrl+C로 중단 가능)..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 1: 테스트 토픽 생성 및 초기 ISR 상태 확인
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 1] 테스트 토픽 생성 및 초기 ISR 상태 확인${NC}"
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
echo -e "  초기 파티션 상태:"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 모든 파티션의 Isr에 3개 브로커(1, 2, 3)가 모두 포함되어 있는가?"
echo -e "  - 각 파티션의 Leader가 브로커에 균등하게 분산되어 있는가?"
echo -e "  - Replicas 목록의 첫 번째 브로커가 'Preferred Leader'다."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 2: 정상 상태에서 메시지 전송
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 2] 정상 상태: acks=all로 메시지 전송${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-producer-perf-test.sh \
    --topic ${TOPIC_NAME} \
    --num-records 500 \
    --record-size 512 \
    --throughput -1 \
    --producer-props \
      bootstrap.servers=${BOOTSTRAP_SERVER} \
      acks=all \
      min.insync.replicas=2

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 3대 모두 ISR에 있으므로 acks=all이 정상 동작한다."
echo -e "  - 기준 처리량(records/sec)을 기록해두자."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 3: 브로커 하나 중지 → ISR 변화 관찰
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 3] broker-2 중지 → ISR 변화 관찰${NC}"
echo -e "${RED}  broker-2를 중지한다...${NC}"
echo ""

docker stop ${BROKER2_CONTAINER}

echo ""
echo -e "  10초 대기 (ISR 변경 감지 시간)..."
sleep 10

echo ""
echo -e "  broker-2 중지 후 파티션 상태:"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - Isr에서 broker-2(ID=2)가 제거되었는가?"
echo -e "  - broker-2가 Leader였던 파티션은 다른 브로커로 리더가 이전되었는가?"
echo -e "  - 이 과정이 'Unclean Leader Election' 없이 이루어진다."
echo -e "  - 참조: 02-토픽과-파티션/concepts.md → ISR과 리더 선출 섹션"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 4: ISR 감소 상태에서 acks=all + min.insync.replicas 실험
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 4] ISR 감소 상태에서 min.insync.replicas 실험${NC}"
echo ""

echo -e "  ${CYAN}4-1. min.insync.replicas=2, ISR=2 → 전송 성공 예상${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-console-producer.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --topic ${TOPIC_NAME} \
    --producer-property acks=all \
    --producer-property min.insync.replicas=2 <<EOF
test-message-isr-2
EOF

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - ISR=2이고 min.insync.replicas=2이므로 조건 충족 → 성공"
echo ""

echo -e "  ${CYAN}4-2. min.insync.replicas=3, ISR=2 → 전송 실패 예상${NC}"
echo -e "  (타임아웃이 발생할 수 있으므로 짧게 테스트)"

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-console-producer.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --topic ${TOPIC_NAME} \
    --producer-property acks=all \
    --producer-property min.insync.replicas=3 \
    --producer-property request.timeout.ms=5000 \
    --producer-property retries=0 <<EOF 2>&1 | head -5
test-message-isr-fail
EOF

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - ISR=2이지만 min.insync.replicas=3 요구 → NotEnoughReplicasException 발생"
echo -e "  - 이것이 데이터 내구성을 위한 '쓰기 거부' 메커니즘이다."
echo -e "  - 프로덕션 권장: min.insync.replicas = replication-factor - 1"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 5: 브로커 재시작 → ISR 복구 관찰
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 5] broker-2 재시작 → ISR 복구 관찰${NC}"
echo -e "${GREEN}  broker-2를 재시작한다...${NC}"
echo ""

docker start ${BROKER2_CONTAINER}

echo ""
echo -e "  30초 대기 (브로커 초기화 및 복제 복구 시간)..."
sleep 15
echo -e "  15초 경과..."
sleep 15
echo -e "  30초 경과. 상태 확인:"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - broker-2가 Isr에 다시 포함되었는가?"
echo -e "  - broker-2가 없는 동안 쓰인 메시지들이 복제되었는가?"
echo -e "  - 아직 Isr에 없다면 더 기다려라 (replica.lag.time.max.ms 설정에 따라 다름)."
echo -e "  - Preferred Leader로 리더십이 복구되는지 확인하라 (auto.leader.rebalance.enable)."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 6: Preferred Leader 선출 강제 트리거
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 6] Preferred Leader 선출 강제 트리거${NC}"
echo -e "${CYAN}  브로커 재시작 후 리더십 불균형을 수동으로 해소한다.${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-leader-election.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --election-type PREFERRED \
    --all-topic-partitions

echo ""
echo -e "  리더 선출 후 최종 상태:"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - Leader가 Replicas 목록의 첫 번째 브로커(Preferred Leader)로 복구되었는가?"
echo -e "  - auto.leader.rebalance.enable=true이면 자동으로 처리된다."
echo -e "  - leader.imbalance.check.interval.seconds: 자동 리밸런싱 주기 (기본 300초)"
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
echo -e "${GREEN}  실습 04 완료!${NC}"
echo -e "${GREEN}  다음 실습: 05-log-segment-inspection.sh${NC}"
echo -e "${GREEN}=====================================================${NC}"
