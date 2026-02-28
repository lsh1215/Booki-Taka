#!/bin/bash
# ==============================================================
# 06-scoring.sh
# 스코어링 원리 (_explain API) 실습
# 관찰 포인트: BM25, TF-IDF, boost, function_score
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  06. 스코어링 원리"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- ES 기본 유사도: BM25 (Best Match 25)"
echo "--- 스코어 = TF(단어 빈도) * IDF(역문서빈도) * 필드 길이 정규화"
echo "--- IDF: 문서 전체에 희귀한 단어일수록 높은 점수"
echo "--- TF: 한 문서에 단어가 자주 나올수록 높은 점수 (BM25는 포화 효과 있음)"
echo ""

# --------------------------------------------------------------
# STEP 1: 기본 검색 스코어 관찰
# --------------------------------------------------------------
echo ">>> [STEP 1] 기본 검색 스코어 확인"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"match": {"title": "무선"}},
    "_source": ["title"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 2: _explain API로 스코어 계산 상세 보기
# --------------------------------------------------------------
echo ">>> [STEP 2] _explain API - 스코어 계산 과정 상세 분석"
echo "--- 첫 번째 매칭 문서의 ID를 찾아 explain 실행"
DOC_ID=$(curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"title": "무선"}}, "size": 1}' | jq -r '.hits.hits[0]._id')

echo "--- 문서 ID: $DOC_ID"
curl -s -X GET "$ES_HOST/$INDEX/_explain/$DOC_ID" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"match": {"title": "무선"}}
  }' | jq '{
    matched: .matched,
    score: .explanation.value,
    description: .explanation.description,
    details: [.explanation.details[] | {value, description}]
  }'
echo ""

# --------------------------------------------------------------
# STEP 3: boost 파라미터로 스코어 조정
# --------------------------------------------------------------
echo ">>> [STEP 3] boost로 특정 필드/조건 가중치 조정"
echo "--- title 매칭에 2배 boost 적용"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "should": [
          {"match": {"title": {"query": "갤럭시", "boost": 3}}},
          {"match": {"description": {"query": "갤럭시", "boost": 1}}}
        ]
      }
    },
    "_source": ["title"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 4: function_score - 비즈니스 로직으로 스코어 조정
# --------------------------------------------------------------
echo ">>> [STEP 4] function_score - 평점을 스코어에 반영"
echo "--- 검색 관련성 * 평점 가중치 조합"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "function_score": {
        "query": {"match": {"title": "스마트폰"}},
        "field_value_factor": {
          "field": "rating",
          "factor": 1.5,
          "modifier": "log1p",
          "missing": 1
        },
        "boost_mode": "multiply"
      }
    },
    "_source": ["title", "rating"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, rating: ._source.rating, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 5: function_score - random_score (추천용 무작위화)
# --------------------------------------------------------------
echo ">>> [STEP 5] function_score - random_score (개인화 추천 변형)"
echo "--- 동일 사용자에겐 같은 순서, 다른 사용자에겐 다른 순서"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "function_score": {
        "query": {"match_all": {}},
        "random_score": {"seed": 12345, "field": "_seq_no"},
        "boost_mode": "replace"
      }
    },
    "_source": ["title"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 6: function_score - 최신 문서 우대 (가우시안 감쇠)
# --------------------------------------------------------------
echo ">>> [STEP 6] function_score - 최신 문서 우대 (decay 함수)"
echo "--- 등록일이 최근일수록 높은 점수 (gauss 감쇠 함수)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "function_score": {
        "query": {"match": {"title": "갤럭시"}},
        "gauss": {
          "created_at": {
            "origin": "now",
            "scale": "180d",
            "offset": "30d",
            "decay": 0.5
          }
        },
        "boost_mode": "multiply"
      }
    },
    "_source": ["title", "created_at"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, created_at: ._source.created_at, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 7: rescore - 1차 검색 후 상위 결과 재스코어링
# --------------------------------------------------------------
echo ">>> [STEP 7] rescore - 1차 검색 후 재스코어링"
echo "--- 대량 문서에서 1차로 필터링 후, 상위 N건만 정밀 재평가"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"match": {"title": "삼성"}},
    "rescore": {
      "window_size": 10,
      "query": {
        "rescore_query": {
          "match_phrase": {"title": "삼성 갤럭시"}
        },
        "query_weight": 0.7,
        "rescore_query_weight": 1.2
      }
    },
    "_source": ["title"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 07-search-template.sh"
echo "============================================================"
