# 01. 인덱스와 매핑 (Index & Mapping)

## 실습 목적

Elasticsearch에서 데이터를 저장하기 전에 반드시 이해해야 하는 인덱스 구조와 매핑 설계를 실습한다.
매핑은 관계형 DB의 스키마에 해당하며, 한번 생성된 필드 타입은 변경할 수 없으므로 설계 단계에서 올바르게 결정해야 한다.

---

## 관련 챕터

- 엘라스틱서치 바이블: 3장 (인덱스 설계), 4장 (매핑)
- Elasticsearch 실무 가이드: 2장 (인덱스 관리), 3장 (매핑)

---

## 실습 절차

```
bash 01-create-index.sh          # 인덱스 생성 및 설정
bash 02-explicit-mapping.sh      # 명시적 매핑 생성
bash 03-dynamic-mapping.sh       # 동적 매핑 실험
bash 04-field-types.sh           # 다양한 필드 타입 비교
bash 05-doc-values-fielddata.sh  # doc_values vs fielddata
bash 06-source-field.sh          # _source 필드 활용
```

---

## 관찰 포인트

### 01-create-index.sh
- `number_of_shards`와 `number_of_replicas` 설정이 클러스터 상태에 미치는 영향
- `refresh_interval`을 `-1`로 설정했을 때 검색 결과에 어떤 변화가 생기는가
- `_cat/indices?v` 결과에서 `health`, `status`, `pri`, `rep` 컬럼 의미

### 02-explicit-mapping.sh
- 명시적 매핑에서 정의하지 않은 필드를 문서에 포함시키면 어떻게 되는가 (dynamic 설정)
- `text`와 `keyword`의 차이: 어떤 필드가 full-text 검색 대상이고 어떤 필드가 정확값 검색 대상인가

### 03-dynamic-mapping.sh
- ES가 자동으로 추론하는 타입이 항상 올바른가
- 숫자처럼 보이는 문자열(예: "12345")을 동적 매핑하면 어떤 타입이 되는가
- `dynamic: strict` 설정 시 알 수 없는 필드가 들어오면 어떤 에러가 발생하는가

### 04-field-types.sh
- `integer`와 `long`의 범위 차이
- `date` 필드에 허용되는 포맷 종류
- `geo_point` 타입은 어떤 형태의 값을 받는가

### 05-doc-values-fielddata.sh
- `doc_values: false`인 `text` 필드를 집계하면 어떤 에러가 발생하는가
- `fielddata: true`를 활성화하면 메모리에 어떤 영향을 주는가
- `keyword` 필드는 별도 설정 없이 왜 집계가 가능한가

### 06-source-field.sh
- `_source: false` 인덱스에서 문서를 조회하면 무엇이 반환되는가
- `includes`/`excludes`로 _source를 필터링하면 어떤 필드만 반환되는가

---

## 핵심 질문

실습 후 스스로 답해보자.

1. 인덱스의 샤드 수는 생성 후에 변경할 수 있는가? 레플리카 수는?
2. `text` 타입과 `keyword` 타입의 차이를 한 문장으로 설명하라.
3. 동적 매핑의 위험성은 무엇인가? 언제 `dynamic: strict`를 사용해야 하는가?
4. `doc_values`와 `fielddata`는 각각 어디에 저장되며, 어떤 용도로 사용되는가?
5. 프로덕션에서 `_source`를 비활성화하는 것이 권장되는가? 그 이유는?
