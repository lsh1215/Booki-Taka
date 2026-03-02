# 03 분석기 — 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch3 §3.4 (p.97-131) / 엘라스틱서치바이블 Ch3 §3.3 (p.77-93)
> 태그: #analyzer #tokenizer #token-filter #char-filter #inverted-index #nori #ngram

---

## 기초 (40%)

### Q1. 텍스트 분석 파이프라인 순서

엘라스틱서치 애널라이저가 텍스트를 처리하는 세 단계를 올바른 순서로 나열하고, 각 단계의 역할을 한 문장으로 설명하라.

<details>
<summary>정답</summary>

1. **캐릭터 필터** (Character Filter): 토크나이저 실행 전 원문 텍스트 자체를 수정한다. HTML 제거, 문자 치환 등 전처리를 수행한다. 0개 이상 지정 가능하며 순서대로 실행된다.

2. **토크나이저** (Tokenizer): 가공된 문자열을 규칙에 따라 여러 토큰으로 분리한다. 애널라이저에 정확히 1개만 지정할 수 있다.

3. **토큰 필터** (Token Filter): 토큰 스트림을 받아 토큰을 추가·변경·삭제한다. 0개 이상 지정 가능하며 지정 순서대로 순차 실행된다.

최종 결과물인 텀(term)이 역색인에 저장된다.

</details>

---

### Q2. 역색인 구조

다음 두 문서가 있다.
- 문서1: `elasticsearch is cool`
- 문서2: `Elasticsearch is great`

standard 애널라이저(lowercase 포함)로 분석한 뒤 생성되는 역색인 구조를 표로 나타내라. 각 텀에 대해 포함된 문서 번호와 위치(position)를 기록하라.

<details>
<summary>정답</summary>

lowercase 필터 적용 후:

| 텀 | 문서 번호 | 위치(Position) |
|---|---|---|
| elasticsearch | 문서1, 문서2 | 1, 1 |
| is | 문서1, 문서2 | 2, 2 |
| cool | 문서1 | 3 |
| great | 문서2 | 3 |

핵심:
- `Elasticsearch`(문서2)와 `elasticsearch`(문서1)는 lowercase 처리 후 동일한 텀 `elasticsearch`로 통합된다.
- 색인 파일에 저장되는 텀만 변경되며, `_source`에 저장된 원문은 변경되지 않는다.

</details>

---

### Q3. 내장 애널라이저 선택

다음 각 시나리오에 적합한 내장 애널라이저를 고르고 이유를 설명하라.

1. 사용자가 입력한 국가 코드 "KR"을 그대로 색인해서 "KR"로만 검색되게 하고 싶다.
2. 영문 기술 문서에서 "the", "a", "is" 같은 불용어를 제거하고 색인하고 싶다.
3. 공백 기준으로만 분리하고 대소문자를 유지하고 싶다.

<details>
<summary>정답</summary>

1. **keyword 애널라이저**: 입력 텍스트 전체를 단일 토큰으로 반환한다. 토큰화를 수행하지 않으므로 "KR"로만 검색 가능하다. (단, keyword 타입 필드 자체가 이 동작을 기본으로 함)

2. **stop 애널라이저**: standard 애널라이저와 동일하지만 stop 토큰 필터가 추가되어 불용어를 제거한다. 또는 커스텀 애널라이저에서 stop 필터를 직접 구성해도 된다.

3. **whitespace 애널라이저**: whitespace 토크나이저로만 구성되어 공백 경계에서만 분리하고 대소문자 변환을 수행하지 않는다.

</details>

---

### Q4. analyze API 사용법

아래 API 호출에서 `char_filter`, `tokenizer`, `filter` 키를 각각 단독으로 테스트할 때 사용하는 방법의 차이를 설명하라. 특히 토큰 필터를 테스트할 때 주의해야 할 점은 무엇인가?

