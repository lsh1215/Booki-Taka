# 12. 성능 최적화 — Practice

> 출처: 엘라스틱서치 실무가이드 Ch10
> 태그: #jvm #heap #compressed-oop #swap #ulimit #vm-max-map-count #g1gc #performance-tuning

---

## 기초 문제 (40%)

### Q1. JVM 힙 설정의 기본 원칙

다음 중 엘라스틱서치 운영 환경에서 JVM 힙 크기 설정에 관한 올바른 설명을 모두 고르시오.

1. Xms는 1GB, Xmx는 64GB로 설정하면 필요에 따라 JVM이 자동으로 메모리를 늘려주므로 성능에 유리하다.
2. Xms와 Xmx를 동일한 값으로 설정하는 것이 권장된다.
3. 힙 크기는 물리 메모리의 75% 이상으로 설정하여 최대한 많은 메모리를 사용하도록 해야 한다.
4. 기본 설치 시 힙 크기는 1GB로 설정되어 있으며, 이는 테스트 용도의 최솟값이다.
5. 엘라스틱서치 힙에 모든 물리 메모리를 할당하면 루씬의 세그먼트 캐시 성능이 저하될 수 있다.

<details>
<summary>정답 및 해설</summary>

**정답: 2, 4, 5**

- **1번 오답**: Xms와 Xmx가 다를 경우, JVM이 메모리를 늘리는 과정에서 성능 저하가 발생한다. 특히 엘라스틱서치처럼 메모리를 많이 사용하는 애플리케이션은 처음부터 최대 힙 크기로 동작하는 것이 유리하다.
- **2번 정답**: 힙 크기 자동 증가 시 발생하는 성능 저하를 막기 위해 Xms = Xmx로 설정하는 것이 권장된다.
- **3번 오답**: 물리 메모리의 **50% 이하**를 힙으로 설정하고, 나머지는 운영체제(루씬 시스템 캐시)에 양보해야 한다.
- **4번 정답**: jvm.options의 기본 힙 크기는 1GB (테스트용 최솟값). 운영환경에서는 반드시 더 큰 값으로 변경해야 한다.
- **5번 정답**: 루씬은 커널 레벨의 파일 시스템 캐시를 통해 세그먼트를 관리한다. 힙에 메모리를 과도하게 할당하면 루씬이 사용할 시스템 캐시가 부족해진다.

</details>

---

### Q2. Java 8 이상이 필요한 핵심 이유

엘라스틱서치 5.x 이후 버전이 Java 8 이상을 요구하는 가장 핵심적인 이유는 무엇인가?

A. Java 8에서 JVM의 안정성이 크게 향상되었기 때문에
B. Java 8에서 도입된 람다와 스트림을 통해 다수의 CPU 코어를 효율적으로 활용할 수 있기 때문에
C. Java 8에서 64비트 지원이 처음으로 도입되었기 때문에
D. Java 8에서 힙 메모리 한계가 32GB에서 128GB로 확장되었기 때문에

<details>
<summary>정답 및 해설</summary>

**정답: B**

Java 8은 함수형 프로그래밍 패러다임을 도입하며 **람다(Lambda) 표현식**과 **스트림(Stream) API**를 지원하기 시작했다. 스트림을 이용하면 멀티 코어에서 함수를 동시에 실행할 수 있어, 일종의 맵리듀스(Map Reduce) 방식으로 다수의 CPU를 효율적으로 활용한다.

- A: 안정성은 이유가 맞지만 "가장 핵심적인 이유"가 아님
- C: 64비트 JVM은 Java 8 이전에도 존재했다
- D: 힙 메모리 확장은 Java 8의 기능이 아님

</details>

---

### Q3. vm.max_map_count 설정

다음 빈칸을 채우시오.

엘라스틱서치는 Bootstrap 과정에서 `vm.max_map_count` 값을 검사하여, 이 값이 ______ 이하이면 오류 메시지를 출력하고 인스턴스를 강제 종료한다. CentOS 7의 기본값은 ______ 이며, 이를 영구적으로 변경하려면 ______ 파일을 수정해야 한다.

<details>
<summary>정답 및 해설</summary>

**정답:**
- `vm.max_map_count` 임계값: **262,144**
- CentOS 7 기본값: **65,530**
- 영구 설정 파일: **/etc/sysctl.conf**

**설정 명령어:**
```bash
# 임시 설정
sudo sysctl -w vm.max_map_count=262144

# 영구 설정
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# 확인
sysctl vm.max_map_count
```

루씬은 Java NIO를 활용하여 mmap 시스템콜을 직접 호출한다. 기본값 65,530은 루씬의 세그먼트 파일 관리에 충분하지 않아 메모리 부족 예외가 발생할 수 있다.

