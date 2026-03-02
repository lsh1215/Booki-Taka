# 03 분석기 — 개념 정리

> 출처: 엘라스틱서치 실무가이드 Ch3 §3.4 (p.97-131) / 엘라스틱서치바이블 Ch3 §3.3 (p.77-93)
> 태그: #analyzer #tokenizer #token-filter #char-filter #inverted-index #nori #ngram

---

## 1. 텍스트 분석 파이프라인

### 정의
텍스트를 색인하기 전에 의미 있는 단위(텀)로 변환하는 3단계 처리 과정이다.

### 왜 필요한가
엘라스틱서치는 루씬 기반 텍스트 검색엔진이다. 원문 그대로 저장하면 대소문자, 어형 변화, 표기 차이로 인해 검색이 실패한다. 예컨대 "Elasticsearch"와 "elasticsearch"는 다른 토큰으로 취급된다. 분석 파이프라인은 입력 텍스트를 정규화하여 일관된 검색을 가능하게 한다.

### 동작 원리
```
원문 텍스트
    │
    ▼ [캐릭터 필터] (0개 이상)
가공된 문자열
    │
    ▼ [토크나이저] (정확히 1개)
토큰 스트림
    │
    ▼ [토큰 필터] (0개 이상, 순차 적용)
최종 텀(term) 목록 → 역색인에 저장
```

실무가이드 예시 (`<B>Elasticsearch</B> is cool`):
1. 캐릭터 필터 `html_strip` → `Elasticsearch is cool`
2. 토크나이저 `standard` → `[Elasticsearch][is][cool]`
3. 토큰 필터 `lowercase` → `[elasticsearch][is][cool]`

### 설계 트레이드오프
- 캐릭터 필터·토큰 필터 수가 늘수록 색인 속도 저하 ↔ 검색 정확도 향상
- 색인 시점 분석기(analyzer)와 검색 시점 분석기(search_analyzer)를 다르게 설정할 수 있다. 예) 색인 시 불용어 제거, 검색 시 불용어 유지