```json
POST _analyze
{
  "??": ["lowercase"],
  "text": "Hello, World!"
}
```

<details>
<summary>정답</summary>

각 컴포넌트를 단독으로 테스트하는 키:
- 캐릭터 필터: `"char_filter": ["html_strip"]`
- 토크나이저: `"tokenizer": "standard"`
- 토큰 필터: `"filter": ["lowercase"]`

**주의**: 토큰 필터의 키는 `"token_filter"`가 아니라 **`"filter"`** 다. 실무가이드에서도 이 차이를 명시적으로 경고하고 있다.

토큰 필터만 단독 적용 시 토크나이저가 없어도 동작하지만, 입력 텍스트 전체가 하나의 토큰으로 처리된다. 따라서 위 예시에서 `"Hello, World!"`는 `"hello, world!"`로 변환된다 (쉼표와 느낌표 포함).

</details>

---

## 응용 (40%)

### Q5. 캐릭터 필터 실전 사용

다음과 같은 로마 숫자로 시작하는 목차 형식의 텍스트를 색인하려 한다.

```
i.Hello ii.World iii.Bye, iv.World!
```

이 텍스트에서 `i. → 1.`, `ii. → 2.`, `iii. → 3.`, `iv. → 4.`로 변환한 뒤 공백 기준으로 분리하고, 최종적으로 소문자화하는 커스텀 애널라이저를 설계하라. 사용할 캐릭터 필터 종류와 인덱스 생성 쿼리의 핵심 구조를 작성하라.

<details>
<summary>정답</summary>

사용할 컴포넌트:
- 캐릭터 필터: **mapping** (문자 치환 맵 선언)
- 토크나이저: **whitespace** (공백 기준 분리)
- 토큰 필터: **lowercase** (소문자화)

```json
PUT analyzer_test2
{
  "settings": {
    "analysis": {
      "char_filter": {
        "my_char_filter": {
          "type": "mapping",
          "mappings": [
            "i. => 1.",
            "ii. => 2.",
            "iii. => 3.",
            "iv. => 4."
          ]
        }
      },
      "analyzer": {
        "my_analyzer": {
          "char_filter": ["my_char_filter"],
          "tokenizer": "whitespace",
          "filter": ["lowercase"]
        }
      }
    }
  }
}
```

테스트:
```json
GET analyzer_test2/_analyze
{
  "analyzer": "my_analyzer",
  "text": "i.Hello ii.World iii.Bye, iv.World!"
}
```

예상 결과: `[1.hello, 2.world, 3.bye,, 4.world!]`

</details>

---

### Q6. ngram vs edge_ngram 선택

다음 두 요구사항에 각각 적합한 토크나이저를 선택하고 그 이유를 설명하라.

1. 상품명 검색에서 " samsung"을 입력하면 "삼성SAMSUNG", "SAMSUNG Galaxy", "new samsung tv" 모두 검색되어야 한다. 단어 어느 위치에 있어도 매칭.
2. 자동완성 기능에서 "sam"을 입력하면 "samsung"으로 시작하는 단어만 제안된다.

<details>
<summary>정답</summary>

1. **ngram 토크나이저**:
   - ngram은 단어의 모든 위치에서 지정된 길이의 토큰을 생성한다.
   - "samsung" → [sa, sam, ams, msu, sun, un, ng, ...] (min_gram=2 기준)
   - 단어 중간 어느 위치의 부분 문자열로도 검색 가능하다.
   - 단점: 인덱스 크기가 급격히 증가, precision 저하 가능.

2. **edge_ngram 토크나이저**:
   - edge_ngram은 모든 토큰의 시작이 단어의 시작으로 고정된다.
   - "samsung" → [sa, sam, sams, samsu, samsun, samsung]
   - 접두사(prefix) 기반 검색에 최적화되어 있어 자동완성에 적합하다.
   - ngram 대비 인덱스 크기가 작다.

</details>

---

