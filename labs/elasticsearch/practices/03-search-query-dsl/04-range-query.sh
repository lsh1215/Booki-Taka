#!/bin/bash
# ==============================================================
# 04-range-query.sh
# Range Query 실습 (숫자, 날짜 범위 검색)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  04. Range Query"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 숫자 범위 검색
# --------------------------------------------------------------
echo ">>> [STEP 1] 가격 범위 검색 (integer 필드)"
echo "--- gte: 이상, gt: 초과, lte: 이하, lt: 미만"

echo "--- 50만원 ~ 100만원 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "price": {"gte": 500000, "lte": 1000000}
      }
    },
    "_source": ["title", "price"],
    "sort": [{"price": "asc"}]
  }' | jq '[.hits.hits[]._source | {title, price}]'
echo ""

echo "--- 100만원 이상 상품 (lte 없음)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"range": {"price": {"gte": 1000000}}},
    "_source": ["title", "price"],
    "sort": [{"price": "asc"}],
    "size": 5
  }' | jq '[.hits.hits[]._source | {title, price}]'
echo ""

# --------------------------------------------------------------
# STEP 2: 평점 범위 검색 (float 필드)
# --------------------------------------------------------------
echo ">>> [STEP 2] 평점 범위 검색 (float 필드)"
echo "--- 평점 4.5 이상인 프리미엄 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"range": {"rating": {"gte": 4.5}}},
    "_source": ["title", "rating"],
    "sort": [{"rating": "desc"}]
  }' | jq '[.hits.hits[]._source | {rating, title}]'
echo ""

# --------------------------------------------------------------
# STEP 3: 날짜 범위 검색
# --------------------------------------------------------------
echo ">>> [STEP 3] 날짜 범위 검색 (date 필드)"
echo "--- 2023년에 등록된 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "created_at": {
          "gte": "2023-01-01",
          "lte": "2023-12-31",
          "format": "yyyy-MM-dd"
        }
      }
    },
    "_source": ["title", "created_at"],
    "sort": [{"created_at": "asc"}]
  }' | jq '[.hits.hits[]._source | {created_at, title}]'
echo ""

echo "--- 2024년 이후 등록된 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "created_at": {
          "gte": "2024-01-01",
          "format": "yyyy-MM-dd"
        }
      }
    },
    "_source": ["title", "created_at"],
    "sort": [{"created_at": "desc"}]
  }' | jq '[.hits.hits[]._source | {created_at, title}]'
echo ""

# --------------------------------------------------------------
# STEP 4: 날짜 수식 (Date Math)
# --------------------------------------------------------------
echo ">>> [STEP 4] 날짜 수식 (Date Math)"
echo "--- now: 현재 시각"
echo "--- now-1y: 1년 전, now-6M: 6개월 전, now-30d: 30일 전"
echo "--- /d: 일 단위로 반올림, /M: 월 단위로 반올림"

echo "--- 최근 2년 이내 등록된 상품 (now-2y 이후)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "created_at": {
          "gte": "now-2y/d"
        }
      }
    },
    "_source": ["title", "created_at"],
    "sort": [{"created_at": "asc"}]
  }' | jq '.hits.total.value'
echo ""

echo "--- 특정 날짜 기준 상대적 범위: 2024-01-01 로부터 30일 이내"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "created_at": {
          "gte": "2024-01-01",
          "lte": "2024-01-01||+30d",
          "format": "yyyy-MM-dd"
        }
      }
    },
    "_source": ["title", "created_at"],
    "sort": [{"created_at": "asc"}]
  }' | jq '[.hits.hits[]._source | {created_at, title}]'
echo ""

# --------------------------------------------------------------
# STEP 5: range + bool 조합 (실무 패턴)
# --------------------------------------------------------------
echo ">>> [STEP 5] range + bool 조합 - 실무 검색 패턴"
echo "--- 조건: 가격 20만~50만원, 평점 4.3 이상, 재고 있음"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "filter": [
          {"range": {"price": {"gte": 200000, "lte": 500000}}},
          {"range": {"rating": {"gte": 4.3}}},
          {"term": {"in_stock": true}}
        ]
      }
    },
    "_source": ["title", "price", "rating", "category"],
    "sort": [{"rating": "desc"}, {"price": "asc"}]
  }' | jq '[.hits.hits[]._source | {rating, price, category, title}]'
echo ""

# --------------------------------------------------------------
# STEP 6: 범위 집계와 함께 사용
# --------------------------------------------------------------
echo ">>> [STEP 6] 가격대별 상품 수 집계"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_ranges": {
        "range": {
          "field": "price",
          "ranges": [
            {"key": "10만원 미만",    "to": 100000},
            {"key": "10-50만원",     "from": 100000, "to": 500000},
            {"key": "50-100만원",    "from": 500000, "to": 1000000},
            {"key": "100-200만원",   "from": 1000000, "to": 2000000},
            {"key": "200만원 이상",   "from": 2000000}
          ]
        }
      }
    }
  }' | jq '.aggregations.price_ranges.buckets[] | {범위: .key, 상품수: .doc_count}'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 05-prefix-exists.sh"
echo "============================================================"
