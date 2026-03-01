#!/bin/bash
# 실습 01: 토픽과 파티션 조작
# Study Vault 참조: 02-토픽과-파티션/concepts.md
#
# 목표: Kafka 토픽의 생성, 조회, 설정 변경, 삭제를 직접 수행하며
#       파티션과 복제계수(Replication Factor)의 동작 원리를 이해한다.
#
# 사전 준비: broker-1, broker-2, broker-3 컨테이너가 실행 중이어야 한다.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

BROKER_CONTAINER="broker-1"
BOOTSTRAP_SERVER="broker-1:29092"
KAFKA_BIN="/opt/kafka/bin"
TOPIC_NAME="study-topic-01"

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 01: 토픽과 파티션 조작${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""

# ─────────────────────────────────────────────────────────
# STEP 1: 토픽 생성 (파티션 3, 복제계수 3)
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 1] 토픽 생성 - 파티션 3개, 복제계수 3${NC}"
echo -e "  토픽명: ${TOPIC_NAME}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --create \
    --topic ${TOPIC_NAME} \
    --partitions 3 \
    --replication-factor 3

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - replication-factor는 브로커 수보다 클 수 없다."
echo -e "  - 브로커가 3대 미만이면 위 명령이 실패한다. 이유를 생각해보자."
echo -e "  - 참조: 02-토픽과-파티션/concepts.md → 복제계수 섹션"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 2: 토픽 목록 조회
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 2] 클러스터 내 전체 토픽 목록 조회${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --list

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 내부 토픽(언더스코어로 시작)도 함께 표시될 수 있다."
echo -e "  - __consumer_offsets: 컨슈머 오프셋 저장용 내부 토픽"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 3: 토픽 상세 정보 조회 (파티션 리더, ISR 확인)
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 3] 토픽 상세 정보 - 파티션 리더 & ISR 확인${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - Leader: 해당 파티션의 읽기/쓰기를 처리하는 브로커 ID"
echo -e "  - Replicas: 복제본을 가진 브로커 ID 목록 (순서 = 우선순위)"
echo -e "  - Isr (In-Sync Replicas): 리더와 동기화된 복제본 목록"
echo -e "  - Isr != Replicas 상태라면 일부 복제본이 뒤처진 것이다."
echo -e "  - 참조: 02-토픽과-파티션/concepts.md → ISR 섹션"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 4: 파티션 수 변경 (3 → 6)
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 4] 파티션 수 변경: 3 → 6${NC}"
echo -e "${CYAN}  주의: Kafka에서 파티션 수는 늘릴 수만 있고 줄일 수 없다!${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --alter \
    --topic ${TOPIC_NAME} \
    --partitions 6

echo ""
echo -e "  변경 후 상세 정보 확인:"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --topic ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 파티션이 3개에서 6개로 늘어났는지 확인하라."
echo -e "  - 새 파티션의 리더가 각 브로커에 분산되는지 확인하라."
echo -e "  - 파티션 축소를 시도해보자 (--partitions 2): 에러 메시지를 읽어보자."
echo -e "  - 왜 줄일 수 없는가? 이미 특정 파티션에 쓰인 데이터는 어디로 가는가?"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 5: 토픽 설정 변경
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 5] 토픽 설정 변경${NC}"
echo -e "  - retention.ms: 메시지 보존 기간 (1시간 = 3600000ms)"
echo -e "  - cleanup.policy: delete(기본) vs compact"
echo ""

echo -e "  ${CYAN}5-1. retention.ms를 1시간으로 설정${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-configs.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --alter \
    --entity-type topics \
    --entity-name ${TOPIC_NAME} \
    --add-config retention.ms=3600000

echo ""
echo -e "  ${CYAN}5-2. cleanup.policy를 compact로 변경${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-configs.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --alter \
    --entity-type topics \
    --entity-name ${TOPIC_NAME} \
    --add-config cleanup.policy=compact

echo ""
echo -e "  ${CYAN}5-3. 현재 토픽 설정 조회${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-configs.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --entity-type topics \
    --entity-name ${TOPIC_NAME}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - retention.ms=3600000: 1시간 후 오래된 메시지 삭제"
echo -e "  - cleanup.policy=compact: 동일 키의 최신 값만 유지 (이벤트 소싱, CDC에 유용)"
echo -e "  - cleanup.policy=delete,compact: 두 정책을 동시에 적용할 수 있다"
echo -e "  - 설정을 원래대로 되돌리려면: --delete-config retention.ms"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 6: 토픽 삭제
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 6] 토픽 삭제${NC}"
echo -e "${CYAN}  주의: delete.topic.enable=true 설정 필요 (기본값은 true)${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --delete \
    --topic ${TOPIC_NAME}

echo ""
echo -e "  삭제 후 토픽 목록 재확인:"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --list

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 삭제는 비동기로 처리된다. 즉시 사라지지 않을 수 있다."
echo -e "  - 프로덕션에서는 토픽 삭제 전 컨슈머 그룹 오프셋도 함께 정리해야 한다."
echo -e "  - 참조: 02-토픽과-파티션/concepts.md → 토픽 관리 섹션"
echo ""

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 01 완료!${NC}"
echo -e "${GREEN}  다음 실습: 02-producer-acks-comparison.sh${NC}"
echo -e "${GREEN}=====================================================${NC}"
