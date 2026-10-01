"""디자인실·기획실 산출물을 기계적으로 점검한다. 통과해야 submit_design / submit_spec 할 수 있다.

    python tools/check_design.py games/<slug> --stage design [--sim passed|skipped] [--milestone N]
    python tools/check_design.py games/<slug> --stage plan   [--godot PATH] [--milestone N]

--milestone 은 몇 차 빌드인지(기본 1 = 프로토타입). 2 이상은 프로덕션 부서의 산출물을 본다:
  design: 위 항목 + design/PRODUCTION_<N>.md
  plan:   FIRST_BUILD.md 대신 design/BUILD_<N>.md, 이전 차수 기획서 design/spec_m<k>.json 보관,
          이전 차수의 must_work 검사가 tests/smoke.gd 에 그대로 남아 있는지(회귀 검사)

design: design/GAME_DESIGN.md(16개 절), design/ROADMAP.md, 시뮬레이션(design/sim/*.py 재실행 + RESULTS.md)
plan:   design/FIRST_BUILD.md(테스트 인터페이스), design/SCREENS.md, design/spec.json(DB와 같은 규칙),
        tests/smoke.gd(must_work 전부 check, SMOKE PASS, 문법), 마지막 줄에 tests_sha256 출력
"""
import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

DESIGN_SECTIONS = [
    "한 줄 정의", "플레이어 판타지", "핵심 판단과 조작", "코어 루프", "세션 구조", "규칙", "상태 모델",
    "콘텐츠 모델", "난이도 곡선", "성장과 메타", "경제", "피드백과 손맛", "화면 흐름", "비주얼 방향",
    "깊이 검증", "리스크와 미해결 질문",
]
MIN_DESIGN_CHARS = 6000
# 제안서 형식(2026-10-02~): 대표의 빌드 결재 전에 쓰는 가벼운 디자인. 깊은 설계는 합격 뒤 프로덕션 디자인실이 한다.
PROPOSAL_SECTIONS = [
    "한 줄 정의", "플레이어 판타지", "핵심 판단과 조작", "한 판의 흐름", "주 화면 설계", "핵심 규칙", "깊이의 근거",
    "키울 방향과 미해결 질문",
]
MIN_PROPOSAL_CHARS = 1500


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def validate_spec(p):
    """supabase validate_spec()과 같은 규칙."""
    errs = []
    if not isinstance(p, dict):
        return ["spec은 객체여야 합니다"]
    for k in ("one_liner", "controls", "win_lose"):
        if not p.get(k):
            errs.append(f"{k} 필요")
    if p.get("orientation") not in ("portrait", "landscape"):
        errs.append("orientation은 portrait|landscape")
    screens = p.get("screens")
    if not isinstance(screens, list):
        errs.append("screens 배열 필요")
    elif not 1 <= len(screens) <= 6:
        errs.append(f"screens는 1~6개 (지금 {len(screens)})")
    mw = p.get("must_work")
    if not isinstance(mw, list):
        errs.append("must_work 배열 필요")
    else:
        if not 3 <= len(mw) <= 12:
            errs.append(f"must_work는 3~12개 (지금 {len(mw)})")
        seen = set()
        for item in mw:
            i = str(item.get("id", ""))
            if not re.fullmatch(r"M[0-9]+", i):
                errs.append(f"must_work id 형식 오류: {i}")
            elif i in seen:
                errs.append(f"must_work id 중복: {i}")
            seen.add(i)
            if not item.get("text"):
                errs.append(f"{i}: text 필요")
            if not item.get("check"):
                errs.append(f"{i}: check(확인 방법) 필요")
    if "not_now" in p and not isinstance(p["not_now"], list):
        errs.append("not_now는 배열")
    return errs


