#!/bin/bash
# ==============================================================
# 01-cluster-health.sh
# 클러스터 상태 확인 (_cluster/health, _cat APIs)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  01. 클러스터 상태 확인"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 클러스터 헬스 개요
# --------------------------------------------------------------
echo ">>> [STEP 1] 클러스터 헬스 개요"
echo "--- green: 모든 샤드 정상"
echo "--- yellow: primary 정상, 일부 replica 미배치"
echo "--- red: 일부 primary 샤드 미배치 (데이터 일부 조회 불가)"
curl -s "$ES_HOST/_cluster/health" | jq '{
  cluster_name,
  status,
  number_of_nodes,
  number_of_data_nodes,
  active_primary_shards,
  active_shards,
  relocating_shards,
  initializing_shards,
  unassigned_shards,
  pending_tasks,
  active_shards_percent_as_number
}'
echo ""

# --------------------------------------------------------------
# STEP 2: 특정 인덱스의 헬스만 조회
# --------------------------------------------------------------
echo ">>> [STEP 2] 특정 인덱스 헬스 조회"
curl -s "$ES_HOST/_cluster/health/products,orders?level=indices" | jq '{status, indices}'
echo ""

# --------------------------------------------------------------
# STEP 3: _cat/health - 간결한 클러스터 상태
# --------------------------------------------------------------
echo ">>> [STEP 3] _cat/health - 간결한 형식"
curl -s "$ES_HOST/_cat/health?v"
echo ""

# --------------------------------------------------------------
# STEP 4: _cat/nodes - 노드 정보
# --------------------------------------------------------------
echo ">>> [STEP 4] _cat/nodes - 노드 목록과 역할"
curl -s "$ES_HOST/_cat/nodes?v&h=name,ip,node.role,master,heap.percent,ram.percent,cpu,load_1m,disk.avail" | column -t
echo ""

echo "--- 노드 상세 통계"
curl -s "$ES_HOST/_nodes/stats" | jq '[.nodes | to_entries[] | {
  name: .value.name,
  heap_used_mb: (.value.jvm.mem.heap_used_in_bytes / 1048576 | round),
  heap_max_mb: (.value.jvm.mem.heap_max_in_bytes / 1048576 | round),
  index_count: .value.indices.docs.count
}]'
echo ""

# --------------------------------------------------------------
# STEP 5: _cat/indices - 인덱스 목록
# --------------------------------------------------------------
echo ">>> [STEP 5] _cat/indices - 인덱스 목록"
curl -s "$ES_HOST/_cat/indices?v&h=health,status,index,pri,rep,docs.count,docs.deleted,store.size,pri.store.size&s=store.size:desc" | column -t
echo ""

# --------------------------------------------------------------
# STEP 6: _cat/shards - 샤드 배분 현황
# --------------------------------------------------------------
echo ">>> [STEP 6] _cat/shards - 샤드 배분 현황"
echo "--- p=primary, r=replica | STARTED=정상, UNASSIGNED=미배치"
curl -s "$ES_HOST/_cat/shards?v&h=index,shard,prirep,state,docs,store,node&s=index" | head -30
echo ""

# --------------------------------------------------------------
# STEP 7: unassigned 샤드 원인 파악
# --------------------------------------------------------------
echo ">>> [STEP 7] UNASSIGNED 샤드가 있을 경우 원인 파악"
UNASSIGNED=$(curl -s "$ES_HOST/_cat/shards?h=index,shard,prirep,state" | grep UNASSIGNED | head -1)
if [ -n "$UNASSIGNED" ]; then
  INDEX_NAME=$(echo "$UNASSIGNED" | awk '{print $1}')
  SHARD_NUM=$(echo "$UNASSIGNED" | awk '{print $2}')
  echo "--- 미배치 샤드 발견: $INDEX_NAME 샤드 $SHARD_NUM"
  curl -s "$ES_HOST/_cluster/allocation/explain" \
    -H 'Content-Type: application/json' \
    -d "{\"index\": \"$INDEX_NAME\", \"shard\": $SHARD_NUM, \"primary\": false}" | jq '.explanation'
else
  echo "--- 현재 UNASSIGNED 샤드 없음 (클러스터 정상)"
fi
echo ""

# --------------------------------------------------------------
# STEP 8: 클러스터 설정 확인
# --------------------------------------------------------------
echo ">>> [STEP 8] 클러스터 설정 확인"
echo "--- persistent: 영구 설정, transient: 임시 설정"
curl -s "$ES_HOST/_cluster/settings" | jq .
echo ""

# --------------------------------------------------------------
# STEP 9: 노드별 디스크 사용량
# --------------------------------------------------------------
echo ">>> [STEP 9] 디스크 사용량 확인"
curl -s "$ES_HOST/_cat/allocation?v&h=node,shards,disk.indices,disk.used,disk.avail,disk.total,disk.percent" | column -t
echo ""

# --------------------------------------------------------------
# STEP 10: _cat/pending_tasks - 대기 중인 작업
# --------------------------------------------------------------
echo ">>> [STEP 10] 대기 중인 클러스터 작업 확인"
curl -s "$ES_HOST/_cat/pending_tasks?v" | head -20
echo ""

# --------------------------------------------------------------
# STEP 11: 클러스터 통계
# --------------------------------------------------------------
echo ">>> [STEP 11] 클러스터 전체 통계"
curl -s "$ES_HOST/_cluster/stats" | jq '{
  status: .status,
  total_nodes: .nodes.count.total,
  data_nodes: .nodes.count.data,
  total_indices: .indices.count,
  total_docs: .indices.docs.count,
  total_store_gb: (.indices.store.size_in_bytes / 1073741824 | . * 100 | round / 100)
}'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 02-shard-allocation.sh"
echo "============================================================"
