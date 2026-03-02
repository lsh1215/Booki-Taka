# 06. 집계 - 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch5 / 엘라스틱서치바이블 Ch4
> 태그: #aggregation #metric-aggregation #bucket-aggregation #pipeline-aggregation #cardinality #histogram

---

## 기초 (40%)

### Q1. 집계 API 기본 구조
다음 중 ES 집계 요청에서 `"aggs"` 키워드를 대신 사용할 수 있는 것은?

A) `"aggregation"`
B) `"aggregate"`
C) `"aggregations"`
D) `"group"`

<details>
<summary>정답 및 해설</summary>

**정답: C) `"aggregations"`**

ES는 집계 요청 시 `"aggs"` 또는 `"aggregations"` 두 가지 모두 사용 가능하다.
`"aggregation"` (단수)이나 `"aggregate"`, `"group"`은 지원하지 않는다.

```json
{
  "aggs": { ... }        // 단축형
  "aggregations": { ... }  // 전체형 (동일)
}
```

</details>

---

### Q2. size: 0의 의미
집계 요청 시 `"size": 0`을 지정하는 이유와 효과를 설명하라.

<details>
<summary>정답 및 해설</summary>

**이유**: 집계 결과만 필요하고 실제 문서 내용은 필요 없을 때 사용한다.

**효과**:
1. 각 샤드에서 상위 문서 수집 작업 불필요 → 성능 향상
2. 점수(score) 계산 과정 생략 → 처리 비용 절감
3. 캐시 활용도 증가

`"size": 0`을 지정해도 집계 작업은 여전히 전체 검색 조건에 매치된 문서를 대상으로 수행된다.

```json
{
  "size": 0,
  "aggs": {
    "region_count": {
      "terms": { "field": "region.keyword" }
    }
  }
}
```

</details>

---

### Q3. 메트릭 집계 종류 매핑
다음 집계 타입과 설명을 올바르게 연결하라.

| 집계 타입 | 설명 |
|-----------|------|
| `sum` | (A) 필드 값의 평균 |
| `avg` | (B) 필드 값의 합계 |
| `value_count` | (C) 중복 제외 고유 값 수 (근사치) |
| `cardinality` | (D) 필드 값이 있는 문서 수 |
| `stats` | (E) count, min, max, avg, sum 한번에 |

<details>
<summary>정답 및 해설</summary>

| 집계 타입 | 정답 |
|-----------|------|
| `sum` | (B) 필드 값의 합계 |
| `avg` | (A) 필드 값의 평균 |
| `value_count` | (D) 필드 값이 있는 문서 수 |
| `cardinality` | (C) 중복 제외 고유 값 수 (근사치, HyperLogLog++) |
| `stats` | (E) count, min, max, avg, sum을 한 번의 쿼리로 |

`value_count`와 `cardinality`의 차이:
- `value_count`: 필드가 있는 모든 문서 수 (중복 포함)
- `cardinality`: 고유한 값의 수 (중복 제거, 근사치)

</details>

---

### Q4. terms 집계의 필드 타입
다음 중 terms 집계에서 사용해야 하는 올바른 필드 타입은?

```json
{
  "aggs": {
    "by_country": {
      "terms": {
        "field": "country_name.???"  // ← 어떤 타입?
      }
    }
  }
}
```

<details>
<summary>정답 및 해설</summary>

**정답: `keyword` 타입**

```json
{
  "aggs": {
    "by_country": {
      "terms": {
        "field": "country_name.keyword"
      }
    }
  }
}
```

**이유**: Text 타입은 형태소 분석기를 통해 분석된 후 역색인에 저장되므로, 집계 시 단어가 쪼개져 원하는 결과가 나오지 않는다. Keyword 타입은 분석 과정 없이 원문 그대로 저장/집계되므로 집계에 적합하다.

country_name 같은 필드는 보통 `text` + `keyword` 멀티필드로 설정되므로, 집계 시 반드시 `.keyword`를 명시한다.

</details>

---

### Q5. histogram과 range의 차이
`histogram` 집계와 `range` 집계의 근본적인 차이점을 설명하라.

<details>
<summary>정답 및 해설</summary>

