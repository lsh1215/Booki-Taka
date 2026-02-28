# Elasticsearch 실습 가이드

실무 기반 Elasticsearch 핸즈온 실습 모음. 각 디렉토리는 특정 주제를 독립적으로 학습할 수 있도록 설계되어 있다.

---

## 환경 요구사항

| 항목 | 최소 | 권장 |
|------|------|------|
| Docker Desktop | 4.x 이상 | 최신 |
| 메모리 | 6GB | 8GB 이상 |
| CPU | 2코어 | 4코어 이상 |
| jq | 1.6 이상 | 최신 |

### jq 설치

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

### Elasticsearch 클러스터 시작

```bash
cd labs/elasticsearch/
./scripts/start.sh              # 기본 시작
./scripts/start.sh --with-monitoring  # 모니터링 포함

# 클러스터 상태 확인 (green이 될 때까지 대기)
curl -s http://localhost:9200/_cluster/health | jq .status
```

### nori 한국어 형태소 분석기

nori 플러그인은 `Dockerfile.es`를 통해 ES 이미지에 사전 설치되어 있다. `docker compose build`만 하면 바로 사용 가능하다.

---

## 실습 순서

```
1. 인덱스 설계 & 매핑     (01-index-and-mapping/)
2. 애널라이저             (02-analyzer/)
3. 검색 & Query DSL      (03-search-query-dsl/)
4. 집계                  (04-aggregation/)
5. 클러스터 운영          (05-cluster-operations/)
6. 내부 동작 & 성능       (06-internal-and-performance/)
```

순서대로 진행하는 것을 권장하지만, 각 디렉토리는 독립적으로 실행 가능하다.

---

## 사용법

각 실습 디렉토리의 `README.md`를 먼저 읽고, 번호 순서대로 스크립트를 실행한다.

```bash
# 예시: 01-index-and-mapping 실습
cd labs/elasticsearch/practices/01-index-and-mapping/
cat README.md          # 실습 목적과 관찰 포인트 확인
bash 01-create-index.sh
bash 02-explicit-mapping.sh
# ...
```

### ES_HOST 환경변수

모든 스크립트는 `ES_HOST` 환경변수를 사용한다. 기본값은 `http://localhost:9200`.

```bash
# 기본 사용 (localhost:9200)
bash 01-create-index.sh

# 다른 호스트 지정
ES_HOST=http://192.168.1.100:9200 bash 01-create-index.sh
```

---

## 실습 디렉토리 설명

| 디렉토리 | 주제 | 핵심 개념 |
|----------|------|----------|
| 01-index-and-mapping | 인덱스와 매핑 | 샤드, 매핑, 필드 타입 |
| 02-analyzer | 텍스트 분석 | 토크나이저, 토큰 필터, nori |
| 03-search-query-dsl | 검색 쿼리 | match, term, bool, 스코어링 |
| 04-aggregation | 집계 | 메트릭, 버킷, 파이프라인 |
| 05-cluster-operations | 클러스터 운영 | 템플릿, alias, ILM, 스냅샷 |
| 06-internal-and-performance | 내부 동작 | 세그먼트, refresh, flush, 캐시 |

---

## 참고 자료

- 엘라스틱서치 바이블 (위키북스)
- Elasticsearch 실무 가이드 (위키북스)
- Elasticsearch 공식 문서: https://www.elastic.co/guide/en/elasticsearch/reference/8.12/index.html
