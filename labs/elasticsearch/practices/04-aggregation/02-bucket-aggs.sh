#!/bin/bash
# ==============================================================
# 02-bucket-aggs.sh
# 버킷 집계 실습 (terms, range, histogram, date_histogram, filters)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="orders"

echo "============================================================"
echo "  02. 버킷 집계 (Bucket Aggregations)"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 버킷 집계: 문서를 그룹으로 분류 (SQL의 GROUP BY에 해당)"
echo "--- 각 버킷에는 해당 문서들이 포함되며, 하위 집계 가능"
echo ""

# --------------------------------------------------------------
# STEP 1: terms - 카테고리별 주문 수
# --------------------------------------------------------------
echo ">>> [STEP 1] terms 집계 - 카테고리별 주문 수"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {
          "field": "category",
          "size": 20,
          "order": {"_count": "desc"}
        }
      }
    }
  }' | jq '[.aggregations.by_category.buckets[] | {카테고리: .key, 주문수: .doc_count}]'
echo ""

echo "--- 결과에서 sum_other_doc_count 확인 (size보다 많은 버킷이 있을 때)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category_top3": {
        "terms": {"field": "category", "size": 3}
      }
    }
  }' | jq '.aggregations.by_category_top3 | {
    buckets: [.buckets[] | {key, doc_count}],
    sum_other: .sum_other_doc_count,
    error_bound: .doc_count_error_upper_bound
  }'
echo ""

# --------------------------------------------------------------
# STEP 2: terms - 지역별, 결제수단별
# --------------------------------------------------------------
echo ">>> [STEP 2] 지역별, 결제수단별 집계"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_region": {
        "terms": {"field": "region", "size": 10}
      },
      "by_payment": {
        "terms": {"field": "payment_method", "size": 10}
      }
    }
  }' | jq '{
    지역별: [.aggregations.by_region.buckets[] | {지역: .key, 주문수: .doc_count}],
    결제수단별: [.aggregations.by_payment.buckets[] | {결제: .key, 주문수: .doc_count}]
  }'
echo ""

# --------------------------------------------------------------
# STEP 3: range - 가격대별 분류
# --------------------------------------------------------------
echo ">>> [STEP 3] range 집계 - 가격대별 분류"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_range": {
        "range": {
          "field": "price",
          "ranges": [
            {"key": "10만원 미만",   "to": 100000},
            {"key": "10-50만원",    "from": 100000, "to": 500000},
            {"key": "50-100만원",   "from": 500000, "to": 1000000},
            {"key": "100-200만원",  "from": 1000000, "to": 2000000},
            {"key": "200만원 이상",  "from": 2000000}
          ]
        }
      }
    }
  }' | jq '[.aggregations.price_range.buckets[] | {가격대: .key, 주문수: .doc_count}]'
echo ""

# --------------------------------------------------------------
# STEP 4: date_range - 날짜 범위 분류
# --------------------------------------------------------------
echo ">>> [STEP 4] date_range 집계 - 분기별 주문"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "quarterly": {
        "date_range": {
          "field": "order_date",
          "format": "yyyy-MM-dd",
          "ranges": [
            {"key": "Q1 2024", "from": "2024-01-01", "to": "2024-04-01"},
            {"key": "Q2 2024", "from": "2024-04-01", "to": "2024-07-01"},
            {"key": "Q3 2024", "from": "2024-07-01", "to": "2024-10-01"},
            {"key": "Q4 2024", "from": "2024-10-01", "to": "2025-01-01"}
          ]
        }
      }
    }
  }' | jq '[.aggregations.quarterly.buckets[] | {분기: .key, 주문수: .doc_count}]'
echo ""

# --------------------------------------------------------------
# STEP 5: histogram - 가격 분포
# --------------------------------------------------------------
echo ">>> [STEP 5] histogram 집계 - 50만원 단위 가격 분포"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_histogram": {
        "histogram": {
          "field": "price",
          "interval": 500000,
          "min_doc_count": 0,
          "extended_bounds": {"min": 0, "max": 3500000}
        }
      }
    }
  }' | jq '[.aggregations.price_histogram.buckets[] | {가격구간: .key, 주문수: .doc_count}]'
echo ""

# --------------------------------------------------------------
# STEP 6: date_histogram - 월별 주문 추이
# --------------------------------------------------------------
echo ">>> [STEP 6] date_histogram 집계 - 월별 주문 추이"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "monthly_orders": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month",
          "format": "yyyy-MM",
          "min_doc_count": 0
        }
      }
    }
  }' | jq '[.aggregations.monthly_orders.buckets[] | {월: .key_as_string, 주문수: .doc_count}]'
echo ""

echo "--- fixed_interval: 정확한 시간 간격"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_30days": {
        "date_histogram": {
          "field": "order_date",
          "fixed_interval": "30d",
          "format": "yyyy-MM-dd"
        }
      }
    }
  }' | jq '.aggregations.by_30days.buckets | length'
echo ""

# --------------------------------------------------------------
# STEP 7: filters - 여러 필터 조건으로 버킷 생성
# --------------------------------------------------------------
echo ">>> [STEP 7] filters 집계 - 여러 필터 조건으로 버킷 분류"
echo "--- 고가/중가/저가 상품으로 분류"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_segments": {
        "filters": {
          "filters": {
            "고가(100만+)":  {"range": {"price": {"gte": 1000000}}},
            "중가(30-100만)": {"range": {"price": {"gte": 300000, "lt": 1000000}}},
            "저가(30만 미만)": {"range": {"price": {"lt": 300000}}}
          }
        }
      }
    }
  }' | jq '.aggregations.price_segments.buckets'
echo ""

# --------------------------------------------------------------
# STEP 8: sampler - 샘플링 집계 (성능 최적화)
# --------------------------------------------------------------
echo ">>> [STEP 8] sampler 집계 - 상위 N건만 샘플링하여 집계"
echo "--- 전체 집계보다 빠른 근사 결과 (대용량 데이터에 유용)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "sample": {
        "sampler": {
          "shard_size": 50
        },
        "aggs": {
          "category_sample": {
            "terms": {"field": "category"}
          }
        }
      }
    }
  }' | jq '[.aggregations.sample.category_sample.buckets[] | {카테고리: .key, 수: .doc_count}]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 03-pipeline-aggs.sh"
echo "============================================================"
