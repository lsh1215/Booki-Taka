#!/bin/bash
# ==============================================================
# 03-force-merge.sh
# Force Merge 실습 - 세그먼트 병합으로 검색 성능 향상
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  03. Force Merge"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- Force Merge: 세그먼트를 강제로 병합 (통합)"
echo "--- 장점: 세그먼트 수 감소 -> 검색 성능 향상, 디스크 공간 회수"
echo "--- 단점: 높은 I/O, CPU 사용률 -> 운영 중 신중하게 사용"
echo "--- 권장: 더 이상 쓰기가 없는 인덱스(로그 아카이브 등)에만 사용"
echo ""

# --------------------------------------------------------------
# STEP 1: 여러 세그먼트를 가진 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 1] 여러 세그먼트를 인위적으로 생성"
curl -s -X DELETE "$ES_HOST/lab-forcemerge" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-forcemerge" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "-1",
      "merge.scheduler.max_thread_count": 1
    }
  }' | jq .acknowledged
echo ""

echo "--- 10번의 개별 색인 + refresh로 10개 세그먼트 생성"
for i in $(seq 1 10); do
  curl -s -X POST "$ES_HOST/lab-forcemerge/_bulk" \
    -H 'Content-Type: application/json' \
    -d "$(for j in $(seq 1 5); do
          echo '{"index": {}}'
          echo "{\"batch\": $i, \"doc\": $j, \"text\": \"segment $i document $j\"}"
        done)" | jq .errors > /dev/null
  curl -s -X POST "$ES_HOST/lab-forcemerge/_refresh" | jq . > /dev/null
done
echo ""

# --------------------------------------------------------------
# STEP 2: Force Merge 전 상태
# --------------------------------------------------------------
echo ">>> [STEP 2] Force Merge 전 세그먼트 상태"
curl -s "$ES_HOST/lab-forcemerge/_segments" | \
  jq '.indices["lab-forcemerge"].shards["0"][0] | {
    num_segments,
    num_docs,
    size_kb: (.size_in_bytes / 1024 | round)
  }'
echo ""

echo "--- _cat/segments로 상세 확인"
curl -s "$ES_HOST/_cat/segments/lab-forcemerge?v&h=segment,generation,docs.count,size,committed,searchable" | head -20
echo ""

# --------------------------------------------------------------
# STEP 3: 일부 문서 삭제 (deleted_docs 생성)
# --------------------------------------------------------------
echo ">>> [STEP 3] 문서 일부 삭제 (deleted_docs 생성)"
echo "--- 삭제된 문서는 디스크 공간을 차지하며, force_merge 후 회수됨"
DOC_IDS=$(curl -s "$ES_HOST/lab-forcemerge/_search?size=5" | jq -r '.hits.hits[]._id')
for id in $DOC_IDS; do
  curl -s -X DELETE "$ES_HOST/lab-forcemerge/_doc/$id" | jq -r '"\(.result): \(._id)"'
done
curl -s -X POST "$ES_HOST/lab-forcemerge/_refresh" | jq . > /dev/null
echo ""

echo "--- 삭제 후 세그먼트 상태 (deleted_docs 있음)"
curl -s "$ES_HOST/lab-forcemerge/_segments" | \
  jq '.indices["lab-forcemerge"].shards["0"][0].segments |
    to_entries | map({segment: .key, num_docs: .value.num_docs, deleted_docs: .value.deleted_docs}) |
    {
      segments: length,
      total_docs: (map(.num_docs) | add),
      total_deleted: (map(.deleted_docs) | add)
    }'
echo ""

# --------------------------------------------------------------
# STEP 4: Force Merge 실행
# --------------------------------------------------------------
echo ">>> [STEP 4] Force Merge 실행 (max_num_segments=1)"
echo "--- wait_for_completion=true: 완료될 때까지 대기"
echo "--- 실습 데이터는 소용량이므로 빠르게 완료됨"
TIME_BEFORE=$SECONDS
curl -s -X POST "$ES_HOST/lab-forcemerge/_forcemerge?max_num_segments=1&only_expunge_deletes=false" | jq .
TIME_AFTER=$SECONDS
echo "--- 소요 시간: $((TIME_AFTER - TIME_BEFORE))초"
echo ""

# --------------------------------------------------------------
# STEP 5: Force Merge 후 상태 비교
# --------------------------------------------------------------
echo ">>> [STEP 5] Force Merge 후 세그먼트 상태 (1개로 통합)"
curl -s "$ES_HOST/lab-forcemerge/_segments" | \
  jq '.indices["lab-forcemerge"].shards["0"][0] | {
    num_segments,
    num_docs,
    size_kb: (.size_in_bytes / 1024 | round)
  }'
echo ""

echo "--- 세그먼트 상세 (1개, deleted_docs=0)"
curl -s "$ES_HOST/_cat/segments/lab-forcemerge?v&h=segment,generation,docs.count,docs.deleted,size,committed,searchable"
echo ""

# --------------------------------------------------------------
# STEP 6: only_expunge_deletes 옵션
# --------------------------------------------------------------
echo ">>> [STEP 6] only_expunge_deletes - 삭제된 문서만 제거 (세그먼트 수 유지)"
echo "--- 세그먼트 수를 줄이지 않고 삭제된 문서만 제거하고 싶을 때 사용"
echo "--- 재색인 후 삭제 마킹 문서 제거에 유용"

curl -s -X DELETE "$ES_HOST/lab-forcemerge2" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-forcemerge2" \
  -H 'Content-Type: application/json' \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0, "refresh_interval": "-1"}}' | jq .acknowledged

for i in $(seq 1 3); do
  curl -s -X POST "$ES_HOST/lab-forcemerge2/_bulk" \
    -H 'Content-Type: application/json' \
    -d "$(for j in $(seq 1 3); do echo '{"index": {}}'; echo "{\"n\": $((i*10+j))}"; done)" | jq .errors > /dev/null
  curl -s -X POST "$ES_HOST/lab-forcemerge2/_refresh" | jq . > /dev/null
done

FIRST_ID=$(curl -s "$ES_HOST/lab-forcemerge2/_search?size=1" | jq -r '.hits.hits[0]._id')
curl -s -X DELETE "$ES_HOST/lab-forcemerge2/_doc/$FIRST_ID" | jq -r '.result'
curl -s -X POST "$ES_HOST/lab-forcemerge2/_refresh" | jq . > /dev/null

echo "--- expunge 전:"
curl -s "$ES_HOST/lab-forcemerge2/_segments" | jq '.indices["lab-forcemerge2"].shards["0"][0] | {num_segments, num_docs}'

curl -s -X POST "$ES_HOST/lab-forcemerge2/_forcemerge?only_expunge_deletes=true" | jq .
echo "--- expunge 후:"
curl -s "$ES_HOST/lab-forcemerge2/_segments" | jq '.indices["lab-forcemerge2"].shards["0"][0] | {num_segments, num_docs}'
echo ""

echo ">>> 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/lab-forcemerge,lab-forcemerge2" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 04-cache.sh"
echo "============================================================"