def check_design(game, sim, errs, milestone=1):
    if milestone >= 2:
        pm = os.path.join(game, "design", f"PRODUCTION_{milestone}.md")
        if not os.path.exists(pm):
            errs.append(f"design/PRODUCTION_{milestone}.md 없음")
        else:
            text = read(pm)
            for title in ("대표 메모", "이번 차수 범위", "규칙 변경", "결정 요청"):
                if not re.search(rf"^##\s*.*{re.escape(title)}", text, re.M):
                    errs.append(f"PRODUCTION_{milestone}.md: '{title}' 절 없음")
    gd = os.path.join(game, "design", "GAME_DESIGN.md")
    if not os.path.exists(gd):
        errs.append("design/GAME_DESIGN.md 없음")
    else:
        text = read(gd)
        # 예전 형식(16개 절)이면 그대로, 아니면 제안서 형식(8개 절)으로 본다
        proposal = not re.search(r"^##\s*16\.", text, re.M)
        sections, min_chars = (PROPOSAL_SECTIONS, MIN_PROPOSAL_CHARS) if proposal else (DESIGN_SECTIONS, MIN_DESIGN_CHARS)
        for n, title in enumerate(sections, 1):
            if not re.search(rf"^##\s*{n}\.\s*{re.escape(title)}", text, re.M):
                errs.append(f"GAME_DESIGN.md: '## {n}. {title}' 절 없음")
        if len(text) < min_chars:
            errs.append(f"GAME_DESIGN.md가 너무 짧음 ({len(text)}자 < {min_chars}자)")
        if proposal and milestone == 1:
            mock = os.path.join(game, "design", "mock", "main.svg")
            if not os.path.exists(mock):
                errs.append("design/mock/main.svg 없음 — 주 화면 시안이 있어야 대표가 빌드 결재를 할 수 있음")
            elif "viewBox" not in read(mock):
                errs.append("design/mock/main.svg 에 viewBox 가 없음")
            return   # 제안서에는 ROADMAP 과 시뮬레이션이 없다
        if re.search(r"TODO|TBD|미정\s*$", text, re.M):
            errs.append("GAME_DESIGN.md에 TODO/TBD/미정이 남아 있음 — 결정하거나 '리스크와 미해결 질문'으로 옮기세요")
    if not os.path.exists(os.path.join(game, "design", "ROADMAP.md")):
        errs.append("design/ROADMAP.md 없음")

    simdir = os.path.join(game, "design", "sim")
    if sim == "passed":
        scripts = sorted(glob.glob(os.path.join(simdir, "*.py")))
        if not scripts:
            errs.append("sim=passed인데 design/sim/*.py 없음")
        if not os.path.exists(os.path.join(simdir, "RESULTS.md")):
            errs.append("sim=passed인데 design/sim/RESULTS.md 없음")
        for s in scripts:
            try:
                p = subprocess.run([sys.executable, s], capture_output=True, text=True, timeout=300, cwd=simdir)
                if p.returncode != 0:
                    errs.append(f"시뮬레이션 재실행 실패: {os.path.basename(s)}\n{(p.stdout + p.stderr)[-800:]}")
            except subprocess.TimeoutExpired:
                errs.append(f"시뮬레이션이 5분 안에 끝나지 않음: {os.path.basename(s)}")
    elif sim == "skipped":
        if os.path.exists(gd) and not re.search(r"시뮬레이션.*(생략|건너)", read(gd)):
            errs.append("sim=skipped면 GAME_DESIGN.md '깊이 검증' 절에 시뮬레이션을 생략한 이유를 적어야 함")


def find_godot(explicit):
    for cand in (explicit, os.environ.get("GODOT"), shutil.which("godot")):
        if cand and (os.path.exists(cand) or shutil.which(cand)):
            return cand
    return None


