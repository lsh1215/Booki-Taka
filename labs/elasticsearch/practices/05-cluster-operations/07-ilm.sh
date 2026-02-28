#!/bin/bash
# ==============================================================
# 07-ilm.sh
# Index Lifecycle Management (ILM) 실습
# 관찰 포인트: Hot-Warm-Cold-Delete 정책, 자동화된 데이터 관리
# ==============================================================

ES_HOST=${ES_HOST:-http://localhost:9200}

echo "============================================================"
echo "  07. Index Lifecycle Management (ILM)"
echo "  ES_HOST: $ES_HOST"
echo "============================================================"
echo ""

echo "--- [개념 정리]"
echo "--- Hot: 활발한 읽기/쓰기 (최신 데이터)"
echo "--- Warm: 읽기 전용, 성능 최적화 (몇 일~몇 주)"
echo "--- Cold: 가끔 조회, 비용 최소화 (몇 개월)"
echo "--- Delete: 데이터 삭제"
echo ""

# --------------------------------------------------------------
# STEP 1: 기존 데이터 정리
# --------------------------------------------------------------
echo ">>> [STEP 1] 기존 실습 데이터 정리"
curl -s -X DELETE "$ES_HOST/_ilm/policy/lab-log-policy" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/_index_template/lab-log-ilm-template" | jq . > /dev/null
curl -s -X DELETE "$ES_HOST/lab-logs-*" | jq . > /dev/null
echo ""

# --------------------------------------------------------------
# STEP 2: ILM 정책 생성
# --------------------------------------------------------------
echo ">>> [STEP 2] ILM 정책 생성 - 로그 데이터 생명주기"
curl -s -X PUT "$ES_HOST/_ilm/policy/lab-log-policy" \
  -H 'Content-Type: application/json' \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "min_age": "0ms",
          "actions": {
            "rollover": {
              "max_docs": 20,
              "max_size": "10gb",
              "max_age": "1d"
            },
            "set_priority": {
              "priority": 100
            }
          }
        },
        "warm": {
          "min_age": "1m",
          "actions": {
            "set_priority": {"priority": 50},
            "readonly": {},
            "forcemerge": {"max_num_segments": 1},
            "shrink": {"number_of_shards": 1}
          }
        },
        "cold": {
          "min_age": "3m",
          "actions": {
            "set_priority": {"priority": 0},
            "freeze": {}
          }
        },
        "delete": {
          "min_age": "5m",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }' | jq .
echo ""

echo "--- 주의: 실습 환경에서는 min_age를 짧게 설정 (1m, 3m, 5m)"
echo "--- 실제 운영에서는 min_age: '7d', '30d', '90d' 등으로 설정"
echo ""

# --------------------------------------------------------------
# STEP 3: ILM 정책 조회
# --------------------------------------------------------------
echo ">>> [STEP 3] 생성된 ILM 정책 조회"
curl -s "$ES_HOST/_ilm/policy/lab-log-policy" | jq '.["lab-log-policy"].policy.phases | keys'
echo ""

# --------------------------------------------------------------
# STEP 4: ILM 정책이 적용된 인덱스 템플릿 생성
# --------------------------------------------------------------
echo ">>> [STEP 4] ILM 정책 연동 인덱스 템플릿 생성"
curl -s -X PUT "$ES_HOST/_index_template/lab-log-ilm-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["lab-logs-*"],
    "priority": 200,
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.lifecycle.name": "lab-log-policy",
        "index.lifecycle.rollover_alias": "lab-logs"
      },
      "mappings": {
        "properties": {
          "@timestamp": {"type": "date"},
          "level":      {"type": "keyword"},
          "service":    {"type": "keyword"},
          "message":    {"type": "text"}
        }
      }
    }
  }' | jq .
echo ""

# --------------------------------------------------------------
# STEP 5: ILM 초기 인덱스 생성
# --------------------------------------------------------------
echo ">>> [STEP 5] ILM 초기 인덱스 생성 (rollover alias 포함)"
curl -s -X PUT "$ES_HOST/lab-logs-000001" \
  -H 'Content-Type: application/json' \
  -d '{
    "aliases": {
      "lab-logs": {"is_write_index": true}
    }
  }' | jq .acknowledged
echo ""

