#!/bin/bash
# ==============================================================
# 03-dynamic-mapping.sh
# 동적 매핑(Dynamic Mapping) 실험
# 관찰 포인트: ES가 타입을 어떻게 추론하는가, dynamic_templates
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  03. 동적 매핑 실험"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-dynamic-default" | jq .
curl -s -X DELETE "$ES_HOST/lab-dynamic-template" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 매핑 선언 없이 인덱스 생성 후 문서 색인
# --------------------------------------------------------------
echo ">>> [STEP 2] 매핑 없이 바로 문서 색인 (동적 매핑 활성화)"
echo "--- ES는 최초 색인 시 값을 보고 타입을 자동으로 결정한다."
curl -s -X POST "$ES_HOST/lab-dynamic-default/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "string_field": "안녕하세요",
    "integer_field": 42,
    "float_field": 3.14,
    "boolean_field": true,
    "date_field": "2024-01-15",
    "date_with_time": "2024-01-15T10:30:00",
    "numeric_string": "12345",
    "array_field": ["a", "b", "c"],
    "object_field": {
      "nested_key": "nested_value",
      "nested_num": 100
    }
  }' | jq .
echo ""

echo ">>> 동적으로 생성된 매핑 확인"
echo "--- 각 필드에 어떤 타입이 할당되었는지 관찰한다."
echo "--- 특히 numeric_string(\"12345\")의 타입에 주목!"
curl -s "$ES_HOST/lab-dynamic-default/_mapping" | jq '.["lab-dynamic-default"].mappings.properties'
echo ""

# --------------------------------------------------------------
# STEP 3: 날짜 형식 자동 감지
# --------------------------------------------------------------
echo ">>> [STEP 3] 날짜 형식 자동 감지 실험"
echo "--- ES의 기본 날짜 감지 패턴: strict_date_optional_time||epoch_millis"
curl -s -X POST "$ES_HOST/lab-dynamic-default/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{
    "date_field": "2024-06-01",
    "not_a_date_string": "not-a-date-12345",
    "epoch_ms": 1704067200000
  }' | jq .
echo ""

echo ">>> 날짜로 감지된 필드 확인"
curl -s "$ES_HOST/lab-dynamic-default/_mapping" | jq '.["lab-dynamic-default"].mappings.properties | with_entries(select(.value.type == "date" or .value.type == "long" or .value.type == "text"))'
echo ""

# --------------------------------------------------------------
# STEP 4: 타입 충돌 (동일 필드에 다른 타입)
# --------------------------------------------------------------
echo ">>> [STEP 4] 타입 충돌 시뮬레이션"
echo "--- integer_field(long 타입)에 문자열을 넣으면 어떻게 되는가?"
curl -s -X POST "$ES_HOST/lab-dynamic-default/_doc/3" \
  -H 'Content-Type: application/json' \
  -d '{
    "integer_field": "이것은 문자열"
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 5: dynamic_templates 설정
# --------------------------------------------------------------
echo ">>> [STEP 5] dynamic_templates가 있는 인덱스 생성"
echo "--- 동적 매핑 규칙을 커스터마이징할 수 있다."
echo "--- 예: _name으로 끝나는 필드는 keyword로, _count로 끝나는 필드는 integer로"
curl -s -X PUT "$ES_HOST/lab-dynamic-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "dynamic_templates": [
        {
          "keyword_for_name_fields": {
            "match": "*_name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "integer_for_count_fields": {
            "match": "*_count",
            "mapping": {
              "type": "integer"
            }
          }
        },
        {
          "text_with_keyword_for_strings": {
            "match_mapping_type": "string",
            "mapping": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            }
          }
        }
      ]
    }
  }' | jq .
echo ""

echo ">>> dynamic_template 인덱스에 문서 색인"
curl -s -X POST "$ES_HOST/lab-dynamic-template/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "product_name": "갤럭시 S24",
    "brand_name": "Samsung",
    "view_count": 1500,
    "like_count": 320,
    "description": "최신 스마트폰 상품 설명"
  }' | jq .
echo ""

echo ">>> dynamic_template 적용 결과 매핑 확인"
echo "--- product_name, brand_name -> keyword"
echo "--- view_count, like_count -> integer"
echo "--- description -> text + keyword (multi-field)"
curl -s "$ES_HOST/lab-dynamic-template/_mapping" | jq '.["lab-dynamic-template"].mappings.properties'
echo ""

# --------------------------------------------------------------
# STEP 6: date_detection 비활성화
# --------------------------------------------------------------
echo ">>> [STEP 6] date_detection=false 인덱스 생성"
echo "--- 날짜처럼 보이는 문자열도 text로 처리된다."
curl -s -X DELETE "$ES_HOST/lab-no-date-detect" | jq .
curl -s -X PUT "$ES_HOST/lab-no-date-detect" \
  -H 'Content-Type: application/json' \
  -d '{
    "mappings": {
      "date_detection": false,
      "numeric_detection": true
    }
  }' | jq .

curl -s -X POST "$ES_HOST/lab-no-date-detect/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "date_string": "2024-01-15",
    "numeric_string": "3.14"
  }' | jq .

echo ">>> date_detection=false 결과: date_string이 text, numeric_string은 float"
curl -s "$ES_HOST/lab-no-date-detect/_mapping" | jq '.["lab-no-date-detect"].mappings.properties'
echo ""

curl -s -X DELETE "$ES_HOST/lab-no-date-detect" | jq . > /dev/null

echo "============================================================"
echo "  실습 완료"
echo "  다음: 04-field-types.sh"
echo "============================================================"
