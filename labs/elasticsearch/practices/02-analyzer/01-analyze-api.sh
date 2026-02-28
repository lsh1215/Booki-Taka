#!/bin/bash
# ==============================================================
# 01-analyze-api.sh
# _analyze API로 분석 과정 관찰
# 관찰 포인트: 토큰 분리, offset, position
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  01. Analyze API로 분석 과정 관찰"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 기본 analyze API
# --------------------------------------------------------------
echo ">>> [STEP 1] standard 애널라이저로 영문 텍스트 분석"
echo "--- 각 토큰의 start_offset, end_offset, position을 관찰한다."
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "standard",
    "text": "The quick brown Fox Jumps Over the Lazy Dog!"
  }' | jq '.tokens[] | {token, start_offset, end_offset, position}'
echo ""

# --------------------------------------------------------------
# STEP 2: 한국어 텍스트에 standard 적용 (한계 관찰)
# --------------------------------------------------------------
echo ">>> [STEP 2] standard 애널라이저로 한국어 텍스트 분석"
echo "--- standard는 한국어를 글자 단위로 분리한다. 의미 단위가 아님!"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "standard",
    "text": "삼성전자 갤럭시 S24 스마트폰"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 3: tokenizer만 지정해서 분석
# --------------------------------------------------------------
echo ">>> [STEP 3] tokenizer만 지정"
echo "--- standard tokenizer: 공백과 구두점으로 분리, 소문자 변환 없음"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "standard",
    "text": "Hello World! I am learning Elasticsearch."
  }' | jq '[.tokens[].token]'
echo ""

echo "--- whitespace tokenizer: 공백으로만 분리, 구두점 유지"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "whitespace",
    "text": "Hello World! I am learning Elasticsearch."
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 4: char_filter 효과 관찰
# --------------------------------------------------------------
echo ">>> [STEP 4] char_filter 적용 관찰"
echo "--- html_strip char_filter: HTML 태그 제거"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "char_filter": ["html_strip"],
    "tokenizer": "standard",
    "text": "<p>Hello <b>World</b>! <a href=\"/es\">Learn</a> Elasticsearch.</p>"
  }' | jq '[.tokens[].token]'
echo ""

echo "--- mapping char_filter: 특정 문자를 다른 문자로 대체"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "char_filter": [
      {
        "type": "mapping",
        "mappings": [
          "& => and",
          "| => or",
          "@ => at"
        ]
      }
    ],
    "tokenizer": "standard",
    "text": "cat & dog | fish @ home"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 5: token_filter 효과 관찰
# --------------------------------------------------------------
echo ">>> [STEP 5] token_filter 적용 관찰"
echo "--- lowercase: 대문자를 소문자로 변환"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "standard",
    "filter": ["lowercase"],
    "text": "Hello WORLD ElasticSearch"
  }' | jq '[.tokens[].token]'
echo ""

echo "--- stop: 불용어(stopword) 제거"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "standard",
    "filter": ["lowercase", "stop"],
    "text": "The quick brown fox is jumping over the lazy dog"
  }' | jq '[.tokens[].token]'
echo ""

echo "--- stemmer: 어간 추출 (영어)"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "standard",
    "filter": ["lowercase", "stemmer"],
    "text": "running runners quickly jumped dogs"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 6: 인덱스에 정의된 애널라이저로 분석
# --------------------------------------------------------------
echo ">>> [STEP 6] 인덱스에 정의된 필드의 애널라이저로 분석"
echo "--- 인덱스 생성 및 필드 분석"
curl -s -X DELETE "$ES_HOST/lab-analyze-test" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/lab-analyze-test" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1, "number_of_replicas": 0,
      "analysis": {
        "analyzer": {
          "my_analyzer": {
            "type": "custom",
            "char_filter": ["html_strip"],
            "tokenizer": "standard",
            "filter": ["lowercase", "stop"]
          }
        }
      }
    },
    "mappings": {
      "properties": {
        "content": {"type": "text", "analyzer": "my_analyzer"}
      }
    }
  }' | jq . > /dev/null

echo "--- 특정 인덱스의 필드 애널라이저 사용"
curl -s -X POST "$ES_HOST/lab-analyze-test/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "field": "content",
    "text": "<p>The Quick Brown Fox jumps over the Lazy Dog!</p>"
  }' | jq '[.tokens[].token]'
echo ""

echo "--- 인덱스에 등록된 애널라이저 이름으로 직접 분석"
curl -s -X POST "$ES_HOST/lab-analyze-test/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "my_analyzer",
    "text": "<b>Hello World</b> The quick fox"
  }' | jq '[.tokens[].token]'
echo ""

curl -s -X DELETE "$ES_HOST/lab-analyze-test" | jq . > /dev/null

echo "============================================================"
echo "  실습 완료"
echo "  다음: 02-builtin-analyzers.sh"
echo "============================================================"
