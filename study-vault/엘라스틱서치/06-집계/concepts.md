# 06. 집계 (Aggregation)

> 출처: 엘라스틱서치 실무가이드 Ch5 / 엘라스틱서치바이블 Ch4
> 태그: #aggregation #metric-aggregation #bucket-aggregation #pipeline-aggregation #cardinality #histogram

관련 개념 링크: [검색 쿼리](../05-검색-쿼리/concepts.md) | [인덱스 설계](../02-인덱스-설계/concepts.md)

---

## 1. 집계란?

### 정의
집계(Aggregation)는 데이터를 그룹화하고 통계를 구하는 기능이다. SQL의 `GROUP BY + 집계 함수`에 대응하지만, ES는 더 강력하고 유연한 집계를 제공한다.

### 왜 필요한가
일반 통계 프로그램은 배치 방식(하둡, RDBMS)으로 데이터를 처리한다. ES는 데이터를 조각내어 샤드 단위로 관리하기 때문에, 문서 수가 늘어나도 **실시간에 가깝게** 집계를 처리할 수 있다.

### ES 집계 vs SQL
```sql
-- SQL
SELECT SUM(ratings) FROM movie_review GROUP BY movie_no;
```
```json
// ES Aggregation DSL
{
  "aggs": {
    "movie_no_agg": {
      "terms": { "field": "movie_no" },
      "aggs": {
        "ratings_agg": { "sum": { "field": "ratings" } }
      }
    }
  }
}
```

ES는 집계 중첩(sub-aggregation), 범위/날짜/위치 집계, 분산 처리를 통한 대용량 처리가 가능하다.

### ES 집계 기술 - 캐시 3종류
집계는 검색보다 더 많은 CPU·메모리를 소모한다. ES는 3가지 캐시로 성능을 보완한다.

| 캐시 종류 | 범위 | 특징 |
|-----------|------|------|
| Node Query Cache | 노드 전체 샤드 공유 | LRU 캐시, 기본 10% 필터 캐시 |
| Shard Request Cache | 샤드 단위 | 샤드 내용 변경 시 캐시 삭제, 업데이트 잦은 인덱스엔 오히려 성능 저하 |
| Field Data Cache | 집계 연산 시 | 필드 값을 메모리에 로드하여 보관 |

---

## 2. Aggregation API 기본 구조

### 기본 구조
```json
{
  "aggregations": {
    "<aggregation_name>": {
      "<aggregation_type>": {
        <aggregation_body>
      },
      "aggs": {
        <sub_aggregation>
      }
    }
  }
}
```
- `aggregations` 대신 `aggs`로 줄여서 사용 가능
- `aggregation_name`: 결과 출력에 사용되는 임의의 이름
- `aggregation_type`: terms, date_histogram, sum 등 집계 유형
- 중첩(nested) 집계 가능 → 중첩 깊어질수록 성능 하락

### 집계와 검색 결합
```json
{
  "query": {
    "constant_score": {
      "filter": { "match": { "field": "value" } }
    }
  },
  "aggs": {
    "집계_이름": {
      "집계_타입": { "field": "필드명" }
    }
  }
}
```
- 질의와 함께 사용하면 **질의 결과 범위 내에서** 집계 수행
- 질의 생략 시 내부적으로 `match_all`로 동작 → 전체 문서 대상

### size: 0 최적화
```json
{
  "size": 0,
  "aggs": { ... }
}
```
- 집계 결과만 필요할 때 `size: 0`으로 검색 결과 제외
- 각 샤드에서 상위 문서 수집 및 점수 계산 불필요 → 성능 향상, 캐시 활용도 증가

### 글로벌 버킷
질의 범위와 무관하게 **전체 문서**에 대해 집계를 수행해야 할 때 사용:
```json
{
  "query": { ... },
  "aggs": {
    "filtered_agg": { "terms": { "field": "field1" } },
    "global_agg": {
      "global": {},
      "aggs": { "all_docs_agg": { "terms": { "field": "field1" } } }
    }
  }
}
```

### 집계 4가지 유형
| 유형 | 설명 |
|------|------|
| 버킷 집계 (Bucket) | 특정 기준으로 문서를 나눠 버킷 생성, 산술 연산 |
| 메트릭 집계 (Metric) | 필드 값의 합/평균 등 산술 연산 수행 |
| 파이프라인 집계 (Pipeline) | 다른 집계 결과를 다시 집계 |
| 행렬 집계 (Matrix) | 여러 필드에서 추출한 값으로 행렬 연산 (실험적 기능) |

