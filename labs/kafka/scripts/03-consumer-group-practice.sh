#!/bin/bash
# 실습 03: 컨슈머 그룹과 파티션 할당
# Study Vault 참조: 04-컨슈머/concepts.md#1-컨슈머-그룹-consumer-group
#
# 목표: 컨슈머 그룹의 파티션 할당 방식, LAG 모니터링,
#       오프셋 리셋 방법을 직접 실습한다.
#
# 사전 준비: broker-1, broker-2, broker-3 컨테이너가 실행 중이어야 한다.
#
# 이 스크립트는 단계별 가이드 형태로 실행된다.
# 일부 단계(컨슈머 추가)는 별도 터미널에서 수행해야 한다.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

BROKER_CONTAINER="broker-1"
BOOTSTRAP_SERVER="broker-1:29092"
KAFKA_BIN="/opt/kafka/bin"
TOPIC_NAME="consumer-group-test"
GROUP_ID="study-group-01"

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 03: 컨슈머 그룹과 파티션 할당${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

# ─────────────────────────────────────────────────────────
# STEP 1: 테스트 토픽 생성 및 데이터 생성
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 1] 테스트 토픽 생성 (파티션 6개)${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --create \
    --topic ${TOPIC_NAME} \
    --partitions 6 \
    --replication-factor 3 \
    --if-not-exists

echo ""
echo -e "${CYAN}  데이터 생성: 1000건 메시지 전송${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-producer-perf-test.sh \
    --topic ${TOPIC_NAME} \
    --num-records 1000 \
    --record-size 256 \
    --throughput -1 \
    --producer-props \
      bootstrap.servers=${BOOTSTRAP_SERVER} \
      acks=1

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 파티션 6개에 1000건이 분산 저장된다."
echo -e "  - 키가 없는 메시지는 라운드로빈 또는 스티키 파티셔너로 분배된다."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 2: 컨슈머 그룹으로 소비 시작 (백그라운드)
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 2] 컨슈머 그룹으로 소비 시작${NC}"
echo -e "${CYAN}  그룹 ID: ${GROUP_ID}${NC}"
echo ""
echo -e "  아래 명령을 별도 터미널(Terminal 2)에서 실행하라:"
echo -e "  ─────────────────────────────────────────────────"
echo -e "${CYAN}  docker exec ${BROKER_CONTAINER} \\"
echo -e "    kafka-console-consumer.sh \\"
echo -e "      --bootstrap-server ${BOOTSTRAP_SERVER} \\"
echo -e "      --topic ${TOPIC_NAME} \\"
echo -e "      --group ${GROUP_ID} \\"
echo -e "      --from-beginning${NC}"
echo -e "  ─────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 컨슈머가 1대이므로 6개 파티션 모두 이 컨슈머에 할당된다."
echo -e "  - --from-beginning: 저장된 모든 메시지부터 읽기 시작"
echo ""
read -p "  Terminal 2에서 컨슈머를 시작한 후 Enter를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 3: 컨슈머 그룹 상태 확인
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 3] 컨슈머 그룹 상태 확인 (LAG, OFFSET)${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --group ${GROUP_ID}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - CONSUMER-ID: 어떤 컨슈머 인스턴스가 파티션을 담당하는지"
echo -e "  - CURRENT-OFFSET: 컨슈머가 마지막으로 커밋한 오프셋"
echo -e "  - LOG-END-OFFSET: 파티션에 저장된 마지막 오프셋"
echo -e "  - LAG: LOG-END-OFFSET - CURRENT-OFFSET (처리 지연 건수)"
echo -e "  - LAG=0이면 모든 메시지를 처리한 상태다."
echo -e "  - 참조: 04-컨슈머/concepts.md → 오프셋 관리 섹션"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 4: 전체 컨슈머 그룹 목록 확인
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 4] 클러스터 내 전체 컨슈머 그룹 목록${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --list

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 여러 그룹이 동일 토픽을 독립적으로 소비할 수 있다."
echo -e "  - 그룹 간 오프셋은 완전히 독립적으로 관리된다."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 5: 컨슈머 추가 시 파티션 재할당 관찰
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 5] 컨슈머 추가 → 파티션 재할당 관찰${NC}"
echo ""
echo -e "  아래 명령을 Terminal 3에서 실행하라 (두 번째 컨슈머 추가):"
echo -e "  ─────────────────────────────────────────────────"
echo -e "${CYAN}  docker exec ${BROKER_CONTAINER} \\"
echo -e "    kafka-console-consumer.sh \\"
echo -e "      --bootstrap-server ${BOOTSTRAP_SERVER} \\"
echo -e "      --topic ${TOPIC_NAME} \\"
echo -e "      --group ${GROUP_ID}${NC}"
echo -e "  ─────────────────────────────────────────────────"
echo ""
echo -e "  두 번째 컨슈머를 시작한 직후 아래 명령으로 재할당을 확인하라:"
echo -e "  ─────────────────────────────────────────────────"
echo -e "${CYAN}  docker exec ${BROKER_CONTAINER} \\"
echo -e "    ${KAFKA_BIN}/kafka-consumer-groups.sh \\"
echo -e "      --bootstrap-server ${BOOTSTRAP_SERVER} \\"
echo -e "      --describe \\"
echo -e "      --group ${GROUP_ID}${NC}"
echo -e "  ─────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 컨슈머 2대 → 각 컨슈머가 3개씩 파티션을 담당 (6/2=3)"
echo -e "  - 컨슈머 3대 → 각 2개씩 (6/3=2)"
echo -e "  - 컨슈머 7대 → 6대만 파티션 할당, 1대는 idle 상태"
echo -e "  - 이것이 '파티션 수 = 컨슈머 최대 병렬 처리 수'인 이유다."
echo -e "  - 재할당 중 일시적으로 소비가 멈추는 것이 'Rebalancing'이다."
echo ""
read -p "  실험 완료 후 Enter를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 6: 오프셋 리셋
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 6] 오프셋 리셋${NC}"
echo -e "${RED}  주의: 오프셋 리셋은 해당 그룹의 모든 컨슈머를 종료한 후 실행해야 한다.${NC}"
echo -e "  Terminal 2, 3의 컨슈머를 Ctrl+C로 종료하라."
echo ""
read -p "  컨슈머를 모두 종료한 후 Enter를 누르세요..."
echo ""

