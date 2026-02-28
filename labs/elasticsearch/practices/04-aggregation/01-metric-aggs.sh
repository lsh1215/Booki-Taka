#!/bin/bash
# ==============================================================
# 01-metric-aggs.sh
# 메트릭 집계 실습 (avg, sum, min, max, stats, cardinality, percentiles)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="orders"

echo "============================================================"
echo "  01. 메트릭 집계 (Metric Aggregations)"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 메트릭 집계: 단일 숫자 값을 계산 (SQL의 집계 함수에 해당)"
echo "--- 버킷 없이 단독으로 사용하거나, 버킷 집계 내부에서 사용"
echo ""

# --------------------------------------------------------------
# STEP 1: avg, sum, min, max
# --------------------------------------------------------------
echo ">>> [STEP 1] 기본 메트릭 집계 (avg, sum, min, max)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "avg_price":    {"avg":    {"field": "price"}},
      "total_price":  {"sum":    {"field": "price"}},
      "min_price":    {"min":    {"field": "price"}},
      "max_price":    {"max":    {"field": "price"}}
    }
  }' | jq '.aggregations | {
    평균가격: .avg_price.value,
    총매출: .total_price.value,
    최소가격: .min_price.value,
    최대가격: .max_price.value
  }'
echo ""

# --------------------------------------------------------------
# STEP 2: 가중 평균 (weighted_avg) - 수량 고려한 실제 매출 평균
# --------------------------------------------------------------
echo ">>> [STEP 2] 가중 평균 - 수량을 가중치로 적용한 매출 단가"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "weighted_avg_price": {
        "weighted_avg": {
          "value":  {"field": "price"},
          "weight": {"field": "quantity"}
        }
      }
    }
  }' | jq '.aggregations.weighted_avg_price.value'
echo ""

# --------------------------------------------------------------
# STEP 3: stats - 여러 메트릭을 한번에
# --------------------------------------------------------------
echo ">>> [STEP 3] stats 집계 - count, min, max, avg, sum 한번에"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_stats":    {"stats": {"field": "price"}},
      "quantity_stats": {"stats": {"field": "quantity"}}
    }
  }' | jq '.aggregations'
echo ""

echo "--- extended_stats: variance, std_deviation 추가 포함"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_extended_stats": {"extended_stats": {"field": "price"}}
    }
  }' | jq '.aggregations.price_extended_stats'
echo ""

# --------------------------------------------------------------
# STEP 4: cardinality - 고유값 수 (근사값)
# --------------------------------------------------------------
echo ">>> [STEP 4] cardinality 집계 - 고유값 수 (HyperLogLog++ 알고리즘, 근사값)"
echo "--- 고객 수, 고유 상품 수, 지역 수 파악"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "unique_customers":   {"cardinality": {"field": "customer_name"}},
      "unique_products":    {"cardinality": {"field": "product"}},
      "unique_regions":     {"cardinality": {"field": "region"}},
      "unique_categories":  {"cardinality": {"field": "category"}}
    }
  }' | jq '.aggregations | {
    고유고객수: .unique_customers.value,
    고유상품수: .unique_products.value,
    지역수: .unique_regions.value,
    카테고리수: .unique_categories.value
  }'
echo ""

echo "--- precision_threshold로 정확도 향상 (메모리 사용 증가)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "unique_customers_precise": {
        "cardinality": {
          "field": "customer_name",
          "precision_threshold": 40000
        }
      }
    }
  }' | jq '.aggregations.unique_customers_precise.value'
echo ""

# --------------------------------------------------------------
# STEP 5: percentiles - 백분위수
# --------------------------------------------------------------
echo ">>> [STEP 5] percentiles 집계 - 백분위수"
echo "--- P50(중앙값), P95, P99로 분포 파악"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_percentiles": {
        "percentiles": {
          "field": "price",
          "percents": [25, 50, 75, 90, 95, 99]
        }
      }
    }
  }' | jq '.aggregations.price_percentiles.values'
echo ""

# --------------------------------------------------------------
# STEP 6: percentile_ranks - 특정 값의 백분위 확인
# --------------------------------------------------------------
echo ">>> [STEP 6] percentile_ranks - 특정 가격이 전체에서 몇 %에 해당하는가"
echo "--- 50만원, 100만원, 200만원이 각각 전체 주문의 몇 %에 해당하는가"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "price_ranks": {
        "percentile_ranks": {
          "field": "price",
          "values": [500000, 1000000, 2000000]
        }
      }
    }
  }' | jq '.aggregations.price_ranks.values'
echo ""

# --------------------------------------------------------------
# STEP 7: top_metrics - 특정 기준의 상위 문서 메트릭
# --------------------------------------------------------------
echo ">>> [STEP 7] top_metrics - 최고/최저 가격 주문 정보"
echo "--- 가격이 가장 높은 주문의 order_id와 product"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "top_order": {
        "top_metrics": {
          "metrics": [
            {"field": "order_id"},
            {"field": "product"}
          ],
          "sort": {"price": "desc"},
          "size": 3
        }
      }
    }
  }' | jq '.aggregations.top_order.top'
echo ""

# --------------------------------------------------------------
# STEP 8: 쿼리와 메트릭 조합
# --------------------------------------------------------------
echo ">>> [STEP 8] 특정 카테고리 필터 + 메트릭 집계"
echo "--- 스마트폰 카테고리의 평균/최대/최소 가격"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"category": "스마트폰"}},
    "size": 0,
    "aggs": {
      "phone_stats": {"stats": {"field": "price"}}
    }
  }' | jq '.aggregations.phone_stats'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 02-bucket-aggs.sh"
echo "============================================================"