---

## 3. 메트릭 집계 (Metric Aggregation)

숫자 연산(정수/실수)에 대한 집계를 수행한다. 단일 숫자 메트릭과 다중 숫자 메트릭으로 구분된다.

### 3-1. sum, avg, min, max, value_count

| 집계 | 키워드 | 설명 | 결과 수 |
|------|--------|------|---------|
| 합산 집계 | `sum` | 필드 값의 합계 | 단일 |
| 평균 집계 | `avg` | 필드 값의 평균 | 단일 |
| 최솟값 집계 | `min` | 필드 값의 최솟값 | 단일 |
| 최댓값 집계 | `max` | 필드 값의 최댓값 | 단일 |
| 개수 집계 | `value_count` | 필드 값의 개수 (요청 횟수 집계) | 단일 |

```json
// sum 예시
{
  "aggs": {
    "total_bytes": {
      "sum": { "field": "bytes" }
    }
  }
}
// 결과: { "total_bytes": { "value": 2747282505 } }
```

**script 활용**: 집계 시 단위 변환 등 추가 연산 가능 (6.x부터 Painless 언어 사용)
```json
{
  "aggs": {
    "total_bytes": {
      "sum": {
        "script": {
          "lang": "painless",
          "source": "doc.bytes.value / (double)params.divide_value",
          "params": { "divide_value": 1000 }
        }
      }
    }
  }
}
```

### 3-2. stats, extended_stats

**stats 집계**: count, min, max, avg, sum을 한 번의 쿼리로 집계 (다중 숫자 메트릭)
```json
{
  "aggs": {
    "bytes_stats": {
      "stats": { "field": "bytes" }
    }
  }
}
// 결과: { "count": 9330, "min": 35, "max": 69192717, "avg": 294456.86, "sum": 2747282505 }
```

**extended_stats 집계**: stats에 표준편차 등 추가 통계값 포함
```json
{
  "aggs": {
    "bytes_extended_stats": {
      "extended_stats": { "field": "bytes" }
    }
  }
}
```
추가 반환값:
- `sum_of_squares`: 제곱합 (변동 측정)
- `variance`: 분산 (확률변수가 기댓값에서 얼마나 떨어지는지)
- `std_deviation`: 표준편차 (자료의 산포도)
- `std_deviation_bounds.upper/lower`: 표준편차 상한/하한

### 3-3. cardinality (HyperLogLog++)

중복을 제거한 고유한 값의 개수를 집계한다. **성능 문제로 근사치 계산**을 사용한다.

```json
{
  "aggs": {
    "us_cardinality": {
      "cardinality": {
        "field": "geoip.city_name.keyword",
        "precision_threshold": 3000
      }
    }
  }
}
// 결과: { "us_cardinality": { "value": 249 } }
```

**HyperLogLog++ 알고리즘 특성**:
- 해시를 기반으로 계산 → 정확성과 메모리를 교환하는 방식
- cardinality가 낮을수록 더 정확하다
- 수십억 개의 고윳값이 있어도 `precision_threshold` 설정에 의존한 고정 메모리 사용
- `precision_threshold`: 0 ~ 40000 설정 가능 (기본값: 3000)
- cardinality < precision_threshold → 거의 100% 정확도
- 메모리 사용량 = `precision_threshold * 8 bytes`

**murmur3 플러그인으로 성능 향상**: 해시값 사전 계산으로 집계 시 해시 계산 생략
```bash
bin/elasticsearch-plugin install mapper-murmur3
```

### 3-4. percentiles, percentile_ranks

**percentiles (백분위 수 집계)**: 데이터가 어느 백분위 구간에 분포하는지 확인
```json
{
  "aggs": {
    "bytes_percentiles": {
      "percentiles": {
        "field": "bytes",
        "percents": [10, 25, 50, 75, 95, 99]
      }
    }
  }
}
// 결과: { "1.0": 229, "25.0": 3000, "50.0": 12265, "75.0": 37333, "99.0": 1204031 }
```

**percentile_ranks (백분위 수 랭크)**: 특정 수치가 백분위의 어느 구간에 속하는지
```json
{
  "aggs": {
    "bytes_percentile_ranks": {
      "percentile_ranks": {
        "field": "bytes",
        "values": [5000, 10000]
      }
    }
  }
}
// 결과: { "5000.0": 32.36, "10000.0": 45.16 } → 각 값이 전체 대비 몇 %에 위치하는지
```

