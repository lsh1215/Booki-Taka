#!/bin/bash
# ==============================================================
# 06-reindex.sh
# Reindex API 실습 - 인덱스 복사, 변환, 마이그레이션
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  06. Reindex API"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- Reindex: 한 인덱스에서 다른 인덱스로 문서를 복사"
echo "--- 사용 사례: 매핑 변경, 샤드 수 변경, 데이터 정제, 인덱스 분할"
echo "--- 원본 인덱스는 변경되지 않음"
echo ""

# --------------------------------------------------------------
# STEP 1: 원본 인덱스 생성 및 데이터 색인
# --------------------------------------------------------------
echo ">>> [STEP 1] 원본 인덱스 생성 (old mapping)"
curl -s -X DELETE "$ES_HOST/reindex-source" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/reindex-dest" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/reindex-filtered" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/reindex-transformed" | jq . > /dev/null

curl -s -X PUT "$ES_HOST/reindex-source" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "properties": {
        "name":     {"type": "text"},
        "price":    {"type": "integer"},
        "category": {"type": "text"},
        "status":   {"type": "text"},
        "created":  {"type": "text"}
      }
    }
  }' | jq .acknowledged

curl -s -X POST "$ES_HOST/reindex-source/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"name": "갤럭시 S24", "price": 1599000, "category": "smartphone", "status": "active", "created": "2024-01-15"}
{"index": {"_id": "2"}}
{"name": "아이폰 15 Pro", "price": 1550000, "category": "smartphone", "status": "active", "created": "2023-09-22"}
{"index": {"_id": "3"}}
{"name": "맥북 프로 M3", "price": 2990000, "category": "laptop", "status": "active", "created": "2023-11-07"}
{"index": {"_id": "4"}}
{"name": "갤럭시 버즈2", "price": 259000, "category": "earphone", "status": "discontinued", "created": "2023-08-10"}
{"index": {"_id": "5"}}
{"name": "소니 WH-1000XM5", "price": 449000, "category": "headphone", "status": "active", "created": "2022-05-12"}
{"index": {"_id": "6"}}
{"name": "구형 스마트폰", "price": 350000, "category": "smartphone", "status": "discontinued", "created": "2021-03-01"}
{"index": {"_id": "7"}}
{"name": "LG 노트북", "price": 1890000, "category": "laptop", "status": "active", "created": "2024-02-05"}
{"index": {"_id": "8"}}
{"name": "구형 태블릿", "price": 500000, "category": "tablet", "status": "discontinued", "created": "2020-06-01"}
' | jq .errors

sleep 1
echo "--- 원본 문서 수: $(curl -s "$ES_HOST/reindex-source/_count" | jq .count)"
echo ""

# --------------------------------------------------------------
# STEP 2: 기본 Reindex
# --------------------------------------------------------------
echo ">>> [STEP 2] 기본 Reindex - 전체 복사 (매핑 개선)"
curl -s -X PUT "$ES_HOST/reindex-dest" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 2, "number_of_replicas": 0},
    "mappings": {
      "properties": {
        "name":     {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
        "price":    {"type": "integer"},
        "category": {"type": "keyword"},
        "status":   {"type": "keyword"},
        "created":  {"type": "date", "format": "yyyy-MM-dd"}
      }
    }
  }' | jq .acknowledged

curl -s -X POST "$ES_HOST/_reindex" \
  -H 'Content-Type: application/json' \
  -d '{
    "source": {"index": "reindex-source"},
    "dest":   {"index": "reindex-dest"}
  }' | jq '{total, created, updated, failures: (.failures | length)}'

sleep 1
echo "--- 복사된 문서 수: $(curl -s "$ES_HOST/reindex-dest/_count" | jq .count)"
echo "--- 개선된 매핑 확인 (category가 keyword 타입)"
curl -s "$ES_HOST/reindex-dest/_mapping" | jq '.["reindex-dest"].mappings.properties | {category: .category, created: .created}'
echo ""

