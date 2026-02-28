#!/bin/bash
# ==============================================================
# 04-field-types.sh
# 다양한 필드 타입 실습
# 관찰 포인트: text/keyword, 숫자 타입, date, geo_point, nested, join
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  04. 다양한 필드 타입 실습"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-fieldtypes" | jq .
curl -s -X DELETE "$ES_HOST/lab-nested" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 다양한 필드 타입을 포함한 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] 다양한 필드 타입 인덱스 생성"
curl -s -X PUT "$ES_HOST/lab-fieldtypes" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "text_field":    { "type": "text" },
        "keyword_field": { "type": "keyword" },
        "byte_field":    { "type": "byte" },
        "short_field":   { "type": "short" },
        "integer_field": { "type": "integer" },
        "long_field":    { "type": "long" },
        "float_field":   { "type": "float" },
        "double_field":  { "type": "double" },
        "boolean_field": { "type": "boolean" },
        "ip_field":      { "type": "ip" },
        "date_field": {
          "type": "date",
          "format": "yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis"
        },
        "geo_point_field": { "type": "geo_point" },
        "range_field":   { "type": "integer_range" },
        "binary_field":  { "type": "binary" }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 각 타입별 문서 색인
# --------------------------------------------------------------
echo ">>> [STEP 3] 다양한 타입의 값으로 문서 색인"
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "text_field": "이것은 전문 검색(full-text search) 대상 텍스트",
    "keyword_field": "KEYWORD_EXACT_MATCH",
    "byte_field": 127,
    "short_field": 32767,
    "integer_field": 2147483647,
    "long_field": 9223372036854775807,
    "float_field": 3.14,
    "double_field": 3.141592653589793,
    "boolean_field": true,
    "ip_field": "192.168.1.100",
    "date_field": "2024-01-15 10:30:00",
    "geo_point_field": {
      "lat": 37.5665,
      "lon": 126.9780
    },
    "range_field": {
      "gte": 10,
      "lte": 20
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 4: geo_point 다양한 형식
# --------------------------------------------------------------
echo ">>> [STEP 4] geo_point 다양한 입력 형식 실습"
echo "--- geo_point는 여러 형식으로 값을 지정할 수 있다."

echo "--- 형식 1: 객체 {lat, lon}"
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{"geo_point_field": {"lat": 37.5665, "lon": 126.9780}}' | jq .status

echo "--- 형식 2: 배열 [lon, lat] (GeoJSON 순서 주의!)"
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/3" \
  -H 'Content-Type: application/json' \
  -d '{"geo_point_field": [126.9780, 37.5665]}' | jq .status

echo "--- 형식 3: 문자열 \"lat,lon\""
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/4" \
  -H 'Content-Type: application/json' \
  -d '{"geo_point_field": "37.5665,126.9780"}' | jq .status
echo ""

# --------------------------------------------------------------
# STEP 5: date 형식 다양성 테스트
# --------------------------------------------------------------
echo ">>> [STEP 5] date 필드 다양한 입력 형식"
echo "--- format에 선언된 형식만 허용된다."

echo "--- yyyy-MM-dd 형식"
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/5" \
  -H 'Content-Type: application/json' \
  -d '{"date_field": "2024-06-15"}' | jq .result

echo "--- epoch_millis (Unix timestamp milliseconds)"
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/6" \
  -H 'Content-Type: application/json' \
  -d '{"date_field": 1705276200000}' | jq .result

echo "--- 허용되지 않는 형식 시도 (에러 예상)"
curl -s -X POST "$ES_HOST/lab-fieldtypes/_doc/7" \
  -H 'Content-Type: application/json' \
  -d '{"date_field": "15/01/2024"}' | jq .error.type
echo ""

# --------------------------------------------------------------
# STEP 6: text vs keyword 검색 동작 비교
# --------------------------------------------------------------
echo ">>> [STEP 6] text vs keyword 검색 차이 관찰"
sleep 1

echo "--- text_field: 'full-text' 단어로 검색 가능"
curl -s -X GET "$ES_HOST/lab-fieldtypes/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"match": {"text_field": "전문"}},
    "_source": ["text_field"]
  }' | jq '.hits.total.value'

echo "--- keyword_field: 정확한 값 전체가 일치해야 검색됨"
echo "--- 'KEYWORD_EXACT_MATCH' 전체로 검색 (성공)"
curl -s -X GET "$ES_HOST/lab-fieldtypes/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"keyword_field": "KEYWORD_EXACT_MATCH"}},
    "_source": ["keyword_field"]
  }' | jq '.hits.total.value'

echo "--- 'KEYWORD' 일부로 term 검색 (실패 - 0건)"
curl -s -X GET "$ES_HOST/lab-fieldtypes/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"keyword_field": "KEYWORD"}},
    "_source": ["keyword_field"]
  }' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 7: nested 타입 실습
# --------------------------------------------------------------
echo ">>> [STEP 7] nested 타입 실습"
echo "--- 배열 안의 객체를 독립적으로 검색하기 위해 nested 타입을 사용한다."
echo "--- 일반 object 타입은 배열 안의 객체 간 필드가 분리되지 않는다."
curl -s -X PUT "$ES_HOST/lab-nested" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "properties": {
        "product_name": {"type": "keyword"},
        "reviews": {
          "type": "nested",
          "properties": {
            "author":  {"type": "keyword"},
            "score":   {"type": "integer"},
            "comment": {"type": "text"}
          }
        }
      }
    }
  }' | jq .
echo ""

echo ">>> nested 문서 색인"
curl -s -X POST "$ES_HOST/lab-nested/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "product_name": "갤럭시 S24",
    "reviews": [
      {"author": "김철수", "score": 5, "comment": "최고의 스마트폰"},
      {"author": "이영희", "score": 2, "comment": "배터리가 아쉬움"}
    ]
  }' | jq .result

sleep 1

echo "--- nested query: 김철수가 5점을 준 상품 검색 (성공)"
curl -s -X GET "$ES_HOST/lab-nested/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "nested": {
        "path": "reviews",
        "query": {
          "bool": {
            "must": [
              {"term": {"reviews.author": "김철수"}},
              {"term": {"reviews.score": 5}}
            ]
          }
        }
      }
    }
  }' | jq '.hits.total.value'

echo "--- nested query: 이영희가 5점을 준 상품 검색 (실패 - 0건)"
echo "--- (이영희는 2점을 줬으므로 조건 불충족)"
curl -s -X GET "$ES_HOST/lab-nested/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "nested": {
        "path": "reviews",
        "query": {
          "bool": {
            "must": [
              {"term": {"reviews.author": "이영희"}},
              {"term": {"reviews.score": 5}}
            ]
          }
        }
      }
    }
  }' | jq '.hits.total.value'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 05-doc-values-fielddata.sh"
echo "============================================================"
