#!/bin/bash
# ==============================================================
# 01-create-index.sh
# 인덱스 생성 및 설정 실습
# 관찰 포인트: number_of_shards, number_of_replicas, refresh_interval
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  01. 인덱스 생성 및 설정 실습"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제 (재실행 가능하도록)
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제 (존재하지 않으면 에러 무시)"
echo "--- 이전 실습 데이터를 초기화한다."
curl -s -X DELETE "$ES_HOST/lab-index-basic" | jq .
curl -s -X DELETE "$ES_HOST/lab-index-custom" | jq .
curl -s -X DELETE "$ES_HOST/lab-index-norefresh" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 기본 설정으로 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] 기본 설정 인덱스 생성"
echo "--- number_of_shards=1, number_of_replicas=1 (기본값)"
echo "--- 3노드 클러스터에서는 replica가 다른 노드에 배치되어 green 상태가 된다."
curl -s -X PUT "$ES_HOST/lab-index-basic" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 커스텀 설정으로 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 3] 커스텀 설정 인덱스 생성"
echo "--- primary shard 3개, replica 1개 -> 총 6개 샤드"
echo "--- refresh_interval: 30s -> 색인 후 30초 뒤에 검색 가능"
curl -s -X PUT "$ES_HOST/lab-index-custom" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "refresh_interval": "30s",
      "index": {
        "max_result_window": 50000
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 4: refresh 비활성화 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 4] refresh_interval=-1 인덱스 생성"
echo "--- -1로 설정하면 자동 refresh가 비활성화된다."
echo "--- 대량 색인 시 성능을 높이기 위해 사용한다."
curl -s -X PUT "$ES_HOST/lab-index-norefresh" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "-1"
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 5: 인덱스 목록 확인
# --------------------------------------------------------------
echo ">>> [STEP 5] 생성된 인덱스 목록 확인"
echo "--- health: green=정상, yellow=replica 미배치, red=데이터 손실"
echo "--- pri=primary shard 수, rep=replica shard 수"
curl -s "$ES_HOST/_cat/indices/lab-index-*?v&h=health,status,index,pri,rep,docs.count,store.size" | column -t
echo ""

# --------------------------------------------------------------
# STEP 6: 특정 인덱스 설정 조회
# --------------------------------------------------------------
echo ">>> [STEP 6] lab-index-custom 설정 상세 조회"
echo "--- 생성할 때 지정한 설정값이 저장되었는지 확인한다."
curl -s "$ES_HOST/lab-index-custom/_settings" | jq .
echo ""

# --------------------------------------------------------------
# STEP 7: 실시간으로 설정 변경 (dynamic settings)
# --------------------------------------------------------------
echo ">>> [STEP 7] 실시간 설정 변경 - refresh_interval 조정"
echo "--- refresh_interval, number_of_replicas는 인덱스 운영 중에도 변경 가능하다."
echo "--- (number_of_shards는 생성 후 변경 불가 - static setting)"
curl -s -X PUT "$ES_HOST/lab-index-norefresh/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": {
      "refresh_interval": "1s",
      "number_of_replicas": 1
    }
  }' | jq .
echo ""

echo ">>> 변경 후 설정 확인"
curl -s "$ES_HOST/lab-index-norefresh/_settings" | jq '.["lab-index-norefresh"].settings.index | {refresh_interval, number_of_replicas}'
echo ""

# --------------------------------------------------------------
# STEP 8: 인덱스 open/close
# --------------------------------------------------------------
echo ">>> [STEP 8] 인덱스 close/open 실습"
echo "--- close된 인덱스는 읽기/쓰기가 불가하지만 디스크에는 존재한다."
echo "--- 설정 변경 등 관리 작업을 위해 사용된다."
curl -s -X POST "$ES_HOST/lab-index-basic/_close" | jq .
sleep 1
echo "--- close 후 상태 확인 (status=close)"
curl -s "$ES_HOST/_cat/indices/lab-index-basic?v&h=health,status,index" | column -t
echo ""

curl -s -X POST "$ES_HOST/lab-index-basic/_open" | jq .
sleep 1
echo "--- open 후 상태 확인 (status=open)"
curl -s "$ES_HOST/_cat/indices/lab-index-basic?v&h=health,status,index" | column -t
echo ""

# --------------------------------------------------------------
# STEP 9: 클러스터 레벨 샤드 배분 확인
# --------------------------------------------------------------
echo ">>> [STEP 9] 샤드 배분 현황 확인"
echo "--- 각 샤드가 어느 노드에 배치되어 있는지 확인한다."
echo "--- p=primary, r=replica"
curl -s "$ES_HOST/_cat/shards/lab-index-*?v&h=index,shard,prirep,state,node" | column -t
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 02-explicit-mapping.sh"
echo "============================================================"