def check_plan(game, godot, errs, milestone=1):
    build_doc = "FIRST_BUILD.md" if milestone == 1 else f"BUILD_{milestone}.md"
    for f in ("GAME_DESIGN.md", build_doc, "SCREENS.md", "spec.json"):
        if not os.path.exists(os.path.join(game, "design", f)):
            errs.append(f"design/{f} 없음")
    test = os.path.join(game, "tests", "smoke.gd")
    if not os.path.exists(test):
        errs.append("tests/smoke.gd 없음")
    if errs:
        return None

    fb = read(os.path.join(game, "design", build_doc))
    if not re.search(r"^##\s*.*테스트 인터페이스", fb, re.M):
        errs.append(f"{build_doc}에 '테스트 인터페이스' 절 없음")

    # 이전 차수의 기획서는 spec_m<k>.json 으로 보관하고, 그 must_work 검사는 smoke.gd 에 그대로 남아야 한다
    regression = []
    for k in range(1, milestone):
        old = os.path.join(game, "design", f"spec_m{k}.json")
        if not os.path.exists(old):
            errs.append(f"design/spec_m{k}.json 없음 — {k}차 기획서(spec.json)를 이 이름으로 보관하세요")
            continue
        try:
            regression += [m.get("id") for m in json.loads(read(old)).get("must_work") or []]
        except json.JSONDecodeError as e:
            errs.append(f"spec_m{k}.json 파싱 실패: {e}")

    try:
        spec = json.loads(read(os.path.join(game, "design", "spec.json")))
    except json.JSONDecodeError as e:
        errs.append(f"spec.json 파싱 실패: {e}")
        return None
    errs.extend("spec.json: " + e for e in validate_spec(spec))

    screens_md = read(os.path.join(game, "design", "SCREENS.md"))
    for sc in spec.get("screens") or []:
        sid = sc.get("id") if isinstance(sc, dict) else None
        if not sid or not re.search(rf"^#+.*\b{re.escape(sid)}\b", screens_md, re.M):
            errs.append(f"SCREENS.md에 화면 '{sid}' 제목이 없음")

    smoke = read(test)
    ids = [m.get("id") for m in spec.get("must_work") or []]
    for i in ids:
        if not re.search(rf'check\(\s*"{re.escape(str(i))}"', smoke):
            errs.append(f'tests/smoke.gd에 check("{i}", ...) 없음')
    overlap = set(ids) & set(regression)
    if overlap:
        errs.append(f"이번 차수 must_work id가 이전 차수와 겹침: {', '.join(sorted(overlap))} — 번호를 이어서 쓰세요")
    for i in regression:
        if not re.search(rf'check\(\s*"{re.escape(str(i))}"', smoke):
            errs.append(f'tests/smoke.gd에서 이전 차수 검사 check("{i}", ...)가 사라짐(회귀 검사는 지우지 않는다)')
    extra = set(re.findall(r'check\(\s*"(M[0-9]+)"', smoke)) - set(ids) - set(regression)
    if extra:
        errs.append(f"tests/smoke.gd에 어느 차수 must_work에도 없는 id: {', '.join(sorted(extra))}")
    if not re.search(r'"SMOKE[ %]', smoke) or "PASS" not in smoke or "quit(" not in smoke:
        errs.append('tests/smoke.gd는 마지막에 "SMOKE PASS"를 출력하고 quit(0|1) 해야 함')

    if os.path.exists(os.path.join(game, "project.godot")):
        g = find_godot(godot)
        if g:
            p = subprocess.run([g, "--headless", "--path", game, "--check-only", "--script", "res://tests/smoke.gd"],
                               capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
            out = p.stdout + p.stderr
            if p.returncode != 0 or re.search(r"Parse Error|SCRIPT ERROR", out):
                errs.append("tests/smoke.gd 문법 오류:\n" + out[-1200:])
        else:
            print("참고: Godot가 없어 smoke.gd 문법 검사는 건너뜀 (GODOT 환경변수 또는 --godot)")
    else:
        errs.append("project.godot 없음 — python tools/new_game.py 로 게임 폴더를 먼저 만드세요")

    with open(test, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--stage", choices=("design", "plan"), required=True)
    ap.add_argument("--sim", choices=("passed", "skipped"))
    ap.add_argument("--godot")
    ap.add_argument("--milestone", type=int, default=1)
    a = ap.parse_args()
    game = os.path.abspath(a.game)
    errs = []
    digest = None
    if a.stage == "design":
        if not a.sim:
            sys.exit("--stage design 에는 --sim passed|skipped 가 필요합니다")
        check_design(game, a.sim, errs, a.milestone)
    else:
        digest = check_plan(game, a.godot, errs, a.milestone)

    name = os.path.basename(game)
    if errs:
        print(f"{name} [{a.stage}]: FAIL")
        for e in errs:
            print(" - " + e)
        sys.exit(1)
    print(f"{name} [{a.stage}]: PASS")
    if digest:
        print(f"tests_sha256={digest}")


if __name__ == "__main__":
    main()
