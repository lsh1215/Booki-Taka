#!/bin/bash
# ==============================================================
# 03-custom-analyzer.sh
# 커스텀 애널라이저 생성 실습
# 관찰 포인트: char_filter + tokenizer + token_filter 조합
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  03. 커스텀 애널라이저 생성"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 인덱스 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 인덱스 삭제"
curl -s -X DELETE "$ES_HOST/lab-custom-analyzer" | jq .
curl -s -X DELETE "$ES_HOST/lab-autocomplete" | jq .
echo ""

# --------------------------------------------------------------
# STEP 2: 다양한 커스텀 애널라이저가 있는 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] 커스텀 애널라이저 인덱스 생성"
curl -s -X PUT "$ES_HOST/lab-custom-analyzer" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "analysis": {
        "char_filter": {
          "html_clean": {
            "type": "html_strip"
          },
          "replace_special": {
            "type": "mapping",
            "mappings": [
              "& => and",
              "+ => plus",
              "% => percent"
            ]
          }
        },
        "tokenizer": {
          "my_ngram_tokenizer": {
            "type": "ngram",
            "min_gram": 2,
            "max_gram": 3,
            "token_chars": ["letter", "digit"]
          },
          "my_edge_ngram_tokenizer": {
            "type": "edge_ngram",
            "min_gram": 1,
            "max_gram": 15,
            "token_chars": ["letter", "digit"]
          }
        },
        "filter": {
          "my_synonym_filter": {
            "type": "synonym",
            "synonyms": [
              "갤럭시, 갤S => 갤럭시",
              "아이폰, iPhone => 아이폰",
              "노트북, 랩탑, laptop => 노트북"
            ]
          },
          "my_stop_filter": {
            "type": "stop",
            "stopwords": ["the", "a", "an", "is", "was", "are"]
          },
          "my_length_filter": {
            "type": "length",
            "min": 2,
            "max": 20
          }
        },
        "analyzer": {
          "html_analyzer": {
            "type": "custom",
            "char_filter": ["html_clean"],
            "tokenizer": "standard",
            "filter": ["lowercase"]
          },
          "synonym_analyzer": {
            "type": "custom",
            "tokenizer": "standard",
            "filter": ["lowercase", "my_synonym_filter"]
          },
          "ngram_analyzer": {
            "type": "custom",
            "tokenizer": "my_ngram_tokenizer",
            "filter": ["lowercase"]
          },
          "edge_ngram_analyzer": {
            "type": "custom",
            "tokenizer": "my_edge_ngram_tokenizer",
            "filter": ["lowercase"]
          },
          "special_char_analyzer": {
            "type": "custom",
            "char_filter": ["replace_special"],
            "tokenizer": "standard",
            "filter": ["lowercase"]
          }
        }
      }
    },
    "mappings": {
      "properties": {
        "title_html":    {"type": "text", "analyzer": "html_analyzer"},
        "title_synonym": {"type": "text", "analyzer": "synonym_analyzer"},
        "title_ngram":   {"type": "text", "analyzer": "ngram_analyzer"}
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: HTML 애널라이저 테스트
# --------------------------------------------------------------
echo ">>> [STEP 3] html_analyzer 테스트"
echo "--- HTML 태그가 제거된 후 토큰화되는 과정 관찰"
curl -s -X POST "$ES_HOST/lab-custom-analyzer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "html_analyzer",
    "text": "<h1>Elasticsearch <b>학습</b> 가이드</h1><p>검색 <i>엔진</i>의 기초</p>"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 4: 동의어 애널라이저 테스트
# --------------------------------------------------------------
echo ">>> [STEP 4] synonym_analyzer 테스트"
echo "--- '갤S'와 '갤럭시'가 같은 토큰으로 처리됨 관찰"
curl -s -X POST "$ES_HOST/lab-custom-analyzer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "synonym_analyzer",
    "text": "갤S 신제품 출시"
  }' | jq '[.tokens[].token]'
echo ""

curl -s -X POST "$ES_HOST/lab-custom-analyzer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "synonym_analyzer",
    "text": "노트북 추천 랩탑 비교"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 5: NGram 애널라이저 테스트
# --------------------------------------------------------------
echo ">>> [STEP 5] ngram_analyzer 테스트"
echo "--- min_gram=2, max_gram=3 으로 모든 2~3글자 조합 생성"
echo "--- 부분 검색(Contains 검색)에 유용"
curl -s -X POST "$ES_HOST/lab-custom-analyzer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "ngram_analyzer",
    "text": "hello"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 6: Edge NGram - 자동완성 구현
# --------------------------------------------------------------
echo ">>> [STEP 6] edge_ngram_analyzer 테스트"
echo "--- 앞에서부터 점진적으로 토큰 생성 -> 자동완성(Autocomplete) 구현에 사용"
curl -s -X POST "$ES_HOST/lab-custom-analyzer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "edge_ngram_analyzer",
    "text": "elasticsearch"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 7: 자동완성 인덱스 실습
# --------------------------------------------------------------
echo ">>> [STEP 7] 자동완성 인덱스 생성 및 실습"
echo "--- 색인 시: edge_ngram (e, el, ela, elas, ...)"
echo "--- 검색 시: standard (일반 분석)"
curl -s -X PUT "$ES_HOST/lab-autocomplete" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1, "number_of_replicas": 0,
      "analysis": {
        "tokenizer": {
          "autocomplete_tokenizer": {
            "type": "edge_ngram",
            "min_gram": 1,
            "max_gram": 20,
            "token_chars": ["letter", "digit"]
          }
        },
        "analyzer": {
          "autocomplete_index": {
            "type": "custom",
            "tokenizer": "autocomplete_tokenizer",
            "filter": ["lowercase"]
          },
          "autocomplete_search": {
            "type": "custom",
            "tokenizer": "standard",
            "filter": ["lowercase"]
          }
        }
      }
    },
    "mappings": {
      "properties": {
        "suggest": {
          "type": "text",
          "analyzer": "autocomplete_index",
          "search_analyzer": "autocomplete_search"
        }
      }
    }
  }' | jq .
echo ""

echo ">>> 자동완성 샘플 데이터 색인"
for item in "elasticsearch" "elastic stack" "kibana" "logstash" "beats" "apm" "fleet"; do
  curl -s -X POST "$ES_HOST/lab-autocomplete/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"suggest\": \"$item\"}" | jq .result
done
echo ""

sleep 1

echo ">>> 자동완성 검색 테스트: 'ela' 입력 시"
curl -s -X GET "$ES_HOST/lab-autocomplete/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"match": {"suggest": "ela"}},
    "_source": ["suggest"]
  }' | jq '[.hits.hits[]._source.suggest]'
echo ""

echo ">>> 자동완성 검색 테스트: 'ki' 입력 시"
curl -s -X GET "$ES_HOST/lab-autocomplete/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"match": {"suggest": "ki"}},
    "_source": ["suggest"]
  }' | jq '[.hits.hits[]._source.suggest]'
echo ""

# --------------------------------------------------------------
# STEP 8: special_char_analyzer 테스트
# --------------------------------------------------------------
echo ">>> [STEP 8] special_char_analyzer 테스트"
echo "--- & -> and, + -> plus, % -> percent 변환 관찰"
curl -s -X POST "$ES_HOST/lab-custom-analyzer/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "analyzer": "special_char_analyzer",
    "text": "50% OFF + Free Shipping & Gift"
  }' | jq '[.tokens[].token]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 04-nori-korean.sh"
echo "============================================================"