### Q7. 동의어 사전 설계

전자상거래 검색 시스템에서 다음 요구사항을 구현하기 위한 동의어 사전 파일 내용과 synonym 필터 설정을 작성하라.

- "TV"로 검색하면 "텔레비전"으로 색인된 문서도 검색됨
- "핸드폰"으로 검색하면 "스마트폰"으로도 검색됨 (양방향)
- "갤럭시"는 색인 시 "galaxy"로만 저장 (단방향 치환)

<details>
<summary>정답</summary>

`config/analysis/synonym.txt` 파일 내용:
```
TV, 텔레비전
핸드폰, 스마트폰
갤럭시 => galaxy
```

- 쉼표 구분: 동의어 추가 (양방향). "TV"와 "텔레비전" 모두 색인하여 어느 쪽으로 검색해도 히트.
- `=>` 구분: 동의어 치환 (단방향). "갤럭시"를 "galaxy"로 교체하여 "갤럭시"로 검색해도 "galaxy" 역색인에서 찾음.

인덱스 설정:
```json
PUT product_index
{
  "settings": {
    "analysis": {
      "filter": {
        "synonym_filter": {
          "type": "synonym",
          "synonyms_path": "analysis/synonym.txt"
        }
      },
      "analyzer": {
        "product_analyzer": {
          "tokenizer": "standard",
          "filter": ["lowercase", "synonym_filter"]
        }
      }
    }
  }
}
```

주의: lowercase 필터를 synonym 필터보다 먼저 적용했으므로, 사전 파일에도 소문자로 등록해야 한다 (또는 최신 ES 버전에서는 자동으로 인식).

</details>

---

### Q8. 색인/검색 분석기 분리

다음과 같은 시나리오를 구현하려 한다:
- 색인 시점: "Harry Potter and the Chamber of Secrets"에서 불용어(the, and, of)를 제거하고 저장
- 검색 시점: 불용어를 제거하지 않고 검색 (검색어 "Chamber of Secrets"가 그대로 분석됨)

이를 위한 인덱스 매핑 설정의 핵심 구조를 작성하고, 왜 색인과 검색에 다른 분석기를 사용하는지 설명하라.

<details>
<summary>정답</summary>

```json
PUT movie_analyzer
{
  "settings": {
    "analysis": {
      "analyzer": {
        "movie_lower_test_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase"]
        },
        "movie_stop_test_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "english_stop"]
        }
      },
      "filter": {
        "english_stop": {
          "type": "stop",
          "stopwords": "_english_"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "movie_stop_test_analyzer",
        "search_analyzer": "movie_lower_test_analyzer"
      }
    }
  }
}
```

색인 결과: `[harry, potter, chamber, secrets]` (the, and, of 제거됨)

검색어 "Chamber of Secrets" 분석 결과(검색 시점): `[chamber, of, secrets]`

왜 분리하는가:
- 색인 시 불용어를 제거하면 인덱스 크기 감소 및 검색 성능 향상.
- 그러나 검색 시에도 불용어를 제거하면 "of the" 같은 검색어의 "of"가 제거되어 역색인에서 못 찾는 문제가 발생할 수 있다.
- 색인에서 제거된 불용어는 어차피 역색인에 없으므로 검색 결과에 영향 없음. 검색 시 불용어를 제거하지 않아도 무해하다.

</details>

---

## 심화 (20%)

### Q9. nori 분석기 동작 분석

다음 문장을 nori 애널라이저로 분석할 때 예상되는 토큰 결과와 분석 방식을 설명하라. standard 애널라이저와의 차이도 비교하라.

```
우리는 컴퓨터를 다룬다.
```

또한 nori 플러그인 설치 시 운영 관점에서 고려해야 할 사항 두 가지를 설명하라.

<details>
<summary>정답</summary>

**nori 분석 결과**:
```json
{"token": "우리", "position": 0}
{"token": "컴퓨터", "position": 2}
{"token": "다루", "position": 4}
```

