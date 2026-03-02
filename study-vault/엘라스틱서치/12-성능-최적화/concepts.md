# 12. 성능 최적화 — Concepts

> 출처: 엘라스틱서치 실무가이드 Ch10 (대용량 처리를 위한 시스템 최적화)
> 태그: #jvm #heap #compressed-oop #swap #ulimit #vm-max-map-count #g1gc #performance-tuning

---

## 목차

1. [JVM 버전과 ES](#1-jvm-버전과-es)
2. [JVM 옵션 — 힙 설정과 GC](#2-jvm-옵션--힙-설정과-gc)
3. [힙 크기를 32GB 이하로 유지해야 하는 이유](#3-힙-크기를-32gb-이하로-유지해야-하는-이유)
4. [OOP — Ordinary Object Pointer](#4-oop--ordinary-object-pointer)
5. [Compressed OOP](#5-compressed-oop)
6. [가상 메모리와 ES](#6-가상-메모리와-es)
7. [vm.max_map_count 설정](#7-vmmax_map_count-설정)
8. [메모리 스와핑](#8-메모리-스와핑)
9. [시스템 튜닝 포인트](#9-시스템-튜닝-포인트)

---

## 1. JVM 버전과 ES

### 정의
엘라스틱서치와 루씬은 모두 자바로 개발됐다. 루씬은 jar 형태의 라이브러리로 배포되고, 엘라스틱서치가 이를 임포트하는 방식으로 활용한다. 두 컴포넌트 모두 **하나의 JVM** 위에서 함께 동작한다.

### 왜 Java 8 이상이 필요한가

| ES 버전 | 최소 Java 버전 |
|---------|--------------|
| 2.x     | Java 7       |
| 5.x 이상 | Java 8 이상  |
| 6.x     | Java 8 이상  |

**Java 8의 핵심 변화:**
- **함수형 프로그래밍 도입** — 람다(Lambda) 표현식, 스트림(Stream) API
- 스트림을 이용하면 멀티 코어에서 함수를 병렬로 동작시킬 수 있음
- 맵리듀스(Map Reduce) 방식으로 동작 → 다수의 CPU 코어를 효율적으로 활용

### 최신 버전을 사용해야 하는 이유
JVM은 소프트웨어이므로 자체 버그를 가진다. 최신 버전에서 대부분 패치되기 때문에 **항상 최신 버전의 JVM 사용**을 권장한다.

### 설계 트레이드오프
- 새로운 버전은 최신 루씬 기능과 JVM 최적화를 모두 활용 가능
- 버전업 시 하위 호환성을 100% 유지하는 것은 어려움 → 반드시 릴리스 노트 확인 필요

### 관련 개념
- 루씬 버전과 ES 버전은 1:1 대응 (`../01-핵심-아키텍처/concepts.md`)

---

## 2. JVM 옵션 — 힙 설정과 GC

### 정의
JVM 기반 애플리케이션은 개발자가 메모리를 직접 관리하지 않는다. GC(Garbage Collection)라는 메커니즘으로 일정 주기마다 사용하지 않는 메모리를 자동 회수한다.

### 주요 JVM 옵션

| 옵션 | 설명 |
|------|------|
| `-Xms` | 초기 힙 크기 (기본값: 64MB) |
| `-Xmx` | 최대 힙 크기 (기본값: 256MB) |
| `-XX:PermSize` | 기본 Perm 영역 크기 |
| `-XX:MaxPermSize` | 최대 Perm 영역 크기 |
| `-XX:NewSize` | 최소 New(Young) 영역 크기 |
| `-XX:MaxNewSize` | 최대 New(Young) 영역 크기 |
| `-XX:SurvivorRatio` | New / Survivor 영역 비율 |
| `-XX:NewRatio` | Young Gen / Old Gen 비율 |
| `-XX:+DisableExplicitGC` | System.gc() 무시 설정 |
| `-XX:+CMSPermGenSweepingEnabled` | Perm Gen도 GC 대상에 포함 |
| `-XX:+CMSClassUnloadingEnabled` | Class 데이터도 GC 대상에 포함 |

### Xms = Xmx로 설정하는 이유
- JVM은 처음 Xms 크기로 시작하다가 메모리가 부족하면 Xmx까지 자동으로 늘어남
- 이 과정에서 **성능 저하**가 발생
- 엘라스틱서치는 기본적으로 메모리를 많이 사용하므로, **처음부터 Xms = Xmx**로 설정하는 것이 유리

### STW (Stop The World)
가상 머신 기반 애플리케이션의 특성으로, 장기간 FullGC가 수행되면 발생한다. STW 상태에서는 애플리케이션이 완전히 프리징된다.
- 힙 크기가 클수록 FullGC 발생 횟수는 적어지지만, 발생 시 STW 시간이 길어짐
- 1초 미만의 STW는 허용 범위이나, 10초 이상이면 서비스 장애

### 엘라스틱서치 기본 JVM 설정 원칙
- 기본 설정은 다년간의 운영 경험이 반영된 최적값
- **원칙적으로 기본 설정을 수정하지 않을 것을 권장**
- 수정이 불가피한 경우 `jvm.options` 파일을 통해 튜닝
- jvm.options의 기본 힙 크기는 1GB (테스트용, 운영환경에서는 반드시 변경)

### 관련 개념
- `../10-모니터링/concepts.md` — GC 모니터링

---

## 3. 힙 크기를 32GB 이하로 유지해야 하는 이유

### 정의
엘라스틱서치에서는 힙 크기의 최댓값으로 **32GB 이하**를 설정하도록 권장한다.

### 두 가지 핵심 이유

**이유 1: Compressed OOP 활성화**
- 힙 크기가 32GB를 넘는 순간 JVM은 Compressed OOP를 일반 64비트 OOP로 자동 전환
- 32비트 포인터 → 64비트 포인터로 변환되면서 메모리 낭비 심화, 캐시 적중률 저하

**이유 2: STW 방지**
- 힙 크기가 클수록 FullGC 수행 시간이 늘어남
- 그에 비례해서 STW 시간도 증가

### 메모리 할당 전략

| 물리 메모리 | 운영체제 할당 | ES 인스턴스 |
|------------|------------|------------|
| 64GB | 32GB (50%) | 1개 × 32GB |
| 128GB | 64GB (50%) | 2개 × 각 32GB |
| 128GB (전문 검색 위주) | 96GB (75%) | 1개 × 32GB |

**원칙: 물리 메모리의 50%는 운영체제(루씬 시스템 캐시용)에 양보**

루씬은 세그먼트 관리를 위해 커널 시스템 캐시를 적극 활용하므로, 운영체제가 충분한 메모리를 가져야 한다.

### 설계 트레이드오프

| 상황 | 추천 설정 |
|------|---------|
| 전문 검색 위주 | 힙 32GB + 나머지 루씬에 (커널 캐시 극대화) |
| Not Analyzed 정렬/집계 위주 | 힙 32GB + 나머지 루씬에 (DocValues 활용) |
| Analyzed 필드 정렬/집계 위주 | 힙 32GB 인스턴스 여러 개 (fielddata 캐시 필요) |

### 관련 개념
- [OOP / Compressed OOP (아래)](#4-oop--ordinary-object-pointer)

---

## 4. OOP — Ordinary Object Pointer

### 정의
자바의 모든 객체는 힙 영역에 생성되며, JVM은 힙에 생성된 객체에 접근하기 위해 포인터의 주소를 **OOP(Ordinary Object Pointer)** 라는 특수한 자료구조로 관리한다.

### 32비트 시스템 vs 64비트 시스템

| 시스템 | 포인터 크기 | 최대 주소 공간 |
|--------|-----------|-------------|
| 32비트 | 32bit | 4GB (2^32) |
| 64비트 | 64bit | 18EB (2^64) |

### 64비트 시스템의 문제점
64비트 JVM에서는 하나의 포인터를 표현하는 데 64비트가 필요하다. 이로 인해:
1. **메모리 공간 낭비** — 32비트 대비 포인터 크기가 2배
2. **캐시 대역폭 소모** — CPU 내부 캐시(L1, L2, LLC)와 메인 메모리 사이 데이터 이동 시 64비트 단위 처리로 더 큰 대역폭 소모

### 중요한 사실
32비트 JVM이든 64비트 JVM이든 **기본적으로 32비트 OOP를 사용한다**. 이는 JVM이 기본적으로 Compressed OOP를 채택하기 때문이다.

### 관련 개념
- [Compressed OOP (아래)](#5-compressed-oop)

---

## 5. Compressed OOP

### 정의
64비트 JVM에서 메모리를 효율적으로 사용하기 위해 도입된 포인터 압축 기법. **포인터가 정확한 메모리 주소를 가리키는 것이 아니라, 상대적인 오브젝트 오프셋(Object Offset)을 가리키도록 변형**하여 동작한다.

- JDK 6에서 최초 탑재 (옵션), JDK 7부터 기본 설정

### 동작 원리

```
일반 OOP (32비트):   2^32개의 메모리 주소 → 최대 4GB 표현
Compressed OOP (32비트):  2^32개의 객체를 가리킴
                       객체 최소 단위 = 8바이트
                       → 2^32 × 8 = 최대 32GB 표현 가능
```

핵심 트릭: 포인터가 주소 대신 **객체 번호(오프셋)** 를 가리키고, 실제 주소 = 오프셋 × 8 (시프트 연산)

### 32GB 경계에서 일어나는 일

```
힙 < 32GB  →  Compressed OOP 사용 (32비트 포인터, 메모리 효율 극대화)
힙 >= 32GB →  JVM이 자동으로 일반 64비트 OOP로 전환
              → 포인터 크기 2배 증가, 메모리 낭비, 캐시 효율 저하
```

실제 테스트 결과 (Linux, JDK 1.8.0_151):
- `32766MB(31.998GB)` → `UseCompressedOops = true`
- `32767MB(31.999GB)` → `UseCompressedOops = false`

JVM 힙 메모리가 0번지부터 시작하지 않기 때문에, 정확한 Limit 값은 시스템마다 조금씩 다르다.

### Zero-Based Compressed OOP
최신 JVM에서 도입된 추가 최적화. JVM 시작 시 힙 메모리의 시작 번지를 논리적으로 0번지로 강제하여, 포인터 계산 시 Add 연산 없이 **시프트 연산만으로** 처리 가능.

```
일반 Compressed OOP:  (shift 연산) + (시작 번지 Add 연산)
Zero-Based:           shift 연산만 수행 → 더 빠른 포인터 계산
```

- 테스트 환경에서 Zero-Based 동작 한계: 약 30GB (정확한 값은 시스템마다 다름)
- 안전한 힙 설정: **31GB** (Compressed OOP 보장) 또는 **30GB** (Zero-Based 가능성 높음)

### 엘라스틱서치 로그로 확인
```
[INFO][env] heap size [989.8mb], compressed ordinary object pointers [true]
```
`false`가 출력된다면 힙 크기 설정을 재확인해야 함.

### JVM 옵션 확인 명령어
```bash
# Compressed OOP 사용 여부 확인
java -Xmx31g -XX:+PrintFlagsFinal -version | grep UseCompressedOops

# Zero-Based 여부 확인
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompressedOopsMode 2>/dev/null
```

### 설계 트레이드오프

| 선택지 | 장점 | 단점 |
|--------|------|------|
| 32GB 이하 힙 | Compressed OOP 활성화, 메모리 효율 | 단일 인스턴스 힙 한계 |
| 32GB 초과 힙 | 단일 인스턴스에서 큰 힙 | 포인터 2배 증가, 메모리 낭비, GC 부담 증가 |
| 하나의 서버에 다수 인스턴스 | 32GB × N으로 효율적 확장 | 고가용성 설정 주의 필요 |

### 관련 개념
- `cluster.routing.allocation.same_shard.host: true` — 같은 물리 서버의 인스턴스에서 Primary/Replica가 같은 호스트에 배치되는 것을 방지

---

## 6. 가상 메모리와 ES

### 정의
현대 운영체제는 **가상 메모리(Virtual Memory)** 를 사용한다. 애플리케이션은 물리 메모리를 직접 할당받지 못하고, 운영체제가 생성한 가상 메모리 번지를 실제 물리 메모리로 착각하며 사용한다.

### JVM과 가상 메모리

```bash
$ java -Xms1024m -Xmx2048m HelloWorld
# 실행 후 ps로 확인하면:
# virtual size: 4GB (설정한 2GB가 아님!)
# resident size: ~21MB (실제 사용 물리 메모리)
```

가상 메모리가 4GB인 이유: ulimit의 `virtual memory` 기본값이 `unlimited`이기 때문에 운영체제가 4GB를 할당한 것.

### 가상 메모리 내부 구성
- 애플리케이션이 생성한 데이터
- ClassLoader의 메타데이터
- 스레드 정보
- 공유 라이브러리
- JNI(NIO)로 생성된 데이터 (힙 외부, 가상 메모리 내부)

### 관련 설정 확인
```bash
$ ulimit -a
virtual memory  (kbytes, -v) unlimited
```

---

## 7. vm.max_map_count 설정

### 정의
루씬은 세그먼트 파일 관리를 위해 Java NIO를 활용하여 **mmap(memory-mapped file)** 시스템콜을 직접 호출한다. `vm.max_map_count`는 가상 메모리에서 생성 가능한 mmap 영역의 최대 개수를 제한하는 커널 파라미터다.

### 왜 필요한가
루씬의 NIO 기술 덕분에:
1. JVM을 거치지 않고 커널 모드로 직접 진입 → 높은 성능
2. **커널 레벨의 파일 시스템 캐시 활용** 가능 → 루씬 세그먼트를 커널 캐시로 관리

이것이 바로 힙 설정 시 "운영체제에 물리 메모리의 50%를 양보하라"고 하는 핵심 이유다.

### 기본값과 문제
- CentOS 7 기본값: **65,530** (너무 작음)
- 엘라스틱서치 Bootstrap 과정에서 262,144 이하이면 오류 발생 후 강제 종료

```
max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

### 설정 방법

```bash
# 임시 설정 (재부팅 시 초기화)
sudo sysctl -w vm.max_map_count=262144

# 영구 설정
vi /etc/sysctl.conf
# vm.max_map_count=262144 추가

# 확인
sysctl vm.max_map_count
cat /proc/sys/vm/max_map_count
```

### 관련 개념
- Java NIO (Non-blocking I/O) — JVM을 우회하여 커널 시스템콜 직접 호출
- 루씬 세그먼트 관리 (`../01-핵심-아키텍처/concepts.md`)

---

## 8. 메모리 스와핑

### 정의
운영체제가 **효율적인 메모리 관리**를 위해 사용하지 않는 애플리케이션의 물리 메모리를 디스크로 내보내는 기술. 이를 **Swap Out**, 다시 메모리로 불러오는 것을 **Swap In**이라고 한다.

### 스와핑이 발생하는 이유
멀티태스킹 환경에서 물리 메모리를 여러 애플리케이션이 나눠서 사용해야 하기 때문이다. 운영체제는 가상 메모리의 데이터를 나눠서:
- 반드시 필요한 부분 → 물리 메모리에 로드
- 나머지 → 디스크에 임시 저장

### ES에서 스와핑을 비활성화해야 하는 이유
스와핑이 발생하면 엘라스틱서치에서:
- **가비지 컬렉션이 수 분 동안 비정상적으로 지속**
- 노드 응답 지연
- 클러스터 연결 불안정 (연결됨/끊어짐 반복)

분산 시스템에서는 불안정한 노드가 클러스터 전체에 영향을 미치는 것보다 **강제 종료 후 제외**되는 편이 훨씬 효율적이다.

### 비활성화 방법 (3가지, CentOS 7 기준)

**방법 1: 스와핑 완전 비활성화 (최선, 전용 서버일 때)**
```bash
# 임시 비활성화
sudo swapoff -a

# 영구 비활성화 (/etc/fstab의 swap 항목 주석 처리)
vi /etc/fstab
```

**방법 2: 스와핑 최소화 (공유 서버일 때)**
```bash
# vm.swappiness를 1로 설정 (스와핑을 최대한 사용하지 않겠다는 의미)
sudo sysctl vm.swappiness=1
cat /proc/sys/vm/swappiness
```
주의: 운영체제가 메모리 부족으로 판단 시 언제든지 스와핑 발생 가능

**방법 3: bootstrap.memory_lock (사용자 권한만 있을 때, 제한적)**
```yaml
# elasticsearch.yml
bootstrap.memory_lock: true
```
- `mlockall()` 함수를 이용하여 애플리케이션 레벨에서 메모리 잠금
- 효과 확인: `GET /_nodes?filter_path=**.mlockall`
- 오류 발생 시: `ulimit -l unlimited` (max locked memory 설정)

```bash
# ulimit으로 max locked memory 설정
ulimit -l unlimited
```

### 권장 이중 방어 전략
1. `swapoff -a` — 운영체제 수준에서 스와핑 비활성화
2. `bootstrap.memory_lock: true` — 엘라스틱서치 레벨에서 메모리 잠금

### 설계 트레이드오프
스와핑을 완전히 비활성화하면 메모리 부족 시 OOM killer가 프로세스를 종료할 수 있다. 클러스터 환경에서는 노드 하나가 종료되더라도 레플리카로 서비스가 유지되므로, 스와핑보다 OOM 종료가 낫다.

---

## 9. 시스템 튜닝 포인트

### 정의
리눅스에서 엘라스틱서치 성능 최적화를 위해 제공되는 두 가지 핵심 튜닝 도구:
- **ulimit** — 유저 레벨 리소스 제한 관리
- **sysctl** — 커널 레벨 파라미터 관리

### 9.1 ulimit — 유저 레벨 튜닝

**소프트 설정 vs 하드 설정**
- **소프트 설정**: 프로세스 실행 시 최초 할당되는 값
- **하드 설정**: 운영 중 리소스 한계 도달 시 추가 할당 가능한 최댓값 (소프트 값은 하드 값을 초과 불가)

엘라스틱서치는 처음부터 많은 리소스를 사용하므로 **소프트 = 하드 설정**을 권장.

**주요 ulimit 옵션**

| 옵션 | 의미 |
|------|------|
| `-n` | nofile: 최대 열 수 있는 파일(파일 디스크립터) 개수 |
| `-u` | nproc: 한 사용자가 생성 가능한 프로세스 수 |
| `-l` | memlock: 스와핑을 방지할 수 있는 locked-in-memory 공간 |
| `-c` | core: 코어 파일 크기 |
| `-T` | 생성 가능한 스레드의 최대 개수 (ulimit -a에 미표시) |

**현재 설정 조회**
```bash
ulimit -a        # 현체 설정 (소프트)
ulimit -Sa       # 소프트 설정 명시적 조회
ulimit -Ha       # 하드 설정 조회

# 실행 중인 프로세스의 리소스 확인
cat /proc/{PID}/limits
```

**영구 설정 파일**: `/etc/security/limits.conf`
```
{사용자} soft nofile 81920
{사용자} hard nofile 81920
{사용자} soft nproc  81920
{사용자} hard nproc  81920
```

### 9.2 Max Open File 설정 (ES 핵심 튜닝)

**왜 파일 디스크립터가 많이 필요한가**
- 리눅스는 모든 리소스를 파일로 표현
- 엘라스틱서치 노드는 클라이언트와 통신에 많은 소켓 사용
- 루씬은 세그먼트 관리를 위해 매우 많은 파일 사용
- 이 모든 작업에 파일 디스크립터 소모

**오류 메시지**
```
max file descriptors [4096] for Elasticsearch process is too low, increase to at least [65536]
```

**설정**
```bash
# 임시 설정
ulimit -n 81920

# 영구 설정 (/etc/security/limits.conf)
# {user} soft nofile 81920
# {user} hard nofile 81920
```

**확인**
```bash
# 설정 확인
ulimit -a  # open files 항목

# 실행 중인 ES 노드에서 확인
GET /_nodes/stats/process
# "open_file_descriptors": 현재 사용 수
# "max_file_descriptors": 최대 허용 수
```

### 9.3 sysctl — 커널 레벨 튜닝

**정의**: 리눅스 커널의 파라미터를 조절하는 도구. ulimit보다 더 낮은 레벨에서 시스템 전체에 영향을 미침.

```bash
# 커널 파라미터 전체 조회
/sbin/sysctl -a

# 특정 파라미터 수정
sysctl -w vm.max_map_count=262144

# 영구 설정
vi /etc/sysctl.conf
# vm.max_map_count=262144 추가
```

### 9.4 튜닝 레이어 정리

```
[애플리케이션 레벨] elasticsearch.yml
                    - bootstrap.memory_lock
                    - index.refresh_interval

[JVM 레벨]         jvm.options
                    - Xms, Xmx (힙 크기)
                    - GC 옵션

[유저 레벨]        ulimit / /etc/security/limits.conf
                    - nofile (파일 디스크립터)
                    - nproc (프로세스/스레드)
                    - memlock (locked memory)

[커널 레벨]        sysctl / /etc/sysctl.conf
                    - vm.max_map_count (mmap 개수)
                    - vm.swappiness (스와핑 빈도)
```

### 엘라스틱서치 권장 최소 설정 체크리스트

| 항목 | 확인 방법 | 권장값 |
|------|----------|--------|
| vm.max_map_count | `sysctl vm.max_map_count` | 262,144 이상 |
| max open files | `ulimit -n` | 65,536 이상 (81,920 권장) |
| max locked memory | `ulimit -l` | unlimited (memory_lock 사용 시) |
| 스와핑 | `cat /proc/swaps` | 비활성화 권장 |
| 힙 크기 | ES 로그 확인 | 32GB 이하, Compressed OOP 활성화 |

---

> 출처: 엘라스틱서치 실무가이드 Ch10 (p.487-542)
> 관련 개념: `../01-핵심-아키텍처/concepts.md`, `../10-모니터링/concepts.md`