echo -e "  ${CYAN}6-1. --to-earliest: 처음부터 다시 읽기 (dry-run 먼저)${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --group ${GROUP_ID} \
    --topic ${TOPIC_NAME} \
    --reset-offsets \
    --to-earliest \
    --dry-run

echo ""
echo -e "  ${CYAN}6-2. --to-earliest 실제 적용${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --group ${GROUP_ID} \
    --topic ${TOPIC_NAME} \
    --reset-offsets \
    --to-earliest \
    --execute

echo ""
echo -e "  ${CYAN}6-3. --to-latest: 가장 최신 오프셋으로 이동${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --group ${GROUP_ID} \
    --topic ${TOPIC_NAME} \
    --reset-offsets \
    --to-latest \
    --execute

echo ""
echo -e "  ${CYAN}6-4. --to-offset: 특정 오프셋으로 이동 (파티션 0을 오프셋 100으로)${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --group ${GROUP_ID} \
    --topic ${TOPIC_NAME}:0 \
    --reset-offsets \
    --to-offset 100 \
    --execute

echo ""
echo -e "  ${CYAN}6-5. --by-duration: 특정 시간 이전으로 이동 (1시간 전)${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-consumer-groups.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --group ${GROUP_ID} \
    --topic ${TOPIC_NAME} \
    --reset-offsets \
    --by-duration PT1H \
    --dry-run

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 오프셋 리셋 후 컨슈머를 재시작하면 지정 위치부터 다시 읽는다."
echo -e "  - --dry-run으로 먼저 확인하고 --execute로 적용하는 것이 안전하다."
echo -e "  - 오프셋은 __consumer_offsets 토픽에 저장된다."
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
echo -e "${GREEN}  실습 03 완료!${NC}"
echo -e "${GREEN}  다음 실습: 04-replication-test.sh${NC}"
echo -e "${GREEN}=====================================================${NC}"
