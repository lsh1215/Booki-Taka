#!/bin/bash
# ==============================================================
# 01-segments.sh
# 세그먼트 관찰 실습 (_segments API)
# 관찰 포인트: 세그먼트 수, 크기, 삭제된 문서
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  01. 세그먼트 관찰"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 세그먼트: Lucene의 불변(immutable) 역색인 단위"
echo "--- refresh 시 메모리 버퍼 -> 새 세그먼트 생성"
echo "--- 세그먼트는 병합(merge)되기 전까지 계속 누적됨"
echo "--- 삭제된 문서는 삭제 마킹만 되고 실제 제거는 merge 시 발생"
echo ""

# --------------------------------------------------------------
# STEP 1: 실습 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 1] 실습 인덱스 생성 (refresh_interval=-1로 수동 제어)"
curl -s -X DELETE "$ES_HOST/lab-segments" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-segments" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "-1"
    }
  }' | jq .acknowledged
echo ""

# --------------------------------------------------------------
# STEP 2: 초기 세그먼트 상태
# --------------------------------------------------------------
echo ">>> [STEP 2] 초기 세그먼트 상태 (문서 없음)"
curl -s "$ES_HOST/lab-segments/_segments" | jq '.indices["lab-segments"].shards["0"][0] | {num_segments: .num_segments, num_docs: .num_docs}'
echo ""

# --------------------------------------------------------------
# STEP 3: 문서 색인 후 refresh -> 세그먼트 생성
# --------------------------------------------------------------
echo ">>> [STEP 3] 문서 5건 색인 후 수동 refresh -> 세그먼트 1개 생성"
for i in $(seq 1 5); do
  curl -s -X POST "$ES_HOST/lab-segments/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"id\": $i, \"text\": \"document $i\"}" | jq -r '.result'
done

curl -s -X POST "$ES_HOST/lab-segments/_refresh" | jq .
echo "--- refresh 후 세그먼트 수:"
curl -s "$ES_HOST/lab-segments/_segments" | jq '.indices["lab-segments"].shards["0"][0].num_segments'
echo ""

echo ">>> 추가 문서 5건 색인 후 두 번째 refresh -> 세그먼트 2개"
for i in $(seq 6 10); do
  curl -s -X POST "$ES_HOST/lab-segments/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"id\": $i, \"text\": \"document $i\"}" | jq -r '.result'
done

curl -s -X POST "$ES_HOST/lab-segments/_refresh" | jq .
echo "--- 두 번째 refresh 후 세그먼트 수:"
curl -s "$ES_HOST/lab-segments/_segments" | jq '.indices["lab-segments"].shards["0"][0].num_segments'
echo ""

echo ">>> 세 번째 refresh (5건 + 2개 세그먼트 추가)"
for i in $(seq 11 15); do
  curl -s -X POST "$ES_HOST/lab-segments/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"id\": $i, \"text\": \"document $i\"}" | jq -r '.result'
done
curl -s -X POST "$ES_HOST/lab-segments/_refresh" | jq .
echo "--- 세 번째 refresh 후 세그먼트 수:"
curl -s "$ES_HOST/lab-segments/_segments" | jq '.indices["lab-segments"].shards["0"][0].num_segments'
echo ""

# --------------------------------------------------------------
# STEP 4: 세그먼트 상세 정보
# --------------------------------------------------------------
echo ">>> [STEP 4] 세그먼트 상세 정보 확인"
curl -s "$ES_HOST/lab-segments/_segments" | \
  jq '.indices["lab-segments"].shards["0"][0].segments | to_entries[] | {
    segment: .key,
    generation: .value.generation,
    num_docs: .value.num_docs,
    deleted_docs: .value.deleted_docs,
    size_kb: (.value.size_in_bytes / 1024 | round),
    committed: .value.committed,
    search: .value.search
  }'
echo ""

# --------------------------------------------------------------
# STEP 5: 문서 삭제 - 세그먼트에서 삭제 마킹 관찰
# --------------------------------------------------------------
echo ">>> [STEP 5] 문서 삭제 후 deleted_docs 증가 관찰"
echo "--- 색인된 문서 ID 목록 가져오기"
curl -s "$ES_HOST/lab-segments/_search?size=3" | jq -r '.hits.hits[]._id' | while read id; do
  curl -s -X DELETE "$ES_HOST/lab-segments/_doc/$id" | jq -r '"삭제: \(._id) - \(.result)"'
done

curl -s -X POST "$ES_HOST/lab-segments/_refresh" | jq . > /dev/null
echo "--- 삭제 후 세그먼트 상태 (deleted_docs 증가 확인)"
curl -s "$ES_HOST/lab-segments/_segments" | \
  jq '.indices["lab-segments"].shards["0"][0].segments | to_entries[] | {
    segment: .key,
    num_docs: .value.num_docs,
    deleted_docs: .value.deleted_docs
  }'
echo ""

# --------------------------------------------------------------
# STEP 6: _cat/segments로 요약 확인
# --------------------------------------------------------------
echo ">>> [STEP 6] _cat/segments로 간결한 세그먼트 요약"
curl -s "$ES_HOST/_cat/segments/lab-segments?v&h=index,shard,prirep,segment,generation,docs.count,docs.deleted,size,committed,searchable"
echo ""

# --------------------------------------------------------------
# STEP 7: 기존 인덱스의 세그먼트 비교
# --------------------------------------------------------------
echo ">>> [STEP 7] 운영 인덱스 세그먼트 현황 비교"
echo "--- products, orders 인덱스의 세그먼트 수"
for idx in products orders; do
  if curl -s "$ES_HOST/$idx" | jq -e '.error' > /dev/null 2>&1; then
    echo "--- $idx: 인덱스 없음"
  else
    SEGS=$(curl -s "$ES_HOST/$idx/_segments" | jq "[.indices[\"$idx\"].shards | to_entries[] | .value[0].num_segments] | add // 0")
    DOCS=$(curl -s "$ES_HOST/$idx/_count" | jq .count)
    echo "--- $idx: 세그먼트 $SEGS개, 문서 $DOCS건"
  fi
done
echo ""

echo ">>> 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/lab-segments" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 02-refresh-flush.sh"
echo "============================================================"
