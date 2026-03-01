#!/bin/bash
# 실습 05: 로그 세그먼트 내부 구조 탐색
# Study Vault 참조: 02-토픽과-파티션/concepts.md (세그먼트)
#
# 목표: Kafka 로그 디렉토리의 실제 파일 구조(.log, .index, .timeindex)를 확인하고,
#       kafka-dump-log.sh로 세그먼트 내용을 덤프하며, 세그먼트 롤링과
#       로그 정책(삭제 vs 압착)의 차이를 직접 관찰한다.
#
# 사전 준비: broker-1 컨테이너가 실행 중이어야 한다.
#            Kafka 로그 데이터 디렉토리: /var/lib/kafka/data (기본값)
#            실제 경로는 broker-1의 log.dirs 설정을 확인하라.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

BROKER_CONTAINER="broker-1"
BOOTSTRAP_SERVER="broker-1:29092"
KAFKA_BIN="/opt/kafka/bin"
TOPIC_SEGMENT="segment-test-01"
TOPIC_COMPACT="compact-test-01"
TOPIC_DELETE="delete-test-01"
# broker-1의 실제 log.dirs 경로로 변경하라
KAFKA_LOG_DIR="/var/lib/kafka/data"

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 05: 로그 세그먼트 내부 구조 탐색${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "  Kafka 로그 디렉토리: ${KAFKA_LOG_DIR}"
echo -e "  실제 경로가 다르다면 스크립트 상단의 KAFKA_LOG_DIR을 수정하라."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 1: 토픽 데이터 디렉토리 구조 확인
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 1] Kafka 로그 디렉토리 전체 구조 확인${NC}"
echo ""

echo -e "  ${CYAN}1-1. 로그 디렉토리 최상위 구조${NC}"
docker exec ${BROKER_CONTAINER} ls -la ${KAFKA_LOG_DIR}

echo ""
echo -e "  ${CYAN}1-2. 특정 토픽-파티션 디렉토리 확인 (있는 경우)${NC}"
echo -e "       형식: {토픽명}-{파티션번호}"
docker exec ${BROKER_CONTAINER} ls -la ${KAFKA_LOG_DIR} | grep -v "^total" | head -20

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 토픽-파티션 디렉토리 형식: {TOPIC_NAME}-{PARTITION_NUMBER}"
echo -e "  - 각 파티션이 별도 디렉토리로 관리된다."
echo -e "  - __consumer_offsets-0 ~ __consumer_offsets-49: 오프셋 저장용 내부 파티션"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 2: 세그먼트 롤링 관찰용 토픽 생성 (작은 segment.bytes)
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 2] 세그먼트 롤링 실험용 토픽 생성${NC}"
echo -e "${CYAN}  segment.bytes=10240 (10KB): 매우 작은 세그먼트 크기로 롤링을 빠르게 관찰${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --create \
    --topic ${TOPIC_SEGMENT} \
    --partitions 1 \
    --replication-factor 1 \
    --config segment.bytes=10240 \
    --config segment.ms=60000 \
    --if-not-exists

echo ""
echo -e "  토픽 설정 확인:"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-configs.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --describe \
    --entity-type topics \
    --entity-name ${TOPIC_SEGMENT}

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - segment.bytes=10240: 세그먼트가 10KB에 도달하면 새 세그먼트 생성"
echo -e "  - segment.ms=60000: 60초가 지나면 크기와 무관하게 새 세그먼트 생성"
echo -e "  - 프로덕션 기본값: segment.bytes=1073741824 (1GB)"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 3: 데이터 전송 후 .log, .index, .timeindex 파일 확인
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 3] 데이터 전송 후 세그먼트 파일 구조 확인${NC}"
echo ""

echo -e "  ${CYAN}3-1. 데이터 전송 (여러 세그먼트 생성을 위해 넉넉히 전송)${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-producer-perf-test.sh \
    --topic ${TOPIC_SEGMENT} \
    --num-records 200 \
    --record-size 512 \
    --throughput -1 \
    --producer-props bootstrap.servers=${BOOTSTRAP_SERVER} acks=1

