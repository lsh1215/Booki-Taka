#!/bin/bash
# ==============================================================
# 06-source-field.sh
# _source 필드 활용 실습
# 관찰 포인트: _source disable/enable, includes/excludes 필터링
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  06. _source 필드 활용 실습"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- _source: ES가 색인할 때 원본 JSON 문서를 저장하는 특수 필드"
echo "--- 비활성화하면 디스크 공간을 절약하지만, 문서 조회/업데이트/reindex에 제한이 생긴다"
echo "--- 부분 활성화(includes/excludes)로 일부 필드만 저장할 수 있다"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-source-enabled" | jq .
curl -s -X DELETE "$ES_HOST/lab-source-disabled" | jq .
curl -s -X DELETE "$ES_HOST/lab-source-partial" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: _source 활성화 인덱스 (기본값)
# --------------------------------------------------------------
echo ">>> [STEP 2] _source 활성화 인덱스 생성 (기본값)"
curl -s -X PUT "$ES_HOST/lab-source-enabled" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "_source": {"enabled": true},
      "properties": {
        "name":     {"type": "keyword"},
        "password": {"type": "keyword"},
        "email":    {"type": "keyword"},
        "age":      {"type": "integer"}
      }
    }
  }' | jq .
echo ""

curl -s -X POST "$ES_HOST/lab-source-enabled/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{"name": "홍길동", "password": "secret123", "email": "hong@example.com", "age": 30}' | jq .result

sleep 1

echo ">>> _source 활성화 인덱스 문서 조회 - 전체 원본 반환"
curl -s "$ES_HOST/lab-source-enabled/_doc/1" | jq '._source'
echo ""

# --------------------------------------------------------------
# STEP 3: _source 비활성화 인덱스
# --------------------------------------------------------------
echo ">>> [STEP 3] _source 비활성화 인덱스 생성"
echo "--- 로그 데이터처럼 원본 조회가 필요 없고 집계만 하는 경우 사용"
curl -s -X PUT "$ES_HOST/lab-source-disabled" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "_source": {"enabled": false},
      "properties": {
        "name":  {"type": "keyword"},
        "score": {"type": "integer"}
      }
    }
  }' | jq .
echo ""

curl -s -X POST "$ES_HOST/lab-source-disabled/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{"name": "테스트", "score": 100}' | jq .result

sleep 1

echo ">>> _source 비활성화 인덱스 문서 조회 - _source가 비어있다"
curl -s "$ES_HOST/lab-source-disabled/_doc/1" | jq '._source'
echo ""

echo ">>> _source 없이도 검색 자체는 가능 (매핑/인덱스 구조는 남아있음)"
curl -s -X GET "$ES_HOST/lab-source-disabled/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"name": "테스트"}}}' | jq '.hits.hits[] | {_id, _source}'
echo ""

echo ">>> _source 비활성화 상태에서 문서 업데이트 시도 (에러 예상)"
curl -s -X POST "$ES_HOST/lab-source-disabled/_update/1" \
  -H 'Content-Type: application/json' \
  -d '{"doc": {"score": 200}}' | jq '.error.root_cause[0].reason'
echo ""

# --------------------------------------------------------------
# STEP 4: _source 부분 활성화 (includes/excludes)
# --------------------------------------------------------------
echo ">>> [STEP 4] _source 부분 활성화 - 민감 정보(password) 제외"
curl -s -X PUT "$ES_HOST/lab-source-partial" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "_source": {
        "includes": ["name", "email", "age"],
        "excludes": ["password", "secret_*"]
      },
      "properties": {
        "name":           {"type": "keyword"},
        "password":       {"type": "keyword"},
        "email":          {"type": "keyword"},
        "age":            {"type": "integer"},
        "secret_token":   {"type": "keyword"}
      }
    }
  }' | jq .
echo ""

curl -s -X POST "$ES_HOST/lab-source-partial/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "이순신",
    "password": "supersecret",
    "email": "lee@example.com",
    "age": 45,
    "secret_token": "tok_abc123"
  }' | jq .result

sleep 1

echo ">>> 부분 _source 문서 조회 - password, secret_token은 저장되지 않음"
curl -s "$ES_HOST/lab-source-partial/_doc/1" | jq '._source'
echo ""

# --------------------------------------------------------------
# STEP 5: 검색 시 _source 필터링 (저장은 했지만 반환만 필터)
# --------------------------------------------------------------
echo ">>> [STEP 5] 검색 시 _source 필터링 (_source_includes/_source_excludes)"
echo "--- 인덱스 설정과 별개로, 검색 쿼리에서도 반환할 필드를 필터링할 수 있다."
curl -s -X GET "$ES_HOST/lab-source-enabled/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "_source": {
      "includes": ["name", "email"],
      "excludes": ["password"]
    },
    "query": {"match_all": {}}
  }' | jq '.hits.hits[]._source'
echo ""

echo ">>> _source: false 로 _source 전체 제외 (검색은 되지만 원본 미반환)"
curl -s -X GET "$ES_HOST/lab-source-enabled/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "_source": false,
    "query": {"match_all": {}}
  }' | jq '.hits.hits[] | {_id, _source}'
echo ""

# --------------------------------------------------------------
# STEP 6: stored_fields 활용
# --------------------------------------------------------------
echo ">>> [STEP 6] stored_fields 활용 - 특정 필드만 저장 선언"
echo "--- _source와 별개로 특정 필드를 store: true로 개별 저장 가능"
curl -s -X DELETE "$ES_HOST/lab-stored-field" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-stored-field" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "_source": {"enabled": false},
      "properties": {
        "title":   {"type": "text", "store": true},
        "content": {"type": "text", "store": false},
        "author":  {"type": "keyword", "store": true}
      }
    }
  }' | jq .

curl -s -X POST "$ES_HOST/lab-stored-field/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{"title": "ES 학습 노트", "content": "세부 내용...", "author": "홍길동"}' | jq .result

sleep 1

echo ">>> stored_fields로 특정 필드만 조회 (_source=false이지만 store=true 필드는 반환)"
curl -s -X GET "$ES_HOST/lab-stored-field/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "stored_fields": ["title", "author"],
    "query": {"match_all": {}}
  }' | jq '.hits.hits[] | {fields}'
echo ""

curl -s -X DELETE "$ES_HOST/lab-stored-field" | jq . > /dev/null

echo "============================================================"
echo "  실습 완료"
echo "  01-index-and-mapping 실습 전체 완료!"
echo "  다음 실습: 02-analyzer/"
echo "============================================================"
