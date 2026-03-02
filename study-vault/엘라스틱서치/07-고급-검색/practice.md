# 07 고급 검색 - 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch6-Ch7
> 태그: #highlight #suggest-api #completion-suggester #search-template #alias #snapshot #korean-analyzer

---

## 기초 (40%)

### Q1. Nori 형태소 분석기의 `decompound_mode` 세 가지 값을 설명하고, `"삼성전자"` 입력 시 각 모드별 출력 토큰을 예시로 설명하라.

<details>
<summary>정답 보기</summary>

| 모드 | 설명 | "삼성전자" 출력 |
|---|---|---|
| `none` | 복합 명사 분해 안 함 | `[삼성전자]` |
| `discard` | 분해 후 원형 토큰 제거 | `[삼성, 전자]` |
| `mixed` | 원형 + 분해 토큰 모두 색인 | `[삼성전자, 삼성, 전자]` |

- `none`: 정확도 높지만 `삼성`만 검색 시 `삼성전자` 문서 누락 가능
- `discard`: 색인 크기 작지만 원형 검색 불가
- `mixed`: 색인 크기 최대지만 검색 커버리지 가장 넓음

</details>

---

### Q2. 하이라이트 기능에서 기본 태그(`<em>`) 대신 `<mark>` 태그를 사용하도록 검색 쿼리를 작성하라. `movie_index`의 `title` 필드에서 `"avengers"` 검색.

<details>
<summary>정답 보기</summary>

```json
POST movie_index/_search
{
  "query": {
    "match": {
      "title": { "query": "avengers" }
    }
  },
  "highlight": {
    "pre_tags": ["<mark>"],
    "post_tags": ["</mark>"],
    "fields": {
      "title": {}
    }
  }
}
```

응답 예시:
```json
"highlight": {
  "title": ["<mark>Avengers</mark>: Endgame"]
}
```

</details>

---

### Q3. Term Suggest API를 사용하여 `movie_index`의 `title` 필드에서 `"spidermann"`과 유사한 단어를 추천하는 쿼리를 작성하라.

<details>
<summary>정답 보기</summary>

```json
POST movie_index/_search
{
  "suggest": {
    "title-suggestion": {
      "text": "spidermann",
      "term": {
        "field": "title"
      }
    }
  }
}
```

응답 예시:
```json
"title-suggestion": [{
  "text": "spidermann",
  "options": [
    { "text": "spiderman", "score": 0.88, "freq": 3 }
  ]
}]
```

- `score`: 유사도 (높을수록 원본과 가까움)
- `freq`: 색인에서 해당 텀의 출현 빈도

</details>

---

### Q4. 엘라스틱서치에서 스냅샷을 사용하기 위한 전체 절차를 순서대로 나열하라.

<details>
<summary>정답 보기</summary>

1. **물리 디렉토리 생성**
   ```bash
   mkdir /home/snapshot/elastic/backup
   ```

2. **elasticsearch.yml 설정**
   ```yaml
   path.repo: ["/home/snapshot/elastic/backup"]
   ```

3. **엘라스틱서치 재시작**

4. **리포지토리 생성**
   ```json
   PUT _snapshot/my_backup
   {
     "type": "fs",
     "settings": {
       "location": "/home/snapshot/elastic/backup",
       "compress": true
     }
   }
   ```

5. **스냅샷 생성**
   ```
   PUT _snapshot/my_backup/snapshot_1
   ```

6. **복구 (필요 시)**
   - 기존 동명 인덱스 삭제
   ```
   POST _snapshot/my_backup/snapshot_1/_restore
   ```

</details>

---

### Q5. 검색 템플릿(Search Template)이란 무엇이고, 어떤 실무 문제를 해결하는가?

<details>
<summary>정답 보기</summary>

**정의**: Mustache 템플릿 엔진을 사용하여 복잡한 검색 로직을 엘라스틱서치 내에 저장하고, 클라이언트는 파라미터만 전달하여 검색을 수행하는 기능.

**해결하는 문제**:
1. **클라이언트 코드 복잡성**: 쿼리 로직이 클라이언트 코드에 분산 → 템플릿으로 중앙화
2. **배포 비용**: 검색 쿼리 변경 시마다 클라이언트 수정/배포 필요 → 템플릿만 수정하면 즉시 반영
3. **쿼리 재사용**: 동일 쿼리 패턴을 여러 클라이언트에서 재사용

