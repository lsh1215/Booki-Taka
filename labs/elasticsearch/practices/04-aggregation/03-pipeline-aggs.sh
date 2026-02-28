#!/bin/bash
# ==============================================================
# 03-pipeline-aggs.sh
# 파이프라인 집계 실습 (derivative, cumulative_sum, avg_bucket)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="orders"

echo "============================================================"
echo "  03. 파이프라인 집계 (Pipeline Aggregations)"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 파이프라인 집계: 다른 집계의 출력을 입력으로 사용"
echo "--- 부모 파이프라인: 상위 버킷 집계 내에서 계산"
echo "--- 형제 파이프라인: 동일 레벨의 버킷 집계 결과를 입력으로 사용"
echo ""

# --------------------------------------------------------------
# STEP 1: derivative - 전월 대비 증감
# --------------------------------------------------------------
echo ">>> [STEP 1] derivative - 월별 주문 수의 전월 대비 증감"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "monthly": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month",
          "format": "yyyy-MM"
        },
        "aggs": {
          "monthly_count": {
            "value_count": {"field": "order_id"}
          },
          "monthly_sum": {
            "sum": {"field": "price"}
          },
          "count_derivative": {
            "derivative": {"buckets_path": "monthly_count"}
          },
          "sum_derivative": {
            "derivative": {"buckets_path": "monthly_sum"}
          }
        }
      }
    }
  }' | jq '[.aggregations.monthly.buckets[] | {
    월: .key_as_string,
    주문수: .monthly_count.value,
    전월대비주문: .count_derivative.value,
    매출합계: .monthly_sum.value,
    전월대비매출: .sum_derivative.value
  }]'
echo ""

# --------------------------------------------------------------
# STEP 2: cumulative_sum - 누적 합계
# --------------------------------------------------------------
echo ">>> [STEP 2] cumulative_sum - 월별 누적 매출"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "monthly": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month",
          "format": "yyyy-MM"
        },
        "aggs": {
          "monthly_revenue": {
            "sum": {"field": "price"}
          },
          "cumulative_revenue": {
            "cumulative_sum": {"buckets_path": "monthly_revenue"}
          }
        }
      }
    }
  }' | jq '[.aggregations.monthly.buckets[] | {
    월: .key_as_string,
    월매출: .monthly_revenue.value,
    누적매출: .cumulative_revenue.value
  }]'
echo ""

# --------------------------------------------------------------
# STEP 3: moving_avg (moving_fn) - 이동 평균
# --------------------------------------------------------------
echo ">>> [STEP 3] moving_fn - 3개월 이동 평균"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "monthly": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month",
          "format": "yyyy-MM"
        },
        "aggs": {
          "monthly_revenue": {
            "sum": {"field": "price"}
          },
          "moving_avg_3m": {
            "moving_fn": {
              "buckets_path": "monthly_revenue",
              "window": 3,
              "script": "MovingFunctions.unweightedAvg(values)"
            }
          }
        }
      }
    }
  }' | jq '[.aggregations.monthly.buckets[] | {
    월: .key_as_string,
    월매출: .monthly_revenue.value,
    이동평균3M: .moving_avg_3m.value
  }]'
echo ""

# --------------------------------------------------------------
# STEP 4: avg_bucket - 형제 집계 평균
# --------------------------------------------------------------
echo ">>> [STEP 4] avg_bucket - 카테고리별 평균 매출 중 전체 평균"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category", "size": 20},
        "aggs": {
          "category_revenue": {"sum": {"field": "price"}}
        }
      },
      "avg_category_revenue": {
        "avg_bucket": {"buckets_path": "by_category>category_revenue"}
      }
    }
  }' | jq '{
    카테고리별매출: [.aggregations.by_category.buckets[] | {카테고리: .key, 매출: .category_revenue.value}],
    카테고리평균매출: .aggregations.avg_category_revenue.value
  }'
echo ""

# --------------------------------------------------------------
# STEP 5: max_bucket - 최고 매출 카테고리
# --------------------------------------------------------------
echo ">>> [STEP 5] max_bucket / min_bucket - 최고/최저 매출 카테고리"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category", "size": 20},
        "aggs": {
          "category_revenue": {"sum": {"field": "price"}}
        }
      },
      "top_category": {
        "max_bucket": {"buckets_path": "by_category>category_revenue"}
      },
      "bottom_category": {
        "min_bucket": {"buckets_path": "by_category>category_revenue"}
      }
    }
  }' | jq '{
    최고매출카테고리: .aggregations.top_category,
    최저매출카테고리: .aggregations.bottom_category
  }'
echo ""

# --------------------------------------------------------------
# STEP 6: sum_bucket - 형제 집계 합계
# --------------------------------------------------------------
echo ">>> [STEP 6] sum_bucket - 월별 매출 총합 (집계로 검증)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "monthly": {
        "date_histogram": {
          "field": "order_date",
          "calendar_interval": "month"
        },
        "aggs": {
          "monthly_revenue": {"sum": {"field": "price"}}
        }
      },
      "total_revenue": {
        "sum_bucket": {"buckets_path": "monthly>monthly_revenue"}
      }
    }
  }' | jq '.aggregations.total_revenue.value'
echo ""

# --------------------------------------------------------------
# STEP 7: bucket_sort - 집계 결과 정렬/페이지
# --------------------------------------------------------------
echo ">>> [STEP 7] bucket_sort - 집계 결과 정렬 및 페이지네이션"
echo "--- 카테고리별 매출 상위 5개, 파이프라인 정렬"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_category": {
        "terms": {"field": "category", "size": 20},
        "aggs": {
          "category_revenue": {"sum": {"field": "price"}},
          "revenue_sort": {
            "bucket_sort": {
              "sort": [{"category_revenue": {"order": "desc"}}],
              "size": 5
            }
          }
        }
      }
    }
  }' | jq '[.aggregations.by_category.buckets[] | {카테고리: .key, 매출: .category_revenue.value}]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 04-nested-aggs.sh"
echo "============================================================"