</details>

---

### Q4. 스와핑 비활성화 방법

엘라스틱서치 운영 서버에서 스와핑을 비활성화하기 위한 방법과 그 특징을 연결하시오.

| 방법 | 설명 |
|------|------|
| A. `sudo swapoff -a` | (1) 애플리케이션 레벨에서 메모리 잠금, 권한 제약 있음 |
| B. `vm.swappiness=1` | (2) 운영체제 수준에서 완전히 비활성화, 재부팅 시 초기화 |
| C. `bootstrap.memory_lock: true` | (3) 스와핑 빈도를 최소화하지만 완전한 방지는 불가 |

<details>
<summary>정답 및 해설</summary>

**정답: A-(2), B-(3), C-(1)**

**권장 사용 상황:**
- **A (swapoff)**: 엘라스틱서치 전용 서버일 때 최선. 영구 설정은 `/etc/fstab`의 swap 항목 주석 처리.
- **B (swappiness=1)**: 다른 애플리케이션과 공유 서버일 때. 값이 1이라도 OS가 필요하다고 판단하면 스와핑 발생 가능.
- **C (memory_lock)**: 사용자 권한만 있을 때 사용 가능. 단, OS 차원에서 메모리 부족 시 무시될 수 있음.

**이중 방어 권장:**
1. 운영체제 레벨: `swapoff -a`
2. 애플리케이션 레벨: `bootstrap.memory_lock: true`

`memory_lock` 활성화 확인:
```bash
GET /_nodes?filter_path=**.mlockall
# mlockall: true 이어야 정상
```

</details>

---

## 응용 문제 (40%)

### Q5. 128GB 물리 메모리 서버 설계

128GB 물리 메모리를 탑재한 서버에서 엘라스틱서치 클러스터를 구축하려 한다. 서비스는 주로 전문(Full Text) 검색에 사용된다. 다음 두 가지 구성 중 어느 것이 더 적합한가? 그 이유를 Compressed OOP와 루씬 캐시 측면에서 설명하시오.

- **구성 A**: 엘라스틱서치 노드 1개, 힙 크기 96GB
- **구성 B**: 엘라스틱서치 노드 1개, 힙 크기 32GB, 나머지 96GB는 운영체제에 양보

<details>
<summary>정답 및 해설</summary>

**정답: 구성 B**

**이유 1 - Compressed OOP:**
- 구성 A(96GB 힙): 힙이 32GB를 초과하므로 JVM이 Compressed OOP를 **비활성화**하고 일반 64비트 OOP로 전환. 포인터 크기가 32비트 → 64비트로 2배 증가하여 메모리 낭비, CPU 캐시 적중률 저하.
- 구성 B(32GB 힙): Compressed OOP **활성화**. 32비트 포인터로 최대 32GB까지 효율적으로 표현 가능.

**이유 2 - 루씬 시스템 캐시:**
- 전문 검색은 루씬의 역색인 구조를 통한 연산이 대부분
- 루씬은 Java NIO를 통해 커널 파일 시스템 캐시를 활용하여 세그먼트를 캐시
- 구성 A: 운영체제에 32GB만 남겨두어 루씬 캐시 공간이 부족
- 구성 B: 운영체제에 96GB를 양보하여 루씬이 풍부한 시스템 캐시를 활용 가능 → **빠른 전문 검색 성능**

**권장 구성 (전문 검색 위주):**
- 총 물리 메모리: 128GB
- 운영체제 할당: 96GB (75%)
- 엘라스틱서치 인스턴스: 1개 × 32GB

</details>

---

### Q6. OOP 동작 원리 분석

다음 표를 완성하시오.

| 포인터 종류 | 비트 수 | 최대 표현 메모리 | 조건 |
|------------|---------|---------------|------|
| 32비트 일반 OOP | 32 | (a) | - |
| 64비트 일반 OOP | 64 | (b) | - |
| 32비트 Compressed OOP | 32 | (c) | 객체 최소 단위 = 8바이트 |

그리고 Compressed OOP가 힙 32GB에서 동작을 멈추는 이유를 한 문장으로 설명하시오.

<details>
<summary>정답 및 해설</summary>

**표 정답:**
- **(a)**: 4GB (2^32 = 4,294,967,296 바이트 = 4GB)
- **(b)**: 18EB (2^64 = 이론상 18엑사바이트)
- **(c)**: 32GB (2^32개 객체 × 8바이트 = 2^35 = 32GB)

**동작 원리:**
Compressed OOP는 포인터가 정확한 메모리 주소가 아닌 **객체 오프셋(번호)** 을 가리키도록 한다. 실제 주소 = 오프셋 × 8 (3비트 시프트 연산). 32비트로 2^32개의 객체를 가리킬 수 있고, 각 객체 최소 크기가 8바이트이므로 최대 32GB까지 표현 가능.

