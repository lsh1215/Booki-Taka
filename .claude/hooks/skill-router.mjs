#!/usr/bin/env node

/**
 * Booki-Taka Skill Router
 *
 * UserPromptSubmit 훅에서 실행.
 * "study : 카프카", "lab : es" 같은 패턴을 감지하면
 * 해당 스킬 파일을 컨텍스트로 주입한다.
 *
 * 패턴: {스킬이름} : {인자}  또는  {스킬이름}:{인자}
 */

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = join(__dirname, "..", "skills");

// 스킬 라우팅 테이블
const SKILL_ROUTES = {
  "study-vault": {
    file: "study/vault.md",
    desc: "Study Vault (사전 노트 생성)",
  },
  study: {
    file: "study/session.md",
    desc: "Deep Study (First Principles 학습)",
  },
  "setup-quiz": {
    file: "study/setup-quiz.md",
    desc: "Setup Quiz (Slack 퀴즈 시스템)",
  },
  blog: {
    file: "writing/blog.md",
    desc: "Blog (기술 블로그 글쓰기)",
  },
  lab: {
    file: "lab/setup.md",
    desc: "Lab (실습 환경 구축)",
  },
};

// study-vault를 study보다 먼저 매칭하기 위해 긴 이름 순으로 정렬
const SKILL_NAMES = Object.keys(SKILL_ROUTES).sort(
  (a, b) => b.length - a.length
);

function main() {
  let input = "";
  try {
    input = readFileSync("/dev/stdin", "utf8").trim();
  } catch {
    console.log(JSON.stringify({ continue: true }));
    return;
  }

  let prompt = "";
  try {
    const data = JSON.parse(input);
    prompt = (data.prompt || data.message || "").trim();
  } catch {
    prompt = input;
  }

  if (!prompt) {
    console.log(JSON.stringify({ continue: true }));
    return;
  }

  // 코드 블록 제거 (오탐 방지)
  const cleanPrompt = prompt.replace(/```[\s\S]*?```/g, "").replace(/`[^`]*`/g, "");

  // 패턴 매칭: "스킬이름 : 인자" 또는 "스킬이름: 인자" 또는 "스킬이름:인자"
  // 메시지 시작 부분에서만 매칭 (중간에 있는 "study"는 무시)
  for (const name of SKILL_NAMES) {
    const pattern = new RegExp(
      `^\\s*${name.replace("-", "[-\\s]?")}\\s*:\\s*(.*)`,
      "is"
    );
    const match = cleanPrompt.match(pattern);
    if (match) {
      const args = match[1].trim();
      const route = SKILL_ROUTES[name];
      const skillPath = join(SKILLS_DIR, route.file);

      let skillContent = "";
      try {
        skillContent = readFileSync(skillPath, "utf8");
      } catch {
        console.log(
          JSON.stringify({
            continue: true,
            message: `[SKILL ERROR] ${skillPath} 파일을 찾을 수 없습니다.`,
          })
        );
        return;
      }

      const message = [
        `[MAGIC KEYWORD: ${name}]`,
        "",
        `**${route.desc} 모드 활성화**`,
        "",
        `아래 스킬 지시를 정확히 따라 진행한다.`,
        args ? `인자: ${args}` : "(인자 없음 — Phase 0에서 사용자에게 선택을 묻는다)",
        "",
        "---",
        "",
        skillContent,
      ].join("\n");

      console.log(JSON.stringify({ continue: true, message }));
      return;
    }
  }

  // 매칭 없음 — 그냥 통과
  console.log(JSON.stringify({ continue: true }));
}

main();
