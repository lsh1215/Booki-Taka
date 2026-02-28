#!/bin/bash
# ==============================================================
# 03-bool-query.sh
# Bool Query 실습 (must, should, filter, must_not)
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  03. Bool Query"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- must:     AND 조건, 스코어에 영향"
echo "--- should:   OR 조건, 스코어에 영향, minimum_should_match로 제어"
echo "--- filter:   AND 조건, 스코어에 영향 없음, 캐싱 대상"
echo "--- must_not: NOT 조건, 스코어에 영향 없음"
echo ""

# --------------------------------------------------------------
# STEP 1: must - AND 조건
# --------------------------------------------------------------
echo ">>> [STEP 1] must - 모든 조건 만족 (AND)"
echo "--- 카테고리가 스마트폰이고, 제목에 갤럭시가 포함된 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"term": {"category": "스마트폰"}},
          {"match": {"title": "갤럭시"}}
        ]
      }
    },
    "_source": ["title", "category", "brand"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 2: filter - 스코어 영향 없는 AND
# --------------------------------------------------------------
echo ">>> [STEP 2] filter - 스코어 영향 없음, 캐싱 최적화"
echo "--- 재고가 있고(in_stock=true), 브랜드가 Samsung인 상품 검색"
echo "--- filter 절은 스코어에 기여하지 않으므로 모든 결과의 _score가 같다"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "filter": [
          {"term": {"in_stock": true}},
          {"term": {"brand": "Samsung"}}
        ]
      }
    },
    "_source": ["title", "brand", "in_stock"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 3: must + filter 조합 (실무 패턴)
# --------------------------------------------------------------
echo ">>> [STEP 3] must + filter 조합 (실무에서 가장 많이 사용)"
echo "--- 필터(filter)로 후보 문서를 좁히고, must로 관련성 스코어 계산"
echo "--- 스마트폰 카테고리(filter) + '갤럭시' 검색(must)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"match": {"title": "갤럭시 스마트폰"}}
        ],
        "filter": [
          {"term": {"category": "스마트폰"}},
          {"term": {"in_stock": true}},
          {"range": {"price": {"lte": 1600000}}}
        ]
      }
    },
    "_source": ["title", "price", "rating"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title, price: ._source.price}]'
echo ""

# --------------------------------------------------------------
# STEP 4: should - OR 조건 (스코어 영향)
# --------------------------------------------------------------
echo ">>> [STEP 4] should - OR 조건 (하나라도 만족하면 점수 가산)"
echo "--- AI 또는 프리미엄 태그가 있는 상품 (하나라도 있으면 매칭, 둘 다 있으면 점수 높음)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "should": [
          {"term": {"tags": "AI"}},
          {"term": {"tags": "프리미엄"}},
          {"term": {"tags": "플래그십"}}
        ]
      }
    },
    "_source": ["title", "tags"],
    "size": 6
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title, tags: ._source.tags}]'
echo ""

# --------------------------------------------------------------
# STEP 5: must_not - 제외 조건
# --------------------------------------------------------------
echo ">>> [STEP 5] must_not - 조건을 만족하는 문서 제외"
echo "--- 이어폰/헤드폰 카테고리를 제외한 Samsung 제품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "filter": [
          {"term": {"brand": "Samsung"}}
        ],
        "must_not": [
          {"terms": {"category": ["이어폰", "헤드폰"]}}
        ]
      }
    },
    "_source": ["title", "category"],
    "size": 10
  }' | jq '[.hits.hits[]._source | {category, title}]'
echo ""

# --------------------------------------------------------------
# STEP 6: 복잡한 bool 쿼리 조합
# --------------------------------------------------------------
echo ">>> [STEP 6] 실무형 복잡 쿼리 - 가성비 AI 스마트폰 찾기"
echo "--- 조건: 스마트폰, 재고 있음, 가격 100만원 이하, '갤럭시' OR '구글' 브랜드"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"match": {"description": "AI"}}
        ],
        "filter": [
          {"term": {"category": "스마트폰"}},
          {"term": {"in_stock": true}},
          {"range": {"price": {"lte": 1300000}}}
        ],
        "should": [
          {"term": {"brand": "Samsung"}},
          {"term": {"brand": "Google"}}
        ],
        "minimum_should_match": 1
      }
    },
    "_source": ["title", "brand", "price"],
    "sort": [{"price": "asc"}]
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title, price: ._source.price}]'
echo ""

# --------------------------------------------------------------
# STEP 7: minimum_should_match 동작
# --------------------------------------------------------------
echo ">>> [STEP 7] minimum_should_match - 최소 should 충족 수"
echo "--- should 3개 중 최소 2개가 만족해야 매칭"
echo "--- 태그: 무선, ANC, 프리미엄 중 2개 이상인 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "should": [
          {"term": {"tags": "무선"}},
          {"term": {"tags": "ANC"}},
          {"term": {"tags": "프리미엄"}}
        ],
        "minimum_should_match": 2
      }
    },
    "_source": ["title", "tags"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title, tags: ._source.tags}]'
echo ""

# --------------------------------------------------------------
# STEP 8: nested bool query
# --------------------------------------------------------------
echo ">>> [STEP 8] 중첩 bool 쿼리"
echo "--- (Apple 또는 Sony 브랜드) AND (이어폰 또는 헤드폰 카테고리) AND 재고 있음"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {
            "bool": {
              "should": [
                {"term": {"brand": "Apple"}},
                {"term": {"brand": "Sony"}}
              ]
            }
          },
          {
            "bool": {
              "should": [
                {"term": {"category": "이어폰"}},
                {"term": {"category": "헤드폰"}}
              ]
            }
          }
        ],
        "filter": [
          {"term": {"in_stock": true}}
        ]
      }
    },
    "_source": ["title", "brand", "category", "price"],
    "sort": [{"price": "desc"}]
  }' | jq '[.hits.hits[]._source | {brand, category, title, price}]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 04-range-query.sh"
echo "============================================================"
