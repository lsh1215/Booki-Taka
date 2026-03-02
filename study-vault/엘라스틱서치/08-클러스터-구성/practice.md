# 08. 클러스터 구성 — 연습 문제

> 출처: 엘라스틱서치 실무가이드 Ch12 / 엘라스틱서치바이블 Ch5
> 태그: #cluster #node-role #master #data-node #coordinating-node #split-brain #security #tls

---

## 기초 (40%)

### Q1. 노드 역할 기본
엘라스틱서치 노드에서 `node.roles: []`(빈 배열)로 설정하면 해당 노드는 어떤 모드로 동작하는가? 이 노드는 어떤 역할을 수행하며, 실제 운영에서 어떤 용도로 사용되는가?

<details>
<summary>정답 보기</summary>

**조정 전용 노드(Coordinating-Only Node)**로 동작한다.

**역할:**
- 클라이언트의 요청을 받아 다른 데이터 노드들에게 요청을 분배
- 각 데이터 노드의 부분 검색 결과를 취합하여 최종 응답을 클라이언트에 반환

**실제 용도:**
- 키바나의 집계/검색 요청 전담 처리
- 키바나가 무리한 집계 요청을 날릴 때 클러스터 전체로 장애가 번지는 것을 방지
- 장애 발생 시 이 노드만 kill하면 되므로 데이터 손실 위험 없음
- 읽기 전용 / 쓰기 전용으로 분리하는 전략도 가능

**구버전 설정:**
```yaml
node.master: false
node.data: false
node.ingest: false
search.remote.connect: false
```

</details>

---

### Q2. 마스터 선출 과정
엘라스틱서치 클러스터에서 마스터 노드에 장애가 발생했을 때 어떤 과정으로 새로운 마스터가 선출되는가? 마스터 후보 노드(master-eligible node)와 투표 구성원(voting configuration)의 관계를 설명하라.

<details>
<summary>정답 보기</summary>

**마스터 선출 과정:**
1. 현재 마스터 노드에 장애 발생
2. 대기 중인 마스터 후보 노드들이 투표를 시작
3. 투표 구성원(voting configuration)의 과반 이상이 동의한 후보가 새 마스터로 선출
4. 선출된 후보 노드가 마스터 역할을 즉시 시작
5. 장애 복구된 이전 마스터는 마스터 후보 노드로 복귀

**마스터 후보 노드 vs 투표 구성원:**
- **마스터 후보 노드**: `node.roles: [master]`로 설정된 노드. 마스터 선거에 참여 자격이 있는 노드.
- **투표 구성원**: 마스터 후보 노드들의 부분 집합. 실제 의사결정(마스터 선출, 클러스터 상태 저장)에 참여하는 노드 모임.
- 일반적으로 두 집합은 동일하지만, 엘라스틱서치 7 버전 이상에서는 안정성을 위해 자동 조정됨.

**7 버전 이상의 자동 조정:**
- 홀수 유지를 위해 마스터 후보 노드 하나를 투표 구성원에서 제외하기도 함
- 후보 노드가 클러스터에 참여/이탈하면 자동으로 투표 구성원 조정

</details>

---

### Q3. minimum_master_nodes 계산
엘라스틱서치 6 버전 클러스터에 전용 마스터 후보 노드가 5대 있다. Split Brain을 방지하기 위해 `discovery.zen.minimum_master_nodes`를 몇으로 설정해야 하는가? 공식과 함께 설명하라.

<details>
<summary>정답 보기</summary>

**공식:** `(마스터 후보 노드 수 / 2) + 1`

**계산:** `(5 / 2) + 1 = 2.5 + 1 = 3` → **3**

```yaml
discovery.zen.minimum_master_nodes: 3
```

**의미:**
- 새로운 마스터를 선출하는 투표를 진행하려면 최소 3대의 마스터 후보 노드가 존재해야 함
- 5대 중 2대가 동시에 장애나도 나머지 3대로 정상 운영 가능
- 이 값이 과반 미만으로 설정되면 네트워크 분리 시 두 그룹이 각자 마스터를 선출할 수 있어 Split Brain 발생

