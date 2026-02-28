#!/bin/bash
# ==============================================================
# 04-nori-korean.sh
# 한국어 nori 형태소 분석기 실습
# 사전 조건: analysis-nori 플러그인이 ES에 설치되어 있어야 함
#
# 플러그인 설치 방법:
#   docker exec es01 elasticsearch-plugin install analysis-nori
#   docker exec es02 elasticsearch-plugin install analysis-nori
#   docker exec es03 elasticsearch-plugin install analysis-nori
#   docker-compose restart
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  04. 한국어 nori 형태소 분석기"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

# --------------------------------------------------------------
# STEP 0: nori 플러그인 설치 여부 확인
# --------------------------------------------------------------
echo ">>> [STEP 0] nori 플러그인 설치 확인"
NORI_CHECK=$(curl -s "$ES_HOST/_nodes/plugins" | jq -r '[.nodes | to_entries[] | .value.plugins[] | select(.name == "analysis-nori")] | length')
echo "설치된 nori 플러그인 수: $NORI_CHECK"
if [ "$NORI_CHECK" -eq 0 ]; then
  echo ""
  echo "[WARNING] analysis-nori 플러그인이 설치되어 있지 않습니다."
  echo "다음 명령어로 설치 후 재실행하세요:"
  echo "  docker exec es01 elasticsearch-plugin install analysis-nori"
  echo "  docker exec es02 elasticsearch-plugin install analysis-nori"
  echo "  docker exec es03 elasticsearch-plugin install analysis-nori"
  echo "  docker-compose restart"
  echo ""
  echo "플러그인 없이 계속 실행하면 일부 단계에서 에러가 발생합니다."
  echo ""
fi

# --------------------------------------------------------------
# STEP 1: nori_tokenizer 기본 동작
# --------------------------------------------------------------
echo ">>> [STEP 1] nori_tokenizer 기본 형태소 분석"
echo "--- 한국어 텍스트를 의미 단위로 분리"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "nori_tokenizer",
    "text": "삼성전자 갤럭시 스마트폰을 구매했습니다"
  }' | jq '[.tokens[] | {token, position, positionLength}]'
echo ""

echo "--- standard vs nori 비교"
echo "standard 분석:"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{"analyzer": "standard", "text": "인공지능 딥러닝 모델을 학습시켰습니다"}' | jq -r '[.tokens[].token] | join(", ")'

echo "nori 분석:"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{"tokenizer": "nori_tokenizer", "text": "인공지능 딥러닝 모델을 학습시켰습니다"}' | jq -r '[.tokens[].token] | join(", ")'
echo ""

# --------------------------------------------------------------
# STEP 2: decompound_mode 옵션 비교
# --------------------------------------------------------------
echo ">>> [STEP 2] nori decompound_mode 비교"
echo "--- none: 복합어 분해 안함"
echo "--- discard: 복합어를 분해하고 원본 제거"
echo "--- mixed: 복합어와 분해된 형태 모두 포함"

for mode in none discard mixed; do
  echo ""
  echo "--- decompound_mode: $mode ---"
  curl -s -X POST "$ES_HOST/_analyze" \
    -H 'Content-Type: application/json' \
    -d "{
      \"tokenizer\": {
        \"type\": \"nori_tokenizer\",
        \"decompound_mode\": \"$mode\"
      },
      \"text\": \"삼성전자 갤럭시S24울트라\"
    }" | jq -r '[.tokens[].token] | join(", ")'
done
echo ""

# --------------------------------------------------------------
# STEP 3: nori_part_of_speech 필터 (품사 필터링)
# --------------------------------------------------------------
echo ">>> [STEP 3] nori_part_of_speech 필터 - 조사/어미 제거"
echo "--- 한국어에서 검색에 불필요한 조사(JX, JC), 어미(E), 기호(SC, SF) 제거"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "nori_tokenizer",
    "filter": [
      {
        "type": "nori_part_of_speech",
        "stoptags": ["JX", "JC", "JO", "JKS", "JKC", "JKG", "JKO", "JKB", "JKV", "JKQ",
                     "E", "EF", "EC", "ETN", "ETM",
                     "SF", "SC", "SP", "SSO", "SSC", "SY", "XSN", "XSV", "XSA"]
      }
    ],
    "text": "엘라스틱서치를 이용하여 빠른 검색을 구현했습니다"
  }' | jq -r '[.tokens[].token] | join(", ")'