### 관련 개념
- [역색인 구조](#2-역색인-구조)
- [커스텀 애널라이저 구성](#8-커스텀-애널라이저-구성)
- [../02-인덱스-설계/concepts.md](../02-인덱스-설계/concepts.md) — text/keyword 필드 타입 선택

---

## 2. 역색인 구조

### 정의
루씬이 텍스트 검색에 사용하는 자료구조로, 토큰 → 해당 토큰이 포함된 문서 목록(포스팅 리스트)의 매핑이다. 책의 색인 페이지와 동일한 개념이다.

### 왜 필요한가
전체 문서를 순차 탐색(sequential scan)하는 대신 토큰을 키로 즉시 문서를 조회할 수 있다. 문서 수가 수억 개여도 검색 속도가 토큰 수에 비례한다.

### 동작 원리
문서 색인 시 각 텀에 대해 다음 정보를 기록한다:

| 텀 | 문서 번호 | 텀의 위치(Position) | 텀의 빈도(TF) |
|---|---|---|---|
| elasticsearch | 문서1, 문서2 | 1, 1 | 2 |
| is | 문서1, 문서2 | 2, 2 | 2 |
| cool | 문서1 | 3 | 1 |
| great | 문서2 | 3 | 1 |

검색어 "elasticsearch"를 입력하면 역색인에서 해당 텀을 찾아 포스팅 리스트(문서 번호 목록)를 반환한다.

**중요**: 색인 파일에 저장되는 텀만 변경되며, `_source`에 저장된 원문은 변경되지 않는다.

### 설계 트레이드오프
- 역색인은 빠른 읽기에 최적화. 쓰기(색인)와 업데이트는 상대적으로 느리다.
- 루씬 세그먼트는 불변(immutable)이므로 업데이트 = 기존 문서 삭제 + 새 문서 색인.
- NoSQL(MongoDB, Cassandra 등)과 달리 역색인이 기본 제공됨 → 전문 검색(full-text search) 가능.

### 관련 개념
- [텍스트 분석 파이프라인](#1-텍스트-분석-파이프라인)
- [../01-핵심-아키텍처/concepts.md](../01-핵심-아키텍처/concepts.md) — 루씬 세그먼트

---

## 3. 내장 애널라이저 종류

### 정의
엘라스틱서치가 루씬의 내장 컴포넌트를 조합하여 미리 만들어 제공하는 애널라이저.

### 주요 목록 (실무가이드 §3.4.3.2, 바이블 §3.3.5)

| 애널라이저 | 토크나이저 | 토큰 필터 | 특징 |
|---|---|---|---|
| **standard** | standard | lowercase | 기본값. 공백·기호 기준 분리, 소문자화 |
| **simple** | letter | lowercase | letter 아닌 문자 경계에서 분리 |
| **whitespace** | whitespace | 없음 | 공백 기준 분리만 수행 |
| **stop** | standard | lowercase, stop | standard + 불용어 제거 |
| **keyword** | keyword | 없음 | 입력 전체를 단일 토큰으로 반환 |
| **pattern** | pattern | lowercase | 정규식으로 구분 |
| **language** | 언어별 | 언어별 | 영어, 독일어 등 지원. 한국어는 미지원 |
| **fingerprint** | standard | lowercase, ASCII folding, stop, fingerprint | 중복 검출용 단일 토큰 생성 |

```bash
# analyze API 사용 예시
POST _analyze
{
  "analyzer": "standard",
  "text": "Harry Potter and the Chamber of Secrets"
}
# 결과: [harry, potter, and, the, chamber, of, secrets]

POST _analyze
{
  "analyzer": "whitespace",
  "text": "Harry Potter and the Chamber of Secrets"
}
# 결과: [Harry, Potter, and, the, Chamber, of, Secrets]

POST _analyze
{
  "analyzer": "keyword",
  "text": "Harry Potter and the Chamber of Secrets"
}
# 결과: [Harry Potter and the Chamber of Secrets]
```

### 설계 트레이드오프
- `standard`는 범용이지만 언어별 형태소를 인식하지 못한다.
- `keyword` 애널라이저를 기본으로 설정하면 text 타입 필드에서도 전체 문자열 단일 토큰으로 색인된다. 인덱스 settings에서 `default` 애널라이저를 지정해 기본값을 변경할 수 있다.

### 관련 개념
- [커스텀 애널라이저 구성](#8-커스텀-애널라이저-구성)
- [한국어 형태소 분석기](#9-한국어-형태소-분석기-nori)

---

## 4. 캐릭터 필터

### 정의
토크나이저 실행 전에 원문 텍스트 자체를 수정하는 전처리 필터. 애널라이저에 0개 이상 지정할 수 있으며 지정 순서대로 실행된다.

### 내장 캐릭터 필터 3종 (바이블 §3.3.2)

| 필터 | 동작 |
|---|---|
| **html_strip** | HTML 태그 제거, HTML 엔티티 디코딩(`&apos;` → `'`) |
| **mapping** | 지정한 문자 쌍을 치환 (`i. => 1.`, `ii. => 2.` 등) |
| **pattern_replace** | 정규식으로 문자 치환 |

```bash
# html_strip 테스트
POST _analyze
{
  "char_filter": ["html_strip"],
  "text": "<p>I&apos;m so <b>happy</b>!</p>"
}
# 결과: "\nI'm so happy!\n"
# <p>, </p>는 줄바꿈으로, <b>, </b>는 제거, &apos;는 홑따옴표로 변환
```

### 설계 트레이드오프
- 캐릭터 필터는 토크나이저보다 활용도가 낮다. 토크나이저 내부에서도 일부 전처리가 가능하기 때문이다.
- `mapping` 필터는 로마 숫자 → 아라비아 숫자 변환 등 도메인 특화 정규화에 유용하다.

### 관련 개념
- [텍스트 분석 파이프라인](#1-텍스트-분석-파이프라인)

---

## 5. 토크나이저

### 정의
캐릭터 스트림을 받아 여러 토큰으로 분리하는 컴포넌트. 애널라이저에 정확히 1개만 지정할 수 있다.

### 주요 내장 토크나이저 (실무가이드 §3.4.5, 바이블 §3.3.3)

#### standard
Unicode Text Segmentation 알고리즘을 사용. 대부분의 구두점은 사라진다. 기본 애널라이저가 사용하는 토크나이저.

#### keyword
입력 텍스트를 그대로 단일 토큰으로 반환. 여러 캐릭터 필터, 토큰 필터와 조합 시 유용하다.

#### whitespace
공백 문자 경계에서만 분리.

#### pattern
지정한 정규식을 단어 구분자로 사용.

#### letter
언어 글자로 분류되지 않는 문자(공백, 특수문자 등)를 만날 때 분리.

#### ngram
```
min_gram ~ max_gram 범위의 모든 문자 조합으로 토큰 생성
예) min=2, max=3, "hello" → [he, hel, el, ell, ll, llo, lo]
```
- `token_chars`로 포함할 문자 타입 지정 가능 (letter, digit, whitespace, punctuation, symbol, custom)
- 먼저 `token_chars`에 없는 문자 경계로 단어를 분리한 후, 각 단어에 ngram 적용
- LIKE `*검색어*` 형태 구현에 활용
- **주의**: `max_gram - min_gram` 차이가 1 초과 시 분석 실패. `index.max_ngram_diff` 인덱스 설정으로 조정 가능(기본값 1)

#### edge_ngram
ngram과 유사하나 모든 토큰의 시작이 단어의 시작 글자로 고정됨.
```
min=2, max=4, token_chars=[letter], "Hello, World!"
→ [He, Hel, Hell, Wo, Wor, Worl]
```
- 자동완성 구현에 주로 활용

```bash
# Standard 토크나이저
POST movie_analyzer/_analyze
{
  "tokenizer": "standard",
  "text": "Harry Potter and the Chamber of Secrets"
}
# 결과: [Harry, Potter, and, the, Chamber, of, Secrets]

# Ngram 토크나이저 (min=3, max=3)
POST movie_ngram_analyzer/_analyze
{
  "tokenizer": "ngram_tokenizer",
  "text": "Harry Potter and the Chamber of Secrets"
}
# 결과: [Har, arr, rry, Pot, ott, tte, ter, and, the, Cha, ham, ...]
```

### 설계 트레이드오프
- ngram: 인덱스 크기가 급격히 증가. 검색 recall은 높지만 precision 저하 가능.
- edge_ngram: ngram 대비 인덱스 크기 작음. 자동완성처럼 접두사 기반 검색에 적합.

### 관련 개념
- [내장 애널라이저 종류](#3-내장-애널라이저-종류)
- [커스텀 애널라이저 구성](#8-커스텀-애널라이저-구성)

---

## 6. 토큰 필터

### 정의
토크나이저가 생성한 토큰 스트림을 받아 토큰을 추가·변경·삭제하는 컴포넌트. 애널라이저에 0개 이상 지정하며 순차적으로 실행된다.

### 주요 내장 토큰 필터 (실무가이드 §3.4.6, 바이블 §3.3.4)

| 필터 | 동작 |
|---|---|
| **lowercase** / uppercase | 토큰을 소문자/대문자로 변환 |
| **stop** | 불용어(the, a, an, in 등) 제거 |
| **synonym** | 유의어 사전을 이용해 토큰 치환 또는 추가 |
| **pattern_replace** | 정규식으로 토큰 내용 치환 |
| **stemmer** | 어간 추출. 일부 언어 지원(한국어 미지원) |
| **trim** | 토큰 전후 공백 제거 |
| **truncate** | 지정 길이로 토큰 잘라냄 |

```bash
# lowercase 토큰 필터 단독 테스트
POST _analyze
{
  "filter": ["lowercase"],
  "text": "Hello, World!"
}
# 결과: [hello, world!]  ← 토크나이저 없이 필터만 적용
```

**Synonym 토큰 필터 사용 예시**:
```
PUT movie_syno_analyzer
{
  "settings": {
    "analysis": {
      "analyzer": {
        "synonym_analyzer": {
          "tokenizer": "whitespace",
          "filter": ["synonym_filter"]
        }
      },
      "filter": {
        "synonym_filter": {
          "type": "synonym",
          "synonyms": ["Harry => 해리"]
        }
      }
    }
  }
}

POST movie_syno_analyzer/_analyze
{
  "analyzer": "synonym_analyzer",
  "text": "Harry Potter and the Chamber of Secrets"
}
# 결과: [해리, Potter, and, the, Chamber, of, Secrets]
```

### 설계 트레이드오프
- 토큰 필터 적용 순서가 결과를 바꾼다. 예) lowercase 후 synonym 적용 시, 사전에 소문자로 등록해야 매칭됨.
- stop 필터는 색인 시점에만 적용하고 검색 시점에는 적용하지 않는 경우도 있다(검색어 "of the" 등을 제거하지 않기 위해).

### 관련 개념
- [동의어 사전](#7-동의어-사전)
- [커스텀 애널라이저 구성](#8-커스텀-애널라이저-구성)

---

## 7. 동의어 사전

### 정의
Synonym 토큰 필터에 연결되어 특정 단어를 다른 단어로 치환하거나, 동의어를 추가로 색인하는 파일 기반 매핑 규칙이다.

### 왜 필요한가
원문에 "Elasticsearch"가 있어도 "엘라스틱서치"로 검색 시 결과가 없다. 동의어 사전으로 두 단어를 연결하면 양쪽 검색어 모두 결과를 반환한다.

### 동작 원리
두 가지 방식 (실무가이드 §3.4.7):

1. **동의어 추가**: 두 단어를 모두 색인
   ```
   Elasticsearch, 엘라스틱서치
   ```
   → "Elasticsearch"를 색인할 때 "엘라스틱서치" 텀도 함께 저장

2. **동의어 치환**: 원본 토큰을 새 토큰으로 교체
   ```
   Harry => 해리
   ```
   → "Harry"를 색인할 때 "Harry" 텀을 제거하고 "해리" 텀만 저장

파일 위치: `<ES설치디렉터리>/config/analysis/synonym.txt`

```
PUT movie_analyzer
{
  "settings": {
    "analysis": {
      "filter": {
        "synonym_filter": {
          "type": "synonym",
          "synonyms_path": "analysis/synonym.txt"
        }
      }
    }
  }
}
```

### 설계 트레이드오프
- **매핑 설정 내 인라인 등록**: 운영 중 변경이 사실상 불가능. 인덱스 재생성 필요.
- **파일 기반 관리**: 운영 중 파일 교체 후 인덱스 reload 가능. 실무 권장 방식.
- 동의어 처리 전에 lowercase 필터를 적용했다면 사전에도 소문자로 등록해야 한다. (최신 버전은 대소문자 자동 인식)

### 관련 개념
- [토큰 필터](#6-토큰-필터)

---

## 8. 커스텀 애널라이저 구성

### 정의
내장 캐릭터 필터·토크나이저·토큰 필터를 원하는 대로 조합하여 직접 정의하는 애널라이저.

### 왜 필요한가
내장 애널라이저가 특정 도메인 요구사항을 충족하지 못할 때 사용한다. 예) HTML 제거 + 소문자 변환, 로마 숫자 변환 + 공백 분리 + 소문자화 등.

### 동작 원리
인덱스 settings의 `analysis` 섹션에 정의:

```
PUT /movie_analyzer
{
  "settings": {
    "analysis": {
      "char_filter": {
        "my_char_filter": {
          "type": "mapping",
          "mappings": ["i. => 1.", "ii. => 2.", "iii. => 3.", "iv. => 4."]
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
  },
  "mappings": {
    "properties": {
      "myText": {
        "type": "text",
        "analyzer": "my_analyzer"
      }
    }
  }
}
```

**색인/검색 시점 분리**:
```
"properties": {
  "title": {
    "type": "text",
    "analyzer": "movie_stop_test_analyzer",        // 색인 시점: 불용어 제거
    "search_analyzer": "movie_lower_test_analyzer" // 검색 시점: 불용어 유지
  }
}
```

**인덱스 기본 애널라이저 변경**:
```
"analysis": {
  "analyzer": {
    "default": {           // 이름을 default로 지정
      "type": "keyword"    // 기본 standard 대신 keyword 적용
    }
  }
}
```

### 설계 트레이드오프
- 커스텀 애널라이저는 인덱스 생성 시 정의한다. 이후 변경은 인덱스 재생성 필요.
- 색인·검색 분석기가 다를 경우 검색어가 역색인에 없는 텀으로 분석될 수 있다. 신중하게 설계해야 한다.

### 관련 개념
- [캐릭터 필터](#4-캐릭터-필터), [토크나이저](#5-토크나이저), [토큰 필터](#6-토큰-필터)
- [analyze API 사용법](#10-analyze-api-사용법)

---

## 9. 한국어 형태소 분석기 (nori)

### 정의
한국어 형태소를 분석하여 조사·어미를 제거하고 의미 있는 어간만 추출하는 플러그인 기반 애널라이저.

### 왜 필요한가
standard 애널라이저는 한국어 형태소를 인식하지 못한다. "우리는 컴퓨터를 다룬다"를 standard로 분석하면 어절 단위(`우리는`, `컴퓨터를`)로만 분리되어 "컴퓨터"로 검색 시 히트하지 않는다. nori는 형태소 분석으로 `우리`, `컴퓨터`, `다루` 등 의미 단위로 분리한다.

### 주요 한국어 분석기 (실무가이드 §6.1)

| 분석기 | 특징 |
|---|---|
| **nori** (analysis-nori) | 엘라스틱서치 공식 플러그인. 루씬 내장 한국어 형태소 분석기 |
| **은전한닢** (seunjeon) | 오픈소스 한국어 형태소 분석기. 정확도 높음 |
| **트위터 형태소 분석기** | SNS 텍스트 특화 |

### nori 설치 및 사용 (바이블 §3.3.8)

```bash
# 플러그인 설치 (모든 노드에 실행 필요, 재기동 필요)
bin/elasticsearch-plugin install analysis-nori

# 일본어: analysis-kuromoji
# 중국어: analysis-smartcn
```

```bash
POST _analyze
{
  "analyzer": "nori",
  "text": "우리는 컴퓨터를 다룬다."
}
```

결과:
```json
{
  "tokens": [
    {"token": "우리", "position": 0},
    {"token": "컴퓨터", "position": 2},
    {"token": "다루", "position": 4}
  ]
}
```
조사 "는", "를" 제거. "다룬다"의 어간 "다루" 추출.

### 설계 트레이드오프
- 플러그인은 클러스터의 **모든 노드에 설치** 후 **재기동** 필요. 운영 중 설치 계획 수립 필요.
- 형태소 분석기 선택에 따라 검색 품질이 달라짐. 도메인 특화 사전 추가 가능 여부 확인 필요.
- nori는 공식 지원이므로 버전 호환성이 보장되나, 은전한닢 등 서드파티는 ES 버전 업그레이드 시 호환성 검토 필요.

### 관련 개념
- [텍스트 분석 파이프라인](#1-텍스트-분석-파이프라인)
- [../01-핵심-아키텍처/concepts.md](../01-핵심-아키텍처/concepts.md) — 플러그인 관리

---

## 10. 노멀라이저 (Normalizer)

### 정의
keyword 타입 필드에 적용하는 분석 도구. 애널라이저와 달리 **단일 토큰만 생성**한다. 토크나이저 없이 캐릭터 필터와 토큰 필터만으로 구성된다.

### 왜 필요한가
keyword 타입은 입력 전체를 단일 토큰으로 역색인한다. 기본적으로 아무 노멀라이저도 적용하지 않아 "Hello, World!"는 그대로 저장된다. "hello"로 검색하면 히트하지 않는다. 노멀라이저로 소문자화 등의 전처리를 적용하면 정규화된 단일 토큰으로 검색할 수 있다.

### 동작 원리 (바이블 §3.3.9)
- 내장 노멀라이저: `lowercase` 한 가지
- 커스텀 노멀라이저: ASCII folding, lowercase, uppercase 등 **글자 단위** 필터만 조합 가능 (토큰을 여러 개로 쪼개는 필터 사용 불가)

```
PUT normalizer_test
{
  "settings": {
    "analysis": {
      "normalizer": {
        "my_normalizer": {
          "type": "custom",
          "char_filter": [],
          "filter": ["asciifolding", "uppercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "myNormalizerKeyword": {
        "type": "keyword",
        "normalizer": "my_normalizer"  // "Happy World!" → "HAPPY WORLD!"
      },
      "lowercaseKeyword": {
        "type": "keyword",
        "normalizer": "lowercase"      // "Happy World!" → "happy world!"
      },
      "defaultKeyword": {
        "type": "keyword"              // "Happy World!" → "Happy World!" (그대로)
      }
    }
  }
}
```

### 설계 트레이드오프
- keyword 필드에서 대소문자 구분 없는 검색이 필요하다면 `lowercase` 노멀라이저 적용.
- text 타입과 keyword 타입 차이: text는 애널라이저 → 여러 텀, keyword는 노멀라이저 → 단일 텀.

### 관련 개념
- [../02-인덱스-설계/concepts.md](../02-인덱스-설계/concepts.md) — text/keyword 타입 비교

---

## 11. analyze API 사용법

### 정의
애널라이저, 토크나이저, 토큰 필터, 캐릭터 필터의 동작을 실시간으로 테스트할 수 있는 API.

### 사용 방법 (실무가이드 §3.4.3.1)

```bash
# 1. 내장 애널라이저로 테스트
POST _analyze
{
  "analyzer": "standard",
  "text": "캐리비안의 해적"
}

# 2. 특정 인덱스에서 커스텀 애널라이저 테스트
GET analyzer_test2/_analyze
POST analyzer_test2/_analyze
{
  "analyzer": "my_analyzer",
  "text": "i.Hello ii.World iii.Bye, iv.World!"
}

# 3. 필드 기준으로 테스트 (해당 필드에 설정된 분석기 사용)
POST movie_analyzer/_analyze
{
  "field": "title",
  "text": "캐리비안의 해적"
}

# 4. 토크나이저만 단독 테스트
POST _analyze
{
  "tokenizer": "standard",
  "text": "Harry Potter and the Chamber of Secrets"
}

# 5. 캐릭터 필터만 단독 테스트 (char_filter 키 사용)
POST _analyze
{
  "char_filter": ["html_strip"],
  "text": "<b>Hello</b>"
}

# 6. 토큰 필터만 단독 테스트 (filter 키 사용, token_filter 아님에 주의)
POST _analyze
{
  "filter": ["lowercase"],
  "text": "Hello, World!"
}
```

### 설계 트레이드오프
- analyze API로 ngram 관련 `index.max_ngram_diff` 값을 변경하며 테스트하려면 인덱스를 먼저 생성하고 해당 인덱스를 지정해야 한다. 인덱스 없이 호출하는 `POST _analyze`에서는 인덱스 설정을 변경할 수 없다.

### 관련 개념
- [커스텀 애널라이저 구성](#8-커스텀-애널라이저-구성)
- [텍스트 분석 파이프라인](#1-텍스트-분석-파이프라인)
