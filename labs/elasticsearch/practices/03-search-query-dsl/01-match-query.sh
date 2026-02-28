#!/bin/bash
# ==============================================================
# 01-match-query.sh
# Match, Multi-Match Query 실습
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  01. Match / Multi-Match Query"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# 헬퍼 함수
search_titles() {
  local desc="$1"
  local body="$2"
  echo "--- $desc"
  curl -s -X GET "$ES_HOST/$INDEX/_search" \
    -H 'Content-Type: application/json' \
    -d "$body" | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
  echo ""
}

# --------------------------------------------------------------
# STEP 1: match 기본 사용
# --------------------------------------------------------------
echo ">>> [STEP 1] match 쿼리 기본"
echo "--- 검색어를 분석(analyze)한 후 역색인을 조회한다"
echo "--- OR 동작: '무선 이어폰' -> '무선' OR '이어폰' 토큰 중 하나라도 매칭"
search_titles "무선 이어폰 검색 (OR 기본)" '{
  "query": {"match": {"title": "무선 이어폰"}},
  "_source": ["title", "category"],
  "size": 5
}'

# --------------------------------------------------------------
# STEP 2: match with AND operator
# --------------------------------------------------------------
echo ">>> [STEP 2] match - AND operator"
echo "--- AND: 모든 토큰이 포함된 문서만 반환"
search_titles "무선 이어폰 검색 (AND)" '{
  "query": {
    "match": {
      "title": {
        "query": "무선 이어폰",
        "operator": "and"
      }
    }
  },
  "_source": ["title"]
}'

# --------------------------------------------------------------
# STEP 3: match_phrase
# --------------------------------------------------------------
echo ">>> [STEP 3] match_phrase 쿼리"
echo "--- 토큰들이 순서대로, 인접하게 존재해야 매칭"
search_titles "match_phrase: '갤럭시 워치'" '{
  "query": {"match_phrase": {"title": "갤럭시 워치"}},
  "_source": ["title"]
}'

echo "--- 단어 순서가 바뀌면 매칭 안됨"
search_titles "match_phrase: '워치 갤럭시' (순서 반전 - 0건 예상)" '{
  "query": {"match_phrase": {"title": "워치 갤럭시"}},
  "_source": ["title"]
}'

# --------------------------------------------------------------
# STEP 4: match_phrase_prefix (자동완성)
# --------------------------------------------------------------
echo ">>> [STEP 4] match_phrase_prefix - 마지막 단어 전방 일치"
search_titles "match_phrase_prefix: '갤럭시 S' (갤럭시 S로 시작)" '{
  "query": {"match_phrase_prefix": {"title": "갤럭시 S"}},
  "_source": ["title"]
}'

# --------------------------------------------------------------
# STEP 5: multi_match - 여러 필드 동시 검색
# --------------------------------------------------------------
echo ">>> [STEP 5] multi_match 쿼리 - 여러 필드 동시 검색"
search_titles "multi_match: '무선 충전' (title + description)" '{
  "query": {
    "multi_match": {
      "query": "무선 충전",
      "fields": ["title", "description"]
    }
  },
  "_source": ["title"]
}'

# --------------------------------------------------------------
# STEP 6: multi_match - 필드별 가중치(boost)
# --------------------------------------------------------------
echo ">>> [STEP 6] multi_match - 필드별 boost (title 더 중요)"
search_titles "title^3 boost 적용" '{
  "query": {
    "multi_match": {
      "query": "무선",
      "fields": ["title^3", "description"]
    }
  },
  "_source": ["title"],
  "size": 5
}'

# --------------------------------------------------------------
# STEP 7: multi_match type 비교
# --------------------------------------------------------------
echo ">>> [STEP 7] multi_match type 비교"

echo "--- type: best_fields (기본) - 가장 높은 점수 필드 기준"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "multi_match": {
        "query": "삼성 갤럭시",
        "fields": ["title", "description"],
        "type": "best_fields"
      }
    },
    "_source": ["title"],
    "size": 3
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

echo "--- type: most_fields - 매칭 필드 수만큼 점수 합산"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "multi_match": {
        "query": "삼성 갤럭시",
        "fields": ["title", "description"],
        "type": "most_fields"
      }
    },
    "_source": ["title"],
    "size": 3
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

echo "--- type: cross_fields - 여러 필드를 하나의 큰 필드처럼 처리"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "multi_match": {
        "query": "삼성 갤럭시",
        "fields": ["title", "description"],
        "type": "cross_fields",
        "operator": "and"
      }
    },
    "_source": ["title"],
    "size": 3
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 8: minimum_should_match
# --------------------------------------------------------------
echo ">>> [STEP 8] minimum_should_match - 최소 매칭 토큰 수 지정"
echo "--- 검색어 중 최소 몇 개의 토큰이 매칭되어야 하는가"
search_titles "3개 단어 중 2개 이상 매칭 (75%)" '{
  "query": {
    "match": {
      "title": {
        "query": "삼성 갤럭시 스마트폰",
        "minimum_should_match": "75%"
      }
    }
  },
  "_source": ["title"]
}'

echo "============================================================"
echo "  실습 완료"
echo "  다음: 02-term-query.sh"
echo "============================================================"