| 구분 | histogram | range |
|------|-----------|-------|
| 버킷 구간 | **자동**: interval 값으로 균등 분할 | **수동**: 사용자가 각 범위를 명시 |
| 유연성 | 낮음 (균등 간격만) | 높음 (구간별 다른 크기 가능) |
| 사용 예 | 0~10000, 10000~20000, ... (균등) | 소: ~1000, 중: 1000~5000, 대: 5000~ |

```json
// histogram: interval로 자동 구간 생성
{
  "aggs": {
    "bytes_hist": {
      "histogram": {
        "field": "bytes",
        "interval": 10000,
        "min_doc_count": 1
      }
    }
  }
}

// range: 수동으로 각 구간 지정
{
  "aggs": {
    "bytes_range": {
      "range": {
        "field": "bytes",
        "ranges": [
          { "to": 1000 },
          { "from": 1000, "to": 5000 },
          { "from": 5000 }
        ]
      }
    }
  }
}
```

`date_histogram`과 `date_range`도 동일한 차이를 가진다.

</details>

---

## 응용 (40%)

### Q6. 파이프라인 집계: 형제 vs 부모
다음 두 파이프라인 집계 유형의 차이점과 각 대표 집계를 설명하라.

- 형제 집계 (Sibling Aggregation)
- 부모 집계 (Parent Aggregation)

<details>
<summary>정답 및 해설</summary>

**형제 집계 (Sibling Aggregation)**:
- 기존 집계와 **동일 선상(같은 레벨)**에 새 집계 결과를 추가한다
- 기존 버킷에 추가되는 게 아니라 새로운 집계 결과가 생성된다
- 대표: `max_bucket`, `min_bucket`, `avg_bucket`, `sum_bucket`, `stats_bucket`

```json
{
  "aggs": {
    "daily": {
      "date_histogram": { "field": "ts", "interval": "day" },
      "aggs": {
        "total": { "sum": { "field": "bytes" } }
      }
    },
    "max_day": {                      // ← daily와 동일 레벨
      "max_bucket": {
        "buckets_path": "daily>total"
      }
    }
  }
}
```

**부모 집계 (Parent Aggregation)**:
- 집계로 생성된 버킷을 사용해 계산하고, **그 결과를 기존 집계(버킷)에 반영**한다
- 버킷 내부에 추가된다
- 대표: `cumulative_sum`, `derivative`, `bucket_script`, `bucket_selector`

```json
{
  "aggs": {
    "daily": {
      "date_histogram": { "field": "ts", "interval": "day" },
      "aggs": {
        "total": { "sum": { "field": "bytes" } },
        "cumulative": {               // ← daily 버킷 내부에 추가
          "cumulative_sum": { "buckets_path": "total" }
        }
      }
    }
  }
}
```

</details>

---

### Q7. cardinality의 precision_threshold 설계
100만 개의 상품 ID 중 고유 상품 수를 집계해야 한다. `cardinality` 집계를 사용할 때:

1. 예상 cardinality가 50,000이라면 `precision_threshold`를 얼마로 설정해야 하는가?
2. 이때 메모리 사용량은?
3. `precision_threshold`를 3000으로 낮추면 어떤 일이 발생하는가?

<details>
<summary>정답 및 해설</summary>

**1. precision_threshold 설정**:
- `precision_threshold >= cardinality`일 때 거의 100% 정확도를 보인다
- 예상 cardinality가 50,000이므로 `precision_threshold >= 50000`으로 설정
- 하지만 최댓값은 40,000이므로, **40,000으로 설정하면 최대 정확도**를 얻을 수 있다
- 50,000 > 40,000(최댓값)이므로 완벽한 정확도는 보장되지 않지만 가장 정확한 결과를 얻는다

**2. 메모리 사용량**:
- 메모리 = `precision_threshold * 8 bytes`
- 40,000 * 8 bytes = **320,000 bytes = 약 320KB**

**3. precision_threshold = 3000으로 낮추면**:
- cardinality(50,000) > precision_threshold(3,000)
- 정확도가 떨어진다 → 50,000이 아닌 **근사치** 반환
- 오차율은 cardinality와 precision_threshold의 차이에 비례해 커진다
- 메모리는 3,000 * 8 bytes = 24KB로 절약된다

핵심 원칙: **cardinality가 precision_threshold보다 낮다면 거의 100% 정확도**. 넘어서면 정확도 하락.

</details>

---

### Q8. date_histogram 타임존 처리
한국 시간(UTC+9)으로 일별 접속자 수를 집계해야 한다. 다음 쿼리의 빈칸을 채워라.

