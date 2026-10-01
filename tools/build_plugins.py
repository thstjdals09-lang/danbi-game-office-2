"""부서 프롬프트(prompts/*.md)를 Claude Code 플러그인으로 묶는다. 부서마다 플러그인 하나.

    python tools/build_plugins.py

prompts/<부서>.md 가 원본이다. 이 스크립트가 그 안의 실행 문구(``` 블록)를 꺼내
plugins/dgo2-<부서>/SKILL.md 로 옮기고, .claude-plugin/marketplace.json 을 다시 쓴다.
프롬프트를 고친 뒤에는 이 스크립트를 다시 돌려 플러그인을 맞춘다(플러그인 쪽을 직접 고치지 않는다).
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = "0.2.0"
OWNER = "danbi-game-office-2"

# 파일 이름, 부서 이름, 언제 부르는지(슬래시 명령 목록에 보이는 한 줄)
DEPARTMENTS = [
    ("idea-lab", "아이디어 연구소", "새 게임 아이디어를 넓게 찾아 구조화·비평한 뒤 제작 가치가 있는 것만 입고한다"),
    ("designer", "디자인실", "아이디어 하나를 가져와 깊이 있는 게임 디자인과 규칙 시뮬레이션을 만든다"),
    ("planner", "기획실", "디자인에서 첫 빌드 조각을 잘라 화면·규칙·검사(tests/smoke.gd)를 확정한다"),
    ("builder", "빌드실", "기획 패키지를 Godot 게임으로 만들고 검사를 통과시킨다"),
    ("qa", "검수실", "빌드를 CI·검사 파일 무결성·화면·빌드 기록의 정직함으로 검수한다"),
    ("artist", "아트실", "검수를 통과한 게임의 핵심 화면을 아트 방향 3안으로 그려 진열장에 올린다"),
    ("prod-designer", "프로덕션 디자인실", "대표가 합격시킨 게임의 다음 차수를 설계한다"),
    ("prod-planner", "프로덕션 기획실", "다음 차수의 빌드 조각과 검사를 확정한다(이전 차수 검사는 회귀로 남긴다)"),
    ("prod-developer", "프로덕션 개발실", "다음 차수를 기존 게임 위에 만들고 회귀 검사까지 통과시킨다"),
]

LOCAL_NOTE = """
## 이 PC에서 손으로 돌릴 때

- 저장소: `C:\\xampp\\htdocs\\danbi-game-office-2` (GitHub `thstjdals09-lang/danbi-game-office-2`, main). 같은 저장소에서 다른 세션이 동시에 커밋할 수 있다 — 내 게임 폴더만 `git add` 하고, push 전에 `git pull --rebase --autostash`.
- DB: Supabase 커넥터의 `execute_sql` (프로젝트 `iqeqcnetdsusqkkxvver`). 여러 문장을 한 번에 보내면 하나가 실패할 때 전부 취소된다.
- Godot: `export GODOT="C:/Users/a/tools/godot/Godot_v4.7.2-stable_win64_console.exe"`
- 이 명령은 사람이 부를 때만 실행한다. 한 번 부르면 일을 하나 가져와 끝까지 하고 퇴근(run_finish)한다.
"""


def extract(path):
    text = io.open(path, encoding="utf-8").read()
    m = re.search(r"^```\n(.*?)^```\s*$", text, re.S | re.M)
    if not m:
        sys.exit(f"{path}: 실행 문구(``` 블록)를 찾지 못함")
    head = text[:m.start()]
    title = head.splitlines()[0].lstrip("# ").strip()
    quote = [l[1:].strip() for l in head.splitlines() if l.startswith(">")]
    return title, quote, m.group(1).rstrip() + "\n"


def main():
    plugins = []
    for slug, name, when in DEPARTMENTS:
        src = os.path.join(ROOT, "prompts", slug + ".md")
        title, quote, body = extract(src)
        pname = "dgo2-" + slug
        pdir = os.path.join(ROOT, "plugins", pname)
        os.makedirs(os.path.join(pdir, ".claude-plugin"), exist_ok=True)
        desc = f"단비의 게임회사2 {name}: {when}."
        manifest = {
            "$schema": "https://anthropic.com/claude-code/plugin.schema.json",
            "name": pname, "version": VERSION, "description": desc,
            "author": {"name": OWNER}, "skills": ["./"],
        }
        with io.open(os.path.join(pdir, ".claude-plugin", "plugin.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
            f.write("\n")
        skill = [
            "---",
            f"name: {pname}",
            "description: " + json.dumps(f"{desc} 사용자가 '{name} 실행', '{name} 돌려'처럼 이 부서를 직접 부를 때만 쓴다.", ensure_ascii=False),
            "disable-model-invocation: true",
            "---",
            "",
            f"# {name}",
            "",
            f"원본: `prompts/{slug}.md` ({title}). 이 파일은 `python tools/build_plugins.py` 가 만든다 — 직접 고치지 말 것.",
            "",
        ]
        skill += [f"> {q}" if q else ">" for q in quote]
        skill += ["", "아래 실행 문구를 그대로 따른다.", "", "## 실행 문구", "", body.rstrip(), LOCAL_NOTE.rstrip(), ""]
        with io.open(os.path.join(pdir, "SKILL.md"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(skill))
        plugins.append({"name": pname, "source": "./plugins/" + pname, "description": desc, "version": VERSION})
        print(f"{pname}: {len(body.splitlines())}줄")
    market = {
        "name": "danbi-game-office-2",
        "owner": {"name": OWNER},
        "metadata": {"description": "단비의 게임회사2의 부서별 실행 프롬프트. 부서마다 플러그인 하나."},
        "plugins": plugins,
    }
    os.makedirs(os.path.join(ROOT, ".claude-plugin"), exist_ok=True)
    with io.open(os.path.join(ROOT, ".claude-plugin", "marketplace.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(market, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
