#!/bin/bash
# ==============================================================
# start.sh
# Elasticsearch 학습 환경 원클릭 시작/종료 스크립트
#
# 사용법:
#   ./scripts/start.sh                   # 기본 클러스터 시작
#   ./scripts/start.sh --with-monitoring # 모니터링 포함 시작
#   ./scripts/start.sh --down            # 클러스터 중지
#   ./scripts/start.sh --destroy         # 클러스터 중지 + 볼륨 삭제 (데이터 초기화)
#
# 사전 요구사항:
#   - Docker 및 Docker Compose 설치
#   - macOS: vm.max_map_count 설정 불필요 (Docker Desktop이 자동 처리)
#   - Linux: sysctl -w vm.max_map_count=262144 실행 필요
# ==============================================================

set -euo pipefail

# ----------------------------------------------------------
# 스크립트 위치 기준으로 labs/elasticsearch 디렉토리를 루트로 설정
# ----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_DIR="${LAB_DIR}/setup"
ES_URL="http://localhost:9200"

# ----------------------------------------------------------
# 색상 출력 함수
# ----------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "${BLUE}[STEP]${NC}  $*"; }

# ----------------------------------------------------------
# 배너 출력
# ----------------------------------------------------------
print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}   Elasticsearch 학습 환경 (es-lab)${NC}"
    echo -e "${CYAN}${BOLD}   버전: 8.12.0 | 노드: 3 | 보안: 비활성화${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo ""
}

# ----------------------------------------------------------
# 사전 요구사항 확인
# ----------------------------------------------------------
check_prerequisites() {
    log_step "사전 요구사항 확인 중..."

    # Docker 설치 확인
    if ! command -v docker &>/dev/null; then
        log_error "Docker가 설치되지 않았습니다."
        log_error "https://docs.docker.com/get-docker/ 에서 설치하세요."
        exit 1
    fi

    # Docker 실행 상태 확인
    if ! docker info &>/dev/null; then
        log_error "Docker 데몬이 실행되지 않았습니다. Docker를 시작해 주세요."
        exit 1
    fi

    # Docker Compose 설치 확인 (v2 플러그인 방식 우선, v1 폴백)
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        log_warn "Docker Compose v1을 사용합니다. v2 (docker compose) 사용을 권장합니다."
    else
        log_error "Docker Compose가 설치되지 않았습니다."
        exit 1
    fi

    log_info "Docker: $(docker --version)"
    log_info "Compose: $(${COMPOSE_CMD} version 2>/dev/null || docker-compose --version)"

    # Linux에서 vm.max_map_count 확인
    if [[ "$(uname -s)" == "Linux" ]]; then
        CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo "0")
        if [ "${CURRENT_MAP_COUNT}" -lt 262144 ]; then
            log_warn "vm.max_map_count=${CURRENT_MAP_COUNT} (권장: 262144)"
            log_warn "다음 명령으로 설정하세요: sudo sysctl -w vm.max_map_count=262144"
            log_warn "영구 적용: echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf"
        fi
    fi
}

# ----------------------------------------------------------
# 시작 함수
# ----------------------------------------------------------
start_cluster() {
    local with_monitoring="${1:-false}"

    print_banner
    check_prerequisites

    echo ""
    log_step "Elasticsearch 클러스터 시작 중..."
    echo ""

    cd "${LAB_DIR}"

    if [ "${with_monitoring}" = "true" ]; then
        log_info "모니터링 포함 모드로 시작합니다 (Prometheus + Grafana)"
        ${COMPOSE_CMD} \
            -f docker-compose.yml \
            -f docker-compose.monitoring.yml \
            up -d
    else
        log_info "기본 모드로 시작합니다 (ES 클러스터 + Kibana + Cerebro)"
        ${COMPOSE_CMD} -f docker-compose.yml up -d
    fi

    echo ""
    log_info "컨테이너 시작 완료. 클러스터 준비를 기다립니다..."
    echo ""

    # 클러스터 초기화 (헬스체크 대기 + 인덱스 템플릿 생성)
    "${SETUP_DIR}/init-cluster.sh" "${ES_URL}"

    # 접속 정보 최종 출력
    print_endpoints "${with_monitoring}"
}