**TDigest 알고리즘 특성** (percentiles에서 사용):
- 노드를 사용해 백분위 수 근사치 계산
- 노드 수 증가 → 정확도 향상
- `compression` 값으로 최대 노드 수 제한
- 메모리 사용량 = 20 * 노드 크기 * compression
- 기본 compression으로 최악 64KB TDigest 생성

### 3-5. geo_bounds, geo_centroid

**geo_bounds (지형 경계 집계)**: geo_point 타입 필드에 대해 경계 상자(bounding box) 계산
```json
{
  "aggs": {
    "viewport": {
      "geo_bounds": {
        "field": "geoip.location",
        "wrap_longitude": true
      }
    }
  }
}
// 결과: top_left(lat, lon), bottom_right(lat, lon)
```

**geo_centroid (지형 중심 집계)**: 경계 범위의 정 중앙 위치 반환
```json
{
  "aggs": {
    "centroid": {
      "geo_centroid": { "field": "geoip.location" }
    }
  }
}
// 결과: { "location": { "lat": 38.71, "lon": -22.19 }, "count": 9993 }
```

---

## 4. 버킷 집계 (Bucket Aggregation)

메트릭을 계산하는 게 아니라 **문서를 특정 기준으로 나눠 버킷(부분 집합)을 생성**한다. 생성된 버킷에 다시 하위 집계를 수행할 수 있다.

> 주의: 버킷 생성 = 집계 결과 데이터 집합을 메모리에 저장. 중첩이 깊어질수록 메모리 사용량 증가.
> ES 기본 최대 버킷 수 제한 존재 (`search.max_buckets` 설정으로 조정)

### 4-1. range, date_range

**range 집계**: 숫자 값 범위로 문서를 분류 (from 이상 to 미만)
```json
{
  "aggs": {
    "bytes_range": {
      "range": {
        "field": "bytes",
        "ranges": [
          { "key": "small", "to": 1000 },
          { "key": "medium", "from": 1000, "to": 2000 },
          { "key": "large", "from": 2000, "to": 3000 }
        ]
      }
    }
  }
}
```

**date_range 집계**: 날짜 값 범위로 분류 (ES 지원 날짜 형식 사용)
```json
{
  "aggs": {
    "request_count_with_date_range": {
      "date_range": {
        "field": "timestamp",
        "ranges": [
          { "from": "2015-01-04T05:14:00.000Z", "to": "2015-01-04T05:16:00.000Z" }
        ]
      }
    }
  }
}
```
결과에 `from_as_string`, `to_as_string`, 밀리초 값 포함.

### 4-2. histogram, date_histogram

**histogram 집계**: 지정한 간격(interval)으로 숫자 범위를 처리하는 다중 버킷 집계
```json
{
  "aggs": {
    "bytes_histogram": {
      "histogram": {
        "field": "bytes",
        "interval": 10000,
        "min_doc_count": 1
      }
    }
  }
}
```
- `interval`: 버킷 구간 크기 (0~10000, 10000~20000, ...)
- `min_doc_count`: 해당 구간 최소 문서 수 (0이면 빈 버킷도 반환)

**date_histogram 집계**: 날짜를 간격으로 분류하는 다중 버킷 집계
```json
{
  "aggs": {
    "daily_request_count": {
      "date_histogram": {
        "field": "timestamp",
        "interval": "day",
        "format": "yyyy-MM-dd",
        "time_zone": "+09:00",
        "offset": "+3h"
      }
    }
  }
}
```
- `interval` 표현식: year, quarter, month, week, day, hour, minute, second
- 세밀한 설정: `30m` (30분 간격), `1.5h` (1시간 30분 간격)
- `format`: 반환 날짜 형식 변경
- `time_zone`: UTC를 특정 시간대로 변환 (`+09:00` = 한국 시간)
- `offset`: 집계 기준 날짜의 시작 일자 조정

### 4-3. terms (size, shard_size, min_doc_count)

빈도수가 높은 텀 순위로 결과를 반환하는 다중 버킷 집계 (버킷이 동적으로 생성됨)

```json
{
  "aggs": {
    "request_count_by_country": {
      "terms": {
        "field": "geoip.country_name.keyword",
        "size": 100,
        "shard_size": 200,
        "min_doc_count": 1
      }
    }
  }
}
```
- 반드시 **Keyword 타입** 필드 사용 (Text는 형태소 분석 수행으로 집계 부적합)
- `size`: 반환할 상위 버킷 수 (기본값 10)
- `min_doc_count`: 버킷에 포함될 최소 문서 수