echo ""

# --------------------------------------------------------------
# STEP 4: nori_readingform 필터 (한자 -> 한글 변환)
# --------------------------------------------------------------
echo ">>> [STEP 4] nori_readingform 필터 - 한자를 한글로 변환"
curl -s -X POST "$ES_HOST/_analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "tokenizer": "nori_tokenizer",
    "filter": ["nori_readingform"],
    "text": "大韓民國 서울特別市"
  }' | jq '[.tokens[].token]'
echo ""

# --------------------------------------------------------------
# STEP 5: 커스텀 nori 애널라이저가 있는 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 5] 커스텀 nori 애널라이저 인덱스 생성"
curl -s -X DELETE "$ES_HOST/lab-nori" | jq .
curl -s -X PUT "$ES_HOST/lab-nori" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1, "number_of_replicas": 0,
      "analysis": {
        "tokenizer": {
          "nori_mixed": {
            "type": "nori_tokenizer",
            "decompound_mode": "mixed"
          }
        },
        "filter": {
          "nori_pos_filter": {
            "type": "nori_part_of_speech",
            "stoptags": ["JX", "JC", "JO", "JKS", "JKC", "JKG", "JKO", "JKB", "JKV", "JKQ",
                         "E", "EF", "EC", "ETN", "ETM", "SF", "SC", "SP", "SSO", "SSC"]
          }
        },
        "analyzer": {
          "korean_analyzer": {
            "type": "custom",
            "tokenizer": "nori_mixed",
            "filter": [
              "nori_pos_filter",
              "nori_readingform",
              "lowercase"
            ]
          }
        }
      }
    },
    "mappings": {
      "properties": {
        "title":    {"type": "text", "analyzer": "korean_analyzer"},
        "content":  {"type": "text", "analyzer": "korean_analyzer"},
        "category": {"type": "keyword"}
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 6: 샘플 데이터 색인 및 검색 테스트
# --------------------------------------------------------------
echo ">>> [STEP 6] 한국어 샘플 데이터 색인"
curl -s -X POST "$ES_HOST/lab-nori/_bulk" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"_id": "1"}}
{"title": "삼성전자 갤럭시 S24 스마트폰 출시", "content": "삼성전자가 최신 AI 기능을 탑재한 갤럭시 S24를 출시했습니다", "category": "전자기기"}
{"index": {"_id": "2"}}
{"title": "인공지능 딥러닝 기반 검색 시스템", "content": "엘라스틱서치를 활용하여 자연어 처리 기반의 검색 엔진을 구축합니다", "category": "기술"}
{"index": {"_id": "3"}}
{"title": "서울 강남구 맛집 추천", "content": "강남역 근처 한식당과 일식당을 소개합니다", "category": "음식"}
{"index": {"_id": "4"}}
{"title": "갤럭시 울트라 카메라 성능 리뷰", "content": "갤럭시S24 울트라의 카메라 기능을 상세히 분석합니다", "category": "전자기기"}
' | jq .errors

sleep 1
echo ""

echo "--- '삼성' 검색 (삼성전자에서 분해된 토큰으로 매칭)"
curl -s -X GET "$ES_HOST/lab-nori/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"title": "삼성"}}, "_source": ["title"]}' | jq '[.hits.hits[]._source.title]'
echo ""

echo "--- '갤럭시' 검색"
curl -s -X GET "$ES_HOST/lab-nori/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"content": "갤럭시"}}, "_source": ["title"]}' | jq '[.hits.hits[]._source.title]'
echo ""

echo "--- '인공지능' 검색 (분해 후 재합성 토큰)"
curl -s -X GET "$ES_HOST/lab-nori/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"title": "인공지능"}}, "_source": ["title"]}' | jq '[.hits.hits[]._source.title]'
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 05-normalizer.sh"
echo "============================================================"