# --------------------------------------------------------------
# STEP 3: 조건부 Reindex (특정 문서만)
# --------------------------------------------------------------
echo ">>> [STEP 3] 조건부 Reindex - active 상태만 복사"
curl -s -X POST "$ES_HOST/_reindex" \
  -H 'Content-Type: application/json' \
  -d '{
    "source": {
      "index": "reindex-source",
      "query": {"term": {"status": "active"}}
    },
    "dest": {"index": "reindex-filtered"}
  }' | jq '{total, created}'

sleep 1
echo "--- active 상태만 복사: $(curl -s "$ES_HOST/reindex-filtered/_count" | jq .count)건 (총 8건 중)"
echo ""

# --------------------------------------------------------------
# STEP 4: 변환 Reindex (script 사용)
# --------------------------------------------------------------
echo ">>> [STEP 4] 변환 Reindex - Script로 데이터 변환"
echo "--- price에 부가세(10%) 추가, 카테고리 대문자화"
curl -s -X POST "$ES_HOST/_reindex" \
  -H 'Content-Type: application/json' \
  -d '{
    "source": {
      "index": "reindex-source",
      "query": {"term": {"status": "active"}}
    },
    "dest": {"index": "reindex-transformed"},
    "script": {
      "source": "ctx._source.price_with_vat = (int)(ctx._source.price * 1.1); ctx._source.category_upper = ctx._source.category.toUpperCase();"
    }
  }' | jq '{total, created}'

sleep 1
echo "--- 변환된 문서 확인"
curl -s "$ES_HOST/reindex-transformed/_search?size=3" | jq '[.hits.hits[]._source | {name, price, price_with_vat, category_upper}]'
echo ""

# --------------------------------------------------------------
# STEP 5: update_by_query - 기존 인덱스 문서 업데이트
# --------------------------------------------------------------
echo ">>> [STEP 5] update_by_query - 조건부 문서 업데이트"
echo "--- reindex-source에서 discontinued 상태를 archive로 변경"
curl -s -X POST "$ES_HOST/reindex-source/_update_by_query" \
  -H 'Content-Type: application/json' \
  -d '{
    "script": {
      "source": "ctx._source.status = '\''archived'\''"
    },
    "query": {"term": {"status": "discontinued"}}
  }' | jq '{updated, total}'

sleep 1
echo "--- 업데이트 결과 확인"
curl -s "$ES_HOST/reindex-source/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"status": "archived"}}}' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 6: delete_by_query - 조건부 문서 삭제
# --------------------------------------------------------------
echo ">>> [STEP 6] delete_by_query - 조건부 문서 삭제"
echo "--- 2021년 이전 생성된 문서 삭제 (archived 중에서 2021년 데이터)"
curl -s -X POST "$ES_HOST/reindex-source/_delete_by_query" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"term": {"status": "archived"}},
          {"term": {"created": "2020-06-01"}}
        ]
      }
    }
  }' | jq '{deleted, total}'

sleep 1
echo "--- 삭제 후 문서 수: $(curl -s "$ES_HOST/reindex-source/_count" | jq .count)"
echo ""

# --------------------------------------------------------------
# STEP 7: 비동기 Reindex (대용량 데이터)
# --------------------------------------------------------------
echo ">>> [STEP 7] 비동기 Reindex (wait_for_completion=false)"
echo "--- 대용량 reindex는 wait_for_completion=false로 비동기 실행"
TASK_ID=$(curl -s -X POST "$ES_HOST/_reindex?wait_for_completion=false" \
  -H 'Content-Type: application/json' \
  -d '{
    "source": {"index": "reindex-source"},
    "dest":   {"index": "reindex-dest-async"}
  }' | jq -r '.task')

echo "--- Task ID: $TASK_ID"
echo "--- Task 상태 확인"
curl -s "$ES_HOST/_tasks/$TASK_ID" | jq '{completed: .completed, status: .task.status}'
echo ""

curl -s -X DELETE "$ES_HOST/reindex-dest-async" | jq . > /dev/null

# --------------------------------------------------------------
# STEP 8: 정리
# --------------------------------------------------------------
echo ">>> [STEP 8] 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/reindex-source,reindex-dest,reindex-filtered,reindex-transformed" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 07-ilm.sh"
echo "============================================================"
