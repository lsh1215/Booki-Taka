#!/bin/bash
# ==============================================================
# 05-normalizer.sh
# 노멀라이저(Normalizer) 실습
# 관찰 포인트: keyword 필드의 값 정규화, 대소문자 무시 검색
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  05. 노멀라이저 실습"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 노멀라이저: 애널라이저와 유사하지만 토크나이저가 없다"
echo "--- keyword 타입 필드에 적용 (단일 토큰 값 정규화)"
echo "--- 사용 사례: 대소문자 무시 검색, 특수문자 제거, 유니코드 정규화"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-normalizer" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 노멀라이저가 있는 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] 노멀라이저 인덱스 생성"
curl -s -X PUT "$ES_HOST/lab-normalizer" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1, "number_of_replicas": 0,
      "analysis": {
        "normalizer": {
          "lowercase_normalizer": {
            "type": "custom",
            "filter": ["lowercase"]
          },
          "lowercase_asciifolding_normalizer": {
            "type": "custom",
            "filter": ["lowercase", "asciifolding"]
          },
          "uppercase_normalizer": {
            "type": "custom",
            "filter": ["uppercase"]
          }
        }
      }
    },
    "mappings": {
      "properties": {
        "brand_raw": {
          "type": "keyword",
          "comment": "노멀라이저 없음 - 대소문자 구분"
        },
        "brand_lower": {
          "type": "keyword",
          "normalizer": "lowercase_normalizer",
          "comment": "lowercase 노멀라이저 - 대소문자 무시 검색"
        },
        "brand_ascii": {
          "type": "keyword",
          "normalizer": "lowercase_asciifolding_normalizer",
          "comment": "lowercase + asciifolding - 악센트 문자 정규화"
        },
        "status_upper": {
          "type": "keyword",
          "normalizer": "uppercase_normalizer",
          "comment": "uppercase 노멀라이저"
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 샘플 데이터 색인
# --------------------------------------------------------------
echo ">>> [STEP 3] 샘플 데이터 색인"
curl -s -X POST "$ES_HOST/lab-normalizer/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"brand_raw": "Samsung", "brand_lower": "Samsung", "brand_ascii": "Samsung", "status_upper": "active"}
{"index": {"_id": "2"}}
{"brand_raw": "SAMSUNG", "brand_lower": "SAMSUNG", "brand_ascii": "SAMSUNG", "status_upper": "INACTIVE"}
{"index": {"_id": "3"}}
{"brand_raw": "samsung", "brand_lower": "samsung", "brand_ascii": "samsung", "status_upper": "pending"}
{"index": {"_id": "4"}}
{"brand_raw": "Apple", "brand_lower": "Apple", "brand_ascii": "Apple", "status_upper": "active"}
{"index": {"_id": "5"}}
{"brand_raw": "ASUS", "brand_lower": "ASUS", "brand_ascii": "ASUS", "status_upper": "active"}
{"index": {"_id": "6"}}
{"brand_raw": "Café Brand", "brand_lower": "Café Brand", "brand_ascii": "Café Brand", "status_upper": "active"}
' | jq .errors

sleep 1
echo ""

# --------------------------------------------------------------
# STEP 4: 노멀라이저 없는 필드 검색 (대소문자 구분)
# --------------------------------------------------------------
echo ">>> [STEP 4] brand_raw (노멀라이저 없음) - 대소문자 구분 검색"
echo "--- 'samsung' 소문자로 검색 -> samsung 문서만 매칭"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"brand_raw": "samsung"}}}' | jq '.hits.total.value'

echo "--- 'Samsung' 으로 검색 -> Samsung만 매칭 (1건)"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"brand_raw": "Samsung"}}}' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 5: lowercase 노멀라이저 검색 (대소문자 무시)
# --------------------------------------------------------------
echo ">>> [STEP 5] brand_lower (lowercase 노멀라이저) - 대소문자 무시 검색"
echo "--- 색인/검색 모두 lowercase로 변환되므로 Samsung, SAMSUNG, samsung 모두 매칭"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"brand_lower": "samsung"}}}' | jq '.hits.total.value'

echo "--- 'SAMSUNG'으로 검색해도 동일하게 3건 매칭"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"brand_lower": "SAMSUNG"}}}' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 6: asciifolding 노멀라이저 (악센트 정규화)
# --------------------------------------------------------------
echo ">>> [STEP 6] brand_ascii (lowercase + asciifolding) - 악센트 무시 검색"
echo "--- 'Café' -> 'cafe' 로 변환되어 저장"
echo "--- 'cafe'로 검색하면 'Café Brand' 매칭"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"brand_ascii": "cafe brand"}}}' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 7: uppercase 노멀라이저 (status 필드 정규화)
# --------------------------------------------------------------
echo ">>> [STEP 7] status_upper (uppercase 노멀라이저)"
echo "--- 'active', 'INACTIVE', 'pending' 모두 대문자로 저장됨"
echo "--- 'ACTIVE'로 검색하면 active, ACTIVE 모두 매칭"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"status_upper": "ACTIVE"}}, "_source": ["status_upper"]}' | jq '[.hits.hits[]._source.status_upper]'
echo ""

# --------------------------------------------------------------
# STEP 8: 노멀라이저 집계에서의 효과
# --------------------------------------------------------------
echo ">>> [STEP 8] 노멀라이저 집계 결과 비교"
echo "--- brand_raw 집계: Samsung, SAMSUNG, samsung 각각 개별 버킷"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {"by_brand_raw": {"terms": {"field": "brand_raw"}}}
  }' | jq '.aggregations.by_brand_raw.buckets'
echo ""

echo "--- brand_lower 집계: samsung으로 통합된 하나의 버킷"
curl -s -X GET "$ES_HOST/lab-normalizer/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {"by_brand_lower": {"terms": {"field": "brand_lower"}}}
  }' | jq '.aggregations.by_brand_lower.buckets'
echo ""

# --------------------------------------------------------------
# STEP 9: _analyze API로 노멀라이저 동작 확인
# --------------------------------------------------------------
echo ">>> [STEP 9] _analyze API로 노멀라이저 동작 확인"
echo "--- 노멀라이저는 단일 토큰(keyword 특성) 출력"
curl -s -X POST "$ES_HOST/lab-normalizer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "normalizer": "lowercase_asciifolding_normalizer",
    "text": "CAFÉ BRAND"
  }' | jq '[.tokens[].token]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  02-analyzer 실습 전체 완료!"
echo "  다음 실습: 03-search-query-dsl/"
echo "============================================================"