**힙 32GB에서 동작을 멈추는 이유:**
JVM의 힙 메모리 시작 번지가 0번지부터 시작하지 않기 때문에 이론상 최대치인 32GB에 도달하기 전에 (실제로는 31.998~31.999GB 근방에서) 32비트 Compressed OOP가 표현할 수 있는 주소 공간을 초과하여, JVM이 자동으로 64비트 일반 OOP로 전환한다.

</details>

---

### Q7. 스와핑 문제 진단

엘라스틱서치 클러스터 운영 중 다음과 같은 증상이 관찰되었다. 근본 원인과 해결 방법을 설명하시오.

**증상:**
- 특정 노드에서 GC가 수 분 동안 지속
- 해당 노드가 클러스터에 연결됐다 끊어지기를 반복
- 노드의 응답 시간이 간헐적으로 크게 증가

<details>
<summary>정답 및 해설</summary>

**근본 원인: 메모리 스와핑 발생**

엘라스틱서치는 메모리를 많이 사용하는 애플리케이션이다. 운영체제가 메모리가 부족하다고 판단하면 엘라스틱서치의 JVM 힙 일부를 디스크로 스왑 아웃한다.

- GC가 스왑된 메모리에 접근하면 스왑 인이 발생하며 수 분간 GC 지속
- GC STW 동안 클러스터 통신이 끊어져 노드 연결 불안정
- 디스크 I/O로 인한 응답 시간 증가

**해결 방법 (우선순위 순):**

1. **스와핑 완전 비활성화 (권장)**:
```bash
sudo swapoff -a
# 영구 설정: /etc/fstab에서 swap 항목 주석 처리
```

2. **스와핑 최소화** (완전 비활성화 불가능 시):
```bash
sudo sysctl vm.swappiness=1
# 영구 설정: /etc/sysctl.conf에 vm.swappiness=1 추가
```

3. **bootstrap.memory_lock 추가 설정** (`elasticsearch.yml`):
```yaml
bootstrap.memory_lock: true
```
필요 시 `ulimit -l unlimited` 설정 후 ES 재시작.

4. **힙 크기 재검토**: 힙이 32GB를 초과하지 않는지, 물리 메모리의 50%를 넘지 않는지 확인.

</details>

---

### Q8. ulimit 설정 분석

다음 `ulimit -a` 출력 결과에서 엘라스틱서치 운영에 문제가 될 수 있는 항목을 찾고 해결 방법을 제시하시오.

```
core file size    (blocks, -c) 0
data seg size     (kbytes, -d) unlimited
file size         (blocks, -f) unlimited
pending signals   (-i) 15243
max locked memory (kbytes, -l) 64
max memory size   (kbytes, -m) unlimited
open files        (-n) 4096
max user processes(-u) 15243
virtual memory    (kbytes, -v) unlimited
```

<details>
<summary>정답 및 해설</summary>

**문제 항목 2가지:**

**1. open files (-n) 4096 — 심각**

엘라스틱서치 노드는 클라이언트 통신용 소켓, 루씬 세그먼트 파일 등 수천 개의 파일 디스크립터를 사용한다. 4,096개는 너무 적으며 실제로 ES 시작 시 다음 오류가 발생한다:
```
max file descriptors [4096] for Elasticsearch process is too low, increase to at least [65536]
```

**해결:**
```bash
ulimit -n 81920  # 임시
# 영구 설정: /etc/security/limits.conf
# {user} soft nofile 81920
# {user} hard nofile 81920
```

**2. max locked memory (kbytes, -l) 64 — `bootstrap.memory_lock` 사용 시 문제**

`bootstrap.memory_lock: true` 설정 시 `mlockall()` 호출에 실패한다:
```
Unable to lock JVM Memory: error=12, reason=Cannot allocate memory
Increase RLIMIT_MEMLOCK, soft limit: 64, hard limit: 64
```

**해결:**
```bash
ulimit -l unlimited  # 임시
# 영구 설정: /etc/security/limits.conf
# {user} soft memlock unlimited
# {user} hard memlock unlimited
```

**pending signals, max user processes (15243)**: 일반적으로 문제없으나 대규모 클러스터에서는 점검 필요.

</details>

---

## 심화 문제 (20%)

### Q9. Compressed OOP 활성화 여부 결정 로직

다음 시나리오에서 각 설정이 Compressed OOP를 활성화하는지 여부를 판단하고, 그 이유를 설명하시오. (테스트 환경: Linux x86_64, OpenJDK 1.8.0_151)

**시나리오:**
- A: `-Xmx31g` (31GB)
- B: `-Xmx32g` (32GB = 32768MB)
- C: `-Xmx32766m` (31.998GB)
- D: `-Xmx32767m` (31.999GB)

