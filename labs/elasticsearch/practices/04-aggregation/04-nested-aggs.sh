#!/bin/bash
# ==============================================================
# 04-nested-aggs.sh
# 중첩 집계 실습 (버킷 안에 메트릭, 버킷 안에 버킷, top_hits)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="orders"

echo "============================================================"
echo "  04. 중첩 집계 (Nested Aggregations)"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- ES 집계는 계층적으로 중첩 가능"
echo "--- 버킷 집계 안에 메트릭 집계: 그룹별 통계"
echo "--- 버킷 집계 안에 버킷 집계: 다차원 분석"
echo ""

# --------------------------------------------------------------
# STEP 1: 버킷 + 메트릭 (가장 기본적인 중첩)
# --------------------------------------------------------------
echo ">>> [STEP 1] 카테고리별 평균 가격, 총 매출, 주문 수"
echo "--- SQL: SELECT category, COUNT(*), AVG(price), SUM(price) FROM orders GROUP BY category"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category", "size": 20},
        "aggs": {
          "avg_price":    {"avg":   {"field": "price"}},
          "total_revenue":{"sum":   {"field": "price"}},
          "max_price":    {"max":   {"field": "price"}},
          "order_count":  {"value_count": {"field": "order_id"}}
        }
      }
    }
  }' | jq '[.aggregations.by_category.buckets[] | {
    카테고리: .key,
    주문수: .doc_count,
    평균가: .avg_price.value,
    총매출: .total_revenue.value
  }] | sort_by(-.총매출)'
echo ""

# --------------------------------------------------------------
# STEP 2: 버킷 + 버킷 (2단계 중첩)
# --------------------------------------------------------------
echo ">>> [STEP 2] 지역 -> 카테고리 2단계 중첩 집계"
echo "--- SQL: SELECT region, category, COUNT(*) FROM orders GROUP BY region, category"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_region": {
        "terms": {"field": "region", "size": 10},
        "aggs": {
          "by_category": {
            "terms": {"field": "category", "size": 5},
            "aggs": {
              "category_revenue": {"sum": {"field": "price"}}
            }
          },
          "region_total": {"sum": {"field": "price"}}
        }
      }
    }
  }' | jq '[.aggregations.by_region.buckets[] | {
    지역: .key,
    주문수: .doc_count,
    지역총매출: .region_total.value,
    주요카테고리: [.by_category.buckets[:3][] | {카테고리: .key, 매출: .category_revenue.value}]
  }]'
echo ""

# --------------------------------------------------------------
# STEP 3: 버킷 + 버킷 + 메트릭 (3단계 중첩)
# --------------------------------------------------------------
echo ">>> [STEP 3] 월 -> 카테고리 -> 평균가격 3단계 중첩"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_month": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month",
          "format": "yyyy-MM"
        },
        "aggs": {
          "by_category": {
            "terms": {"field": "category", "size": 3, "order": {"_count": "desc"}},
            "aggs": {
              "avg_price": {"avg": {"field": "price"}}
            }
          }
        }
      }
    }
  }' | jq '[.aggregations.by_month.buckets[] | {
    월: .key_as_string,
    상위카테고리: [.by_category.buckets[] | {카테고리: .key, 주문수: .doc_count, 평균가: .avg_price.value}]
  }]'
echo ""

# --------------------------------------------------------------
# STEP 4: top_hits - 각 버킷의 상위 문서 가져오기
# --------------------------------------------------------------
echo ">>> [STEP 4] top_hits - 각 카테고리의 최고가 주문 문서"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category", "size": 5},
        "aggs": {
          "top_orders": {
            "top_hits": {
              "_source": ["order_id", "product", "price", "customer_name"],
              "sort": [{"price": "desc"}],
              "size": 2
            }
          }
        }
      }
    }
  }' | jq '[.aggregations.by_category.buckets[] | {
    카테고리: .key,
    최고가주문들: [.top_orders.hits.hits[]._source | {상품: .product, 가격: .price, 고객: .customer_name}]
  }]'