```json
{
  "size": 0,
  "aggs": {
    "daily_visits": {
      "date_histogram": {
        "field": "timestamp",
        "interval": "___",
        "format": "___",
        "time_zone": "___"
      }
    }
  }
}
```

<details>
<summary>정답 및 해설</summary>

```json
{
  "size": 0,
  "aggs": {
    "daily_visits": {
      "date_histogram": {
        "field": "timestamp",
        "interval": "day",
        "format": "yyyy-MM-dd",
        "time_zone": "+09:00"
      }
    }
  }
}
```

- `interval: "day"`: 일 단위 집계
- `format: "yyyy-MM-dd"`: 결과 날짜 형식 (기본값은 UTC ISO8601 형식)
- `time_zone: "+09:00"`: UTC+9 (한국 시간). UTC보다 이른 경우 `-09:00`처럼 마이너스 사용

`time_zone`을 설정하면 `key_as_string` 필드의 날짜가 한국 시간으로 반환된다:
```json
{ "key_as_string": "2015-05-17T00:00:00.000+09:00", "doc_count": 538 }
```

</details>

---

### Q9. terms 집계의 shard_size 문제
다음 시나리오에서 집계 결과가 부정확한 이유를 설명하고, 해결 방법을 제시하라.

**시나리오**: 3개 샤드에 상품 데이터가 분산되어 있고, `terms` 집계로 `size: 5` 설정.
- 샤드 A에는 Product C가 6건
- 샤드 B에는 Product C가 없음 (집계 상위 5위에 미포함)
- 샤드 C에는 Product C가 44건

실제 총합은 50건이어야 하지만 집계 결과에서 누락될 수 있다.

<details>
<summary>정답 및 해설</summary>

**부정확한 이유**:
각 샤드는 로컬 데이터 기준으로 상위 N개(size 값)를 반환한다. 샤드 B에서 Product C가 상위 5위에 들지 못하면 최종 병합 시 Product C의 카운트가 불완전하게 집계된다.

```
샤드 A: Product C(6) → 상위 5위에 포함되어 전송
샤드 B: Product C(0) → 상위 5위에 미포함, 전송 안됨
샤드 C: Product C(44) → 상위 5위에 포함되어 전송
최종: 6 + 0 + 44 = 50건 (샤드 B 데이터 누락으로 과소집계 가능)
```

**해결 방법**:

1. **size 증가**: 충분히 큰 size를 설정해 모든 문서 포함
   ```json
   { "terms": { "field": "product.keyword", "size": 100 } }
   ```

2. **shard_size 증가**: 각 샤드에서 더 많은 후보를 수집
   ```json
   { "terms": { "field": "product.keyword", "size": 5, "shard_size": 50 } }
   ```
   - shard_size를 크게 할수록 정확도 향상, 하지만 메모리/처리 비용 증가
   - 정확도 vs 성능의 트레이드오프

3. 결과의 `doc_count_error_upper_bound` 값으로 오차 범위 확인:
   - 0이면 정확, 0보다 크면 누락된 문서 있음

</details>

---

### Q10. 파이프라인 집계 buckets_path 작성
다음 집계 구조에서 각 집계에 접근하기 위한 `buckets_path` 값을 작성하라.

```json
{
  "aggs": {
    "by_region": {
      "terms": { "field": "region.keyword" },
      "aggs": {
        "monthly": {
          "date_histogram": { "field": "timestamp", "interval": "month" },
          "aggs": {
            "revenue_stats": {
              "stats": { "field": "revenue" }
            }
          }
        }
      }
    }
  }
}
```

1. monthly의 revenue_stats에서 avg 값에 접근하는 경로
2. monthly의 revenue_stats에서 max 값에 접근하는 경로

<details>
<summary>정답 및 해설</summary>

**1. avg 값 접근**:
```
monthly>revenue_stats.avg
```

**2. max 값 접근**:
```
monthly>revenue_stats.max
```

**규칙**:
- `>`: 하위 집계로 이동 (버킷 집계 간 이동)
- `.`: 하위 메트릭으로 이동 (단일 메트릭은 이름만, 다중 메트릭은 .메트릭명 필요)
- `stats` 같은 다중 메트릭 집계는 `.avg`, `.max`, `.min`, `.sum`, `.count` 중 하나 명시 필요
- 단일 메트릭 집계(`sum`, `avg` 등)는 집계 이름만으로 참조 가능

