#!/bin/bash
# ==============================================================
# 02-refresh-flush.sh
# refresh와 flush 동작 관찰 실습
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  02. Refresh & Flush 동작 관찰"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- refresh: 메모리 버퍼 -> 세그먼트 (검색 가능 상태)"
echo "--- flush: 세그먼트를 디스크에 영구 기록 + translog 비우기"
echo "--- translog: 색인 요청을 즉시 기록하는 WAL (Write-Ahead Log)"
echo "--- 기본 refresh_interval: 1s (1초마다 자동 refresh)"
echo ""

# --------------------------------------------------------------
# STEP 1: refresh_interval 비활성화 인덱스
# --------------------------------------------------------------
echo ">>> [STEP 1] refresh_interval=-1 인덱스 생성"
curl -s -X DELETE "$ES_HOST/lab-refresh-test" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-refresh-test" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "-1"
    }
  }' | jq .acknowledged
echo ""

echo ">>> 문서 색인 후 즉시 검색 (refresh 전 - 0건 예상)"
curl -s -X POST "$ES_HOST/lab-refresh-test/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{"text": "refresh 실험용 문서"}' | jq .result

echo "--- refresh 없이 즉시 검색 결과 (0건):"
curl -s "$ES_HOST/lab-refresh-test/_count" | jq .count
echo ""

echo ">>> 수동 refresh 후 검색 (1건 예상)"
curl -s -X POST "$ES_HOST/lab-refresh-test/_refresh" | jq .
echo "--- refresh 후 검색 결과 (1건):"
curl -s "$ES_HOST/lab-refresh-test/_count" | jq .count
echo ""

# --------------------------------------------------------------
# STEP 2: refresh_interval 자동 조정
# --------------------------------------------------------------
echo ">>> [STEP 2] refresh_interval=1s 로 변경 후 자동 검색 가능 확인"
curl -s -X PUT "$ES_HOST/lab-refresh-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"refresh_interval": "1s"}}' | jq .acknowledged

curl -s -X POST "$ES_HOST/lab-refresh-test/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{"text": "자동 refresh 실험 문서"}' | jq .result

echo "--- 0초 후 카운트 (refresh 전):"
curl -s "$ES_HOST/lab-refresh-test/_count" | jq .count

echo "--- 2초 대기 후 카운트 (자동 refresh 후):"
sleep 2
curl -s "$ES_HOST/lab-refresh-test/_count" | jq .count
echo ""

# --------------------------------------------------------------
# STEP 3: ?refresh 파라미터 - 즉시 refresh
# --------------------------------------------------------------
echo ">>> [STEP 3] ?refresh=true - 색인 후 즉시 refresh"
curl -s -X PUT "$ES_HOST/lab-refresh-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"refresh_interval": "-1"}}' | jq .acknowledged

echo "--- ?refresh=true로 즉시 refresh 포함 색인"
curl -s -X POST "$ES_HOST/lab-refresh-test/_doc/3?refresh=true" \
  -H 'Content-Type: application/json' \
  -d '{"text": "즉시 refresh 문서"}' | jq '{result, _id}'

echo "--- 즉시 조회 (refresh 없이도 보임):"
curl -s "$ES_HOST/lab-refresh-test/_count" | jq .count
echo ""

echo "--- ?refresh=wait_for - refresh 될 때까지 대기"
curl -s -X POST "$ES_HOST/lab-refresh-test/_doc/4?refresh=wait_for" \
  -H 'Content-Type: application/json' \
  -d '{"text": "wait_for refresh 문서"}' | jq '{result, _id}'
echo ""

# --------------------------------------------------------------
# STEP 4: translog 설정 관찰
# --------------------------------------------------------------
echo ">>> [STEP 4] translog 설정 및 flush 동작"
echo "--- translog.durability: request(기본) - 요청마다 fsync"
echo "--- translog.durability: async - 5초마다 fsync (성능 우수, 최대 5초 데이터 손실)"
echo "--- translog.sync_interval: async 모드의 fsync 간격"

echo "--- 현재 translog 설정 확인"
curl -s "$ES_HOST/lab-refresh-test/_settings" | \
  jq '.["lab-refresh-test"].settings.index | {refresh_interval}'
echo ""

echo "--- 대량 색인 최적화: durability=async 설정"
curl -s -X PUT "$ES_HOST/lab-refresh-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index.translog.durability": "async",
    "index.translog.sync_interval": "5s"
  }' | jq .acknowledged
echo ""

# --------------------------------------------------------------
# STEP 5: flush 실행
# --------------------------------------------------------------
echo ">>> [STEP 5] flush 실행"
echo "--- flush: translog를 비우고 Lucene commit (segment -> disk)"
curl -s -X POST "$ES_HOST/lab-refresh-test/_flush" | jq .
echo ""

echo "--- flush 후 translog 상태"
curl -s "$ES_HOST/lab-refresh-test/_stats/translog" | \
  jq '.indices["lab-refresh-test"].primaries.translog | {operations, size_in_bytes, uncommitted_operations}'
echo ""

# --------------------------------------------------------------
# STEP 6: 대량 색인 전후 최적 설정 패턴
# --------------------------------------------------------------
echo ">>> [STEP 6] 대량 색인 시 권장 설정 패턴"
echo "--- 색인 전: replica=0, refresh_interval=-1"
echo "--- 색인 후: replica 복원, refresh_interval 복원, force_merge"
echo ""

echo "--- [색인 전 최적화 설정 적용]"
curl -s -X PUT "$ES_HOST/lab-refresh-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": {
      "refresh_interval": "-1",
      "number_of_replicas": 0,
      "translog.durability": "async"
    }
  }' | jq .acknowledged

echo "--- 대량 색인 시뮬레이션 (50건)"
curl -s -X POST "$ES_HOST/lab-refresh-test/_bulk" \
  -H 'Content-Type: application/json' \
  -d "$(for i in $(seq 10 60); do echo '{"index": {}}'; echo "{\"id\": $i, \"text\": \"bulk document $i\"}"; done)" | \
  jq '{errors, took}'
echo ""

echo "--- [색인 후 설정 복원]"
curl -s -X PUT "$ES_HOST/lab-refresh-test/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": {
      "refresh_interval": "1s",
      "number_of_replicas": 0,
      "translog.durability": "request"
    }
  }' | jq .acknowledged

curl -s -X POST "$ES_HOST/lab-refresh-test/_refresh" | jq .
sleep 1
echo "--- 설정 복원 후 문서 수: $(curl -s "$ES_HOST/lab-refresh-test/_count" | jq .count)"
echo ""

echo ">>> 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/lab-refresh-test" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 03-force-merge.sh"
echo "============================================================"