echo ""

# --------------------------------------------------------------
# STEP 5: global 집계 - 쿼리와 무관한 전체 집계
# --------------------------------------------------------------
echo ">>> [STEP 5] global 집계 - 쿼리 필터와 무관하게 전체 집계"
echo "--- 스마트폰 카테고리의 평균가격과 전체 평균가격을 동시에 비교"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"term": {"category": "스마트폰"}},
    "size": 0,
    "aggs": {
      "phone_avg":  {"avg": {"field": "price"}},
      "all_orders": {
        "global": {},
        "aggs": {
          "overall_avg": {"avg": {"field": "price"}}
        }
      }
    }
  }' | jq '{
    스마트폰평균가: .aggregations.phone_avg.value,
    전체평균가: .aggregations.all_orders.overall_avg.value
  }'
echo ""

# --------------------------------------------------------------
# STEP 6: filter 집계 - 집계 내 추가 필터
# --------------------------------------------------------------
echo ">>> [STEP 6] filter 집계 - 집계 내 추가 필터 조건"
echo "--- 전체 집계하면서 고가 상품(100만+)만 별도 집계"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "all_orders_count": {"value_count": {"field": "order_id"}},
      "premium_orders": {
        "filter": {"range": {"price": {"gte": 1000000}}},
        "aggs": {
          "count": {"value_count": {"field": "order_id"}},
          "avg_price": {"avg": {"field": "price"}}
        }
      },
      "budget_orders": {
        "filter": {"range": {"price": {"lt": 300000}}},
        "aggs": {
          "count": {"value_count": {"field": "order_id"}},
          "avg_price": {"avg": {"field": "price"}}
        }
      }
    }
  }' | jq '{
    전체주문수: .aggregations.all_orders_count.value,
    고가주문: {수: .aggregations.premium_orders.count.value, 평균가: .aggregations.premium_orders.avg_price.value},
    저가주문: {수: .aggregations.budget_orders.count.value, 평균가: .aggregations.budget_orders.avg_price.value}
  }'
echo ""

# --------------------------------------------------------------
# STEP 7: 실무 대시보드형 집계 - 종합 분석
# --------------------------------------------------------------
echo ">>> [STEP 7] 실무 종합 분석 - 대시보드 데이터 한번에 가져오기"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "total_stats": {
        "stats": {"field": "price"}
      },
      "total_quantity": {
        "sum": {"field": "quantity"}
      },
      "top5_categories": {
        "terms": {"field": "category", "size": 5, "order": {"revenue": "desc"}},
        "aggs": {
          "revenue": {"sum": {"field": "price"}},
          "avg_price": {"avg": {"field": "price"}}
        }
      },
      "monthly_trend": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month",
          "format": "yyyy-MM"
        },
        "aggs": {
          "revenue": {"sum": {"field": "price"}},
          "order_count": {"value_count": {"field": "order_id"}}
        }
      },
      "region_dist": {
        "terms": {"field": "region", "size": 10}
      },
      "payment_dist": {
        "terms": {"field": "payment_method", "size": 10}
      }
    }
  }' | jq '{
    전체통계: .aggregations.total_stats,
    총수량: .aggregations.total_quantity.value,
    상위카테고리: [.aggregations.top5_categories.buckets[] | {카테고리: .key, 매출: .revenue.value}],
    월별추이: [.aggregations.monthly_trend.buckets[] | {월: .key_as_string, 매출: .revenue.value, 주문수: .order_count.value}],
    지역분포: [.aggregations.region_dist.buckets[] | {지역: .key, 수: .doc_count}],
    결제방법: [.aggregations.payment_dist.buckets[] | {방법: .key, 수: .doc_count}]
  }'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  04-aggregation 실습 전체 완료!"
echo "  다음 실습: 05-cluster-operations/"
echo "============================================================"