nori는:
- 조사 "는" (는/JX), "를" (를/JKO) 제거
- "다룬다"에서 어간 "다루" 추출, 어미 "ㄴ다" 제거

**standard 분석 결과**:
```json
{"token": "우리는", "position": 0}
{"token": "컴퓨터를", "position": 1}
{"token": "다룬다", "position": 2}
```

standard는 한국어 형태소를 인식하지 못해 어절 단위로만 분리한다. "컴퓨터"로 검색 시 "컴퓨터를" 텀과 매칭되지 않아 검색 실패.

**운영 고려사항**:
1. **모든 노드에 설치 필요**: 클러스터를 구성하는 모든 노드에서 `elasticsearch-plugin install analysis-nori`를 실행해야 한다. 일부 노드에만 설치하면 샤드 할당 오류 발생 가능.
2. **재기동 필요**: 플러그인 설치 완료 후 엘라스틱서치 클러스터를 재기동해야 새로 설치한 플러그인이 적용된다. 무중단 운영 환경에서는 롤링 재기동 계획이 필요하다.

</details>

---

### Q10. 역색인 한계와 분석기 설계 문제

다음 상황을 분석하고 해결 방안을 제시하라.

전자문서 검색 시스템에서 다음과 같은 문제가 발생했다:
- "Samsung Galaxy S24 Ultra"라는 상품명을 색인했는데 "galaxy s24"로 검색 시 결과가 없음
- "엘라스틱서치"로 검색 시 "Elasticsearch"가 포함된 문서가 검색되지 않음
- 자동완성에서 "Sams"를 입력했을 때 "Samsung"이 제안되어야 함

각 문제의 원인과 해결을 위한 분석기 구성 방안을 설명하라.

<details>
<summary>정답</summary>

**문제 1: "galaxy s24"로 검색 시 "Galaxy S24 Ultra" 문서가 없음**

원인: 대소문자 불일치. "Galaxy"(대문자 G)는 standard 애널라이저에서 소문자화되어 "galaxy"로 저장되지만, 검색어 "galaxy"도 소문자이므로 매칭되어야 한다. 문제는 필드가 keyword 타입이거나 분석기가 소문자화를 수행하지 않는 경우 발생한다.

해결:
- text 타입에 standard 애널라이저(lowercase 포함) 적용
- 또는 keyword 타입에 lowercase 노멀라이저 적용

**문제 2: "엘라스틱서치"로 "Elasticsearch" 문서 검색 안 됨**

원인: 동의어 매핑 없음. 두 단어는 서로 다른 텀으로 색인된다.

해결:
- 동의어 필터에 `Elasticsearch, 엘라스틱서치` 등록 (양방향 동의어 추가)
- synonym.txt 파일 기반 관리 권장 (운영 중 갱신 가능)

**문제 3: "Sams" 입력 시 자동완성 미작동**

원인: 접두사 기반 부분 일치가 되지 않는 일반 분석기 사용.

해결:
- edge_ngram 토크나이저 사용. 색인 시 "Samsung" → `[Sa, Sam, Sams, Samsu, Samsun, Samsung]`으로 저장
- 검색 시 분석기는 keyword 또는 standard(원문 그대로)로 설정하여 "Sams"를 그대로 검색
- 색인 시 edge_ngram 적용, 검색 시 standard 적용하는 분리 설계 필요

종합 설계:
```json
"analyzer": {
  "autocomplete_index": {
    "tokenizer": "edge_ngram_tokenizer",
    "filter": ["lowercase"]
  },
  "autocomplete_search": {
    "tokenizer": "standard",
    "filter": ["lowercase"]
  }
},
"properties": {
  "productName": {
    "type": "text",
    "analyzer": "autocomplete_index",
    "search_analyzer": "autocomplete_search"
  }
}
```

</details>
