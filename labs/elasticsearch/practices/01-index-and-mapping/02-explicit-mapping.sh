#!/bin/bash
# ==============================================================
# 02-explicit-mapping.sh
# 명시적 매핑(Explicit Mapping) 생성 실습
# 관찰 포인트: 필드 타입 선언, dynamic 설정, multi-field
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  02. 명시적 매핑 생성 실습"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-mapping-explicit" | jq .
curl -s -X DELETE "$ES_HOST/lab-mapping-strict" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 명시적 매핑이 있는 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] 명시적 매핑으로 인덱스 생성"
echo "--- 실무에서 사용하는 전자상거래 상품 인덱스 매핑을 예시로 사용한다."
echo "--- text: full-text 검색, keyword: 정확값 검색/집계/정렬"
curl -s -X PUT "$ES_HOST/lab-mapping-explicit" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "title": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "category": {
          "type": "keyword"
        },
        "price": {
          "type": "integer"
        },
        "brand": {
          "type": "keyword"
        },
        "description": {
          "type": "text"
        },
        "created_at": {
          "type": "date",
          "format": "yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis"
        },
        "in_stock": {
          "type": "boolean"
        },
        "rating": {
          "type": "float"
        },
        "tags": {
          "type": "keyword"
        },
        "metadata": {
          "type": "object",
          "properties": {
            "sku": { "type": "keyword" },
            "weight_kg": { "type": "float" }
          }
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 매핑 조회
# --------------------------------------------------------------
echo ">>> [STEP 3] 생성된 매핑 조회"
echo "--- 선언한 필드 타입이 정확히 저장되었는지 확인한다."
curl -s "$ES_HOST/lab-mapping-explicit/_mapping" | jq '.["lab-mapping-explicit"].mappings.properties'
echo ""

# --------------------------------------------------------------
# STEP 4: 올바른 문서 색인
# --------------------------------------------------------------
echo ">>> [STEP 4] 올바른 형식의 문서 색인"
curl -s -X POST "$ES_HOST/lab-mapping-explicit/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "삼성 갤럭시 S24 스마트폰",
    "category": "전자기기",
    "price": 1200000,
    "brand": "Samsung",
    "description": "최신 AI 기능을 탑재한 플래그십 스마트폰",
    "created_at": "2024-01-15",
    "in_stock": true,
    "rating": 4.7,
    "tags": ["스마트폰", "삼성", "안드로이드"],
    "metadata": {
      "sku": "SM-S24-256-BLK",
      "weight_kg": 0.167
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 5: 타입 불일치 문서 색인 (에러 관찰)
# --------------------------------------------------------------
echo ">>> [STEP 5] 타입 불일치 문서 색인 시도 - 에러를 관찰한다"
echo "--- price 필드(integer)에 문자열을 넣으면 어떻게 되는가?"
curl -s -X POST "$ES_HOST/lab-mapping-explicit/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "잘못된 가격 필드",
    "price": "비쌈"
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 6: 매핑에 없는 새 필드 추가 (dynamic=true 기본 동작)
# --------------------------------------------------------------
echo ">>> [STEP 6] 매핑에 없는 필드를 포함한 문서 색인"
echo "--- dynamic=true(기본값)이므로 알 수 없는 필드는 자동으로 매핑에 추가된다."
curl -s -X POST "$ES_HOST/lab-mapping-explicit/_doc/3" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "LG 노트북",
    "category": "컴퓨터",
    "price": 1500000,
    "new_field_not_in_mapping": "동적으로 추가되는 필드"
  }' | jq .
echo ""

echo ">>> 새 필드가 매핑에 추가되었는지 확인"
curl -s "$ES_HOST/lab-mapping-explicit/_mapping" | jq '.["lab-mapping-explicit"].mappings.properties | keys'
echo ""

# --------------------------------------------------------------
# STEP 7: strict dynamic 매핑 설정
# --------------------------------------------------------------
echo ">>> [STEP 7] dynamic: strict 인덱스 생성"
echo "--- strict: 정의되지 않은 필드가 들어오면 색인을 거부한다."
curl -s -X PUT "$ES_HOST/lab-mapping-strict" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "name": { "type": "keyword" },
        "age":  { "type": "integer" }
      }
    }
  }' | jq .
echo ""

echo ">>> strict 인덱스에 알 수 없는 필드로 색인 시도 (에러 예상)"
curl -s -X POST "$ES_HOST/lab-mapping-strict/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "홍길동",
    "age": 30,
    "unknown_field": "이 필드는 매핑에 없다"
  }' | jq .
echo ""

echo ">>> strict 인덱스에 허용된 필드만 색인 (성공 예상)"
curl -s -X POST "$ES_HOST/lab-mapping-strict/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "홍길동",
    "age": 30
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 8: 매핑에 새 필드 추가 (기존 필드 타입은 변경 불가)
# --------------------------------------------------------------
echo ">>> [STEP 8] 기존 인덱스 매핑에 새 필드 추가"
echo "--- 이미 존재하는 필드의 타입은 변경할 수 없지만, 새 필드는 추가 가능하다."
curl -s -X PUT "$ES_HOST/lab-mapping-explicit/_mapping" \
  -H 'Content-Type: application/json' \
  -d '{
    "properties": {
      "view_count": {
        "type": "long"
      }
    }
  }' | jq .
echo ""

echo ">>> 기존 필드 타입 변경 시도 (에러 예상)"
echo "--- price(integer)를 keyword로 변경하려고 하면 에러가 발생한다."
curl -s -X PUT "$ES_HOST/lab-mapping-explicit/_mapping" \
  -H 'Content-Type: application/json' \
  -d '{
    "properties": {
      "price": {
        "type": "keyword"
      }
    }
  }' | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 03-dynamic-mapping.sh"
echo "============================================================"
