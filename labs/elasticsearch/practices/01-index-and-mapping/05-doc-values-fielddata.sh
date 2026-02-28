#!/bin/bash
# ==============================================================
# 05-doc-values-fielddata.sh
# doc_values vs fielddata 비교 실습
# 관찰 포인트: 집계/정렬 시 메모리 사용, 에러 메시지 분석
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  05. doc_values vs fielddata 비교"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- doc_values: 디스크 기반 열 지향 저장소. keyword, 숫자, date 필드에 기본 활성화"
echo "--- fielddata:  힙 메모리 기반. text 필드에서 집계/정렬이 필요할 때 명시적으로 활성화"
echo "--- 결론: 집계/정렬용 텍스트 필드는 keyword 타입을 사용하는 것이 메모리 효율적"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-docvalues" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 다양한 설정의 필드를 포함한 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] 인덱스 생성 - doc_values/fielddata 설정 비교"
curl -s -X PUT "$ES_HOST/lab-docvalues" \
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
          "comment": "text 타입 - fielddata 기본 false"
        },
        "title_with_fielddata": {
          "type": "text",
          "fielddata": true,
          "comment": "text 타입 - fielddata 명시적 활성화 (메모리 사용)"
        },
        "category": {
          "type": "keyword",
          "comment": "keyword - doc_values 기본 true (디스크)"
        },
        "category_no_docvalues": {
          "type": "keyword",
          "doc_values": false,
          "comment": "keyword - doc_values 비활성화 (집계/정렬 불가)"
        },
        "price": {
          "type": "integer",
          "comment": "숫자 - doc_values 기본 true"
        },
        "price_no_docvalues": {
          "type": "integer",
          "doc_values": false,
          "comment": "숫자 - doc_values 비활성화"
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 샘플 데이터 색인
# --------------------------------------------------------------
echo ">>> [STEP 3] 샘플 데이터 색인"
curl -s -X POST "$ES_HOST/lab-docvalues/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"title": "갤럭시 S24", "title_with_fielddata": "갤럭시 S24", "category": "스마트폰", "category_no_docvalues": "스마트폰", "price": 1200000, "price_no_docvalues": 1200000}
{"index": {"_id": "2"}}
{"title": "아이폰 15", "title_with_fielddata": "아이폰 15", "category": "스마트폰", "category_no_docvalues": "스마트폰", "price": 1500000, "price_no_docvalues": 1500000}
{"index": {"_id": "3"}}
{"title": "LG 그램 노트북", "title_with_fielddata": "LG 그램 노트북", "category": "노트북", "category_no_docvalues": "노트북", "price": 2000000, "price_no_docvalues": 2000000}
{"index": {"_id": "4"}}
{"title": "삼성 TV", "title_with_fielddata": "삼성 TV", "category": "TV", "category_no_docvalues": "TV", "price": 1800000, "price_no_docvalues": 1800000}
' | jq .errors

sleep 1
echo ""

# --------------------------------------------------------------
# STEP 4: keyword (doc_values) 집계 - 정상
# --------------------------------------------------------------
echo ">>> [STEP 4] keyword(doc_values=true) 필드로 집계 - 정상 동작"
echo "--- category 필드는 keyword 타입, doc_values 기본 true"
curl -s -X GET "$ES_HOST/lab-docvalues/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category"}
      }
    }
  }' | jq '.aggregations.by_category.buckets'
echo ""

# --------------------------------------------------------------
# STEP 5: text (fielddata=false) 집계 - 에러
# --------------------------------------------------------------
echo ">>> [STEP 5] text(fielddata=false) 필드로 집계 시도 - 에러 관찰"
echo "--- title 필드는 text 타입, fielddata 기본 false"
echo "--- 에러 메시지를 주의 깊게 읽어보자!"
curl -s -X GET "$ES_HOST/lab-docvalues/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_title": {
        "terms": {"field": "title"}
      }
    }
  }' | jq '.error.root_cause[0].reason'
echo ""

# --------------------------------------------------------------
# STEP 6: text (fielddata=true) 집계 - 동작하지만 메모리 사용
# --------------------------------------------------------------
echo ">>> [STEP 6] text(fielddata=true) 필드로 집계 - 동작하지만 메모리 사용"
echo "--- title_with_fielddata는 fielddata=true로 설정된 text 필드"
echo "--- 토큰 단위로 집계됨에 주의 (분석된 토큰별로 버킷 생성)"
curl -s -X GET "$ES_HOST/lab-docvalues/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_title_tokens": {
        "terms": {"field": "title_with_fielddata", "size": 10}
      }
    }
  }' | jq '.aggregations.by_title_tokens.buckets'
echo ""

# --------------------------------------------------------------
# STEP 7: doc_values=false 필드로 집계 - 에러
# --------------------------------------------------------------
echo ">>> [STEP 7] keyword(doc_values=false) 필드로 집계 시도 - 에러"
curl -s -X GET "$ES_HOST/lab-docvalues/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category_no_dv": {
        "terms": {"field": "category_no_docvalues"}
      }
    }
  }' | jq '.error.root_cause[0].reason'
echo ""

# --------------------------------------------------------------
# STEP 8: doc_values=false 필드 정렬 - 에러
# --------------------------------------------------------------
echo ">>> [STEP 8] doc_values=false 필드로 정렬 시도 - 에러"
curl -s -X GET "$ES_HOST/lab-docvalues/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "sort": [{"price_no_docvalues": "asc"}]
  }' | jq '.error.root_cause[0].reason'
echo ""

# --------------------------------------------------------------
# STEP 9: fielddata 메모리 현황 확인
# --------------------------------------------------------------
echo ">>> [STEP 9] fielddata 메모리 현황 확인"
echo "--- fielddata=true 필드를 집계한 후 메모리 사용량을 확인한다."
curl -s "$ES_HOST/_nodes/stats/indices/fielddata?fields=*" | jq '.nodes | to_entries[] | {node: .value.name, fielddata_memory: .value.indices.fielddata.memory_size}'
echo ""

echo ">>> fielddata 캐시 비우기"
curl -s -X POST "$ES_HOST/lab-docvalues/_cache/clear?fielddata=true" | jq .
echo ""

echo ">>> 캐시 비운 후 메모리 확인 (감소했는지 확인)"
curl -s "$ES_HOST/_nodes/stats/indices/fielddata?fields=*" | jq '.nodes | to_entries[] | {node: .value.name, fielddata_memory: .value.indices.fielddata.memory_size}'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 06-source-field.sh"
echo "============================================================"
