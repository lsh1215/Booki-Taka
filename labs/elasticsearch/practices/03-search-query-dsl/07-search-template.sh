#!/bin/bash
# ==============================================================
# 07-search-template.sh
# 검색 템플릿(Search Template) 실습
# 관찰 포인트: Mustache 템플릿, 재사용 가능한 쿼리 패턴
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  07. 검색 템플릿"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 검색 템플릿: Mustache 문법으로 파라미터화된 쿼리를 저장"
echo "--- 장점: 애플리케이션에서 쿼리 로직 분리, ES에서 쿼리 관리"
echo "--- 사용 사례: 복잡한 쿼리 재사용, A/B 테스트, 쿼리 버전 관리"
echo ""

# --------------------------------------------------------------
# STEP 1: 검색 템플릿 저장
# --------------------------------------------------------------
echo ">>> [STEP 1] 검색 템플릿 저장 - 기본 상품 검색 템플릿"
curl -s -X PUT "$ES_HOST/_scripts/product-search-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "script": {
      "lang": "mustache",
      "source": {
        "query": {
          "bool": {
            "must": [
              {
                "{{#keyword}}multi_match{{/keyword}}{{^keyword}}match_all{{/keyword}}": {
                  "{{#keyword}}query{{/keyword}}": "{{keyword}}",
                  "{{#keyword}}fields{{/keyword}}": ["{{#keyword}}title^3{{/keyword}}", "{{#keyword}}description{{/keyword}}"]
                }
              }
            ],
            "filter": [
              "{{#category}}{\"term\": {\"category\": \"{{category}}\"}}{{/category}}",
              "{{#in_stock}}{\"term\": {\"in_stock\": {{in_stock}}}}{{/in_stock}}",
              "{{#max_price}}{\"range\": {\"price\": {\"lte\": {{max_price}}}}}{{/max_price}}",
              "{{#min_price}}{\"range\": {\"price\": {\"gte\": {{min_price}}}}}{{/min_price}}"
            ]
          }
        },
        "size": "{{size}}{{^size}}10{{/size}}",
        "from": "{{from}}{{^from}}0{{/from}}",
        "sort": [
          {"{{sort_field}}{{^sort_field}}_score{{/sort_field}}": "{{sort_order}}{{^sort_order}}desc{{/sort_order}}"}
        ]
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 단순한 템플릿 (기본 상품 검색)
# --------------------------------------------------------------
echo ">>> [STEP 2] 단순 검색 템플릿 저장"
curl -s -X PUT "$ES_HOST/_scripts/simple-product-search" \
  -H 'Content-Type: application/json' \
  -d '{
    "script": {
      "lang": "mustache",
      "source": {
        "query": {
          "bool": {
            "must": [
              {
                "match": {
                  "title": "{{query}}"
                }
              }
            ],
            "filter": [
              {"term": {"in_stock": true}},
              {"range": {"price": {"gte": "{{min_price}}{{^min_price}}0{{/min_price}}", "lte": "{{max_price}}{{^max_price}}99999999{{/max_price}}"}}}
            ]
          }
        },
        "_source": ["title", "price", "brand", "category", "rating"],
        "size": "{{size}}{{^size}}10{{/size}}",
        "sort": [{"price": "asc"}]
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 카테고리 필터 템플릿
# --------------------------------------------------------------
echo ">>> [STEP 3] 카테고리 필터 + 정렬 템플릿"
curl -s -X PUT "$ES_HOST/_scripts/category-filter-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "script": {
      "lang": "mustache",
      "source": {
        "query": {
          "bool": {
            "filter": [
              {"term": {"category": "{{category}}"}},
              {"term": {"in_stock": true}}
            ]
          }
        },
        "_source": ["title", "price", "brand", "rating"],
        "size": "{{size}}{{^size}}10{{/size}}",
        "sort": [
          {"{{sort_by}}{{^sort_by}}rating{{/sort_by}}": "{{order}}{{^order}}desc{{/order}}"}
        ]
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 4: 저장된 템플릿 목록 확인
# --------------------------------------------------------------
echo ">>> [STEP 4] 저장된 검색 템플릿 확인"
curl -s "$ES_HOST/_scripts/simple-product-search" | jq '.script.source'
echo ""

# --------------------------------------------------------------
# STEP 5: 템플릿으로 검색 실행
# --------------------------------------------------------------
echo ">>> [STEP 5] simple-product-search 템플릿으로 검색"
echo "--- 키워드: '갤럭시', 최대 가격: 1,500,000"
curl -s -X GET "$ES_HOST/$INDEX/_search/template" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "simple-product-search",
    "params": {
      "query": "갤럭시",
      "max_price": 1500000,
      "size": 5
    }
  }' | jq '[.hits.hits[]._source | {title, price, brand}]'
echo ""

echo "--- 키워드: '무선', 가격 범위: 100,000 ~ 400,000"
curl -s -X GET "$ES_HOST/$INDEX/_search/template" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "simple-product-search",
    "params": {
      "query": "무선",
      "min_price": 100000,
      "max_price": 400000
    }
  }' | jq '[.hits.hits[]._source | {title, price}]'
echo ""

# --------------------------------------------------------------
# STEP 6: category-filter-template 사용
# --------------------------------------------------------------
echo ">>> [STEP 6] category-filter-template으로 카테고리 검색"
echo "--- 스마트폰 카테고리, 가격 오름차순"
curl -s -X GET "$ES_HOST/$INDEX/_search/template" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "category-filter-template",
    "params": {
      "category": "스마트폰",
      "sort_by": "price",
      "order": "asc",
      "size": 5
    }
  }' | jq '[.hits.hits[]._source | {title, price, rating}]'
echo ""

# --------------------------------------------------------------
# STEP 7: render 기능으로 템플릿 미리보기
# --------------------------------------------------------------
echo ">>> [STEP 7] 템플릿 렌더링 미리보기 (실제 쿼리 확인)"
curl -s -X POST "$ES_HOST/_render/template" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "simple-product-search",
    "params": {
      "query": "노트북",
      "max_price": 2000000,
      "size": 3
    }
  }' | jq '.template_output'
echo ""

# --------------------------------------------------------------
# STEP 8: 인라인 템플릿 (저장 없이 즉시 사용)
# --------------------------------------------------------------
echo ">>> [STEP 8] 인라인 템플릿 (저장 없이 직접 실행)"
curl -s -X GET "$ES_HOST/$INDEX/_search/template" \
  -H 'Content-Type: application/json' \
  -d '{
    "source": {
      "query": {
        "bool": {
          "filter": [
            {"term": {"brand": "{{brand}}"}},
            {"range": {"rating": {"gte": "{{min_rating}}"}}}
          ]
        }
      },
      "_source": ["title", "brand", "rating"],
      "sort": [{"rating": "desc"}],
      "size": "{{size}}"
    },
    "params": {
      "brand": "Apple",
      "min_rating": 4.5,
      "size": 5
    }
  }' | jq '[.hits.hits[]._source | {brand, rating, title}]'
echo ""

# --------------------------------------------------------------
# STEP 9: 템플릿 삭제
# --------------------------------------------------------------
echo ">>> [STEP 9] 실습 템플릿 정리"
curl -s -X DELETE "$ES_HOST/_scripts/simple-product-search" | jq .
curl -s -X DELETE "$ES_HOST/_scripts/category-filter-template" | jq .
curl -s -X DELETE "$ES_HOST/_scripts/product-search-template" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  03-search-query-dsl 실습 전체 완료!"
echo "  다음 실습: 04-aggregation/"
echo "============================================================"
