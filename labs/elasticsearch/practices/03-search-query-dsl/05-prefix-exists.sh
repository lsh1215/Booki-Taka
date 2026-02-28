#!/bin/bash
# ==============================================================
# 05-prefix-exists.sh
# Prefix, Exists Query 실습
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}
INDEX="products"

echo "============================================================"
echo "  05. Prefix / Exists Query"
echo "  인덱스: $INDEX | ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: prefix 쿼리 - 전방 일치
# --------------------------------------------------------------
echo ">>> [STEP 1] prefix 쿼리 - 값의 앞부분 일치 검색"
echo "--- keyword 필드에 사용. brand가 'S'로 시작하는 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"prefix": {"brand": {"value": "S"}}},
    "_source": ["brand"]
  }' | jq '[.hits.hits[]._source.brand] | unique | sort'
echo ""

echo "--- category가 '스마트'로 시작하는 상품"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"prefix": {"category": "스마트"}},
    "_source": ["title", "category"],
    "size": 8
  }' | jq '[.hits.hits[]._source | {category, title}]'
echo ""

# --------------------------------------------------------------
# STEP 2: exists 쿼리 - 필드 존재 여부
# --------------------------------------------------------------
echo ">>> [STEP 2] exists 쿼리 - 필드가 존재하는 문서 검색"
echo "--- rating 필드가 존재하는 문서"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"exists": {"field": "rating"}},
    "size": 1,
    "_source": ["title", "rating"]
  }' | jq '.hits.total.value'
echo ""

echo "--- exists + must_not: 특정 필드가 없는 문서 검색"
echo "--- (샘플 데이터는 모든 필드가 있으므로 0건 예상)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must_not": [{"exists": {"field": "tags"}}]
      }
    }
  }' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 3: null 값 처리 실습
# --------------------------------------------------------------
echo ">>> [STEP 3] null 값 처리 실습"
echo "--- null 값이 있는 문서 색인"
curl -s -X DELETE "$ES_HOST/lab-null-test" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-null-test" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "properties": {
        "name": {"type": "keyword"},
        "score": {"type": "integer", "null_value": -1}
      }
    }
  }' | jq . > /dev/null

curl -s -X POST "$ES_HOST/lab-null-test/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"name": "정상", "score": 100}
{"index": {"_id": "2"}}
{"name": "null값", "score": null}
{"index": {"_id": "3"}}
{"name": "필드없음"}
' | jq .errors

sleep 1

echo "--- score 필드가 존재하는 문서 (null이어도 null_value 설정 시 색인됨)"
curl -s -X GET "$ES_HOST/lab-null-test/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"exists": {"field": "score"}}}' | jq '[.hits.hits[] | {id: ._id, name: ._source.name, score: ._source.score}]'
echo ""

echo "--- score가 -1인 문서 검색 (null_value=-1로 대체 저장됨)"
curl -s -X GET "$ES_HOST/lab-null-test/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"term": {"score": -1}}}' | jq '[.hits.hits[]._source]'
echo ""

curl -s -X DELETE "$ES_HOST/lab-null-test" | jq . > /dev/null

# --------------------------------------------------------------
# STEP 4: match_all vs match_none
# --------------------------------------------------------------
echo ">>> [STEP 4] match_all / match_none"
echo "--- match_all: 모든 문서 매칭 (스코어=1.0)"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_all": {}}, "size": 1}' | jq '{total: .hits.total.value, score: .hits.hits[0]._score}'
echo ""

echo "--- match_none: 아무 문서도 매칭 안함"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_none": {}}}' | jq '.hits.total.value'
echo ""

# --------------------------------------------------------------
# STEP 5: constant_score 쿼리
# --------------------------------------------------------------
echo ">>> [STEP 5] constant_score - 필터를 고정 스코어로 래핑"
echo "--- filter 절만 있는 bool 쿼리와 동일하나, 더 명시적"
echo "--- 스코어 계산을 완전히 무시하고 boost 값으로 고정"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "constant_score": {
        "filter": {
          "term": {"brand": "Samsung"}
        },
        "boost": 1.5
      }
    },
    "_source": ["title", "brand"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

# --------------------------------------------------------------
# STEP 6: dis_max 쿼리 (Disjunction Max)
# --------------------------------------------------------------
echo ">>> [STEP 6] dis_max 쿼리 - 가장 높은 점수 서브쿼리 사용"
echo "--- multi_match의 best_fields type이 내부적으로 사용하는 방식"
curl -s -X GET "$ES_HOST/$INDEX/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "dis_max": {
        "queries": [
          {"match": {"title": "무선 이어폰"}},
          {"match": {"description": "무선 이어폰"}}
        ],
        "tie_breaker": 0.3
      }
    },
    "_source": ["title"],
    "size": 5
  }' | jq '[.hits.hits[] | {score: ._score, title: ._source.title}]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 06-scoring.sh"
echo "============================================================"
