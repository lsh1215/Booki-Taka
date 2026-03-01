# 카프카 통합 Study Vault (Part 1: 기초)

## 학습 지도

```
Topic 01 (아키텍처) → Topic 02 (토픽/파티션)
                         ↙           ↘
            Topic 03 (프로듀서)    Topic 04 (컨슈머)
```

## 토픽 목록

| # | 토픽 | 핵심 개념 수 | 연습 문제 수 | 난이도 | 태그 |
|---|------|-------------|------------|--------|------|
| 01 | [핵심 아키텍처](./01-핵심-아키텍처/concepts.md) | 6 | 10 | ★☆☆ | #broker #cluster #zookeeper #kraft #controller #distributed-system |
| 02 | [토픽과 파티션](./02-토픽과-파티션/concepts.md) | 8 | 10 | ★★☆ | #topic #partition #offset #segment #record #replication #isr #log-compaction |
| 03 | [프로듀서](./03-프로듀서/concepts.md) | 8 | 10 | ★★☆ | #producer #serializer #partitioner #acks #batch #compression #idempotent #transaction |
| 04 | [컨슈머](./04-컨슈머/concepts.md) | 8 | 10 | ★★☆ | #consumer #consumer-group #rebalance #offset-commit #polling #partition-assignment #coordinator |

## 학습 통계

- **총 핵심 개념**: 30개
- **총 연습 문제**: 40개
- **전체 추정 학습 시간**: 20-25시간

## 주요 학습 경로

### 초급자 경로
1. Topic 01: 핵심 아키텍처 (Kafka의 기본 구조 이해)
2. Topic 02: 토픽과 파티션 (데이터 저장소 구조)
3. Topic 03 또는 04 선택 (프로듀서/컨슈머 중 관심사 선택)

### 전체 숙달 경로
1. Topic 01 → Topic 02 (기초 완성)
2. Topic 03 (프로듀서 이해)
3. Topic 04 (컨슈머 이해)
4. 통합 연습 및 실제 케이스 분석

## 약점 영역

_(학습 후 tracking/ 메타인지 추적 파일에서 자동 반영)_

## 참고

- 출처: 카프카 핵심 가이드(그웬 샤피라 외), 실전카프카(여백줄임), 아파치 카프카 애플리케이션 프로그래밍(최원영)
- 생성일: 2026-03-01
- 관련 스킬: `/study`로 깊이 파기, `/lab kafka`로 실습
