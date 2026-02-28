#!/bin/bash
# ==============================================================
# 02-term-query.sh
# Term, Terms Query 실습
# 관찰 포인트: 분석 없는 정확값 검색, text vs keyword
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  02. Term / Terms Query"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- term 쿼리: 검색어를 분석하지 않고 역색인과 정확히 비교"
echo "--- match 쿼리: 검색어를 분석 후 비교"
echo "--- keyword 필드에는 term, text 필드에는 match 사용이 원칙"
echo ""

# --------------------------------------------------------------
# STEP 1: term 쿼리 - keyword 필드 (정상)
# --------------------------------------------------------------
echo ">>> [STEP 1] term 쿼리 - keyword 필드 (brand)"
echo "--- brand는 keyword 타입, 분석 없이 저장됨"
echo "--- 'Samsung'으로 term 검색 -> Samsung 문서 매칭"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"brand": "Samsung"}},
    "_source": ["title", "brand"],
    "size": 5
  }' | jq '[.hits.hits[]._source | {brand, title}]'
echo ""

echo "--- 'samsung' 소문자로 term 검색 -> 0건 (keyword는 대소문자 구분)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"brand": "samsung"}},
    "_source": ["brand"]
  }' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 2: term 쿼리 - text 필드 (함정!)
# --------------------------------------------------------------
echo ">>> [STEP 2] term 쿼리 - text 필드 (title) 함정!"
echo "--- title은 text 타입으로 분석되어 저장됨"
echo "--- '삼성 갤럭시 S24 울트라 256GB' -> 토큰 단위로 분해되어 저장"
echo "--- term으로 '삼성 갤럭시 S24 울트라 256GB' 전체 검색 -> 0건!"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"title": "삼성 갤럭시 S24 울트라 256GB"}},
    "_source": ["title"]
  }' | jq '.hits.total.value'
echo ""

echo "--- term으로 개별 토큰 검색 -> 매칭됨 (하지만 match 쓰는 게 올바른 방법)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"title": "삼성"}},
    "_source": ["title"],
    "size": 3
  }' | jq '[.hits.hits[]._source.title]'
echo ""

echo "--- title.keyword 필드로 정확값 검색 (multi-field 활용)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"title.keyword": "삼성 갤럭시 S24 울트라 256GB"}},
    "_source": ["title"]
  }' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 3: terms 쿼리 - 여러 값 OR 검색
# --------------------------------------------------------------
echo ">>> [STEP 3] terms 쿼리 - 여러 값 OR 조건"
echo "--- brand가 Apple 또는 Sony인 상품 검색"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"terms": {"brand": ["Apple", "Sony"]}},
    "_source": ["title", "brand"],
    "size": 10
  }' | jq '[.hits.hits[]._source | {brand, title}]'
echo ""

# --------------------------------------------------------------
# STEP 4: terms 쿼리 - tags (배열 필드)
# --------------------------------------------------------------
echo ">>> [STEP 4] terms 쿼리 - tags 배열 필드 검색"
echo "--- tags에 '무선' 또는 'ANC'가 포함된 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"terms": {"tags": ["무선", "ANC"]}},
    "_source": ["title", "tags"],
    "size": 8
  }' | jq '[.hits.hits[]._source | {title, tags}]'
echo ""

# --------------------------------------------------------------
# STEP 5: ids 쿼리
# --------------------------------------------------------------
echo ">>> [STEP 5] ids 쿼리 - _id로 여러 문서 조회"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"ids": {"values": ["1", "5", "10"]}},
    "_source": ["title"]
  }' | jq '[.hits.hits[] | {id: ._id, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 6: fuzzy 쿼리 - 오타 허용
# --------------------------------------------------------------
echo ">>> [STEP 6] fuzzy 쿼리 - 오타 허용 검색"
echo "--- 'Samsumg' (오타) 로 Samsung 검색"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "fuzzy": {
        "brand": {
          "value": "Samsumg",
          "fuzziness": "AUTO"
        }
      }
    },
    "_source": ["brand", "title"],
    "size": 3
  }' | jq '[.hits.hits[]._source | {brand, title}]'
echo ""

# --------------------------------------------------------------
# STEP 7: wildcard 쿼리
# --------------------------------------------------------------
echo ">>> [STEP 7] wildcard 쿼리"
echo "--- brand가 'S'로 시작하는 모든 브랜드 (*=여러 문자)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"wildcard": {"brand": {"value": "S*"}}},
    "_source": ["brand"]
  }' | jq '[.hits.hits[]._source.brand] | unique'
echo ""

echo "--- title.keyword에 wildcard 사용 (주의: 성능 저하 가능)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"wildcard": {"title.keyword": {"value": "*무선*"}}},
    "_source": ["title"],
    "size": 5
  }' | jq '[.hits.hits[]._source.title]'
echo ""

# --------------------------------------------------------------
# STEP 8: regexp 쿼리
# --------------------------------------------------------------
echo ">>> [STEP 8] regexp 쿼리 - 정규식 검색"
echo "--- brand가 'Apple' 또는 'ASUS' (A로 시작)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"regexp": {"brand": "A.*"}},
    "_source": ["brand"]
  }' | jq '[.hits.hits[]._source.brand] | unique'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 03-bool-query.sh"
echo "============================================================"