# ----------------------------------------------------------
# 중지 함수
# ----------------------------------------------------------
stop_cluster() {
    local destroy="${1:-false}"

    print_banner
    cd "${LAB_DIR}"

    # 실행 중인 compose 파일 자동 감지
    local compose_files="-f docker-compose.yml"
    if docker ps --format '{{.Names}}' | grep -q "^prometheus$"; then
        compose_files="${compose_files} -f docker-compose.monitoring.yml"
        log_info "모니터링 서비스도 함께 종료합니다."
    fi

    if [ "${destroy}" = "true" ]; then
        log_warn "모든 데이터 볼륨을 삭제합니다! (es01-data, es02-data, es03-data)"
        read -r -p "정말로 삭제하시겠습니까? (yes/N): " confirm
        if [ "${confirm}" != "yes" ]; then
            log_info "취소되었습니다."
            exit 0
        fi
        log_step "클러스터 중지 및 볼륨 삭제 중..."
        ${COMPOSE_CMD} ${compose_files} down -v
        log_info "클러스터가 중지되고 볼륨이 삭제되었습니다."
    else
        log_step "클러스터 중지 중... (데이터는 보존됩니다)"
        ${COMPOSE_CMD} ${compose_files} down
        log_info "클러스터가 중지되었습니다. 데이터는 볼륨에 보존됩니다."
        log_info "재시작하려면: ./scripts/start.sh"
    fi
}

# ----------------------------------------------------------
# 접속 엔드포인트 안내 출력
# ----------------------------------------------------------
print_endpoints() {
    local with_monitoring="${1:-false}"

    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}   서비스 접속 정보${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo ""
    echo -e "  ${BOLD}Elasticsearch${NC}"
    echo "    - es01: http://localhost:9200"
    echo "    - es02: http://localhost:9201"
    echo "    - es03: http://localhost:9202"
    echo ""
    echo -e "  ${BOLD}Kibana${NC} (DevTools, 인덱스 관리)"
    echo "    - http://localhost:5601"
    echo ""
    echo -e "  ${BOLD}Cerebro${NC} (클러스터 시각화)"
    echo "    - http://localhost:9000"
    echo ""

    if [ "${with_monitoring}" = "true" ]; then
        echo -e "  ${BOLD}모니터링${NC}"
        echo "    - Prometheus: http://localhost:9090"
        echo "    - Grafana:    http://localhost:3000  (admin / admin)"
        echo ""
    fi

    echo -e "  ${BOLD}빠른 시작 쿼리 (curl)${NC}"
    echo "    curl http://localhost:9200/_cluster/health?pretty"
    echo "    curl http://localhost:9200/_cat/nodes?v"
    echo "    curl http://localhost:9200/lab-books/_search?pretty"
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo ""
}

# ----------------------------------------------------------
# 도움말 출력
# ----------------------------------------------------------
print_help() {
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  (없음)              기본 클러스터 시작 (ES + Kibana + Cerebro)"
    echo "  --with-monitoring   모니터링 포함 시작 (Prometheus + Grafana 추가)"
    echo "  --down              클러스터 중지 (데이터 보존)"
    echo "  --destroy           클러스터 중지 + 볼륨 삭제 (데이터 초기화)"
    echo "  --help, -h          이 도움말 출력"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 시작"
    echo "  $0 --with-monitoring  # 모니터링 포함 시작"
    echo "  $0 --down             # 중지"
    echo "  $0 --destroy          # 완전 초기화"
    echo ""
}

# ----------------------------------------------------------
# 인수 파싱 및 실행
# ----------------------------------------------------------
WITH_MONITORING=false
ACTION="start"

for arg in "$@"; do
    case "${arg}" in
        --with-monitoring)
            WITH_MONITORING=true
            ;;
        --down)
            ACTION="down"
            ;;
        --destroy)
            ACTION="destroy"
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            log_error "알 수 없는 옵션: ${arg}"
            print_help
            exit 1
            ;;
    esac
done

case "${ACTION}" in
    start)
        start_cluster "${WITH_MONITORING}"
        ;;
    down)
        stop_cluster "false"
        ;;
    destroy)
        stop_cluster "true"
        ;;
esac
