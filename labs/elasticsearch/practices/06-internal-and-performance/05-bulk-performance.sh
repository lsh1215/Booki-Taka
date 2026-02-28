#!/bin/bash
# ==============================================================
# 05-bulk-performance.sh
# Bulk API 성능 테스트
# 관찰 포인트: 배치 크기별 성능, refresh/replica 설정 영향
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  05. Bulk API 성능 테스트"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- Bulk API: 단일 요청에 여러 색인/삭제/업데이트 작업을 묶어서 전송"
echo "--- 단건 요청보다 네트워크 오버헤드 대폭 감소"
echo "--- 적절한 배치 크기: 5MB~15MB 또는 1000~5000건"
echo ""

# --------------------------------------------------------------
# 유틸리티 함수
# --------------------------------------------------------------

# N건의 JSON 문서 bulk 데이터 생성
generate_bulk_data() {
  local count=$1
  local batch_num=$2
  for i in $(seq 1 $count); do
    echo '{"index": {}}'
    echo "{\"batch\": $batch_num, \"doc\": $i, \"title\": \"상품 $batch_num-$i\", \"price\": $((RANDOM % 1000000 + 10000)), \"category\": \"테스트\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  done
}

# 시간 측정 + 색인 함수
bulk_index_timed() {
  local index="$1"
  local data="$2"
  local start=$(date +%s%3N)
  curl -s -X POST "$ES_HOST/$index/_bulk" \
    -H 'Content-Type: application/json' \
    -d "$data" | jq -r 'if .errors then "errors: \(.items | map(select(.index.error != null)) | length)" else "ok" end'
  local end=$(date +%s%3N)
  echo $((end - start))
}

# --------------------------------------------------------------
# STEP 1: 단건 vs 벌크 비교
# --------------------------------------------------------------
echo ">>> [STEP 1] 단건 색인 vs 벌크 색인 비교 (100건)"
curl -s -X DELETE "$ES_HOST/lab-perf-single" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-perf-single" \
  -H 'Content-Type: application/json' \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0, "refresh_interval": "1s"}}' | jq .acknowledged

echo "--- 단건 색인 100건 시작..."
START=$(date +%s%3N)
for i in $(seq 1 100); do
  curl -s -X POST "$ES_HOST/lab-perf-single/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"id\": $i, \"text\": \"document $i\"}" > /dev/null
done
END=$(date +%s%3N)
SINGLE_TIME=$((END - START))
echo "--- 단건 색인 100건 소요 시간: ${SINGLE_TIME}ms"
echo ""

curl -s -X DELETE "$ES_HOST/lab-perf-bulk" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-perf-bulk" \
  -H 'Content-Type: application/json' \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0, "refresh_interval": "1s"}}' | jq .acknowledged

echo "--- 벌크 색인 100건 (1 배치)..."
BULK_DATA=$(generate_bulk_data 100 1)
START=$(date +%s%3N)
curl -s -X POST "$ES_HOST/lab-perf-bulk/_bulk" \
  -H 'Content-Type: application/json' \
  -d "$BULK_DATA" | jq .errors
END=$(date +%s%3N)
BULK_TIME=$((END - START))
echo "--- 벌크 색인 100건 소요 시간: ${BULK_TIME}ms"
echo ""

echo "--- 성능 차이 배율: $(echo "scale=1; $SINGLE_TIME / $BULK_TIME" | bc)x"
echo ""

# --------------------------------------------------------------
# STEP 2: 배치 크기별 성능 비교
# --------------------------------------------------------------
echo ">>> [STEP 2] 배치 크기별 성능 비교 (총 1000건)"
echo "--- 배치 크기: 10, 50, 100, 500, 1000건"

for BATCH_SIZE in 10 50 100 500 1000; do
  INDEX_NAME="lab-perf-batch-$BATCH_SIZE"
  curl -s -X DELETE "$ES_HOST/$INDEX_NAME" | jq . > /dev/null
  curl -s -X PUT "$ES_HOST/$INDEX_NAME" \
    -H 'Content-Type: application/json' \
    -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0, "refresh_interval": "-1"}}' | jq .acknowledged > /dev/null

  ITERATIONS=$((1000 / BATCH_SIZE))
  START=$(date +%s%3N)
  for batch in $(seq 1 $ITERATIONS); do
    BULK_DATA=$(generate_bulk_data $BATCH_SIZE $batch)
    curl -s -X POST "$ES_HOST/$INDEX_NAME/_bulk" \
      -H 'Content-Type: application/json' \
      -d "$BULK_DATA" | jq .errors > /dev/null
  done
  END=$(date +%s%3N)
  ELAPSED=$((END - START))
  DOCS=$(curl -s -X POST "$ES_HOST/$INDEX_NAME/_refresh" && sleep 0.5 && curl -s "$ES_HOST/$INDEX_NAME/_count" | jq .count)
  echo "--- 배치크기 $BATCH_SIZE건 | $ITERATIONS회 전송 | 총 ${ELAPSED}ms | 문서수 $DOCS"

  curl -s -X DELETE "$ES_HOST/$INDEX_NAME" | jq . > /dev/null
