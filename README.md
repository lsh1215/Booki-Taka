# Booki-Taka

> 책 내용을 토대로 AI와 티키타카하며 사고력을 높여보자

기술 서적 PDF를 기반으로 **구조화된 학습 → 실습 검증 → 지식 출력**까지 이어지는 AI 보조 학습 시스템.

---

## 어떤 프로젝트인가

기술 서적을 읽을 때 흔히 겪는 문제:

- 책을 읽었는데 뭘 배웠는지 설명하지 못한다
- 개념은 이해했는데 실제로 동작을 확인해본 적이 없다
- 한 번 읽고 끝이라 금방 잊어버린다

Booki-Taka는 이 문제를 **5개의 Claude Code 커스텀 스킬**로 해결한다.

```
책 PDF
  │
  ├─ /study-vault ──→ 구조화된 학습 노트 자동 생성 (개념 + 비교 + 연습문제)
  │
  ├─ /study ────────→ First Principles 기반 대화형 학습 (왜? 를 끝까지 파고듦)
  │
  ├─ /lab ──────────→ Docker 기반 실습 환경 즉시 구축 (Kafka, ES, MySQL, Redis)
  │
  ├─ /setup-quiz ───→ Slack 일일 복습 퀴즈 (Leitner 간격반복)
  │
  └─ /blog ─────────→ 배운 내용을 기술 블로그로 정리 (Toulmin 논증 + 담백한 문체)
```

---

## 빠른 시작

### 사전 요구사항

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI 설치
- Docker Desktop (lab 실습 시)
- PDF 책 파일들을 `책 목록/` 하위에 카테고리별로 정리

### 1. 저장소 클론

```bash
git clone https://github.com/lsh1215/Booki-Taka.git
cd Booki-Taka
```

### 2. Claude Code에서 실행

```bash
claude
```

Claude Code가 `.claude/CLAUDE.md`의 스킬 카탈로그를 자동으로 인식한다.

---

## 스킬 사용법

### `/study-vault` — 학습 노트 사전 생성

책 전체를 분석해서 구조화된 학습 노트를 한번에 만든다.

```
study-vault : 카프카
```

**생성물:**
- `00-dashboard.md` — 전체 조감도 (토픽 의존관계, 학습 경로)
- `00-quick-reference.md` — 핵심 용어/설정/CLI/패턴 빠른 참조
- `00-concept-compare.md` — 혼동하기 쉬운 개념 비교 (구조적 차이 분석)
- `{토픽}/concepts.md` — 개념 노트 (정의 → 왜 필요한가 → 동작 원리 → 트레이드오프)
- `{토픽}/practice.md` — 연습 문제 (답은 접힌 상태로 능동적 회상 유도)

### `/study` — 대화형 깊이 학습

특정 챕터를 골라 First Principles로 깊이 파고든다.

```
study : 카프카 Ch3 프로듀서
```

**흐름:** PDF 읽기 → 핵심 원리 추출 → "왜?" 대화 → 유형별 검증 → 메타인지 추적

### `/lab` — 실습 환경 구축

학습한 내용을 직접 확인할 수 있는 Docker 환경을 즉시 띄운다.

```
lab : kafka       # KRaft 3-broker + Kafka UI + Prometheus/Grafana
lab : es          # Elasticsearch 클러스터 + Kibana
lab : kafka destroy  # 환경 정리
```

**포함:**
- docker-compose.yml (기본) + monitoring.yml (선택)
- 실습 스크립트 (단계별 관찰 포인트 포함)
- 실습 가이드 README

### `/setup-quiz` — Slack 일일 퀴즈

학습 중 틀린 문제를 자동으로 수집해서 Slack으로 매일 복습 퀴즈를 보낸다.

```
setup-quiz : 카프카
```

**구성:** GitHub Actions + Leitner 간격반복 알고리즘

### `/blog` — 기술 블로그 글쓰기

배운 내용을 블로그 글로 정리한다.

```
blog : 카프카 프로듀서의 acks 설정
```

**문체:** 오웰의 6가지 규칙 + Toulmin 논증 + Steel Man + 담백한 문체

---

## 프로젝트 구조

```
Booki-Taka/
├── .claude/
│   ├── CLAUDE.md                    # 프로젝트 설정 + 스킬 카탈로그
│   ├── skills/                      # 커스텀 스킬 정의
│   │   ├── index.md                 # 스킬 마스터 인덱스
│   │   ├── study/
│   │   │   ├── session.md           # /study 스킬
│   │   │   ├── vault.md             # /study-vault 스킬
│   │   │   └── setup-quiz.md        # /setup-quiz 스킬
│   │   ├── writing/
│   │   │   └── blog.md              # /blog 스킬
│   │   └── lab/
│   │       └── setup.md             # /lab 스킬
│   ├── hooks/
│   │   └── skill-router.mjs         # 키워드 기반 스킬 자동 라우팅
│   └── commands/                    # 슬래시 커맨드 래퍼
│
├── study-vault/                     # 생성된 학습 노트
│   └── 카프카/
│       └── 카프카_통합_Part1/
│           ├── 00-dashboard.md
│           ├── 00-quick-reference.md
│           ├── 00-concept-compare.md
│           ├── 01-핵심-아키텍처/
│           ├── 02-토픽과-파티션/
│           ├── 03-프로듀서/
│           └── 04-컨슈머/
│
├── labs/                            # Docker 실습 환경
│   ├── kafka/                       # Kafka Lab
│   │   ├── docker-compose.yml
│   │   ├── docker-compose.monitoring.yml
│   │   ├── scripts/                 # 5개 실습 스크립트
│   │   └── config/                  # Prometheus, Grafana 설정
│   └── elasticsearch/               # ES Lab
│
├── 책 목록/                          # PDF 원본 (카테고리별 정리)
│   ├── 카프카/
│   ├── 엘라스틱서치/
│   ├── 데이터베이스/
│   └── ...
│
└── README.md
```

---

## 스킬 간 연동 흐름

```
/study-vault (사전 노트)
  └── 대시보드 + 빠른참조 + 개념비교 + 개념/실습 노트
                    ↓
/study (깊이 학습) ─── 개념별 메타인지 추적
  ├── 검증 중 "직접 해보고 싶다" → /lab 실습 환경 구축
  ├── 틀린 문제 → /setup-quiz 로 Slack 복습
  └── 학습 메모 → /blog 로 블로그 정리
```

---

## 스킬 호출 방식

두 가지 방식으로 호출할 수 있다:

**1. 슬래시 커맨드** (Claude Code 기본)
```
/study 카프카
/lab kafka
```

**2. 키워드 트리거** (skill-router 훅)
```
study : 카프카
lab : kafka
blog : 카프카 프로듀서
```

프롬프트 시작 부분에 `{스킬이름} : {인자}` 패턴이 감지되면 해당 스킬이 자동 활성화된다.

---

## 새 스킬 추가하기

1. `.claude/skills/{카테고리}/{이름}.md` 파일 생성
2. `.claude/skills/index.md` 카탈로그 테이블에 등록
3. `.claude/CLAUDE.md` 스킬 카탈로그 섹션에도 등록
4. (선택) `.claude/hooks/skill-router.mjs`의 `SKILL_ROUTES`에 키워드 추가

---

## 라이선스

이 프로젝트는 [MIT License](LICENSE)를 따릅니다.

학습 노트와 실습 스크립트는 자유롭게 사용할 수 있습니다.
단, `책 목록/` 하위의 PDF 파일은 각 출판사의 저작권을 따릅니다.