**적용 예시 (max_bucket)**:
```json
{
  "best_month": {
    "max_bucket": {
      "buckets_path": "monthly>revenue_stats.avg"
    }
  }
}
```

</details>

---

## 심화 (20%)

### Q11. HyperLogLog++ vs TDigest 트레이드오프 분석
cardinality 집계(HyperLogLog++)와 percentiles 집계(TDigest)는 둘 다 근사치 알고리즘을 사용한다. 두 알고리즘의 특성을 비교하고, 각각 언제 정확도를 높여야 하는지 설명하라.

<details>
<summary>정답 및 해설</summary>

**HyperLogLog++ (cardinality 집계)**:
- 해시를 기반으로 계산
- 메모리 사용량: `precision_threshold * 8 bytes` (고정)
- cardinality가 낮을수록 정확도 높음
- cardinality < precision_threshold → 거의 100% 정확
- **cardinality가 극단적으로 높아도 메모리는 precision_threshold에만 의존** (핵심 강점)

**TDigest (percentiles 집계)**:
- 노드를 사용해 분위수 근사치 계산
- 메모리 사용량: `20 * 노드크기 * compression` (compression에 비례)
- 버킷 크기가 작을수록 정확도 높음 (데이터 적을수록 정확)
- compression 증가 → 정확도 향상, 속도 저하, 메모리 증가

**정확도를 높여야 하는 상황**:

| 알고리즘 | 정확도를 높여야 할 때 |
|----------|----------------------|
| HyperLogLog++ | 예상 cardinality가 precision_threshold에 근접하거나 넘어설 때 (e.g., 고유 사용자 ID가 100만 개 예상이면 threshold를 높여야) |
| TDigest | 극단적인 백분위(1%, 99%)의 정밀도가 중요할 때, 또는 데이터 분포가 균등하지 않을 때 |

**실무 시사점**:
- cardinality는 precision_threshold 값이 고정 메모리를 결정 → 예산에 맞게 설정
- percentiles는 tail(극단값) 정확도가 중요한 SLA 지표 모니터링 시 compression 높게 설정
- 두 집계 모두 "정확도 vs 메모리/성능"의 트레이드오프 파라미터가 존재한다

</details>

---

### Q12. 집계 중첩 설계 - 실무 시나리오
다음 요구사항을 ES 집계 쿼리로 설계하라.

**요구사항**: 이커머스 데이터에서 다음 정보를 **한 번의 요청으로** 구하라.
1. 카테고리별 주문 건수 (상위 10개)
2. 각 카테고리 내 월별 매출 합계
3. 전체 기간 중 일별 매출이 가장 높았던 날짜와 금액

<details>
<summary>정답 및 해설</summary>

```json
{
  "size": 0,
  "aggs": {
    "by_category": {
      "terms": {
        "field": "category.keyword",
        "size": 10
      },
      "aggs": {
        "monthly_revenue": {
          "date_histogram": {
            "field": "order_date",
            "interval": "month",
            "format": "yyyy-MM"
          },
          "aggs": {
            "total_revenue": {
              "sum": { "field": "revenue" }
            }
          }
        }
      }
    },
    "daily_revenue": {
      "date_histogram": {
        "field": "order_date",
        "interval": "day",
        "format": "yyyy-MM-dd"
      },
      "aggs": {
        "daily_total": {
          "sum": { "field": "revenue" }
        }
      }
    },
    "best_day": {
      "max_bucket": {
        "buckets_path": "daily_revenue>daily_total"
      }
    }
  }
}
```

**설계 포인트**:
- 요구사항 1+2: `by_category(terms)` → `monthly_revenue(date_histogram)` → `total_revenue(sum)` 중첩
- 요구사항 3: 별도 `daily_revenue(date_histogram)` + `best_day(max_bucket)` 형제 집계
- `best_day`는 `daily_revenue`와 동일 레벨의 형제 집계 → `buckets_path`로 참조
- `size: 0`으로 검색 결과 제외, 집계만 수행

**주의사항**:
- 집계 중첩이 깊어질수록 메모리 사용량과 처리 시간 증가
- 카테고리 수 * 월 수 만큼 버킷 생성 → 카테고리가 많으면 메모리 주의
- `shard_size` 미설정 시 terms 집계 결과가 근사치일 수 있음

</details>
