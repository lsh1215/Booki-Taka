#!/bin/bash
# ==============================================================
# wait-for-es.sh
# Elasticsearch 클러스터가 정상 상태(green 또는 yellow)가 될 때까지 대기하는 스크립트
#
# 사용법:
#   ./wait-for-es.sh [ES_URL]
#   ./wait-for-es.sh http://localhost:9200
#
# 기본값: http://localhost:9200
# 타임아웃: 120초
# ==============================================================

set -euo pipefail

# ----------------------------------------------------------
# 설정값
# ----------------------------------------------------------
ES_URL="${1:-http://localhost:9200}"   # ES URL (인수로 전달하지 않으면 기본값 사용)
TIMEOUT=120                             # 최대 대기 시간 (초)
INTERVAL=5                              # 폴링 간격 (초)
ELAPSED=0                               # 경과 시간

# ----------------------------------------------------------
# 색상 출력 함수 (터미널에서 가독성 향상)
# ----------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ----------------------------------------------------------
# 메인 루프: 클러스터 상태 확인
# ----------------------------------------------------------
log_info "Elasticsearch 클러스터 상태를 확인합니다..."
log_info "대상 URL: ${ES_URL}"
log_info "최대 대기 시간: ${TIMEOUT}초"
echo ""

while true; do
    # curl 로 클러스터 헬스 상태 조회
    HEALTH=$(curl -s --connect-timeout 5 "${ES_URL}/_cluster/health" 2>/dev/null | \
             grep -o '"status":"[^"]*"' | \
             grep -o '"[^"]*"$' | \
             tr -d '"') || HEALTH="unknown"

    case "${HEALTH}" in
        green)
            log_info "클러스터 상태: GREEN - 모든 샤드가 정상입니다."
            log_info "Elasticsearch가 준비되었습니다! (소요 시간: ${ELAPSED}초)"
            exit 0
            ;;
        yellow)
            log_warn "클러스터 상태: YELLOW - 레플리카 샤드 일부가 미할당 상태입니다."
            log_warn "학습 환경에서는 YELLOW도 정상입니다. 계속 진행합니다."
            log_info "Elasticsearch가 준비되었습니다! (소요 시간: ${ELAPSED}초)"
            exit 0
            ;;
        red)
            log_error "클러스터 상태: RED - 일부 프라이머리 샤드가 미할당 상태입니다."
            log_info "${INTERVAL}초 후 재시도... (경과: ${ELAPSED}/${TIMEOUT}초)"
            ;;
        *)
            log_info "Elasticsearch 응답 대기 중... (상태: ${HEALTH}, 경과: ${ELAPSED}/${TIMEOUT}초)"
            ;;
    esac

    # 타임아웃 체크
    if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
        log_error "타임아웃! ${TIMEOUT}초 내에 Elasticsearch가 준비되지 않았습니다."
        log_error "다음 명령으로 로그를 확인하세요: docker compose logs es01"
        exit 1
    fi

    sleep "${INTERVAL}"
    ELAPSED=$((ELAPSED + INTERVAL))
done