**런타임 변경:**
```json
PUT _cluster/settings
{
  "transient": {
    "discovery.zen.minimum_master_nodes": 3
  }
}
```

</details>

---

### Q4. 노드 역할 설정
다음 `elasticsearch.yml` 설정에서 이 노드는 어떤 역할을 수행하는가?

```yaml
node.roles: [ master ]
cluster.name: prod-es
node.name: master-node-01
```

<details>
<summary>정답 보기</summary>

**마스터 후보 노드 (Master-Eligible Node)**다.

**이 노드가 수행하는 역할:**
- 마스터 선거에 참여 (마스터 후보)
- 마스터로 선출되면: 인덱스 생성/삭제, 어떤 샤드를 어느 노드에 할당할지 결정, 클러스터 전체 관리

**이 노드가 수행하지 않는 역할:**
- 데이터 저장 불가 (data 역할 없음)
- 인제스트 파이프라인 불가 (ingest 역할 없음)
- 단, 조정(coordinating) 역할은 모든 노드가 기본으로 수행

**운영 시 권장:**
- 마스터 후보 노드는 데이터 노드보다 낮은 사양의 서버 사용 가능
- 최소 3대 이상 홀수 대로 구성 권장
- 가상 서버 사용 가능하나 같은 물리 장비에 몰리지 않도록 주의

</details>

---

## 응용 (40%)

### Q5. Split Brain 발생 시나리오
마스터 후보 노드 2대(A, B)로 구성된 클러스터에서 네트워크 단절이 발생했다. A 노드는 B를 볼 수 없고, B 노드는 A를 볼 수 없는 상황이다. 이때 어떤 문제가 발생하는가? 이를 예방하기 위해 최소 몇 대의 마스터 후보 노드가 필요하며, 그 이유는 무엇인가?

<details>
<summary>정답 보기</summary>

**발생하는 문제 (Split Brain):**
1. A 노드: "B가 없으니 나만 남았다" → 마스터로 자가 선출
2. B 노드: "A가 없으니 나만 남았다" → 마스터로 자가 선출
3. 클러스터에 마스터가 2개 존재
4. 데이터 노드들이 두 그룹으로 분리
5. 각 그룹이 독립적으로 샤드 복구, 색인 수행
6. 데이터 정합성 붕괴, 이후 강제 복구해도 유실/변경된 데이터 완벽 복구 불가

**예방을 위한 최소 마스터 후보 노드 수: 3대**

**이유:**
- `minimum_master_nodes` 공식: `(3 / 2) + 1 = 2`
- 3대 중 1대가 단절되어도 나머지 2대가 정족수를 채워 마스터 선출 가능
- 3대 중 2대가 단절된 나머지 1대는 정족수 미달로 마스터 선출 불가 → Split Brain 방지
- 결국 어느 그룹도 단독으로 정족수를 채울 수 없어야 Split Brain이 방지됨

</details>

---

### Q6. 구성 전략 선택
다음 상황에서 가장 적절한 클러스터 구성 전략을 제시하고, 그 이유를 설명하라.

**상황:** 서비스를 시작하는 스타트업. 현재 보유 서버 3대. 각 서버의 사양은 동일하며 메모리 32GB. 데이터 예상 크기는 100GB. 향후 1년 내 1TB로 성장 예상.

<details>
<summary>정답 보기</summary>

**권장 구성: 3대 모두 master + data 겸임 (Single Node 모드)**

```yaml
# 모든 노드 동일 설정
node.roles: [ master, data ]
```

**이유:**
- 장비가 3대뿐이므로 마스터/데이터를 분리하면 각 역할에 1~2대밖에 배정 불가
- 마스터를 1~2대만 두면 최소 마스터 수(3대) 미달
- 3대 겸임 구성으로 1대 장애 시에도 서비스 유지 가능 (레플리카 설정 전제)

**보완 조치:**
- `number_of_replicas: 1` 설정으로 각 샤드의 복제본 유지
- `discovery.zen.minimum_master_nodes: 2` 설정 (6 버전 이하)

**1TB 성장 대응 시:**
- 서버 추가 확보 후 사양이 낮은 장비 3대를 마스터 전용으로, 고사양 장비를 데이터 전용으로 분리 이전