**예시**:
```json
// 템플릿 등록
POST _scripts/product_search
{
  "script": {
    "lang": "mustache",
    "source": {
      "query": { "match": { "name": "{{keyword}}" } },
      "size": "{{size}}"
    }
  }
}

// 검색 시
POST products/_search/template
{
  "id": "product_search",
  "params": { "keyword": "laptop", "size": 20 }
}
```

</details>

---

## 응용 (40%)

### Q6. Alias를 이용한 롤링 인덱스 전략을 설명하라. 매일 새로운 인덱스를 생성하는 시스템에서 클라이언트 코드 변경 없이 항상 최신 인덱스를 참조하도록 하는 방법을 단계별로 설명하라.

<details>
<summary>정답 보기</summary>

**시나리오**: 매일 새로운 `logs_YYYYMMDD` 인덱스 생성, 클라이언트는 `logs_current` alias로 항상 최신 접근.

**1단계: 첫 날 인덱스 생성 및 alias 설정**
```json
PUT _aliases
{
  "actions": [
    { "add": { "index": "logs_20240301", "alias": "logs_current" } }
  ]
}
```

**2단계: 다음 날 새 인덱스 생성 후 원자적으로 alias 교체**
```json
POST _aliases
{
  "actions": [
    { "delete": { "index": "logs_20240301", "alias": "logs_current" } },
    { "add":    { "index": "logs_20240302", "alias": "logs_current" } }
  ]
}
```

**핵심 원칙**:
- `delete`와 `add`가 하나의 요청으로 원자적 처리 → 다운타임 없음
- 클라이언트는 `logs_current`만 알면 됨
- 실무에서는 보통 `인덱스명_타임스탬프(Unix 시간)` 형식 사용

**주의사항**: 여러 인덱스에 묶인 alias에는 쓰기 불가. 쓰기용 alias는 단일 인덱스에만 연결.

</details>

---

### Q7. Completion Suggest API가 기본적으로 전방일치(prefix)만 지원하는 이유를 기술적으로 설명하고, "Love"를 포함하는 모든 영화 제목을 자동완성하기 위한 데이터 색인 전략을 설명하라.

<details>
<summary>정답 보기</summary>

**전방일치만 지원하는 이유**:
Completion Suggest API는 내부적으로 FST(Finite State Transducer)를 사용한다. FST는 prefix에 대해 O(prefix 길이) 시간으로 빠른 검색이 가능하나, 임의 위치 검색(substring)은 FST 구조상 지원이 어렵다. 성능을 위해 전방일치만 지원하는 것.

**해결 전략: 단어 단위 분리 색인**

```json
// "After Love" 색인 시
PUT movie_completion/_doc/1
{
  "movieNmComple": {
    "input": ["After", "Love"]
  }
}

// "Love for a mother" 색인 시
PUT movie_completion/_doc/3
{
  "movieNmComple": {
    "input": ["Love", "for", "a", "mother"]
  }
}
```

검색 시 `prefix: "L"` 로 "Love", "Lover" 등 모든 단어에서 "L"로 시작하는 경우를 커버함.

**트레이드오프**:
- 색인 데이터 크기 증가 (단어 수에 비례)
- FST 메모리 사용 증가
- 검색 커버리지 향상

</details>

---

### Q8. 아래 상황에서 올바른 대응 방법을 고르고 이유를 설명하라.

> 운영 중인 `product_v1` 인덱스의 매핑을 변경해야 한다. 현재 클라이언트는 `product` alias를 통해 검색 중이다. 어떤 순서로 작업해야 하는가?
>
> A) `product_v1` 인덱스 직접 수정 → 재색인
> B) `product_v2` 인덱스 새로 생성 → `_reindex`로 데이터 복사 → alias 교체 → `product_v1` 삭제
> C) 서비스 중단 → `product_v1` 삭제 → `product_v2` 생성 → alias 설정 → 서비스 재시작

<details>
<summary>정답 보기</summary>

**정답: B**

**이유**:
- **A 불가**: 엘라스틱서치는 기존 필드의 매핑 타입 변경을 허용하지 않음. 새 인덱스 생성 필요.
- **C 불가**: 서비스 중단 동반. `alias`를 쓰는 의미가 없음.
- **B 정답**: 무중단 배포 전략