**분산 환경에서의 정확도 문제**:
- 각 샤드에서 로컬 집계 후 병합 → 샤드 간 데이터 불균형으로 근사치 결과 가능
- `doc_count_error_upper_bound`: 최종 결과에서 누락된 잠재 문서 수 상한
- `sum_other_doc_count`: 반환된 결과에 포함되지 않은 문서 수

**shard_size**: 각 샤드에서 집계할 크기 직접 지정 (정확도 vs 성능 트레이드오프)
- 기본값(-1)이면 ES가 자동 추정: `shard_size = size * 1.5 + 10`
- shard_size > size 관계 유지 필요
- shard_size 증가 → 정확도 향상, 하지만 메모리/처리 비용 증가

### 4-4. nested

중첩(nested) 타입의 필드에 대한 집계를 수행할 때 사용. nested 집계로 감싸야 내부 필드에 접근 가능하다.
```json
{
  "aggs": {
    "nested_reviews": {
      "nested": { "path": "reviews" },
      "aggs": {
        "avg_rating": { "avg": { "field": "reviews.rating" } }
      }
    }
  }
}
```

---

## 5. 파이프라인 집계 (Pipeline Aggregation)

쿼리에 부합하는 문서를 직접 집계하는 게 아니라, **다른 집계로 생성된 버킷을 참조해서** 집계를 수행한다.

- `buckets_path` 파라미터로 참조할 집계의 경로 지정 (체인 형식)
- 모든 집계가 완료된 후 실행 → 하위 집계 불가능
- `>`: 하위 집계로 이동하는 구분자
- `.`: 하위 메트릭으로 이동하는 구분자

### 5-1. 형제 집계 (Sibling Aggregation)

동일 선상(같은 레벨)에 새 집계를 생성한다. 기존 버킷에 추가되는 게 아니라 동일 위치에 새 집계 결과가 추가된다.

| 집계 | 설명 |
|------|------|
| `avg_bucket` | 버킷들의 평균 |
| `max_bucket` | 버킷들 중 최댓값과 해당 key |
| `min_bucket` | 버킷들 중 최솟값과 해당 key |
| `sum_bucket` | 버킷들의 합계 |
| `stats_bucket` | 버킷들의 통계 |
| `extended_stats_bucket` | 버킷들의 확장 통계 |
| `percentiles_bucket` | 버킷들의 백분위 수 |

```json
{
  "aggs": {
    "histo": {
      "date_histogram": { "field": "timestamp", "interval": "minute" },
      "aggs": {
        "bytes_sum": { "sum": { "field": "bytes" } }
      }
    },
    "max_bytes": {
      "max_bucket": {
        "buckets_path": "histo>bytes_sum"
      }
    }
  }
}
// 결과: histo 버킷과 동일 선상에 max_bytes가 추가됨
// { "value": 4379454, "keys": ["2015-01-04T05:13:00.000Z"] }
```

### 5-2. 부모 집계 (Parent Aggregation)

집계를 통해 생성된 버킷을 사용해 계산하고, **그 결과를 기존 집계에 반영**한다.

| 집계 | 설명 |
|------|------|
| `derivative` | 파생 집계 - 값의 변화량(차분) 계산 |
| `cumulative_sum` | 누적 합산 집계 |
| `bucket_script` | 버킷 스크립트 집계 |
| `bucket_selector` | 버킷 셀렉터 집계 |
| `serial_differencing` | 시계열 차분 집계 |

**cumulative_sum 예시** (바이블):
```json
{
  "aggs": {
    "daily-date-histogram": {
      "date_histogram": { "field": "order_date", "interval": "day" },
      "aggs": {
        "daily-total-quantity-average": {
          "avg": { "field": "total_quantity" }
        },
        "pipeline-sum": {
          "cumulative_sum": {
            "buckets_path": "daily-total-quantity-average"
          }
        }
      }
    }
  }
}
```

**derivative (파생 집계)**: 시간에 따른 값 변화폭 추이 확인
```json
{
  "aggs": {
    "histo": {
      "date_histogram": { "field": "timestamp", "interval": "day" },
      "aggs": {
        "bytes_sum": { "sum": { "field": "bytes" } },
        "sum_deriv": {
          "derivative": { "buckets_path": "bytes_sum" }
        }
      }
    }
  }
}
```
- 선행 데이터 없으면 집계 불가 → 첫 버킷은 derivative 결과 없음
- `min_doc_count: 0` 설정 권장 (일부 간격 생략 방지)

