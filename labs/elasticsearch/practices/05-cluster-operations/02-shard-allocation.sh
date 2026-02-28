#!/bin/bash
# ==============================================================
# 02-shard-allocation.sh
# 샤드 할당 관찰 실습
# 관찰 포인트: 샤드 라우팅, 수동 이동, 할당 필터링
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  02. 샤드 할당 관찰"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 현재 샤드 배분 현황
# --------------------------------------------------------------
echo ">>> [STEP 1] 현재 샤드 배분 현황"
curl -s "$ES_HOST/_cat/shards?v&h=index,shard,prirep,state,node&s=node,index" | head -40
echo ""

# --------------------------------------------------------------
# STEP 2: replica 수 변경으로 샤드 수 조절
# --------------------------------------------------------------
echo ">>> [STEP 2] replica 수 변경 실습"
curl -s -X DELETE "$ES_HOST/lab-shard-test" | jq . > /dev/null
echo "--- 테스트 인덱스 생성: 2 primary, 0 replica"
curl -s -X PUT "$ES_HOST/lab-shard-test" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 2,
      "number_of_replicas": 0
    }
  }' | jq .acknowledged
echo ""

echo "--- 샤드 배분 확인 (primary만 있음)"
curl -s "$ES_HOST/_cat/shards/lab-shard-test?v&h=shard,prirep,state,node" | column -t
echo ""

echo "--- replica를 1로 변경 -> 3노드 클러스터에서 자동 배분"
curl -s -X PUT "$ES_HOST/lab-shard-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"number_of_replicas": 1}}' | jq .acknowledged

sleep 2
echo "--- replica 추가 후 샤드 배분 확인"
curl -s "$ES_HOST/_cat/shards/lab-shard-test?v&h=shard,prirep,state,node" | column -t
echo ""

# --------------------------------------------------------------
# STEP 3: 샤드 할당 비활성화/활성화
# --------------------------------------------------------------
echo ">>> [STEP 3] 클러스터 전체 샤드 재할당 비활성화"
echo "--- 주의: 운영 환경에서는 노드 재시작 전 사용. 실습 후 반드시 복원"
curl -s -X PUT "$ES_HOST/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "transient": {
      "cluster.routing.allocation.enable": "none"
    }
  }' | jq .acknowledged

echo "--- 샤드 재할당 비활성화 상태"
curl -s "$ES_HOST/_cluster/settings" | jq '.transient'
echo ""

echo "--- 샤드 재할당 다시 활성화"
curl -s -X PUT "$ES_HOST/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "transient": {
      "cluster.routing.allocation.enable": "all"
    }
  }' | jq .acknowledged
echo ""

# --------------------------------------------------------------
# STEP 4: 수동 샤드 이동 (reroute)
# --------------------------------------------------------------
echo ">>> [STEP 4] 수동 샤드 이동 (reroute)"
echo "--- 현재 샤드 배분 확인"
curl -s "$ES_HOST/_cat/shards/lab-shard-test?v&h=shard,prirep,state,node" | column -t
echo ""

# 노드 이름 가져오기
NODE1=$(curl -s "$ES_HOST/_cat/nodes?h=name" | head -1 | tr -d ' \n\r')
NODE2=$(curl -s "$ES_HOST/_cat/nodes?h=name" | sed -n '2p' | tr -d ' \n\r')
echo "--- 노드1: $NODE1, 노드2: $NODE2"

echo "--- 샤드 0번을 $NODE2로 이동 시도"
curl -s -X POST "$ES_HOST/_cluster/reroute" \
  -H 'Content-Type: application/json' \
  -d "{
    \"commands\": [
      {
        \"move\": {
          \"index\": \"lab-shard-test\",
          \"shard\": 0,
          \"from_node\": \"$NODE1\",
          \"to_node\": \"$NODE2\"
        }
      }
    ]
  }" | jq '{acknowledged, state: .state.routing_table.indices["lab-shard-test"] | .shards | with_entries(select(.key == "0")) | .["0"] | [.[] | {node, state, primary}]}' 2>/dev/null || echo "--- reroute 시도 (노드 배분에 따라 결과 다를 수 있음)"
echo ""

# --------------------------------------------------------------
# STEP 5: 인덱스별 샤드 할당 필터 (exclude 특정 노드)
# --------------------------------------------------------------
echo ">>> [STEP 5] 인덱스별 샤드 할당 필터"
echo "--- 특정 인덱스의 샤드를 특정 노드로만 할당 제한"
curl -s -X PUT "$ES_HOST/lab-shard-test/_settings" \
  -H 'Content-Type: application/json' \
  -d "{
    \"index.routing.allocation.include._name\": \"$NODE1,$NODE2\"
  }" | jq .acknowledged

echo "--- 할당 제한 해제"
curl -s -X PUT "$ES_HOST/lab-shard-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index.routing.allocation.include._name": null
  }' | jq .acknowledged
echo ""

# --------------------------------------------------------------
# STEP 6: 클러스터 레벨 샤드 할당 설정
# --------------------------------------------------------------
echo ">>> [STEP 6] 클러스터 레벨 샤드 수 제한"
echo "--- 노드당 최대 샤드 수 확인 (기본값: 1000)"
curl -s "$ES_HOST/_cluster/settings?include_defaults=true" | \
  jq '.defaults["cluster.max_shards_per_node"]'
echo ""

echo "--- disk watermark 설정 확인"
echo "--- low: 85%(기본), high: 90%, flood_stage: 95%"
curl -s "$ES_HOST/_cluster/settings?include_defaults=true" | \
  jq '.defaults | {
    low: .["cluster.routing.allocation.disk.watermark.low"],
    high: .["cluster.routing.allocation.disk.watermark.high"],
    flood: .["cluster.routing.allocation.disk.watermark.flood_stage"]
  }'
echo ""

# --------------------------------------------------------------
# STEP 7: 정리
# --------------------------------------------------------------
echo ">>> [STEP 7] 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/lab-shard-test" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 03-index-template.sh"
echo "============================================================"
