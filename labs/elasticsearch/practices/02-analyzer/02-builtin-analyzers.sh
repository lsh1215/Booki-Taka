#!/bin/bash
# ==============================================================
# 02-builtin-analyzers.sh
# 내장 애널라이저 비교 실습
# 관찰 포인트: 각 애널라이저별 토큰화 방식의 차이
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

SAMPLE_TEXT="The Quick-Brown Fox, Jumps Over The Lazy Dog! (Elasticsearch 8.12)"

echo "============================================================"
echo "  02. 내장 애널라이저 비교"
echo "  ES_HOST: $ES_HOST"
echo "  샘플 텍스트: $SAMPLE_TEXT"
echo "============================================================"
echo ""

# 분석 함수 정의
analyze() {
  local analyzer="$1"
  local text="$2"
  curl -s -X POST "$ES_HOST/_analyze" \
    -H 'Content-Type: application/json' \
    -d "{\"analyzer\": \"$analyzer\", \"text\": \"$text\"}" | jq -r '[.tokens[].token] | join(" | ")'
}

# --------------------------------------------------------------
# STEP 1: standard
# --------------------------------------------------------------
echo ">>> [STEP 1] standard 애널라이저"
echo "--- 유니코드 텍스트 분할 + 소문자 변환 + 불용어 제거(기본 비활성)"
echo "--- 구두점 제거, 대부분의 언어에 적합한 기본 애널라이저"
echo "결과: $(analyze standard "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 2: simple
# --------------------------------------------------------------
echo ">>> [STEP 2] simple 애널라이저"
echo "--- 알파벳이 아닌 모든 문자로 분리 + 소문자 변환"
echo "--- 숫자는 분리자로 처리되어 토큰에 포함되지 않음"
echo "결과: $(analyze simple "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 3: whitespace
# --------------------------------------------------------------
echo ">>> [STEP 3] whitespace 애널라이저"
echo "--- 공백(whitespace)으로만 분리, 소문자 변환 없음, 구두점 유지"
echo "결과: $(analyze whitespace "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 4: stop
# --------------------------------------------------------------
echo ">>> [STEP 4] stop 애널라이저"
echo "--- simple 애널라이저 + 영어 불용어(the, over, the 등) 제거"
echo "결과: $(analyze stop "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 5: keyword
# --------------------------------------------------------------
echo ">>> [STEP 5] keyword 애널라이저"
echo "--- 전체 입력을 하나의 토큰으로 처리 (분리 없음)"
echo "--- keyword 필드 타입에서 내부적으로 사용"
echo "결과: $(analyze keyword "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 6: pattern
# --------------------------------------------------------------
echo ">>> [STEP 6] pattern 애널라이저"
echo "--- 정규식 패턴으로 분리. 기본 패턴: \\W+ (비문자)"
echo "결과: $(analyze pattern "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 7: english (언어별 내장 애널라이저)
# --------------------------------------------------------------
echo ">>> [STEP 7] english 애널라이저"
echo "--- 어간 추출(stemming) + 불용어 제거 포함"
echo "--- 'jumps' -> 'jump', 'lazy' -> 'lazi' 관찰"
echo "결과: $(analyze english "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 8: fingerprint (중복 감지용)
# --------------------------------------------------------------
echo ">>> [STEP 8] fingerprint 애널라이저"
echo "--- 소문자 변환 + 정렬 + 중복 제거 + 단일 토큰으로 합치기"
echo "--- 문서 중복 감지에 사용"
echo "결과: $(analyze fingerprint "$SAMPLE_TEXT")"
echo ""

# --------------------------------------------------------------
# STEP 9: 각 애널라이저 검색 동작 차이 비교
# --------------------------------------------------------------
echo ">>> [STEP 9] 실제 검색에서의 차이 비교"
curl -s -X DELETE "$ES_HOST/lab-analyzer-compare" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-analyzer-compare" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "properties": {
        "text_standard":   {"type": "text", "analyzer": "standard"},
        "text_whitespace": {"type": "text", "analyzer": "whitespace"},
        "text_english":    {"type": "text", "analyzer": "english"}
      }
    }
  }' | jq . > /dev/null

curl -s -X POST "$ES_HOST/lab-analyzer-compare/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "text_standard":   "Running Foxes are quick",
    "text_whitespace": "Running Foxes are quick",
    "text_english":    "Running Foxes are quick"
  }' | jq .result

sleep 1

echo "--- 검색어 'running' (소문자)으로 각 필드 검색"
echo "standard 검색 결과 (소문자 변환으로 매칭):"
curl -s -X GET "$ES_HOST/lab-analyzer-compare/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"text_standard": "running"}}}' | jq '.hits.total.value'

echo "whitespace 검색 결과 (Running 그대로 저장, running != Running):"
curl -s -X GET "$ES_HOST/lab-analyzer-compare/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"text_whitespace": "running"}}}' | jq '.hits.total.value'

echo "english 검색 결과 (run으로 stem되어 run으로 검색해도 매칭):"
curl -s -X GET "$ES_HOST/lab-analyzer-compare/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"text_english": "run"}}}' | jq '.hits.total.value'
echo ""

curl -s -X DELETE "$ES_HOST/lab-analyzer-compare" | jq . > /dev/null

echo "============================================================"
echo "  실습 완료"
echo "  다음: 03-custom-analyzer.sh"
echo "============================================================"