</details>

---

### Q7. TLS 설정 이해
엘라스틱서치에서 `xpack.security.transport.ssl.verification_mode: certificate`로 설정했을 때 어떤 검증이 수행되는가? 이것이 `full`이나 `none`과 다른 이유는 무엇이며, 언제 `certificate` 모드를 사용하는가?

<details>
<summary>정답 보기</summary>

**certificate 모드 수행 내용:**
- CA에 의해 서명된 유효한 인증서인지만 검증
- 호스트 이름(도메인)이나 IP가 인증서의 Subject Alternative Name과 일치하는지는 검증하지 않음

**full 모드와의 차이:**
- `full`: 인증서 유효성 + 서버의 호스트 이름/IP가 인증서와 일치하는지 모두 검증
- `certificate`: 인증서 유효성만 검증 (호스트 이름 검증 없음)
- `none`: 아무 검증도 하지 않음 (디버깅 전용, 운영 환경 절대 금지)

**certificate 모드를 사용하는 경우:**
- 모든 노드에 동일한 인증서를 복사하여 사용할 때
  - 노드별로 다른 도메인/IP가 있어도 같은 인증서를 공유하므로 호스트 이름 검증 불필요
- `elasticsearch-certutil cert`로 생성한 `elastic-certificates.p12`를 모든 노드에 배포하는 경우
- 공인 CA가 아닌 자체 CA로 서명한 인증서를 사용할 때

**주의:** `none` 모드는 인증서와 관련된 어떤 검증도 하지 않으므로 악의적인 노드가 클러스터에 참여할 수 있어 운영 환경에서 절대 사용 금지.

</details>

---

### Q8. 부트스트랩 체크 실패 대응
새로 구성한 엘라스틱서치 노드를 기동했을 때 다음 오류가 발생했다.

