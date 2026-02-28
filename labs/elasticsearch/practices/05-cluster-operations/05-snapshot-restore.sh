#!/bin/bash
# ==============================================================
# 05-snapshot-restore.sh
# 스냅샷 백업/복구 실습
# 사전 조건: docker-compose.yml에 path.repo 설정 필요
#
# docker-compose.yml 환경변수에 추가:
#   - path.repo=/usr/share/elasticsearch/snapshots
# volumes에 추가:
#   - es-snapshots:/usr/share/elasticsearch/snapshots
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
REPO_NAME="lab-backup"

echo "============================================================"
echo "  05. 스냅샷 백업/복구"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [사전 조건]"
echo "--- docker-compose.yml의 ES 서비스에 path.repo 설정이 필요합니다."
echo "--- 설정이 없으면 repository 등록 단계에서 에러가 발생합니다."
echo ""

# --------------------------------------------------------------
# STEP 1: 스냅샷 저장소 등록
# --------------------------------------------------------------
echo ">>> [STEP 1] 스냅샷 저장소 등록 (로컬 파일시스템)"
curl -s -X PUT "$ES_HOST/_snapshot/$REPO_NAME" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "fs",
    "settings": {
      "location": "/usr/share/elasticsearch/snapshots",
      "compress": true,
      "max_restore_bytes_per_sec": "40mb",
      "max_snapshot_bytes_per_sec": "40mb"
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 저장소 검증
# --------------------------------------------------------------
echo ">>> [STEP 2] 저장소 검증"
curl -s -X POST "$ES_HOST/_snapshot/$REPO_NAME/_verify" | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 실습용 인덱스 생성 및 데이터 색인
# --------------------------------------------------------------
echo ">>> [STEP 3] 백업할 인덱스 생성 및 데이터 색인"
curl -s -X DELETE "$ES_HOST/snapshot-test-*" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/snapshot-test-products" \
  -H 'Content-Type: application/json' \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}' | jq .acknowledged

curl -s -X POST "$ES_HOST/snapshot-test-products/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"name": "갤럭시 S24", "price": 1599000}
{"index": {"_id": "2"}}
{"name": "아이폰 15 Pro", "price": 1550000}
{"index": {"_id": "3"}}
{"name": "맥북 프로 M3", "price": 2990000}
' | jq .errors
sleep 1

curl -s "$ES_HOST/snapshot-test-products/_count" | jq '{index: "snapshot-test-products", docs: .count}'
echo ""

# --------------------------------------------------------------
# STEP 4: 스냅샷 생성
# --------------------------------------------------------------
echo ">>> [STEP 4] 스냅샷 생성"
SNAPSHOT_NAME="snap-$(date +%Y%m%d-%H%M%S)"
echo "--- 스냅샷 이름: $SNAPSHOT_NAME"

curl -s -X PUT "$ES_HOST/_snapshot/$REPO_NAME/$SNAPSHOT_NAME?wait_for_completion=true" \
  -H 'Content-Type: application/json' \
  -d '{
    "indices": "snapshot-test-*",
    "ignore_unavailable": true,
    "include_global_state": false,
    "metadata": {
      "taken_by": "lab-user",
      "taken_because": "실습 목적 스냅샷"
    }
  }' | jq '.snapshot | {snapshot: .snapshot, state: .state, start_time: .start_time, end_time: .end_time, indices: .indices}'
echo ""

# --------------------------------------------------------------
# STEP 5: 스냅샷 목록 조회
# --------------------------------------------------------------
echo ">>> [STEP 5] 스냅샷 목록 조회"
curl -s "$ES_HOST/_snapshot/$REPO_NAME/_all" | jq '[.snapshots[] | {snapshot: .snapshot, state: .state, indices: .indices}]'
echo ""

# --------------------------------------------------------------
# STEP 6: 스냅샷 상세 정보
# --------------------------------------------------------------
echo ">>> [STEP 6] 스냅샷 상세 정보"
curl -s "$ES_HOST/_snapshot/$REPO_NAME/$SNAPSHOT_NAME" | jq '.snapshots[0] | {snapshot, state, start_time, end_time, shards: .shards}'
echo ""

# --------------------------------------------------------------
# STEP 7: 인덱스 삭제 후 복구 (재해 복구 시나리오)
# --------------------------------------------------------------
echo ">>> [STEP 7] 재해 복구 시나리오 - 인덱스 삭제 후 복구"
echo "--- 인덱스 삭제 (장애 시뮬레이션)"
curl -s -X DELETE "$ES_HOST/snapshot-test-products" | jq .acknowledged
sleep 1

echo "--- 삭제 확인 (존재하지 않아야 함)"
curl -s "$ES_HOST/snapshot-test-products/_count" | jq '.error.type // "not found"'
echo ""

echo "--- 스냅샷에서 복구"
curl -s -X POST "$ES_HOST/_snapshot/$REPO_NAME/$SNAPSHOT_NAME/_restore?wait_for_completion=true" \
  -H 'Content-Type: application/json' \
  -d '{
    "indices": "snapshot-test-products",
    "ignore_unavailable": true,
    "include_global_state": false
  }' | jq '.snapshot | {snapshot: .snapshot, indices: .indices, shards: .shards}'
echo ""

sleep 2
echo "--- 복구된 데이터 확인"
curl -s "$ES_HOST/snapshot-test-products/_count" | jq '{복구완료: true, docs: .count}'
curl -s "$ES_HOST/snapshot-test-products/_search?size=5" | jq '[.hits.hits[]._source]'
echo ""

# --------------------------------------------------------------
# STEP 8: 다른 이름으로 복구 (rename)
# --------------------------------------------------------------
echo ">>> [STEP 8] 다른 이름으로 복구 (rename 옵션)"
echo "--- snapshot-test-products -> snapshot-test-products-restored"
curl -s -X DELETE "$ES_HOST/snapshot-test-products-restored" | jq . > /dev/null
curl -s -X POST "$ES_HOST/_snapshot/$REPO_NAME/$SNAPSHOT_NAME/_restore?wait_for_completion=true" \
  -H 'Content-Type: application/json' \
  -d '{
    "indices": "snapshot-test-products",
    "rename_pattern": "(.+)",
    "rename_replacement": "$1-restored",
    "include_global_state": false
  }' | jq '.snapshot.indices'
sleep 2

echo "--- 복구된 인덱스 확인"
curl -s "$ES_HOST/_cat/indices/snapshot-test-*?v&h=index,docs.count" | column -t
echo ""

# --------------------------------------------------------------
# STEP 9: 스냅샷 상태 모니터링
# --------------------------------------------------------------
echo ">>> [STEP 9] 진행 중인 스냅샷 상태 확인"
curl -s "$ES_HOST/_snapshot/status" | jq '.snapshots | if length == 0 then "현재 진행 중인 스냅샷 없음" else . end'
echo ""

# --------------------------------------------------------------
# STEP 10: 정리
# --------------------------------------------------------------
echo ">>> [STEP 10] 실습 데이터 및 스냅샷 정리"
curl -s -X DELETE "$ES_HOST/snapshot-test-products" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/snapshot-test-products-restored" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/_snapshot/$REPO_NAME/$SNAPSHOT_NAME" | jq .
curl -s -X DELETE "$ES_HOST/_snapshot/$REPO_NAME" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 06-reindex.sh"
echo "============================================================"
