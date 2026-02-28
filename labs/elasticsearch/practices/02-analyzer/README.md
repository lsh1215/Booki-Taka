# 02. 애널라이저 (Analyzer)

## 실습 목적

Elasticsearch의 텍스트 분석 파이프라인을 이해한다. 텍스트가 색인되거나 검색될 때 어떤 과정을 거쳐 토큰으로 변환되는지 직접 관찰하고, 커스텀 애널라이저를 구성하는 방법을 익힌다.

애널라이저 = Character Filter(선처리) + Tokenizer(분리) + Token Filter(후처리)

---

## 관련 챕터

- 엘라스틱서치 바이블: 5장 (텍스트 분석)
- Elasticsearch 실무 가이드: 4장 (애널라이저)

---

## 실습 전 확인사항

### nori 플러그인 설치 (04-nori-korean.sh 실습 전)

nori는 Elasticsearch에 기본 포함되지 않는 플러그인이다. 실습 전 설치가 필요하다.

```bash
# 실행 중인 컨테이너에 설치 (재시작 필요)
docker exec es01 elasticsearch-plugin install analysis-nori
docker exec es02 elasticsearch-plugin install analysis-nori
docker exec es03 elasticsearch-plugin install analysis-nori
docker-compose restart

# 또는 Dockerfile로 이미지 빌드
# FROM docker.elastic.co/elasticsearch/elasticsearch:8.12.0
# RUN elasticsearch-plugin install analysis-nori
```

---

## 실습 절차

```
bash 01-analyze-api.sh       # Analyze API로 분석 과정 관찰
bash 02-builtin-analyzers.sh # 내장 애널라이저 비교
bash 03-custom-analyzer.sh   # 커스텀 애널라이저 생성
bash 04-nori-korean.sh       # 한국어 nori 형태소 분석기
bash 05-normalizer.sh        # 노멀라이저 실습
```

---

## 관찰 포인트

### 01-analyze-api.sh
- `_analyze` API 응답에서 `token`, `start_offset`, `end_offset`, `position`의 의미
- standard 애널라이저는 한국어를 어떻게 처리하는가
- `char_filter`를 거치기 전과 후의 텍스트 차이

### 02-builtin-analyzers.sh
- `standard` vs `whitespace`: 구두점 처리 방식의 차이
- `simple` vs `keyword`: 소문자 변환 여부
- `english` 애널라이저의 어간 추출(stemming) 동작

### 03-custom-analyzer.sh
- char_filter, tokenizer, token_filter를 조합하는 방법
- `synonym` 토큰 필터로 동의어를 처리하면 어떤 토큰이 생성되는가
- `edge_ngram`으로 자동완성 기능을 구현하는 원리

### 04-nori-korean.sh
- nori가 "삼성전자"를 어떻게 분해하는가 ("삼성" + "전자")
- `nori_part_of_speech` 필터로 조사, 어미를 제거하는 효과
- `user_dictionary`로 사용자 정의 사전을 등록하는 방법

### 05-normalizer.sh
- 노멀라이저는 애널라이저와 어떤 점이 다른가 (토크나이저 없음, 단일 토큰)
- keyword 필드에서 대소문자를 무시하고 검색하기 위한 방법

---

## 핵심 질문

1. `_analyze` API는 어떤 상황에서 유용한가?
2. 애널라이저가 색인 시와 검색 시 다르게 적용되면 어떤 문제가 생기는가?
3. `synonym` 토큰 필터를 색인 시에만 적용하는 것과 검색 시에만 적용하는 것의 차이는?
4. 한국어 검색에서 nori를 사용해야 하는 이유를 standard 애널라이저와 비교하여 설명하라.
5. keyword 필드에는 왜 애널라이저가 아닌 노멀라이저를 사용하는가?
