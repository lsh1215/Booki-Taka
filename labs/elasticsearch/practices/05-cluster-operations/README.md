# 05. 클러스터 운영 (Cluster Operations)

## 실습 목적

Elasticsearch 클러스터를 실무에서 안정적으로 운영하는 데 필요한 핵심 API와 기능을 학습한다.
인덱스 템플릿으로 일관된 매핑을 관리하고, Alias와 Rollover로 무중단 인덱스 전환을,
ILM으로 데이터 생명주기를 자동화하는 방법을 익힌다.

---

## 관련 챕터

- 엘라스틱서치 바이블: 9장 (클러스터 관리), 10장 (인덱스 템플릿), 11장 (ILM)
- Elasticsearch 실무 가이드: 8장 (클러스터 운영)

---

## 실습 전 확인사항

### 스냅샷 실습 (05-snapshot-restore.sh)

로컬 파일시스템 스냅샷 저장소를 사용하려면 `path.repo` 설정이 필요하다.
`docker-compose.yml`에 다음을 추가:

```yaml
# es01, es02, es03 서비스에 추가
environment:
  - path.repo=/usr/share/elasticsearch/snapshots
volumes:
  - es-snapshots:/usr/share/elasticsearch/snapshots

volumes:
  es-snapshots:
```

---

## 실습 절차

```
bash 01-cluster-health.sh   # 클러스터 상태 확인
bash 02-shard-allocation.sh # 샤드 할당 관찰
bash 03-index-template.sh   # 인덱스 템플릿 + 컴포넌트 템플릿
bash 04-alias-rollover.sh   # Alias와 Rollover
bash 05-snapshot-restore.sh # 스냅샷 백업/복구
bash 06-reindex.sh          # Reindex API
bash 07-ilm.sh              # Index Lifecycle Management
```

---

## 관찰 포인트

### 01-cluster-health.sh
- `status: green/yellow/red` 의 의미와 발생 조건
- `_cat` API의 `v` 파라미터로 헤더 출력, `h` 파라미터로 컬럼 선택
- `unassigned_shards`가 발생하는 원인

### 03-index-template.sh
- 컴포넌트 템플릿(reusable) vs 인덱스 템플릿(composed_of)
- `priority`가 높은 템플릿이 우선 적용됨
- 와일드카드 패턴으로 새 인덱스에 자동 적용

### 04-alias-rollover.sh
- Alias를 사용하면 애플리케이션 코드 변경 없이 인덱스를 교체할 수 있다
- Rollover 조건: max_docs, max_size, max_age 중 하나라도 충족하면 새 인덱스 생성
- write alias와 read alias의 구분

### 07-ilm.sh
- Hot-Warm-Cold-Delete 4단계 데이터 생명주기
- ILM 정책 + 인덱스 템플릿 연동으로 자동화
- `_ilm/explain`으로 현재 인덱스의 ILM 상태 확인

---

## 핵심 질문

1. 클러스터 상태가 yellow일 때 데이터 손실이 발생하는가?
2. 인덱스 템플릿 vs 동적 매핑: 언제 어떤 것을 사용해야 하는가?
3. Rollover를 사용하는 이유는 무엇인가? 단순히 새 인덱스를 수동으로 만드는 것과의 차이는?
4. Reindex와 Update by Query의 차이는 무엇인가?
5. ILM의 Warm 단계에서 force_merge를 하는 이유는 무엇인가?
