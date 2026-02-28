#!/bin/bash
# ==============================================================
# 04-alias-rollover.sh
# Alias와 Rollover 실습
# 관찰 포인트: 무중단 인덱스 전환, 쓰기/읽기 alias 분리
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  04. Alias & Rollover"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- Alias: 하나 이상의 인덱스를 가리키는 논리적 이름"
echo "--- Rollover: 조건 충족 시 새 인덱스를 자동 생성하고 alias를 이전"
echo "--- 장점: 애플리케이션 코드 변경 없이 인덱스를 교체 가능"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 데이터 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 데이터 삭제"
curl -s -X DELETE "$ES_HOST/logs-000001" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/logs-000002" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/logs-000003" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/shop-v1" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/shop-v2" | jq . > /dev/null
echo ""

# --------------------------------------------------------------
# STEP 2: 기본 Alias 사용법
# --------------------------------------------------------------
echo ">>> [STEP 2] 기본 Alias 생성 및 사용"
echo "--- shop-v1 인덱스 생성 후 alias 부여"
curl -s -X PUT "$ES_HOST/shop-v1" \
  -H 'Content-Type: application/json' \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}' | jq .acknowledged

curl -s -X POST "$ES_HOST/_aliases" \
  -H 'Content-Type: application/json' \
  -d '{
    "actions": [
      {"add": {"index": "shop-v1", "alias": "shop"}}
    ]
  }' | jq .acknowledged
echo ""

echo "--- alias로 문서 색인"
curl -s -X POST "$ES_HOST/shop/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{"product": "갤럭시 S24", "price": 1599000}' | jq '._index'
echo ""

echo "--- alias 정보 조회"
curl -s "$ES_HOST/_alias/shop" | jq 'keys'
echo ""

echo "--- shop-v2 인덱스 생성 후 alias 원자적 전환"
curl -s -X PUT "$ES_HOST/shop-v2" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 2, "number_of_replicas": 0},
    "mappings": {
      "properties": {
        "product": {"type": "text"},
        "price": {"type": "integer"},
        "version": {"type": "keyword"}
      }
    }
  }' | jq .acknowledged

echo "--- 원자적 alias 전환 (downtime 없음)"
curl -s -X POST "$ES_HOST/_aliases" \
  -H 'Content-Type: application/json' \
  -d '{
    "actions": [
      {"remove": {"index": "shop-v1", "alias": "shop"}},
      {"add":    {"index": "shop-v2", "alias": "shop"}}
    ]
  }' | jq .acknowledged

echo "--- 전환 후 alias 확인 (shop-v2가 가리켜야 함)"
curl -s "$ES_HOST/_alias/shop" | jq 'keys'
echo ""

# --------------------------------------------------------------
# STEP 3: 필터가 있는 Alias
# --------------------------------------------------------------
echo ">>> [STEP 3] 필터 Alias - 가격 100만원 이상만 보이는 alias"
curl -s -X POST "$ES_HOST/_aliases" \
  -H 'Content-Type: application/json' \
  -d '{
    "actions": [{
      "add": {
        "index": "shop-v2",
        "alias": "shop-premium",
        "filter": {"range": {"price": {"gte": 1000000}}}
      }
    }]
  }' | jq .acknowledged

curl -s -X POST "$ES_HOST/shop-v2/_doc" \
  -H 'Content-Type: application/json' \
  -d '{"product": "저가 상품", "price": 50000, "version": "v2"}' | jq .result
curl -s -X POST "$ES_HOST/shop-v2/_doc" \
  -H 'Content-Type: application/json' \
  -d '{"product": "고가 상품", "price": 2000000, "version": "v2"}' | jq .result
sleep 1

echo "--- shop 전체 alias로 검색 (2건)"
curl -s "$ES_HOST/shop/_count" | jq .count
echo "--- shop-premium alias로 검색 (100만원 이상만, 1건)"
curl -s "$ES_HOST/shop-premium/_count" | jq .count
echo ""

# --------------------------------------------------------------
# STEP 4: Rollover - write alias를 이용한 자동 인덱스 교체
# --------------------------------------------------------------
echo ">>> [STEP 4] Rollover 설정 및 실습"
echo "--- rollover를 위한 초기 인덱스 생성 (명명 규칙: name-000001)"
curl -s -X PUT "$ES_HOST/logs-000001" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "aliases": {
      "logs-write": {"is_write_index": true},
      "logs":       {}
    }
  }' | jq .acknowledged
echo ""

echo "--- 로그 데이터 색인"
for i in $(seq 1 10); do
  curl -s -X POST "$ES_HOST/logs-write/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"level\": \"INFO\", \"message\": \"Test log $i\", \"@timestamp\": \"2024-01-15 10:$(printf '%02d' $i):00\"}" | jq .result
done
sleep 1
echo ""

echo "--- 현재 상태 확인"
curl -s "$ES_HOST/_cat/indices/logs-*?v&h=index,docs.count" | column -t
echo ""

echo "--- Rollover 실행 (max_docs: 5 - 이미 10개 있으므로 롤오버 발생)"
curl -s -X POST "$ES_HOST/logs-write/_rollover" \
  -H 'Content-Type: application/json' \
  -d '{
    "conditions": {
      "max_docs": 5,
      "max_age": "1d",
      "max_size": "1gb"
    }
  }' | jq '{rolled_over, old_index, new_index, conditions}'
echo ""

echo "--- 롤오버 후 인덱스 목록 확인"
curl -s "$ES_HOST/_cat/indices/logs-*?v&h=index,docs.count,aliases" | column -t
echo ""

echo "--- write alias가 새 인덱스를 가리키는지 확인"
curl -s "$ES_HOST/_alias/logs-write" | jq 'to_entries[] | {index: .key, is_write: .value.aliases["logs-write"].is_write_index}'
echo ""

echo "--- 새 인덱스에 문서 색인 (롤오버 후)"
curl -s -X POST "$ES_HOST/logs-write/_doc" \
  -H 'Content-Type: application/json' \
  -d '{"level": "INFO", "message": "Post-rollover log"}' | jq '._index'
echo ""

echo "--- logs alias로 전체 조회 (모든 인덱스 포함)"
curl -s "$ES_HOST/logs/_count" | jq .count
echo ""

# --------------------------------------------------------------
# STEP 5: 정리
# --------------------------------------------------------------
echo ">>> [STEP 5] 실습 데이터 정리"
curl -s -X DELETE "$ES_HOST/shop-v1,shop-v2,logs-000001,logs-000002" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 05-snapshot-restore.sh"
echo "============================================================"