**갭 정책 (gap_policy)**:
- `skip`: 누락 데이터는 버킷이 없는 것으로 간주, 건너뛰고 다음 값 사용
- `insert_zeros`: 누락 값을 0으로 대체 후 정상 진행

---

## 6. 근삿값 집계 - 정확도 vs 성능 트레이드오프

ES의 대부분 집계 연산은 100% 정확한 결과를 제공한다. 하지만 **3가지 집계는 근삿값**으로 동작한다.

### 근삿값을 사용하는 집계
1. **cardinality 집계** (HyperLogLog++ 알고리즘)
2. **percentiles 집계** (TDigest 알고리즘)
3. **percentile_ranks 집계** (TDigest 알고리즘)

### 왜 근삿값인가 - 분산 환경에서의 어려움

ES는 루씬의 Facet API 대신 독자적인 Aggregation API를 사용한다 (루씬은 분산 처리 미지원).

분산 집계 동작 방식:
1. 코디네이터 노드가 요청 수신
2. 모든 샤드로 집계 요청 전파
3. 각 샤드에서 로컬 집계 후 중간 결과 반환
4. 코디네이터가 중간 결과를 모아 최종 계산

**일반 집계 vs cardinality 집계의 차이**:

| 집계 | 각 샤드에서 전송하는 것 | 코디네이터 처리 |
|------|----------------------|----------------|
| avg, min, max, sum | 계산 값 (1KB * 샤드 수) | 단순 재계산 |
| cardinality | 중복 제거된 데이터 리스트 (500MB * 샤드 수) | 다시 중복 제거 |

cardinality는 최종 중복 제거를 위해 **모든 중간 결과 리스트**를 하나로 모아야 한다. 1천만 건 / 10샤드 기준으로 약 500MB의 중간 결과를 네트워크로 전송하고 메모리에 로드해야 한다. 이 문제를 해결하기 위해 **HyperLogLog++ 알고리즘으로 근사치**를 계산한다.

### precision_threshold vs compression 요약

| 집계 | 파라미터 | 기본값 | 최댓값 | 효과 |
|------|---------|-------|-------|------|
| cardinality | `precision_threshold` | 3000 | 40000 | 높을수록 정확, 메모리 = threshold * 8 bytes |
| percentiles | `compression` | 100 | 제한없음 | 높을수록 정확하지만 느리고 메모리 증가 |

---

## 7. 집계와 검색 결합 패턴

### 패턴 1: 검색 결과 내에서 집계
```json
{
  "query": { "match": { "status": "200" } },
  "aggs": {
    "bytes_avg": { "avg": { "field": "bytes" } }
  }
}
```

### 패턴 2: 집계만 수행 (size: 0)
```json
{
  "size": 0,
  "aggs": { "region_count": { "terms": { "field": "region.keyword" } } }
}
```

### 패턴 3: 중첩 집계 (버킷 안에 메트릭)
```json
{
  "size": 0,
  "aggs": {
    "by_country": {
      "terms": { "field": "country.keyword" },
      "aggs": {
        "avg_bytes": { "avg": { "field": "bytes" } },
        "max_bytes": { "max": { "field": "bytes" } }
      }
    }
  }
}
```

### 패턴 4: 시계열 집계 + 파이프라인
```json
{
  "size": 0,
  "aggs": {
    "daily": {
      "date_histogram": { "field": "timestamp", "interval": "day" },
      "aggs": {
        "total": { "sum": { "field": "bytes" } },
        "derivative": { "derivative": { "buckets_path": "total" } }
      }
    },
    "max_day": {
      "max_bucket": { "buckets_path": "daily>total" }
    }
  }
}
```

---

## 개념 간 관계도

```
집계 (Aggregation)
├── 메트릭 집계 (단일 숫자 결과)
│   ├── sum, avg, min, max, value_count ← 정확한 결과
│   ├── stats, extended_stats ← 여러 통계를 한번에
│   ├── cardinality ← HyperLogLog++ (근사치)
│   ├── percentiles, percentile_ranks ← TDigest (근사치)
│   └── geo_bounds, geo_centroid ← 위치 정보
│
├── 버킷 집계 (문서 그룹 생성)
│   ├── range, date_range ← 명시적 범위
│   ├── histogram, date_histogram ← 자동 간격
│   ├── terms ← 값 기준 동적 버킷
│   └── nested ← 중첩 타입
│
└── 파이프라인 집계 (집계의 집계)
    ├── 형제 집계: max_bucket, avg_bucket, sum_bucket
    └── 부모 집계: cumulative_sum, derivative, moving_avg
```
