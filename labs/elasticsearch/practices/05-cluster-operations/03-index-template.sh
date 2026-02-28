#!/bin/bash
# ==============================================================
# 03-index-template.sh
# 인덱스 템플릿 + 컴포넌트 템플릿 생성/적용 실습
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  03. 인덱스 템플릿 & 컴포넌트 템플릿"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- 컴포넌트 템플릿: 재사용 가능한 설정/매핑 조각"
echo "--- 인덱스 템플릿: 컴포넌트 템플릿을 조합하여 인덱스에 적용"
echo "--- 인덱스 이름 패턴이 매칭되면 자동으로 템플릿이 적용됨"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 템플릿 삭제
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 템플릿 삭제"
curl -s -X DELETE "$ES_HOST/_component_template/settings-base" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/_component_template/mappings-log" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/_component_template/mappings-timestamp" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/_index_template/log-template" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/_index_template/ecommerce-template" | jq . > /dev/null
echo ""

# --------------------------------------------------------------
# STEP 2: 컴포넌트 템플릿 생성 - 기본 설정
# --------------------------------------------------------------
echo ">>> [STEP 2] 컴포넌트 템플릿 생성 - 공통 설정"
curl -s -X PUT "$ES_HOST/_component_template/settings-base" \
  -H 'Content-Type: application/json' \
  -d '{
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 1,
        "refresh_interval": "5s",
        "index.mapping.total_fields.limit": 2000
      }
    },
    "_meta": {
      "description": "기본 인덱스 설정 컴포넌트"
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 3: 컴포넌트 템플릿 - 타임스탬프 매핑
# --------------------------------------------------------------
echo ">>> [STEP 3] 컴포넌트 템플릿 - 타임스탬프 공통 매핑"
curl -s -X PUT "$ES_HOST/_component_template/mappings-timestamp" \
  -H 'Content-Type: application/json' \
  -d '{
    "template": {
      "mappings": {
        "properties": {
          "@timestamp": {
            "type": "date",
            "format": "yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis"
          },
          "created_at": {"type": "date"},
          "updated_at": {"type": "date"}
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 4: 컴포넌트 템플릿 - 로그 매핑
# --------------------------------------------------------------
echo ">>> [STEP 4] 컴포넌트 템플릿 - 로그 전용 매핑"
curl -s -X PUT "$ES_HOST/_component_template/mappings-log" \
  -H 'Content-Type: application/json' \
  -d '{
    "template": {
      "mappings": {
        "dynamic": "strict",
        "properties": {
          "level":    {"type": "keyword"},
          "service":  {"type": "keyword"},
          "host":     {"type": "keyword"},
          "message":  {"type": "text"},
          "trace_id": {"type": "keyword"},
          "span_id":  {"type": "keyword"},
          "duration_ms": {"type": "long"},
          "error": {
            "type": "object",
            "properties": {
              "type":       {"type": "keyword"},
              "message":    {"type": "text"},
              "stack_trace":{"type": "text", "index": false}
            }
          }
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 5: 인덱스 템플릿 생성 (컴포넌트 조합)
# --------------------------------------------------------------
echo ">>> [STEP 5] 인덱스 템플릿 생성 - 로그 인덱스 템플릿"
curl -s -X PUT "$ES_HOST/_index_template/log-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["logs-*", "app-logs-*"],
    "priority": 100,
    "composed_of": ["settings-base", "mappings-timestamp", "mappings-log"],
    "template": {
      "settings": {
        "number_of_replicas": 0
      }
    },
    "_meta": {
      "description": "애플리케이션 로그 인덱스 템플릿",
      "version": "1.0"
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 6: 이커머스 인덱스 템플릿 (다른 컴포넌트 조합)
# --------------------------------------------------------------
echo ">>> [STEP 6] 이커머스 인덱스 템플릿 생성"
curl -s -X PUT "$ES_HOST/_index_template/ecommerce-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["ecommerce-*", "shop-*"],
    "priority": 90,
    "composed_of": ["settings-base", "mappings-timestamp"],
    "template": {
      "settings": {
        "number_of_shards": 2,
        "refresh_interval": "1s"
      },
      "mappings": {
        "properties": {
          "product_id":  {"type": "keyword"},
          "product_name":{"type": "text", "fields": {"keyword": {"type": "keyword"}}},
          "category":    {"type": "keyword"},
          "price":       {"type": "integer"},
          "quantity":    {"type": "integer"}
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 7: 템플릿 조회
# --------------------------------------------------------------
echo ">>> [STEP 7] 생성된 컴포넌트 템플릿 조회"
curl -s "$ES_HOST/_component_template?pretty" | jq '[.component_templates[] | {name: .name}]'
echo ""

echo ">>> 생성된 인덱스 템플릿 조회"
curl -s "$ES_HOST/_index_template?pretty" | jq '[.index_templates[] | {name: .name, patterns: .index_template.index_patterns, priority: .index_template.priority}]'
echo ""

# --------------------------------------------------------------
# STEP 8: 템플릿 자동 적용 확인
# --------------------------------------------------------------
echo ">>> [STEP 8] 새 인덱스 생성 - 템플릿 자동 적용 확인"
echo "--- logs-app-2024-01 인덱스는 log-template이 자동 적용되어야 함"
curl -s -X DELETE "$ES_HOST/logs-app-2024-01" | jq . > /dev/null
curl -s -X PUT "$ES_HOST/logs-app-2024-01" | jq .acknowledged
sleep 1

echo "--- 적용된 매핑 확인 (log-template의 매핑이 있어야 함)"
curl -s "$ES_HOST/logs-app-2024-01/_mapping" | jq '.["logs-app-2024-01"].mappings.properties | keys'
echo ""

echo "--- 적용된 설정 확인"
curl -s "$ES_HOST/logs-app-2024-01/_settings" | jq '.["logs-app-2024-01"].settings.index | {number_of_shards, number_of_replicas, refresh_interval}'
echo ""

# --------------------------------------------------------------
# STEP 9: strict 매핑에서 미정의 필드 색인 시도
# --------------------------------------------------------------
echo ">>> [STEP 9] strict 매핑 확인 - 미정의 필드 거부"
curl -s -X POST "$ES_HOST/logs-app-2024-01/_doc" \
  -H 'Content-Type: application/json' \
  -d '{
    "level": "INFO",
    "service": "auth-service",
    "host": "app-01",
    "message": "User login successful",
    "@timestamp": "2024-01-15 10:30:00"
  }' | jq .result
echo ""

echo "--- 미정의 필드 포함 색인 시도 (에러 예상)"
curl -s -X POST "$ES_HOST/logs-app-2024-01/_doc" \
  -H 'Content-Type: application/json' \
  -d '{
    "level": "ERROR",
    "service": "auth-service",
    "message": "Login failed",
    "undefined_field": "이 필드는 매핑에 없음"
  }' | jq '.error.type'
echo ""

# --------------------------------------------------------------
# STEP 10: 정리
# --------------------------------------------------------------
echo ">>> [STEP 10] 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/logs-app-2024-01" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  다음: 04-alias-rollover.sh"
echo "============================================================"