**B 절차**:
```
1. product_v2 인덱스 생성 (변경된 매핑)
2. _reindex API로 product_v1 데이터 → product_v2 복사
3. alias 원자적 교체:
   POST _aliases {
     "actions": [
       { "delete": { "index": "product_v1", "alias": "product" } },
       { "add":    { "index": "product_v2", "alias": "product" } }
     ]
   }
4. product_v1 삭제 (선택)
```

클라이언트는 `product` alias만 사용하므로 전환 중 어떤 시점에도 검색 가능.

</details>

---

### Q9. 한글 Term Suggest API가 기본적으로 동작하지 않는 이유와 해결 방법 두 가지를 설명하라.

<details>
<summary>정답 보기</summary>

**동작하지 않는 이유**:
한글 유니코드는 초성/중성/종성이 결합된 복합 문자 체계(예: '가' = U+AC00). 편집거리 알고리즘이 글자(음절) 단위로 계산하기 때문에 한 음절의 오타도 편집거리가 크게 나타남.
- 예: "삼성전자" vs "샴성전자" → 실제 음소 차이는 1개지만 글자 레벨에서는 '삼'과 '샴'이 완전히 다른 코드

**해결 방법 1: ICU 분석기**
- 한글 자소를 초성/중성/종성으로 분해하여 색인
- 자소 단위로 편집거리 계산 가능
- 단점: 정교한 오타 교정, 한영 변환 등 복잡한 기능 불가

**해결 방법 2: 자바카페(JavaCafe) 플러그인**
- `javacafe_spell` 필터: 자소 분해 기반 맞춤법 교정
- `javacafe_eng2kor`, `javacafe_kor2eng` 필터: 한영/영한 변환
- 추천 결과는 자소 분해 상태로 반환 → Java `Normalizer.normalize()`로 재합성 필요
- 단점: 외부 플러그인 의존, 엘라스틱서치 버전 호환성 관리 필요

</details>

---

### Q10. Painless 스크립트로 `movie_index`의 특정 문서에서 `rating` 필드 값을 현재 값의 1.5배로 업데이트하는 쿼리를 작성하라.

<details>
<summary>정답 보기</summary>

```json
POST movie_index/_doc/1/_update
{
  "script": {
    "lang": "painless",
    "source": "ctx._source.rating = ctx._source.rating * 1.5"
  }
}
```

**또는 파라미터 사용**:
```json
POST movie_index/_doc/1/_update
{
  "script": {
    "lang": "painless",
    "source": "ctx._source.rating = ctx._source.rating * params.multiplier",
    "params": {
      "multiplier": 1.5
    }
  }
}
```

**파라미터 사용의 장점**:
- Painless가 스크립트를 컴파일/캐시할 수 있음 (값이 리터럴이면 매번 다른 스크립트로 인식)
- 런타임에 값 변경 가능

</details>

---

## 심화 (20%)

### Q11. 대규모 서비스에서 자동완성(Completion Suggest API)을 구현할 때 발생할 수 있는 성능 문제를 두 가지 이상 설명하고, 각 문제에 대한 해결 방법을 제시하라.

<details>
<summary>정답 보기</summary>

**문제 1: FST 메모리 초기 로딩 비용**

**원인**: Completion Suggest API는 FST를 메모리에 로드하는 구조. 첫 로딩 시 리소스 급증 가능.

**해결**:
- 색인 중에 FST를 점진적으로 빌드하는 엘라스틱서치의 기본 동작 활용 (즉시 로드 X)
- 노드 재시작 후 워밍업(warm-up) 쿼리로 FST 사전 로드
- 힙(heap) 메모리 충분히 확보

---

**문제 2: 완성도 필드 용량 비대**

**원인**: 부분 일치를 위해 단어 단위로 분리하여 배열로 색인할 경우 색인 크기 급증.

**해결**:
- 자동완성에 사용할 데이터만 별도 인덱스로 관리 (본 데이터와 분리)
- 색인 시 불필요한 단어(조사, 접속사 등) 제외하여 `input` 배열 크기 최소화
- `weight` 필드로 중요도 부여하여 실제로 필요한 결과 우선 제공

---

**문제 3: 한글 자동완성에서 음절 단위 입력 처리**

**원인**: 한글은 음절을 타이핑하는 중간에도 자동완성 요청이 들어옴. 예: '가'를 타이핑하는 중 'ㄱ', 'ㄱㅏ' 상태에서도 요청.

