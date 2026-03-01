# Kafka Lab 실습 가이드

## 환경 구성

### 구성 요소
- Kafka 3.7.1 (KRaft 모드, ZooKeeper 없음)
- 3-broker 클러스터
- Kafka UI (http://localhost:8080)
- Prometheus (http://localhost:9090) + Grafana (http://localhost:3000)

### 시작하기

```bash
# 기본 환경만
docker compose up -d

# 모니터링 포함
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# 상태 확인
docker compose ps

# 종료
docker compose down        # 데이터 보존
docker compose down -v     # 완전 정리
```

### 접속 정보
| 서비스 | URL | 비고 |
|--------|-----|------|
| Kafka Broker 1 | localhost:9092 | |
| Kafka Broker 2 | localhost:9094 | |
| Kafka Broker 3 | localhost:9096 | |
| Kafka UI | http://localhost:8080 | 토픽/메시지/컨슈머그룹 |
| Prometheus | http://localhost:9090 | 메트릭 쿼리 |
| Grafana | http://localhost:3000 | admin/admin |

## 실습 목록

### 실습 01: 토픽과 파티션 조작
- Study Vault: 02-토픽과-파티션/concepts.md
- 스크립트: scripts/01-topic-operations.sh
- 목적: 토픽 CRUD, 파티션 확장, 설정 변경
- 관찰 포인트: 파티션 리더 분배, ISR 상태, 파티션은 줄일 수 없는 이유

### 실습 02: acks 설정별 프로듀서 성능 비교
- Study Vault: 03-프로듀서/concepts.md
- 스크립트: scripts/02-producer-acks-comparison.sh
- 목적: acks=0/1/all의 처리량과 안정성 트레이드오프 직접 체험
- 관찰 포인트: 처리량 차이, 리더 장애 시 데이터 유실 여부

### 실습 03: 컨슈머 그룹과 파티션 할당
- Study Vault: 04-컨슈머/concepts.md
- 스크립트: scripts/03-consumer-group-practice.sh
- 목적: 컨슈머 그룹 동작, LAG 모니터링, 오프셋 리셋
- 관찰 포인트: 파티션 할당, 리밸런스, LAG 변화

### 실습 04: 리플리케이션과 ISR
- Study Vault: 02-토픽과-파티션/concepts.md
- 스크립트: scripts/04-replication-test.sh
- 목적: 브로커 장애 시 ISR 변화, 리더 선출, 데이터 안전성 확인
- 관찰 포인트: ISR 축소/복구, min.insync.replicas 효과

### 실습 05: 로그 세그먼트 탐색
- Study Vault: 02-토픽과-파티션/concepts.md
- 스크립트: scripts/05-log-segment-inspection.sh
- 목적: 카프카 데이터 저장 구조 직접 확인
- 관찰 포인트: .log/.index/.timeindex 파일, 세그먼트 롤링

## 추천 학습 순서

1. 실습 01 → 토픽과 파티션의 기본 개념 확인
2. 실습 05 → 내부 저장 구조 이해
3. 실습 04 → 리플리케이션과 장애 복구
4. 실습 02 → 프로듀서 안전성 vs 성능
5. 실습 03 → 컨슈머 그룹과 오프셋 관리

## 트러블슈팅

### 브로커가 시작되지 않는 경우
- Docker Desktop 메모리 확인 (최소 4GB 권장)
- `docker compose logs broker-1` 로 로그 확인
- CLUSTER_ID가 모든 브로커에서 동일한지 확인

### Kafka UI 접속 불가
- 브로커 3대가 모두 healthy 상태인지 확인
- `docker compose ps` 로 상태 확인

## 참고
- Study Vault: study-vault/카프카/카프카_통합_Part1/
- 관련 스킬: /study 카프카, /lab kafka destroy
