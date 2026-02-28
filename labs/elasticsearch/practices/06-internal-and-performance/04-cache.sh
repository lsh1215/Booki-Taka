#!/bin/bash
# ==============================================================
# 04-cache.sh
# Request Cache, Query Cache 관찰 실습
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  04. 캐시 동작 관찰"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- Request Cache (샤드 쿼리 캐시): size=0 집계 쿼리 결과를 샤드 레벨 캐싱"
echo "--- Query Cache (필터 캐시): filter context 쿼리 결과를 비트셋으로 캐싱"
echo "--- Fielddata Cache: text 필드 집계 시 힙 메모리에 캐싱"
echo "--- 캐시는 인덱스 갱신(refresh) 시 무효화됨"
echo ""

# --------------------------------------------------------------
# STEP 1: 캐시 초기화
# --------------------------------------------------------------
echo ">>> [STEP 1] 캐시 초기화"
curl -s -X POST "$ES_HOST/$INDEX/_cache/clear" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: Request Cache 동작 관찰
# --------------------------------------------------------------
echo ">>> [STEP 2] Request Cache - 집계 쿼리 캐싱"
echo "--- 첫 번째 집계 쿼리 실행 (캐시 미스)"
TIME1=$(date +%s%N)
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{"size": 0, "aggs": {"by_category": {"terms": {"field": "category"}}}}' | jq -r '.took'
TIME2=$(date +%s%N)
echo "--- 첫 번째 took: $(curl -s -X GET "$ES_HOST/$INDEX/_search" -H 'Content-Type: application/json' -d '{"size": 0, "aggs": {"by_category": {"terms": {"field": "category"}}}}' | jq .took)ms"
echo ""

echo "--- 두 번째 동일 쿼리 실행 (캐시 히트 예상 - took 감소)"
echo "--- took: $(curl -s -X GET "$ES_HOST/$INDEX/_search" -H 'Content-Type: application/json' -d '{"size": 0, "aggs": {"by_category": {"terms": {"field": "category"}}}}' | jq .took)ms"
echo ""

echo "--- 캐시 통계 확인 (hit_count 증가)"
curl -s "$ES_HOST/$INDEX/_stats/request_cache" | \
  jq '.indices["'$INDEX'"].primaries.request_cache | {hit_count, miss_count, evictions, memory_size_in_bytes}'
echo ""

# --------------------------------------------------------------
# STEP 3: Request Cache 비활성화
# --------------------------------------------------------------
echo ">>> [STEP 3] Request Cache 비활성화 파라미터"
echo "--- request_cache=false: 이 쿼리만 캐시 비활성화"
curl -s -X GET "$ES_HOST/$INDEX/_search?request_cache=false" \
  -H 'Content-Type: application/json' \
  -d '{"size": 0, "aggs": {"by_category": {"terms": {"field": "category"}}}}' | jq .took
echo ""

# --------------------------------------------------------------
# STEP 4: Query Cache (필터 캐시) 관찰
# --------------------------------------------------------------
echo ">>> [STEP 4] Query Cache - filter context 쿼리 캐싱"
echo "--- filter context에 있는 쿼리는 내부적으로 비트셋으로 캐싱됨"
echo "--- 동일 filter 조건을 여러 쿼리에서 재사용하면 성능 향상"

echo "--- 동일 filter 조건 반복 실행"
for i in $(seq 1 3); do
  TOOK=$(curl -s -X GET "$ES_HOST/$INDEX/_search" \
    -H 'Content-Type: application/json' \
    -d '{
      "query": {
        "bool": {
          "filter": [
            {"term": {"in_stock": true}},
            {"range": {"price": {"gte": 500000}}}
          ]
        }
      },
      "size": 0,
      "aggs": {"count": {"value_count": {"field": "price"}}}
    }' | jq .took)
  echo "--- 실행 $i: took=${TOOK}ms"
done
echo ""

echo "--- query cache 통계"
curl -s "$ES_HOST/_nodes/stats/indices/query_cache" | \
  jq '[.nodes | to_entries[] | {
    node: .value.name,
    hit_count: .value.indices.query_cache.hit_count,
    miss_count: .value.indices.query_cache.miss_count,
    cache_size: .value.indices.query_cache.cache_size,
    memory_kb: (.value.indices.query_cache.memory_size_in_bytes / 1024 | round)
  }]'
echo ""

# --------------------------------------------------------------
# STEP 5: 캐시 무효화 (refresh 후)
# --------------------------------------------------------------
echo ">>> [STEP 5] 캐시 무효화 - 새 문서 색인 후 refresh"
echo "--- 인덱스가 refresh되면 request cache가 무효화됨"
curl -s -X POST "$ES_HOST/$INDEX/_doc" \
  -H 'Content-Type: application/json' \
  -d '{"title": "새 문서 캐시 무효화 테스트", "category": "테스트", "price": 10000, "brand": "Test", "in_stock": true, "rating": 1.0, "tags": ["test"]}' | jq .result

sleep 2

echo "--- refresh 후 캐시 통계 (hit_count 리셋)"
curl -s "$ES_HOST/$INDEX/_stats/request_cache" | \
  jq '.indices["'$INDEX'"].primaries.request_cache | {hit_count, miss_count}'
echo ""

# --------------------------------------------------------------
# STEP 6: 캐시 수동 비우기
# --------------------------------------------------------------
echo ">>> [STEP 6] 캐시 수동 비우기"
echo "--- request cache만 비우기"
curl -s -X POST "$ES_HOST/$INDEX/_cache/clear?request=true" | jq .

echo "--- query cache만 비우기"
curl -s -X POST "$ES_HOST/$INDEX/_cache/clear?query=true" | jq .

echo "--- fielddata cache만 비우기"
curl -s -X POST "$ES_HOST/$INDEX/_cache/clear?fielddata=true" | jq .

echo "--- 전체 캐시 비우기"
curl -s -X POST "$ES_HOST/_cache/clear" | jq .
echo ""

# --------------------------------------------------------------
# STEP 7: 노드별 캐시 메모리 현황
# --------------------------------------------------------------
echo ">>> [STEP 7] 노드별 캐시 메모리 현황"
curl -s "$ES_HOST/_nodes/stats" | \
  jq '[.nodes | to_entries[] | {
    node: .value.name,
    heap_used_mb: (.value.jvm.mem.heap_used_in_bytes / 1048576 | round),
    heap_max_mb: (.value.jvm.mem.heap_max_in_bytes / 1048576 | round),
    heap_percent: .value.jvm.mem.heap_used_percent,
    query_cache_mb: (.value.indices.query_cache.memory_size_in_bytes / 1048576 | round),
    fielddata_mb: (.value.indices.fielddata.memory_size_in_bytes / 1048576 | round),
    request_cache_mb: (.value.indices.request_cache.memory_size_in_bytes / 1048576 | round)
  }]'
echo ""

# --------------------------------------------------------------
# STEP 8: 인덱스별 캐시 사용량
# --------------------------------------------------------------
echo ">>> [STEP 8] 인덱스별 캐시 사용량"
curl -s "$ES_HOST/_stats/request_cache,query_cache,fielddata" | \
  jq '[.indices | to_entries[] | {
    index: .key,
    request_cache_hit: .value.primaries.request_cache.hit_count,
    query_cache_hit: .value.primaries.query_cache.hit_count,
    fielddata_mb: (.value.primaries.fielddata.memory_size_in_bytes / 1048576 | round)
  }] | sort_by(-.request_cache_hit)'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 05-bulk-performance.sh"
echo "============================================================"