done
echo ""

# --------------------------------------------------------------
# STEP 3: refresh_interval이 색인 성능에 미치는 영향
# --------------------------------------------------------------
echo ">>> [STEP 3] refresh_interval 설정별 색인 성능 비교 (500건)"
BULK_DATA=$(generate_bulk_data 500 1)

for INTERVAL in "1s" "10s" "-1"; do
  INDEX_NAME="lab-perf-refresh"
  curl -s -X DELETE "$ES_HOST/$INDEX_NAME" | jq . > /dev/null
  curl -s -X PUT "$ES_HOST/$INDEX_NAME" \
    -H 'Content-Type: application/json' \
    -d "{\"settings\": {\"number_of_shards\": 1, \"number_of_replicas\": 0, \"refresh_interval\": \"$INTERVAL\"}}" | jq .acknowledged > /dev/null

  START=$(date +%s%3N)
  curl -s -X POST "$ES_HOST/$INDEX_NAME/_bulk" \
    -H 'Content-Type: application/json' \
    -d "$BULK_DATA" | jq .errors > /dev/null
  END=$(date +%s%3N)
  echo "--- refresh_interval=$INTERVAL: $((END - START))ms"

  curl -s -X DELETE "$ES_HOST/$INDEX_NAME" | jq . > /dev/null
done
echo ""

# --------------------------------------------------------------
# STEP 4: replica 수가 색인 성능에 미치는 영향
# --------------------------------------------------------------
echo ">>> [STEP 4] replica 수별 색인 성능 비교 (500건)"
BULK_DATA=$(generate_bulk_data 500 1)

for REPLICAS in 0 1; do
  INDEX_NAME="lab-perf-replica"
  curl -s -X DELETE "$ES_HOST/$INDEX_NAME" | jq . > /dev/null
  curl -s -X PUT "$ES_HOST/$INDEX_NAME" \
    -H 'Content-Type: application/json' \
    -d "{\"settings\": {\"number_of_shards\": 1, \"number_of_replicas\": $REPLICAS, \"refresh_interval\": \"-1\"}}" | jq .acknowledged > /dev/null

  sleep 1
  START=$(date +%s%3N)
  curl -s -X POST "$ES_HOST/$INDEX_NAME/_bulk" \
    -H 'Content-Type: application/json' \
    -d "$BULK_DATA" | jq .errors > /dev/null
  END=$(date +%s%3N)
  echo "--- replicas=$REPLICAS: $((END - START))ms"

  curl -s -X DELETE "$ES_HOST/$INDEX_NAME" | jq . > /dev/null
done
echo ""

# --------------------------------------------------------------
# STEP 5: Bulk API 에러 처리
# --------------------------------------------------------------
echo ">>> [STEP 5] Bulk API 에러 처리 관찰"
curl -s -X DELETE "$ES_HOST/lab-bulk-error" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-bulk-error" \
  -H 'Content-Type: application/json' \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0},
       "mappings": {"properties": {"price": {"type": "integer"}}}}' | jq .acknowledged

echo "--- 올바른 문서 + 잘못된 문서 혼합 bulk 요청"
curl -s -X POST "$ES_HOST/lab-bulk-error/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"price": 1000}
{"index": {"_id": "2"}}
{"price": "not_a_number"}
{"index": {"_id": "3"}}
{"price": 3000}
' | jq '{
  errors,
  results: [.items[] | {
    id: .index._id,
    result: (.index.result // "error"),
    error: .index.error.reason
  }]
}'
echo ""

sleep 1
echo "--- 에러가 있어도 정상 문서는 색인됨: $(curl -s "$ES_HOST/lab-bulk-error/_count" | jq .count)건"
echo ""

# --------------------------------------------------------------
# STEP 6: 최적 대량 색인 패턴 요약
# --------------------------------------------------------------
echo ">>> [STEP 6] 최적 대량 색인 설정 패턴 요약"
echo ""
echo "1. 색인 전 설정:"
echo "   - refresh_interval: -1 (자동 refresh 비활성화)"
echo "   - number_of_replicas: 0 (임시 replica 제거)"
echo "   - translog.durability: async"
echo ""
echo "2. 색인 중:"
echo "   - 배치 크기: 5~15MB 또는 500~2000건"
echo "   - 적절한 병렬 처리 (노드당 1~2 스레드)"
echo ""
echo "3. 색인 후:"
echo "   - refresh_interval 복원 (1s)"
echo "   - number_of_replicas 복원"
echo "   - _refresh 한번 실행"
echo "   - 필요시 force_merge"
echo ""

echo ">>> 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/lab-perf-single,lab-perf-bulk,lab-bulk-error" | jq . 2>/dev/null | jq .acknowledged
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  06-internal-and-performance 실습 전체 완료!"
echo "  모든 Elasticsearch 실습 완료!"
echo "============================================================"