echo ""
echo -e "  ${CYAN}3-2. 파티션 디렉토리의 세그먼트 파일 목록${NC}"
docker exec ${BROKER_CONTAINER} ls -lah ${KAFKA_LOG_DIR}/${TOPIC_SEGMENT}-0/ 2>/dev/null || \
  echo -e "  ${RED}디렉토리를 찾을 수 없다. KAFKA_LOG_DIR 경로를 확인하라.${NC}"

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - {offset}.log: 실제 메시지 데이터 (바이너리)"
echo -e "  - {offset}.index: 오프셋 → 파일 위치 인덱스 (빠른 검색용)"
echo -e "  - {offset}.timeindex: 타임스탬프 → 오프셋 인덱스 (시간 기반 검색용)"
echo -e "  - 파일명의 숫자: 해당 세그먼트의 첫 번째 메시지 오프셋"
echo -e "  - 00000000000000000000.log: 오프셋 0부터 시작하는 첫 번째 세그먼트"
echo -e "  - 활성 세그먼트(현재 쓰기 중): .log 파일이 segment.bytes 미만"
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 4: kafka-dump-log.sh로 세그먼트 내용 덤프
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 4] kafka-dump-log.sh로 세그먼트 내용 덤프${NC}"
echo ""

# 첫 번째 .log 파일 경로 동적 탐색
FIRST_LOG_FILE=$(docker exec ${BROKER_CONTAINER} \
  ls ${KAFKA_LOG_DIR}/${TOPIC_SEGMENT}-0/*.log 2>/dev/null | head -1)

if [ -z "${FIRST_LOG_FILE}" ]; then
  echo -e "${RED}  .log 파일을 찾을 수 없다. KAFKA_LOG_DIR을 확인하라.${NC}"
  echo -e "${CYAN}  수동 실행 예시:${NC}"
  echo -e "  docker exec ${BROKER_CONTAINER} \\"
  echo -e "    ${KAFKA_BIN}/kafka-dump-log.sh \\"
  echo -e "      --files /var/lib/kafka/data/${TOPIC_SEGMENT}-0/00000000000000000000.log \\"
  echo -e "      --print-data-log | head -30"
else
  echo -e "  ${CYAN}4-1. 메시지 내용 포함 덤프 (처음 10개 레코드)${NC}"
  docker exec ${BROKER_CONTAINER} \
    ${KAFKA_BIN}/kafka-dump-log.sh \
      --files ${FIRST_LOG_FILE} \
      --print-data-log 2>/dev/null | head -40

  echo ""
  echo -e "  ${CYAN}4-2. 오프셋 인덱스 파일 덤프${NC}"
  FIRST_INDEX_FILE=$(echo ${FIRST_LOG_FILE} | sed 's/.log$/.index/')
  docker exec ${BROKER_CONTAINER} \
    ${KAFKA_BIN}/kafka-dump-log.sh \
      --files ${FIRST_INDEX_FILE} 2>/dev/null | head -20
fi

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - offset: 파티션 내 메시지의 고유 번호 (단조 증가, 변경 불가)"
echo -e "  - CreateTime: 메시지 생성 타임스탬프 (epoch ms)"
echo -e "  - keysize / valuesize: 키/값의 바이트 크기"
echo -e "  - .index 파일: 듬성듬성(sparse) 저장 - 모든 오프셋이 아니라 일부만 인덱싱"
echo -e "  - 이진 탐색으로 특정 오프셋을 O(log n)에 찾을 수 있다."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 5: 로그 압착(Compaction) vs 삭제(Delete) 정책 비교
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 5] 로그 정책 비교: delete vs compact${NC}"
echo ""

echo -e "  ${CYAN}5-1. cleanup.policy=delete 토픽 생성 (retention.ms=5000: 5초 후 삭제)${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --create \
    --topic ${TOPIC_DELETE} \
    --partitions 1 \
    --replication-factor 1 \
    --config cleanup.policy=delete \
    --config retention.ms=5000 \
    --config segment.ms=3000 \
    --if-not-exists

echo ""
echo -e "  ${CYAN}5-2. cleanup.policy=compact 토픽 생성${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-topics.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --create \
    --topic ${TOPIC_COMPACT} \
    --partitions 1 \
    --replication-factor 1 \
    --config cleanup.policy=compact \
    --config min.cleanable.dirty.ratio=0.01 \
    --config segment.ms=3000 \
    --if-not-exists

echo ""
echo -e "  ${CYAN}5-3. 동일 키로 여러 버전의 메시지 전송 (compact 토픽)${NC}"
echo -e "       키 'user-1'로 3번, 키 'user-2'로 2번 전송"
for i in 1 2 3; do
  echo "user-1:version-${i}" | docker exec -i ${BROKER_CONTAINER} \
    ${KAFKA_BIN}/kafka-console-producer.sh \
      --bootstrap-server ${BOOTSTRAP_SERVER} \
      --topic ${TOPIC_COMPACT} \
      --property parse.key=true \
      --property key.separator=:
done
for i in 1 2; do
  echo "user-2:version-${i}" | docker exec -i ${BROKER_CONTAINER} \
    ${KAFKA_BIN}/kafka-console-producer.sh \
      --bootstrap-server ${BOOTSTRAP_SERVER} \
      --topic ${TOPIC_COMPACT} \
      --property parse.key=true \
      --property key.separator=:
done

echo ""
echo -e "  ${CYAN}5-4. 즉시 확인 (압착 전): 5건 모두 존재해야 함${NC}"
docker exec ${BROKER_CONTAINER} \
  ${KAFKA_BIN}/kafka-console-consumer.sh \
    --bootstrap-server ${BOOTSTRAP_SERVER} \
    --topic ${TOPIC_COMPACT} \
    --from-beginning \
    --property print.key=true \
    --timeout-ms 3000 2>/dev/null

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - cleanup.policy=delete: 시간(retention.ms) 또는 크기(retention.bytes) 초과 시 오래된 세그먼트 삭제"
echo -e "    → 전체 메시지 히스토리가 사라진다 (이벤트 스트리밍에 적합)"
echo -e ""
echo -e "  - cleanup.policy=compact: 동일 키의 최신 값만 유지, 이전 버전 삭제"
echo -e "    → 키의 최신 상태만 필요한 경우에 적합 (데이터베이스 변경 스트림, CDC)"
echo -e "    → 압착은 백그라운드로 실행되어 즉시 반영되지 않을 수 있다."
echo -e ""
echo -e "  - cleanup.policy=delete,compact: 두 정책을 동시 적용"
echo -e "    → retention.ms 이상 된 메시지 중 최신 키 버전도 삭제 가능"
echo -e ""
echo -e "  - 압착 후 compact 토픽을 재조회하면 user-1:version-3, user-2:version-2만 남는다."
echo ""
read -p "  계속하려면 Enter 키를 누르세요..."
echo ""

# ─────────────────────────────────────────────────────────
# STEP 6: 로그 디렉토리 크기 모니터링
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[STEP 6] 로그 디렉토리 용량 확인${NC}"
echo ""

docker exec ${BROKER_CONTAINER} \
  du -sh ${KAFKA_LOG_DIR}/* 2>/dev/null | sort -rh | head -20

echo ""
echo -e "${YELLOW}[관찰 포인트]${NC}"
echo -e "  - 각 파티션 디렉토리의 디스크 사용량을 확인한다."
echo -e "  - retention.ms=5000인 ${TOPIC_DELETE} 토픽은 곧 데이터가 삭제된다."
echo -e "  - 실제 삭제는 log.retention.check.interval.ms 주기(기본 5분)마다 실행된다."
echo ""

# ─────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────
echo -e "${GREEN}[CLEANUP] 테스트 토픽들 삭제${NC}"
for TOPIC in ${TOPIC_SEGMENT} ${TOPIC_DELETE} ${TOPIC_COMPACT}; do
  docker exec ${BROKER_CONTAINER} \
    ${KAFKA_BIN}/kafka-topics.sh \
      --bootstrap-server ${BOOTSTRAP_SERVER} \
      --delete \
      --topic ${TOPIC} 2>/dev/null
  echo -e "  삭제: ${TOPIC}"
done

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  실습 05 완료!${NC}"
echo -e "${GREEN}  Kafka Architecture 실습 시리즈 전체 완료.${NC}"
echo -e "${GREEN}  Study Vault Part 1 개념 정리를 다시 읽으며${NC}"
echo -e "${GREEN}  실습에서 관찰한 내용을 연결해보자.${NC}"
echo -e "${GREEN}=====================================================${NC}"