(힌트: 해당 환경의 Limit 값은 32766MB)

<details>
<summary>정답 및 해설</summary>

| 설정 | Compressed OOP | 이유 |
|------|---------------|------|
| A (-Xmx31g) | **활성화** | 31GB < Limit(32766MB = 31.998GB), 안전하게 Compressed OOP 범위 내 |
| B (-Xmx32g) | **비활성화** | 32GB(32768MB) > Limit(32766MB), 64비트 OOP로 자동 전환 |
| C (-Xmx32766m) | **활성화** | 정확히 Limit 값(32766MB)이므로 경계값에서 활성화 |
| D (-Xmx32767m) | **비활성화** | Limit 값(32766MB)을 1MB 초과, 64비트 OOP로 전환 |

**핵심 원리:**
JVM 힙의 시작 번지가 0이 아니기 때문에, Compressed OOP가 표현할 수 있는 실제 최대치는 이론값 32GB보다 약간 작다. 이 Limit 값은 JVM 버전, 플랫폼, 시스템마다 다르다.

**확인 방법:**
```bash
java -Xmx32766m -XX:+PrintFlagsFinal -version | grep UseCompressedOops
# bool UseCompressedOops = true  → 활성화

java -Xmx32767m -XX:+PrintFlagsFinal -version | grep UseCompressedOops
# bool UseCompressedOops = false → 비활성화
```

**실용적 권장사항:**
- 정확한 Limit을 모를 경우 **31GB**로 설정 → 어떤 환경에서도 안전하게 Compressed OOP 보장
- Zero-Based Compressed OOP를 원한다면 **30GB** 설정 고려

</details>

---

### Q10. 다층 성능 튜닝 설계

엘라스틱서치 전용으로 사용할 256GB 메모리 서버를 최적 설정하려 한다. 다음 각 레이어별 최적 설정값과 그 근거를 제시하시오.

1. 엘라스틱서치 인스턴스 구성 (인스턴스 수, 힙 크기, 운영체제 할당)
2. JVM 옵션 (jvm.options)
3. 유저 레벨 ulimit 설정
4. 커널 레벨 sysctl 설정
5. 엘라스틱서치 설정 (elasticsearch.yml)

<details>
<summary>정답 및 해설</summary>

**1. 인스턴스 구성**

```
총 물리 메모리:    256GB
운영체제 할당:     128GB (50%) — 루씬 시스템 캐시용
ES 인스턴스 수:    4개 (각각 32GB 힙)
총 ES 힙:          128GB
```

- 각 인스턴스가 32GB 힙 → Compressed OOP 활성화
- 4개의 노드가 클러스터를 구성하여 병렬 처리

고가용성 주의:
```yaml
cluster.routing.allocation.same_shard.host: true
# 물리 서버 내 인스턴스 간 Primary/Replica가 같은 호스트에 배치되는 것 방지
```

**2. JVM 옵션 (jvm.options)**

```
-Xms32g
-Xmx32g
```
- Xms = Xmx: 힙 크기 자동 조정으로 인한 성능 저하 방지
- 기타 GC 옵션은 ES 기본 설정 유지 (임의 변경 지양)

**3. ulimit 설정 (/etc/security/limits.conf)**

```
elasticsearch soft nofile 81920
elasticsearch hard nofile 81920
elasticsearch soft nproc  81920
elasticsearch hard nproc  81920
elasticsearch soft memlock unlimited
elasticsearch hard memlock unlimited
```
- nofile: 루씬 세그먼트 파일 + 네트워크 소켓 디스크립터
- memlock: bootstrap.memory_lock 사용을 위해 unlimited

**4. sysctl 설정 (/etc/sysctl.conf)**

```
vm.max_map_count=262144
vm.swappiness=0        # 또는 1 (완전 비활성화보다 한 단계 낮은 설정)
```
- max_map_count: 루씬 mmap 세그먼트 파일 관리
- swappiness=0: 가능한 한 스와핑 사용 안 함

**5. elasticsearch.yml**

```yaml
bootstrap.memory_lock: true
```
- 이중 방어: sysctl swappiness 설정 + memory_lock

**추가 고려사항:**
- `sudo swapoff -a` 실행 후 `/etc/fstab` 영구 비활성화
- 각 인스턴스 재시작 후 `GET /_nodes?filter_path=**.mlockall`로 memory_lock 확인
- ES 로그에서 `compressed ordinary object pointers [true]` 확인

</details>

---

> 출처: 엘라스틱서치 실무가이드 Ch10 (p.487-542)
> 관련 개념: `../01-핵심-아키텍처/concepts.md`, `../10-모니터링/concepts.md`