```
[1] bootstrap checks failed
[1]: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

이 오류의 원인, 의미, 그리고 해결 방법을 설명하라.

<details>
<summary>정답 보기</summary>

**원인:**
- 리눅스 커널 파라미터 `vm.max_map_count`가 65530으로 설정되어 있어 엘라스틱서치 최소 요구값(262144)보다 낮음
- 이 값은 프로세스가 최대 몇 개의 메모리 맵 영역을 가질 수 있는지 제한

**의미:**
- 엘라스틱서치 내부 루씬은 역색인 관리를 위해 mmap을 적극 활용
- mmap은 커널 레벨 메모리를 직접 할당받아 가상 메모리 주소에 매핑
- 메모리맵 개수가 부족하면 OOM 발생 가능

**해결 방법:**

즉시 적용 (재부팅 시 초기화):
```bash
sudo sysctl -w vm.max_map_count=262144
```

영구 적용:
```bash
sudo vim /etc/sysctl.d/98-elasticsearch.conf
```
```
vm.max_map_count = 262144
```

**추가 참고:**
- 엘라스틱서치는 운영 환경(IP가 루프백이 아닌 경우)에서 이 체크를 필수로 수행
- 개발 환경(localhost)에서는 체크를 건너뜀
- 시스템 메모리가 64GB라면 `vm.max_map_count = 524288`(64GB/128KB)을 권장하는 운영체제 가이드도 있으나, 엘라스틱서치 공식 가이드는 262144 이상이면 충분

</details>

---

## 심화 (20%)

### Q9. 클러스터 구성 설계 문제
대규모 이커머스 서비스에서 엘라스틱서치를 운영 중이다. 다음 요구사항에 맞는 클러스터 구성을 설계하라:

- 일평균 10GB 데이터 증가
- 키바나에서 비개발자(데이터 분석팀)들이 집계 작업 빈번히 수행
- 장애 발생 시 읽기 서비스는 계속 제공해야 하며, 쓰기는 잠시 중단 허용
- 서버 12대 확보 가능 (고사양 6대, 저사양 6대)

<details>
<summary>정답 보기</summary>

**권장 구성:**

| 역할 | 서버 수 | 서버 사양 | 설정 |
|------|---------|----------|------|
| 마스터 후보 전용 | 3대 | 저사양 | `node.roles: [master]` |
| 데이터 전용 | 6대 | 고사양 | `node.roles: [data]` |
| 읽기 전용 조정 | 2대 | 저사양 | `node.roles: []` |
| 쓰기 전용 조정 | 1대 | 저사양 | `node.roles: []` |

**설계 근거:**

**마스터 후보 노드 3대 (저사양):**
- 홀수 대로 Split Brain 방지
- 저사양 서버도 충분 (디스크/메모리 많이 필요 없음)
- 데이터 노드와 완전 분리로 안정성 확보

**데이터 노드 6대 (고사양):**
- 일 10GB × 365일 = 약 3.65TB/년 → 충분한 디스크 용량 필요
- CRUD, 검색, 집계 처리를 위한 고성능 CPU/메모리

**읽기/쓰기 조정 전용 노드 분리:**
- 키바나와 데이터 분석팀은 읽기 조정 노드만 바라보도록 설정
- 쓰기 요청은 쓰기 조정 노드를 통해서만 처리
- 장애 발생 시 쓰기 조정 노드만 내리면: 샤드 복구 중 주/복제 샤드 차이 축소, 복구 속도 향상
- 읽기 서비스는 계속 제공

**보안 설정:**
- `xpack.security.enabled: true`
- transport/HTTP 레이어 TLS 적용
- 데이터 분석팀 전용 계정에 읽기 권한만 부여 (RBAC)

</details>

---

### Q10. 자동 보안 설정 심층 분석
엘라스틱서치 8 버전에서 단일 노드로 최초 기동 시 `discovery.type: single-node`를 설정하는 이유와, 이후 클러스터에 추가 노드를 합류시킬 때의 순서를 설명하라. TLS 부트스트랩 체크와의 관계도 포함하라.

<details>
<summary>정답 보기</summary>

**`discovery.type: single-node` 설정 이유 — TLS 부트스트랩 체크 우회:**

1. 자동 보안 설정을 적용하려면 클러스터를 먼저 기동해야 한다
2. 그런데 보안 설정을 아무것도 안 한 상태 = 노드 간 TLS 미적용
3. 운영 모드에서 노드 간 TLS 없으면 **TLS 부트스트랩 체크 실패** → 기동 거부
4. `discovery.type: single-node`로 설정하면 TLS 부트스트랩 체크를 건너뜀
5. 단일 노드로 기동 성공 후 엘라스틱서치가 CA/인증서를 자동 생성하고 보안 설정 자동 적용

**추가 조건:**
- `cluster.initial_master_nodes`와 `xpack.security.enabled` 설정을 기입하지 말아야 함
- `node.roles`에 `master`와 `data` 반드시 포함 (내부 시스템 인덱스 생성 필요)

**최초 기동 후 추가 노드 합류 순서:**

1. **enrollment 토큰 발급** (분실 시 재발급):
   ```bash
   bin/elasticsearch-create-enrollment-token -s node
   ```

2. **기존 노드 설정 수정**: `discovery.type: single-node` 제거 후 재기동
   ```bash
   bin/elasticsearch -d
   ```

3. **추가 노드 설정 준비** (`elasticsearch.yml`):
   - `cluster.name` 동일하게
   - `node.name`, `network.host` 등 새 노드 정보 입력
   - `cluster.initial_master_nodes`, `xpack.security.enabled`, `discovery.seed_hosts`, `discovery.type` 기입 **하지 않음**

4. **enrollment 토큰으로 기동**:
   ```bash
   bin/elasticsearch -d --enrollment-token <토큰>
   ```

5. **합류 완료**: 자동으로 인증서 복사, 보안 설정 적용됨

6. **추가 작업**: 모든 노드의 `discovery.seed_hosts`를 올바른 마스터 후보 노드로 수정 후 전체 재기동

**자동 보안 설정 후 구조:**
- 엘라스틱서치 노드 간: transport TLS 적용
- 클라이언트 ↔ 엘라스틱서치: HTTP TLS 적용
- 키바나 ↔ 브라우저: 별도 작업 필요 (5.3.4항 참조)

</details>
