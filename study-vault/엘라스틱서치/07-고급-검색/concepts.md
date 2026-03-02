# 07 고급 검색 - 개념 정리

> 출처: 엘라스틱서치 실무가이드 Ch6-Ch7
> 태그: #highlight #suggest-api #completion-suggester #search-template #alias #snapshot #korean-analyzer

---

## 목차

1. [한글 형태소 분석기](#1-한글-형태소-분석기)
2. [검색 결과 하이라이트](#2-검색-결과-하이라이트)
3. [Painless 스크립트를 이용한 동적 필드 추가](#3-painless-스크립트를-이용한-동적-필드-추가)
4. [검색 템플릿 (Search Template)](#4-검색-템플릿-search-template)
5. [Alias를 이용한 항상 최신 인덱스 유지](#5-alias를-이용한-항상-최신-인덱스-유지)
6. [스냅샷을 이용한 백업과 복구](#6-스냅샷을-이용한-백업과-복구)
7. [Suggest API](#7-suggest-api)
8. [한글 자동완성 구현](#8-한글-자동완성-구현)
9. [한영/영한 오타 교정](#9-한영영한-오타-교정)

---

## 1. 한글 형태소 분석기

### 1.1 은전한닢 (seunjeon) 형태소 분석기

**정의**
은전한닢은 MeCab 기반의 한국어 형태소 분석기로, 엘라스틱서치 플러그인 형태로 제공된다.

**왜 필요한가**
한글은 교착어(조사, 어미가 변형되는 언어)이기 때문에 단순 공백 기준 토큰화로는 의미 있는 검색이 불가능하다. "먹었다", "먹고", "먹으니"를 모두 "먹다"로 인식해야 검색 품질이 높아진다.

**동작 원리**
- 내부적으로 MeCab 사전(mecab-ko-dic)을 사용
- 품사 태그(Part-of-Speech) 기반으로 토큰 분리
- 주요 옵션:
  - `decompound`: 복합 명사 분해 여부
  - `deinflect`: 활용형을 원형으로 변환 여부
  - `index_eojeol`: 어절 단위 색인 여부
  - `index_poses`: 색인할 품사 목록
  - `pos_tagging`: 품사 태그 부착 여부
  - `stoptags`: 색인하지 않을 품사 목록

**설계 트레이드오프**
| 선택 | 장점 | 단점 |
|---|---|---|
| decompound: true | 복합 명사 검색 가능 | 색인 크기 증가, 속도 저하 |
| stoptags 적극 활용 | 노이즈 제거, 정확도 향상 | 필요한 품사가 걸릴 수 있음 |

**관련 개념**: [분석기 기본 구조](../03-분석기/concepts.md)

---

### 1.2 Nori 형태소 분석기

**정의**
루씬(Lucene) 프로젝트에서 공식 제공하는 한글 형태소 분석기. 엘라스틱서치 6.4 버전부터 공식 지원. 기본 플러그인에 포함되지 않아 별도 설치 필요.

```bash
./bin/elasticsearch-plugin install analysis-nori
```

**왜 필요한가**
서드파티 플러그인(은전한닢)과 달리 루씬 공식 지원으로 장기적 안정성과 호환성 보장.

**구성 요소**

| 컴포넌트 | 이름 | 역할 |
|---|---|---|
| Tokenizer | `nori_tokenizer` | 문장을 토큰으로 분리 |
| Token Filter | `nori_part_of_speech` | 품사 기반 필터링 |
| Token Filter | `nori_readingform` | 한자를 한글로 변환 |

**nori_tokenizer 옵션**
- `decompound_mode`:
  - `none`: 복합 명사 분해 안 함 (`삼성전자` → `삼성전자`)
  - `discard`: 복합 명사 분해 후 원형 제거 (`삼성전자` → `삼성`, `전자`)
  - `mixed`: 원형 + 분해 토큰 모두 색인 (`삼성전자` → `삼성전자`, `삼성`, `전자`)
- `user_dictionary`: 사용자 정의 사전 경로

**nori_part_of_speech 옵션**
- `stoptags`: 색인에서 제외할 품사 태그 목록
  - 주요 태그: `IC`(감탄사), `NNB`(의존명사), `SP`(공백), `SY`(심벌), `VA`(형용사), `VV`(동사) 등

**nori_readingform 예시**
```
"中國" → "중국"
```

**전체 설정 예시**
```json
PUT nori_full_analyzer
{
  "mappings": {
    "_doc": {
      "properties": {
        "description": {
          "type": "text",
          "analyzer": "korean_analyzer"
        }
      }
    }
  },
  "settings": {
    "index": {
      "analysis": {
        "analyzer": {
          "korean_analyzer": {
            "filter": ["pos_filter_speech", "nori_readingform", "lowercase"],
            "tokenizer": "nori_tokenizer"
          }
        },
        "filter": {
          "pos_filter_speech": {
            "type": "nori_part_of_speech",
            "stoptags": ["IC", "MAJ", "NNB", "SP", "SSC", "SSO", "SY", "UNKNOWN", "VA", "VV", "VX", "XPN", "XSA", "XSN", "XSV"]
          }
        }
      }
    }
  }
}
```

**동작 원리**
내부적으로 세종 말뭉치와 mecab-ko-dic을 기반으로 구축된 사전을 사용하여 형태소를 분리한다.

**관련 개념**: [분석기 기본 구조](../03-분석기/concepts.md)

---

### 1.3 트위터 형태소 분석기 (open-korean-text)

**정의**
트위터에서 한글 처리를 위해 개발한 형태소 분석기. 2017년 4.4 버전 이후 `open-korean-text`로 이관되어 오픈소스로 개발 중. 스칼라(Scala)로 구현.

**주요 기능**
| 기능 | 예시 |
|---|---|
| 정규화 | `입니당 =ㅋ` → `입니다 ㅋ` |
| 토큰화 | `한국어를 처리하는 예시` → `[한국어/Noun, 를/Josa, 처리/Noun, 하는/Verb, 예시/Noun]` |
| 스테밍 | `하는` → `하다` |
| 어구 추출 | `한국어를 처리하는 예시입니다` → `[한국어, 처리, 예시, 처리하는 예시]` |

**플러그인 구성 요소**

| 컴포넌트 | 이름 | 역할 |
|---|---|---|
| Character Filter | `openkoreantext-normalizer` | 구어체 표준화 |
| Tokenizer | `openkoreantext-tokenizer` | 문장 토큰화 |
| Token Filter | `openkoreantext-stemmer` | 형용사/동사 스테밍 |
| Token Filter | `openkoreantext-redundant-filter` | 접속사/공백/조사/마침표 제거 |
| Token Filter | `openkoreantext-phrase-extractor` | 명사구 추출 |

**설치**
```bash
./bin/elasticsearch-plugin install https://github.com/..../elasticsearch-analysis-openkoreantext-6.4.3.0.zip
```

**사용자 사전 추가**
`plugins/elasticsearch-analysis-openkoreantext/dic/` 디렉토리에 텍스트 파일 추가. 한 줄에 단어 하나, 띄어쓰기 포함 불가.

**설계 트레이드오프**
- 트위터/SNS 텍스트에 특화 → 정형화된 문서에는 오히려 노이즈 발생 가능
- 은전한닢: 6.4.3 이상 버전 공식 릴리스 없음 (저자가 포팅한 버전 사용 필요)

---

## 2. 검색 결과 하이라이트

**정의**
검색 결과에서 사용자가 입력한 검색어와 일치하는 부분을 강조 표시하는 기능.

**왜 필요한가**
긴 문서 검색 시 사용자가 검색어가 어느 문맥에서 등장하는지 시각적으로 즉시 파악 가능. 검색 만족도 향상.

**동작 원리**
1. 검색 쿼리와 일치하는 텀을 찾음
2. 해당 텀을 기본 `<em>` 태그로 감싸서 반환
3. 원문이 길 경우 하이라이트된 부분 중심으로 전후 텍스트 일부만 제공

**기본 사용법**
```json
POST movie_highlighting/_search
{
  "query": {
    "match": {
      "title": { "query": "harry" }
    }
  },
  "highlight": {
    "fields": {
      "title": {}
    }
  }
}
```

**결과 예시**
```json
"highlight": {
  "title": ["<em>Harry</em> Potter and the Deathly Hallows"]
}
```

**커스텀 태그 설정**
```json
"highlight": {
  "pre_tags": ["<strong>"],
  "post_tags": ["</strong>"],
  "fields": {
    "title": {}
  }
}
```

**결과 예시**
```json
"highlight": {
  "title": ["<strong>Harry</strong> Potter and the Deathly Hallows"]
}
```

**설계 트레이드오프**
- 하이라이트 연산은 추가 처리 비용 발생 → 대규모 검색에서는 성능 고려 필요
- 전문 필드에 대한 하이라이트는 별도 stored field 없이도 동작하지만, `store: true` 설정 시 성능 향상

**관련 개념**: [검색 쿼리 기본](../05-검색-쿼리/concepts.md)

---

## 3. Painless 스크립트를 이용한 동적 필드 추가

**정의**
스크립팅(Scripting)은 엘라스틱서치에서 사용자가 특정 로직을 직접 삽입하는 방식. Painless는 엘라스틱서치 전용 스크립트 언어.

**왜 필요한가**
- 두 개 이상의 필드 스코어를 하나로 합치거나 특정 수식으로 재계산
- 검색 요청 시 특정 필드를 선택적으로 반환
- 색인된 문서의 필드를 동적으로 추가/수정/삭제

**동작 원리**
엘라스틱서치는 기본적으로 업데이트를 허용하지 않고 재색인으로만 처리한다. 그러나 `update API`가 내부적으로 스크립팅을 사용하여 업데이트를 처리한다.

**스크립팅 언어 변천사**
| 버전 | 언어 |
|---|---|
| 초기 | MVEL (보안 취약점으로 지원 중단) |
| 1.4+ | Groovy (자바스크립트 유사 구문) |
| 현재 | Painless (전용 언어, 권장) |

**필드 추가 예시**
```json
POST movie_script/_doc/1/_update
{
  "script": "ctx._source.movieList.Black_Panther = 3.7"
}
```

- `ctx._source`: 색인된 문서에 접근하는 특수 문법
- 결과: `movieList`에 `Black_Panther: 3.7` 필드 추가

**필드 제거 예시**
```json
POST movie_script/_doc/1/_update
{
  "script": "ctx._source.movieList.remove(\"Suits\")"
}
```

**두 가지 스크립팅 방식**
1. **config 폴더 저장 방식**: 스크립트를 파일로 저장 후 이름으로 호출
2. **In-requests 방식 (동적 스크립팅)**: API 호출 시 코드 내에서 직접 정의 (일반적으로 더 많이 사용)

동적 스크립팅 활성화 설정 (구버전):
```yaml
script.disable_dynamic: false
```

**설계 트레이드오프**
- 스크립트 남용 → 복잡성 증가, 디버깅 어려움
- 동적 스크립트 허용 → 보안 위험 가능성 (버전에 따라 기본 비활성화)
- Painless는 빠르고 안전하도록 설계되어 있으나 복잡한 로직에는 한계 존재

---

## 4. 검색 템플릿 (Search Template)

**정의**
복잡한 검색 로직을 Mustache 템플릿으로 저장하고 파라미터만 제공하여 검색을 수행하는 기능.

**왜 필요한가**
- 클라이언트 코드 단순화: 내부 쿼리 구조를 몰라도 파라미터만 전달
- 쿼리 변경 시 클라이언트 수정/배포 없이 엘라스틱서치 내 템플릿만 수정
- 검색 로직의 중앙 집중화

**동작 원리**
1. `_scripts` API로 Mustache 템플릿 저장
2. 클라이언트는 템플릿 ID와 파라미터만 전달
3. 엘라스틱서치가 파라미터를 템플릿에 대입하여 실제 쿼리 실행

**템플릿 생성**
```json
POST _scripts/movie_search_example_template
{
  "script": {
    "lang": "mustache",
    "source": {
      "query": {
        "match": {
          "movieNm": "{{movie_name}}"
        }
      }
    }
  }
}
```

**템플릿 확인**
```
GET _scripts/movie_search_example_template
```

**템플릿으로 검색**
```json
POST movie_template_test/_doc/_search/template
{
  "id": "movie_search_example_template",
  "params": {
    "movie_name": "titanic"
  }
}
```

**설계 트레이드오프**
- 템플릿 관리 포인트 추가 → 문서화/버전 관리 필요
- 파라미터 변경만으로 유연한 검색 제공 vs 복잡한 조건 분기는 Mustache 문법 한계로 어려움

**관련 개념**: [검색 쿼리 기본](../05-검색-쿼리/concepts.md)

---

## 5. Alias를 이용한 항상 최신 인덱스 유지

**정의**
별칭(Alias)은 하나 이상의 인덱스에 대한 논리적 이름. 클라이언트는 별칭만 알면 되고, 실제 인덱스는 내부적으로 관리.

**왜 필요한가**
운영 중 인덱스 삭제/재생성 시 클라이언트에 장애 발생. Alias를 사용하면 무중단으로 인덱스 교체 가능.

**두 가지 주요 활용 패턴**

**패턴 1: 멀티테넌시**
```json
POST _aliases
{
  "actions": [
    { "add": { "index": "movie_search", "alias": "movie" } },
    { "add": { "index": "movie_info",   "alias": "movie" } }
  ]
}
```
→ `POST movie/_search`로 두 인덱스를 동시 검색

**패턴 2: 롤링 인덱스 (더 많이 사용)**
```json
POST _aliases
{
  "actions": [
    { "delete": { "index": "movie_search_1544054400", "alias": "movie_search" } },
    { "add":    { "index": "movie_search_1544140800", "alias": "movie_search" } }
  ]
}
```
→ `movie_search_타임스탬프` 형태로 새 인덱스 생성 후 alias를 원자적으로 교체

**동작 원리**
- `_aliases` API는 여러 액션을 원자적으로 처리 (중간 상태 없음)
- `add`와 `delete`를 하나의 요청으로 수행하면 다운타임 없음

**설계 트레이드오프**
- Alias 사용 시 쓰기는 단일 인덱스에만 가능 (여러 인덱스에 묶인 alias에는 쓰기 불가)
- 인덱스 재생성 비용(재색인 시간) vs 운영 안정성 사이의 트레이드오프

**관련 개념**: [인덱스 설계](../02-인덱스-설계/concepts.md)

---

## 6. 스냅샷을 이용한 백업과 복구

**정의**
스냅샷(Snapshot)은 엘라스틱서치 인덱스 또는 클러스터 전체를 특정 시점의 상태로 저장하는 백업 기능.

**왜 필요한가**
- 수억 건 데이터의 재색인에는 며칠 소요 가능 → 스냅샷으로 빠른 복구
- 하드웨어 장애, 운영 실수, 데이터 손상 대비

**동작 원리**
1. 물리적 디렉토리 생성 (`/home/snapshot/elastic/backup`)
2. `elasticsearch.yml`에 경로 등록
3. 리포지토리(논리적 저장 공간) 생성
4. 스냅샷 생성 (리포지토리 내에 저장)
5. 필요 시 스냅샷으로 복구

**설정 (elasticsearch.yml)**
```yaml
path.repo: ["/home/snapshot/elastic/backup"]
```

**리포지토리 생성**
```json
PUT _snapshot/movie_data_backup
{
  "type": "fs",
  "settings": {
    "location": "/home/snapshot/elastic/backup",
    "compress": true
  }
}
```

**스냅샷 생성**
```json
PUT _snapshot/movie_data_backup/movie_snapshot_part1
{
  "indices": "movie_search_1544054400",
  "ignore_unavailable": true
}
```

**스냅샷 목록 조회**
```
GET _snapshot/movie_data_backup/_all
```

**복구**
```
POST _snapshot/movie_data_backup/movie_snapshot_part1/_restore
```
- 동일 이름의 인덱스가 존재하면 복구 실패 → 먼저 삭제 후 복구

**스냅샷 삭제**
```
DELETE _snapshot/movie_data_backup/movie_snapshot_part1
```

**주요 설정 옵션**

| 옵션 | 설명 | 기본값 |
|---|---|---|
| `location` | 스냅샷 저장 경로 | - |
| `compress` | 메타데이터 압축 여부 (데이터 자체는 미압축) | false |
| `chunk_size` | 파일 분할 크기 | 단일 파일 |
| `max_restore_bytes_per_sec` | 복구 속도 제한 | 40MB/s |
| `max_snapshot_bytes_per_sec` | 생성 속도 제한 | 40MB/s |

**설계 트레이드오프**
- 스냅샷 생성/복구는 시스템 리소스 다량 사용 → `max_*_bytes_per_sec` 옵션으로 속도 제어 필요
- 단일 파일 vs chunk_size 분할: 대용량 시 분할이 관리 편의성 높음
- 스냅샷은 증분(incremental) 방식이므로 첫 스냅샷 이후 변경분만 저장

---

## 7. Suggest API

**정의**
검색어와 정확히 일치하지 않는 단어도 자동으로 인식하여 비슷한 키워드를 제안하거나 자동완성하는 기능.

**왜 필요한가**
사용자가 오타를 입력하거나 정확한 단어를 모를 때 "검색 결과 없음" 대신 유사한 결과 제공 → 사용자 만족도 향상.

**4가지 Suggest API 유형**

| 유형 | 용도 |
|---|---|
| Term Suggest API | 잘못된 철자에 대해 유사한 단어 추천 (오타 교정) |
| Completion Suggest API | 입력 중인 검색어 자동완성 |
| Phrase Suggest API | 추천 문장 제안 |
| Context Suggest API | 추천 문맥 제안 |

### 7.1 Term Suggest API

**정의**
편집거리(edit distance) 알고리즘을 사용하여 색인된 데이터 중 입력한 단어와 가장 유사한 단어를 추천.

**편집거리란**
한 문자열을 다른 문자열로 바꾸는 데 필요한 삽입/삭제/치환 연산의 최소 횟수.
- 예: `"tamming test"` → `"taming text"` = 편집거리 2 (m 삭제 1회 + s→x 치환 1회)

**편집거리 알고리즘**
- 리벤슈타인(Levenshtein) 편집거리
- 자로-윙클러(Jaro-Winkler) 편집거리

**사용 예시**
```json
POST movie_term_suggest/_search
{
  "suggest": {
    "spell-suggestion": {
      "text": "lave",
      "term": {
        "field": "movieNm"
      }
    }
  }
}
```

**결과 구조**
```json
"spell-suggestion": [{
  "text": "lave",
  "offset": 0,
  "length": 4,
  "options": [
    { "text": "love", "score": 0.75, "freq": 1 },
    { "text": "lover", "score": 0.5, "freq": 1 }
  ]
}]
```
- `text`: 제안 단어
- `score`: 원본과의 유사도
- `freq`: 전체 문서에서의 빈도

**한글에서의 한계**
한글 유니코드 체계의 복잡성으로 기본 Term Suggest는 한글에서 동작하지 않음. 해결책: 한글 자소를 분해하여 색인 → 자바카페(JavaCafe) 플러그인 또는 ICU 분석기 활용.

**ICU 분석기**
국제화 처리용 분석기. 내부 ICU 필터가 한글 자소 분해/합치기 기능 보유. 단, 정교한 오타 교정/한영 변환에는 별도 플러그인 필요.

### 7.2 Completion Suggest API

**정의**
사용자가 입력을 완료하기 전에 자동완성을 제공하는 API. 입력 즉시 응답해야 하므로 성능이 핵심.

**왜 빠른가**
내부적으로 FST(Finite State Transducer)를 사용. 검색어가 모두 메모리에 로드. 성능 최적화를 위해 색인 시점에 FST를 빌드.

**사용 조건**
자동완성에 사용할 필드의 데이터 타입을 `completion`으로 설정해야 함.

**매핑 설정**
```json
PUT movie_term_completion
{
  "mappings": {
    "_doc": {
      "properties": {
        "movieNmEnComple": {
          "type": "completion"
        }
      }
    }
  }
}
```

**전방일치(prefix) 검색**
```json
POST movie_term_completion/_search
{
  "suggest": {
    "movie_completion": {
      "prefix": "L",
      "completion": {
        "field": "movieNmEnComple",
        "size": 5
      }
    }
  }
}
```
→ "L"로 시작하는 데이터만 반환 (전방일치만 지원)

**부분 일치 구현 방법**
단어를 분리하여 배열 형태의 `input` 필드로 색인:
```json
PUT movie_term_completion/_doc/1
{
  "movieNmEnComple": {
    "input": ["After", "Love"]
  }
}
```
→ "A"로 검색 시 "After Love" 반환, "L"로 검색 시에도 반환

**설계 트레이드오프**
| 전략 | 특징 |
|---|---|
| 단순 문자열 색인 | 구현 단순, 전방일치만 가능 |
| 배열 분리 색인 | 부분 일치 가능, 색인 데이터 증가 |
| FST 메모리 로딩 | 빠른 응답, 메모리 사용 증가 |

---

## 8. 한글 자동완성 구현

**정의**
기본 Completion Suggest API로는 한글 자동완성이 정상 동작하지 않으므로 자바카페(JavaCafe) 플러그인을 사용하여 직접 구현.

**자바카페 플러그인 제공 필터 (총 5개)**

| 필터명 | 역할 |
|---|---|
| `javacafe_chosung` | 한글 초성 분석 (초성 검색 지원) |
| `javacafe_jamo` | 한글 자모 분석 |
| `javacafe_eng2kor` | 영한 오타 변환 |
| `javacafe_kor2eng` | 한영 오타 변환 |
| `javacafe_spell` | 한글 맞춤법 검사 |

**설치**
```bash
wget https://github.com/javacafe-project/elastic-book-etc/.../javacafe-analyzer-6.4.3.zip
./bin/elasticsearch-plugin install file://<절대경로>/javacafe-analyzer-6.4.3.zip
```

**동작 원리**
1. `javacafe_spell` 필터가 색인 데이터를 자소 단위로 분해
2. 검색어도 자소로 분해하여 편집거리 계산 가능
3. 추천 결과는 자소 분해 상태로 반환 → Java `Normalizer.normalize(keyword, Normalizer.Form.NFC)`로 합치기

---

## 9. 한영/영한 오타 교정

**정의**
한영 자판 혼용으로 발생하는 오타를 감지하고 올바른 언어로 변환하여 의도한 검색어를 제안하는 기능.

**왜 필요한가**
한글로 "삼성전자"를 입력하려다 영문 자판으로 "tkatjdwjswk"를 입력한 경우, 편집거리 계산으로는 해결 불가 (유니코드가 완전히 다른 코드 사용).

**두 가지 오타 유형**
1. **한글→영문 입력**: 한글 검색어를 영문 자판으로 입력 (`삼성전자` → `tkatjdwjswk`)
2. **영문→한글 입력**: 영문 검색어를 한글 자판으로 입력 (`apple` → `메ㅔㅣㄷ`)

**자바카페 플러그인 해결 방법**

```json
PUT /company_spell_checker
{
  "settings": {
    "index": {
      "analysis": {
        "analyzer": {
          "korean_spell_analyzer": {
            "type": "custom",
            "tokenizer": "standard",
            "filter": ["trim", "lowercase", "javacafe_spell"]
          }
        }
      }
    }
  }
}
```

**매핑 설정 (copy_to 활용)**
```json
PUT /company_spell_checker/_doc/_mappings
{
  "properties": {
    "name": {
      "type": "keyword",
      "copy_to": ["suggest"]
    },
    "suggest": {
      "type": "completion",
      "analyzer": "korean_spell_analyzer"
    }
  }
}
```

**오타 교정 쿼리**
```json
PUT /company_spell_checker/_doc/_search
{
  "suggest": {
    "my-suggestion": {
      "text": "샴성전자",
      "term": {
        "field": "suggest"
      }
    }
  }
}
```
→ "샴성전자" 입력 시 "삼성전자" 추천

**설계 트레이드오프**
- 오타 교정 적용 시점: 검색 결과가 0건 또는 전체의 1~2% 미만일 때만 호출하여 리소스 절약
- 오타 교정 vs 원래 결과 병행 제공 vs 교정된 결과로 대체 — UX 정책 결정 필요

**관련 개념**: [분석기 기본 구조](../03-분석기/concepts.md), [검색 쿼리 기본](../05-검색-쿼리/concepts.md)
