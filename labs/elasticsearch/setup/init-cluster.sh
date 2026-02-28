#!/bin/bash
# ==============================================================
# init-cluster.sh
# Elasticsearch 클러스터 초기화 스크립트
#
# 실행 순서:
#   1. wait-for-es.sh 로 클러스터 준비 대기
#   2. 클러스터 영구 설정 적용
#   3. 학습용 인덱스 템플릿 생성
#   4. 기본 샘플 데이터 인덱싱 (선택적)
#
# 사용법:
#   ./init-cluster.sh [ES_URL]
#   ./init-cluster.sh http://localhost:9200
# ==============================================================

set -euo pipefail

# ----------------------------------------------------------
# 설정값
# ----------------------------------------------------------
ES_URL="${1:-http://localhost:9200}"   # ES URL
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------------------------------------
# 색상 출력 함수
# ----------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "${BLUE}[STEP]${NC}  $*"; }

# curl 실행 후 HTTP 상태코드 확인하는 헬퍼 함수
curl_check() {
    local description="$1"
    shift
    local response
    response=$(curl -s -w "\n%{http_code}" "$@")
    local http_code
    http_code=$(echo "${response}" | tail -n1)
    local body
    body=$(echo "${response}" | head -n -1)

    if [[ "${http_code}" -ge 200 && "${http_code}" -lt 300 ]]; then
        log_info "${description} 완료 (HTTP ${http_code})"
        echo "${body}"
    else
        log_error "${description} 실패 (HTTP ${http_code})"
        log_error "응답: ${body}"
        return 1
    fi
}

# ----------------------------------------------------------
# Step 1: 클러스터 준비 대기
# ----------------------------------------------------------
echo ""
echo "============================================================"
echo "  Elasticsearch 클러스터 초기화 시작"
echo "  대상: ${ES_URL}"
echo "============================================================"
echo ""

log_step "1/4 - 클러스터 상태 확인 중..."
"${SCRIPT_DIR}/wait-for-es.sh" "${ES_URL}"

# ----------------------------------------------------------
# Step 2: 클러스터 영구(Persistent) 설정 적용
# ----------------------------------------------------------
log_step "2/4 - 클러스터 설정 적용 중..."

curl_check "클러스터 영구 설정" \
    -X PUT "${ES_URL}/_cluster/settings" \
    -H "Content-Type: application/json" \
    -d '{
        "persistent": {
            "cluster.routing.allocation.enable": "all",
            "indices.recovery.max_bytes_per_sec": "50mb"
        },
        "transient": {
            "logger.level": "INFO"
        }
    }'

# ----------------------------------------------------------
# Step 3: 학습용 인덱스 템플릿 생성
#
# - 이름: lab-template
# - 대상 인덱스 패턴: lab-* (예: lab-books, lab-logs 등)
# - 프라이머리 샤드: 1개 (학습 환경에서는 1개로 충분)
# - 레플리카 샤드: 1개 (3노드 환경에서 노드 장애 시 데이터 보호)
# ----------------------------------------------------------
log_step "3/4 - 학습용 인덱스 템플릿 생성 중..."

curl_check "인덱스 템플릿(lab-template) 생성" \
    -X PUT "${ES_URL}/_index_template/lab-template" \
    -H "Content-Type: application/json" \
    -d '{
        "index_patterns": ["lab-*"],
        "priority": 1,
        "template": {
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 1,
                "refresh_interval": "1s",
                "analysis": {
                    "analyzer": {
                        "korean_text": {
                            "type": "standard",
                            "stopwords": "_korean_"
                        }
                    }
                }
            },
            "mappings": {
                "_source": { "enabled": true },
                "dynamic": true
            }
        }
    }'

# ----------------------------------------------------------
# Step 4: 샘플 데이터 인덱싱
#
# 학습 시 바로 쿼리 실습이 가능하도록 기본 도서 데이터를 인덱싱합니다.
# 인덱스 이름: lab-books
# ----------------------------------------------------------
log_step "4/4 - 샘플 데이터 인덱싱 중..."

# 인덱스가 이미 존재하는지 확인
INDEX_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" "${ES_URL}/lab-books")
if [ "${INDEX_EXISTS}" = "200" ]; then
    log_warn "lab-books 인덱스가 이미 존재합니다. 샘플 데이터 삽입을 건너뜁니다."
else
    # Bulk API로 샘플 도서 데이터 삽입
    curl_check "샘플 도서 데이터(lab-books) 인덱싱" \
        -X POST "${ES_URL}/_bulk" \
        -H "Content-Type: application/json" \
        -d '
{"index": {"_index": "lab-books", "_id": "1"}}
{"title": "Elasticsearch 완벽 가이드", "author": "클린턴 고만", "category": "기술서", "year": 2023, "rating": 4.8, "description": "Elasticsearch의 핵심 개념부터 고급 활용까지 다루는 종합 가이드"}
{"index": {"_index": "lab-books", "_id": "2"}}
{"title": "데이터 엔지니어링 실무", "author": "이상훈", "category": "기술서", "year": 2022, "rating": 4.5, "description": "현업에서 사용되는 데이터 파이프라인 구축 방법론"}
{"index": {"_index": "lab-books", "_id": "3"}}
{"title": "클라우드 네이티브 아키텍처", "author": "김철수", "category": "기술서", "year": 2023, "rating": 4.3, "description": "쿠버네티스와 마이크로서비스를 이용한 클라우드 네이티브 설계"}
{"index": {"_index": "lab-books", "_id": "4"}}
{"title": "검색 엔진 최적화 실전", "author": "박영희", "category": "기술서", "year": 2021, "rating": 4.6, "description": "Elasticsearch를 이용한 풀텍스트 검색 최적화 기법"}
{"index": {"_index": "lab-books", "_id": "5"}}
{"title": "파이썬 머신러닝 입문", "author": "정민준", "category": "기술서", "year": 2022, "rating": 4.2, "description": "scikit-learn과 tensorflow를 이용한 머신러닝 기초"}
'
fi

# ----------------------------------------------------------
# 완료 메시지 및 접속 안내
# ----------------------------------------------------------
echo ""
echo "============================================================"
log_info "클러스터 초기화 완료!"
echo "============================================================"
echo ""
echo "  접속 URL:"
echo "    - Elasticsearch: ${ES_URL}"
echo "    - Kibana:        http://localhost:5601"
echo "    - Cerebro:       http://localhost:9000"
echo ""
echo "  학습용 인덱스:"
echo "    - lab-books (샘플 도서 5건)"
echo ""
echo "  Kibana DevTools에서 다음 쿼리를 실행해 보세요:"
echo "    GET /lab-books/_search"
echo "    GET /_cluster/health"
echo "    GET /_cat/nodes?v"
echo ""