**해결**:
- 자바카페 플러그인의 `javacafe_jamo` 필터로 자모 단위 분해 색인
- 클라이언트에서 IME 입력 완료 이벤트 기준으로 요청 제한 (composition event 활용)
- 디바운싱(debouncing)으로 연속 요청 제한

---

**문제 4: 스냅샷 vs 실시간 색인 간 데이터 불일치**

**원인**: 대량 재색인 중 기존 인덱스에서 계속 데이터가 변경되면 `_reindex` 완료 후 불일치 발생.

**해결**:
- `_reindex` 완료 후 alias 교체 전 incremental update 적용
- 또는 원천 시스템의 변경 이벤트를 큐에 쌓고 재색인 완료 후 적용
- Read alias와 Write alias를 분리하여 재색인 중에도 쓰기는 새 인덱스로 라우팅

</details>

---

### Q12. 아래 요구사항을 모두 만족하는 엘라스틱서치 인덱스 설계와 검색 API를 설계하라.

> **요구사항**:
> - 상품명(`name`) 필드에 대해 한글 자동완성 지원 (초성 검색 포함)
> - 상품명 오타 교정 지원 (한영 오타 포함)
> - 검색 결과에서 검색어 하이라이트
> - 검색 쿼리 변경이 잦아 클라이언트 코드 변경 없이 서버에서만 수정 가능해야 함

<details>
<summary>정답 보기</summary>

**설계 원칙**:
- 자동완성용 `completion` 타입 + 자바카페 플러그인 필터 조합
- 검색용 `text` 타입 + Nori 분석기
- 검색 템플릿으로 쿼리 중앙화

**1단계: 분석기 설정 및 인덱스 생성**
```json
PUT products_v1
{
  "settings": {
    "analysis": {
      "analyzer": {
        "nori_analyzer": {
          "tokenizer": "nori_tokenizer",
          "filter": ["pos_filter", "nori_readingform", "lowercase"]
        },
        "javacafe_spell_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["trim", "lowercase", "javacafe_spell"]
        },
        "javacafe_jamo_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["trim", "javacafe_jamo"]
        }
      },
      "filter": {
        "pos_filter": {
          "type": "nori_part_of_speech",
          "stoptags": ["SP", "SSC", "SSO", "SY", "VA", "VV"]
        }
      }
    }
  },
  "mappings": {
    "_doc": {
      "properties": {
        "name": {
          "type": "text",
          "analyzer": "nori_analyzer",
          "copy_to": ["name_suggest", "name_spell"]
        },
        "name_suggest": {
          "type": "completion",
          "analyzer": "javacafe_jamo_analyzer"
        },
        "name_spell": {
          "type": "completion",
          "analyzer": "javacafe_spell_analyzer"
        }
      }
    }
  }
}
```

**2단계: Alias 설정**
```json
POST _aliases
{
  "actions": [
    { "add": { "index": "products_v1", "alias": "products" } }
  ]
}
```

**3단계: 검색 템플릿 등록**
```json
POST _scripts/product_search_template
{
  "script": {
    "lang": "mustache",
    "source": {
      "query": {
        "match": {
          "name": "{{keyword}}"
        }
      },
      "highlight": {
        "fields": {
          "name": {}
        }
      }
    }
  }
}
```

**4단계: 클라이언트 API 호출**

자동완성:
```json
POST products/_search
{
  "suggest": {
    "name_completion": {
      "prefix": "삼ㅅ",
      "completion": { "field": "name_suggest", "size": 5 }
    }
  }
}
```

검색 (템플릿 활용):
```json
POST products/_search/template
{
  "id": "product_search_template",
  "params": { "keyword": "삼성전자" }
}
```

오타 교정:
```json
POST products/_search
{
  "suggest": {
    "spell_check": {
      "text": "샴성전자",
      "term": { "field": "name_spell" }
    }
  }
}
```

**이점**:
- 검색 쿼리 변경 시 `product_search_template`만 수정
- 인덱스 매핑 변경 시 `products_v2` 생성 후 alias 교체로 무중단 배포
- `copy_to`로 원본 데이터 중복 저장 없이 여러 분석기 적용

</details>

---

*총 문제 수: 12 | 기초: 5 | 응용: 4 | 심화: 2*