# --------------------------------------------------------------
# STEP 6: 로그 데이터 색인 (rollover 조건 충족)
# --------------------------------------------------------------
echo ">>> [STEP 6] 로그 데이터 색인 (25건 - max_docs:20 초과)"
for i in $(seq 1 25); do
  LEVEL="INFO"
  if [ $((i % 5)) -eq 0 ]; then LEVEL="ERROR"; fi
  curl -s -X POST "$ES_HOST/lab-logs/_doc" \
    -H 'Content-Type: application/json' \
    -d "{
      \"@timestamp\": \"2024-01-15T10:$(printf '%02d' $((i % 60))):00Z\",
      \"level\": \"$LEVEL\",
      \"service\": \"app-service\",
      \"message\": \"Log message $i\"
    }" | jq -r '"\(._index): \(.result)"'
done
sleep 1
echo ""

echo "--- 현재 인덱스 상태"
curl -s "$ES_HOST/_cat/indices/lab-logs-*?v&h=index,docs.count,health" | column -t
echo ""

# --------------------------------------------------------------
# STEP 7: ILM 상태 확인
# --------------------------------------------------------------
echo ">>> [STEP 7] ILM 상태 확인 (_ilm/explain)"
curl -s "$ES_HOST/lab-logs-000001/_ilm/explain" | jq '.indices["lab-logs-000001"] | {
  index,
  phase: .phase,
  action: .action,
  step: .step,
  age: .age,
  policy: .policy
}'
echo ""

# --------------------------------------------------------------
# STEP 8: 수동 Rollover 트리거
# --------------------------------------------------------------
echo ">>> [STEP 8] 수동 Rollover 실행 (ILM 자동 대기 없이 즉시)"
curl -s -X POST "$ES_HOST/lab-logs/_rollover" | jq '{rolled_over, old_index, new_index}'
echo ""

sleep 1
echo "--- rollover 후 인덱스 목록"
curl -s "$ES_HOST/_cat/indices/lab-logs-*?v&h=index,docs.count" | column -t
echo ""

echo "--- 새 인덱스에서 계속 색인 (lab-logs alias -> 새 인덱스)"
for i in $(seq 1 5); do
  curl -s -X POST "$ES_HOST/lab-logs/_doc" \
    -H 'Content-Type: application/json' \
    -d "{\"@timestamp\": \"2024-01-16T10:00:$(printf '%02d' $i)Z\", \"level\": \"INFO\", \"service\": \"app\", \"message\": \"Post-rollover $i\"}" | jq -r '._index'
done
echo ""

# --------------------------------------------------------------
# STEP 9: ILM 실행 간격 단축 (실습용)
# --------------------------------------------------------------
echo ">>> [STEP 9] ILM 실행 간격을 10초로 단축 (실습용)"
echo "--- 기본값은 10분. 실습을 위해 10초로 단축"
curl -s -X PUT "$ES_HOST/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "transient": {
      "indices.lifecycle.poll_interval": "10s"
    }
  }' | jq .acknowledged
echo ""

echo "--- ILM 강제 실행"
curl -s -X POST "$ES_HOST/_ilm/move/lab-logs-000001" \
  -H 'Content-Type: application/json' \
  -d '{
    "current_step": {
      "phase": "hot",
      "action": "rollover",
      "name": "check-rollover-ready"
    },
    "next_step": {
      "phase": "warm",
      "action": "forcemerge",
      "name": "forcemerge"
    }
  }' | jq . 2>/dev/null || echo "--- (현재 단계에 따라 이동 가능 여부 다름)"
echo ""

# --------------------------------------------------------------
# STEP 10: ILM 설정 복원 및 정리
# --------------------------------------------------------------
echo ">>> [STEP 10] ILM 실행 간격 복원 및 정리"
curl -s -X PUT "$ES_HOST/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{"transient": {"indices.lifecycle.poll_interval": null}}' | jq .acknowledged

echo "--- 실습 인덱스 정리"
curl -s -X DELETE "$ES_HOST/lab-logs-*" | jq .
curl -s -X DELETE "$ES_HOST/_index_template/lab-log-ilm-template" | jq .
curl -s -X DELETE "$ES_HOST/_ilm/policy/lab-log-policy" | jq .
echo ""

echo "============================================================"
echo "  실습 완료"
echo "  05-cluster-operations 실습 전체 완료!"
echo "  다음 실습: 06-internal-and-performance/"
echo "============================================================"
