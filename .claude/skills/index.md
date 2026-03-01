# Booki-Taka 스킬 인덱스

이 파일은 프로젝트의 모든 커스텀 스킬을 정리한 오케스트레이션 문서다.
새 스킬을 추가할 때 반드시 여기에도 등록한다.

---

## 스킬 카탈로그

### 📖 study/ — 학습 관련
| 스킬 | 호출 | 설명 |
|---|---|---|
| [session](study/session.md) | `/study` | First Principles 기반 학습 세션. PDF 읽기→원리 추출→"왜?" 대화→유형별 검증→블로그 작성 + 개념별 메타인지 추적 |
| [vault](study/vault.md) | `/study-vault` | 책 PDF → 구조화된 학습 노트 사전 생성. 대시보드/빠른참조/시험함정/개념별 노트 + 능동적 회상 + 설계 트레이드오프 |
| [setup-quiz](study/setup-quiz.md) | `/setup-quiz` | Slack 일일 복습 퀴즈 시스템 구축. GitHub Actions + Leitner 간격반복 |

### ✍️ writing/ — 글쓰기 관련
| 스킬 | 호출 | 설명 |
|---|---|---|
| [blog](writing/blog.md) | `/blog` | 기술 블로그 글쓰기. 오웰·진서·그레이엄 철학 + Toulmin 논증 + Steel Man + 담백한 문체 |

### 🔬 lab/ — 실습 환경 구축
| 스킬 | 호출 | 설명 |
|---|---|---|
| [setup](lab/setup.md) | `/lab [기술]` | Docker Compose 기반 실습 환경. Kafka/ES/MySQL/Redis + 모니터링 + 부하테스트 |

---

## 스킬 추가 규칙

1. **디렉토리 분류**: 관련 스킬끼리 같은 폴더에 넣는다.
   ```
   .claude/skills/
   ├── index.md              ← 이 파일 (마스터 인덱스)
   ├── study/                ← 학습 관련
   │   ├── session.md
   │   ├── vault.md
   │   └── setup-quiz.md
   ├── writing/              ← 블로그/문서 관련 (예시)
   └── infra/                ← 인프라/DevOps 관련 (예시)
   ```

2. **네이밍**: `{동사 또는 명사}.md` — 짧고 명확하게.

3. **등록**: 새 스킬 생성 시 이 index.md의 해당 카테고리 테이블에 추가한다.
   카테고리가 없으면 새 섹션을 만든다.

4. **스킬 파일 필수 항목**:
   - `# 제목` — 스킬 이름과 한줄 설명
   - `## 트리거` — 어떻게 호출하는지
   - 나머지는 자유 형식

---

## 연동 관계

```
/study-vault (사전 노트 생성) ─── 책 읽기 전 구조화된 노트 먼저 생성
  └── 대시보드 + 빠른참조 + 시험함정 + 개념/실습 노트
                    ↓ (노트를 기반으로 깊은 학습)
/study (학습 세션) ─── 개념별 메타인지 추적 (🟦🟩🟨🟥⬜)
  ├── Phase 3 검증 → quiz_bank.json에 퀴즈 자동 저장
  │                       ↓
  │   /setup-quiz (퀴즈 시스템)
  │     └── GitHub Actions → 매일 Slack으로 복습 퀴즈 발송 + 키워드 채점
  │
  ├── Phase 3 검증 중 "직접 해보고 싶다" → /lab 실습 환경 구축
  │                                          ↓
  │   /lab (실습 환경)
  │     └── Docker Compose 기동 → 모니터링 → 테스트 → 관찰 → 분석
  │
  └── Phase 4 블로그 작성 → /blog 글쓰기 철학 공유
                                ↓
      /blog (블로그 글쓰기)
        └── 뼈대 → 초안 → Kill Your Darlings 검수 → Notion 저장
```
