(function () {
  "use strict";

  var CFG = window.DANBI2 || {};
  var LIVE = !!(CFG.supabaseUrl && CFG.supabaseAnonKey && window.supabase);
  var sb = LIVE ? window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey) : null;

  var ROLES = [
    { id: "idea_lab", name: "아이디어 연구소" },
    { id: "designer", name: "디자인실" },
    { id: "planner", name: "기획실" },
    { id: "builder", name: "빌드실" },
    { id: "qa", name: "검수실" },
    { id: "artist", name: "아트실" },
    { id: "prod_designer", name: "프로덕션 디자인실" },
    { id: "prod_planner", name: "프로덕션 기획실" },
    { id: "prod_developer", name: "프로덕션 개발실" }
  ];
  var STATIONS = [
    { stage: "idea", who: "디자인", nm: "디자인 대기" },
    { stage: "designing", who: "디자인", nm: "디자인 중" },
    { stage: "designed", who: "기획", nm: "기획 대기" },
    { stage: "planning", who: "기획", nm: "기획 중" },
    { stage: "ready", who: "빌드·개발", nm: "빌드 대기" },
    { stage: "building", who: "빌드·개발", nm: "빌드 중" },
    { stage: "qa", who: "검수실", nm: "검수 대기" },
    { stage: "playtest", who: "대표", nm: "플레이 대기" },
    { stage: "kept", who: "프로덕션", nm: "다음 차수 대기", goal: true },
    { stage: "done", who: "", nm: "완료", goal: true }
  ];
  var RUN_LABEL = { success: "진행", noop: "할 일 없음", running: "작업 중", blocked: "대표 판단 요청", failed: "운영 장애" };
  var PAGE = 40;

  var state = { games: [], runs: [], events: [], builds: [], decisions: [], limits: {}, play: null, ceo: false, email: null };
  var ui = { view: "home", filter: "all", game: null, query: "", shown: PAGE, onlyStar: false, idea: null, open: {} };

  // ---------------------------------------------------------------- 유틸

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function ago(iso) {
    if (!iso) return "기록 없음";
    var m = Math.max(0, Math.round((Date.now() - new Date(iso)) / 60000));
    if (m < 1) return "방금";
    if (m < 60) return m + "분 전";
    var h = Math.round(m / 60);
    if (h < 24) return h + "시간 전";
    return Math.round(h / 24) + "일 전";
  }
  function stamp(iso) {
    var d = new Date(iso);
    var p = function (n) { return String(n).padStart(2, "0"); };
    return p(d.getMonth() + 1) + "/" + p(d.getDate()) + " " + p(d.getHours()) + ":" + p(d.getMinutes());
  }
  var toastTimer;
  function toast(msg, isErr) {
    var t = document.querySelector(".toast");
    if (!t) { t = document.createElement("div"); t.className = "toast"; t.setAttribute("role", "status"); document.body.appendChild(t); }
    t.textContent = msg;
    t.classList.toggle("err", !!isErr);
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, isErr ? 6000 : 3000);
  }
  function byStage(stage) { return state.games.filter(function (g) { return g.stage === stage; }); }
  function queueOrder(a, b) {
    if (a.starred !== b.starred) return a.starred ? -1 : 1;
    return new Date(a.stage_changed_at) - new Date(b.stage_changed_at);
  }
  function latestBuild(gameId) {
    for (var i = 0; i < state.builds.length; i++) if (state.builds[i].game_id === gameId) return state.builds[i];
    return null;
  }
  function playable(slug) {
    if (!state.play || !state.play.games) return null;
    var s = state.play.games[slug];
    return s ? s.smoke === true : false;
  }

  // ---------------------------------------------------------------- 데이터

  async function load() {
    try {
      if (LIVE) {
        var r = await Promise.all([
          sb.from("games").select("id,slug,title,pitch,core_verb,fun_hypothesis,genre,idea_scores,why_promoted,next_test,idea_brief,design_summary,sim_status,design_version,spec_version,art,art_pick,milestone,keep_notes,stage,attempt,starred,spec,fix_notes,lease_owner,lease_until,created_at,stage_changed_at").order("stage_changed_at", { ascending: false }).limit(2000),
          sb.from("runs").select("*").order("started_at", { ascending: false }).limit(200),
          sb.from("events").select("*").order("id", { ascending: false }).limit(30),
          sb.from("builds").select("game_id,attempt,commit_sha,smoke_passed,created_at").order("created_at", { ascending: false }).limit(500),
          sb.from("wip_limits").select("*"),
          sb.from("decisions").select("*").order("created_at", { ascending: false }).limit(500)
        ]);
        r.forEach(function (x) { if (x.error) throw x.error; });
        state.games = r[0].data; state.runs = r[1].data; state.events = r[2].data; state.builds = r[3].data;
        state.limits = {};
        r[4].data.forEach(function (l) { state.limits[l.stage] = l.max_items; });
        state.decisions = r[5].data;
      } else if (!state.games.length) {
        Object.assign(state, demoData());
      }
      state.play = await fetch("play/status.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
      if (!LIVE && !state.play) state.play = { games: { "first-lantern": { smoke: true } } };
      $("updated").textContent = stamp(new Date()) + " 기준";
      render();
    } catch (e) {
      toast("불러오기 실패: " + (e.message || e), true);
    }
  }

  async function refreshAuth() {
    if (!LIVE) { state.ceo = true; return; }
    var s = await sb.auth.getSession();
    var session = s.data.session;
    state.email = session ? session.user.email : null;
    state.ceo = false;
    if (session) {
      var r = await sb.rpc("is_ceo");
      state.ceo = !r.error && r.data === true;
      if (!state.ceo) toast(state.email + "은 대표로 등록되지 않은 메일입니다", true);
    }
  }

  async function act(fn, args, okMsg) {
    if (!state.ceo) { toast("대표 로그인이 필요합니다", true); return; }
    if (!LIVE) { demoAct(fn, args); toast(okMsg + " (예시 모드라 저장되지 않음)"); render(); return; }
    var r = await sb.rpc(fn, args);
    if (r.error) { toast(r.error.message, true); return; }
    toast(okMsg);
    await load();
  }

  // ---------------------------------------------------------------- 그리기

  var VIEWS = [
    { id: "home", label: "결재함" },
    { id: "games", label: "게임" },
    { id: "ideas", label: "아이디어" },
    { id: "factory", label: "공장" }
  ];
  // 단계 이름과 모양. [표시 이름, 모양]
  var STAGE_LABEL = {
    idea: ["디자인 대기", "wait"], designing: ["디자인 중", ""], designed: ["기획 대기", "wait"], planning: ["기획 중", ""],
    ready: ["빌드 대기", "wait"], building: ["빌드 중", ""], qa: ["검수 대기", "wait"],
    playtest: ["플레이 대기", "warn"], kept: ["합격 · 다음 차수 대기", "done"], held: ["판단 필요", "warn"], dropped: ["버림", "off"],
    done: ["완료", "done"]
  };
  // 진행 점 6칸: 디자인 · 기획 · 빌드 · 검수 · 플레이 · 합격
  var STEP_OF = { idea: 0, designing: 0, designed: 1, planning: 1, ready: 2, building: 2, qa: 3, playtest: 4, kept: 5, done: 5 };
  var WIP_STAGES = ["designing", "designed", "planning", "ready", "building", "qa"];
  // 문서 탭. 차수 2 이상이면 차수마다 프로덕션 설계·기획 문서가 붙는다(최신 차수가 앞).
  function docsOf(g) {
    var docs = [{ id: "design", label: "디자인", file: "design/GAME_DESIGN.md" }];
    for (var n = g.milestone || 1; n >= 2; n--) {
      docs.push({ id: "prod" + n, label: n + "차 설계", file: "design/PRODUCTION_" + n + ".md" });
      docs.push({ id: "build" + n, label: n + "차 기획", file: "design/BUILD_" + n + ".md" });
    }
    return docs.concat([
      { id: "sim", label: "시뮬레이션", file: "design/sim/RESULTS.md" },
      { id: "roadmap", label: "로드맵", file: "design/ROADMAP.md" },
      { id: "first", label: "첫 빌드 기획", file: "design/FIRST_BUILD.md" },
      { id: "screens", label: "화면", file: "design/SCREENS.md" },
      { id: "build", label: "빌드 기록", file: "BUILD.md" },
      { id: "shots", label: "스크린샷", dir: "shots" }
    ]);
  }
  var docState = { game: null, tab: "design" };

  function count(stages) { return state.games.filter(function (g) { return stages.indexOf(g.stage) >= 0; }).length; }
  function dis() { return state.ceo ? "" : ' disabled title="대표 로그인 필요"'; }
  function stageChip(g) {
    var st = STAGE_LABEL[g.stage] || [g.stage, "wait"];
    return '<span class="stage ' + st[1] + '">' + esc(st[0]) + "</span>" + (g.milestone > 1 ? '<span class="chip ms">' + g.milestone + "차</span>" : "");
  }
  function gameOf(id) { return state.games.find(function (x) { return x.id === id; }); }
  function pendingDecisions() {
    return state.decisions.filter(function (d) {
      var g = gameOf(d.game_id);
      return !d.chosen && g && g.stage !== "dropped" && g.stage !== "done";
    });
  }
  function deptName(owner) {
    var id = String(owner || "").split(":")[0];
    var r = ROLES.find(function (x) { return x.id === id; });
    return r ? r.name : id;
  }
  // 결정 요청 한 줄. 접혀 있을 때는 질문·게임·추천만 보이고, "추천대로"는 펼치지 않고 바로 누를 수 있다.
  function decisionHtml(d, withGame) {
    var g = gameOf(d.game_id);
    var key = "d:" + d.id;
    var label = function (id) { var o = (d.options || []).find(function (x) { return x.id === id; }); return o ? o.label : id; };
    var opts = (d.options || []).map(function (o) {
      var rec = o.id === d.recommended, chosen = o.id === d.chosen;
      return '<div class="opt' + (chosen ? " chosen" : "") + '"><div class="nm">' + esc(o.label) + (rec ? '<span class="chip next">부서 추천</span>' : "") + (chosen ? '<span class="chip ok">대표 결정</span>' : "") + "</div>" +
        '<div class="ds">' + esc(o.detail) + "</div>" +
        (o.pros ? '<div class="pc"><b class="pro">+</b> ' + esc(o.pros) + "</div>" : "") + (o.cons ? '<div class="pc"><b class="con">−</b> ' + esc(o.cons) + "</div>" : "") +
        '<div class="acts"><button class="btn small' + (chosen ? " go" : "") + '" type="button" data-decide="' + d.id + '" data-choice="' + esc(o.id) + '"' + dis() + ">" + (chosen ? "✓ 결정함" : "이걸로") + "</button></div></div>";
    }).join("");
    var sub = (withGame && g ? esc(g.title) + " · " : "") + (d.chosen ? "결정: " + esc(label(d.chosen)) : "추천: " + esc(label(d.recommended)));
    var side = d.chosen
      ? '<span class="chip ok">결정함</span>'
      : '<button class="btn small" type="button" data-decide="' + d.id + '" data-choice="' + esc(d.recommended) + '"' + dis() + ">추천대로</button>";
    return '<details class="fold ask' + (d.chosen ? "" : " attn") + '" data-fold="' + key + '"' + foldOpen(key) + '><summary><span class="chev">›</span>' +
      '<span class="fold-main"><span class="fold-title">' + esc(d.question) + '</span><span class="fold-sub">' + sub + "</span></span>" +
      '<span class="fold-side">' + side + '</span></summary><div class="fold-body">' +
      (withGame && g ? '<div class="p"><button class="linkish" type="button" data-game="' + esc(g.slug) + '">' + esc(g.title) + " 열기 ↗</button> · " + esc(deptName(d.asked_by)) + "</div>" : "") +
      '<div class="opts">' + opts + "</div>" + (d.reason ? '<div class="p">추천 이유: ' + esc(d.reason) + "</div>" : "") +
      (d.note ? '<div class="note">' + esc(d.note) + "</div>" : "") + "</div></details>";
  }
  function versionText(g) {
    var parts = [];
    if (g.design_version) parts.push("디자인 v" + g.design_version);
    if (g.spec_version) parts.push("기획 v" + g.spec_version);
    if (g.attempt) parts.push((g.milestone > 1 ? g.milestone + "차 " : "") + "빌드 " + g.attempt + "회차");
    var b = latestBuild(g.id);
    if (b) parts.push(b.commit_sha.slice(0, 7));
    if (g.sim_status === "passed") parts.push("시뮬레이션 검증");
    return parts.join(" · ");
  }
  function docButton(g) {
    return g.design_version ? '<button class="btn ghost" type="button" data-doc="' + g.id + '">문서 보기</button>' : "";
  }
  function foldOpen(key) { return ui.open[key] ? " open" : ""; }

  function render() {
    $("demoTag").hidden = LIVE;
    $("login").textContent = !LIVE ? "예시 모드" : state.email ? (state.ceo ? "대표 · " : "") + state.email.split("@")[0] : "대표 로그인";
    $("login").disabled = !LIVE;
    $("docLink").href = "https://github.com/" + (CFG.repo || "") + "/blob/main/docs/OPERATING_MODEL.md";
    $("promptLink").href = "https://github.com/" + (CFG.repo || "") + "/tree/main/prompts";
    renderNav();
    renderHome();
    renderGames();
    renderIdeas();
    renderFactory();
  }

  function setView(hash) {
    var parts = String(hash || "").split("/");
    var id = parts[0];
    if (!VIEWS.some(function (v) { return v.id === id; })) id = "home";
    ui.view = id;
    ui.game = id === "games" && parts[1] ? decodeURIComponent(parts[1]) : null;
    hash = id + (ui.game ? "/" + ui.game : "");
    renderGames();
    VIEWS.forEach(function (v) { $("view-" + v.id).hidden = v.id !== id; });
    renderNav();
    if (location.hash !== "#" + hash) history.replaceState(null, "", "#" + hash);
    window.scrollTo(0, 0);
  }

  function renderNav() {
    var todo = count(["playtest", "held"]) + pendingDecisions().length;
    var badges = { home: todo, games: count(WIP_STAGES.concat(["playtest", "kept", "done"])), ideas: count(["idea"]), factory: null };
    $("nav").innerHTML = VIEWS.map(function (v) {
      var n = badges[v.id];
      var badge = n == null ? "" : '<span class="badge num' + (v.id === "home" && n > 0 ? " attn" : "") + '">' + n + "</span>";
      return '<button type="button" data-go="' + v.id + '"' + (v.id === ui.view ? ' aria-current="page"' : "") + ">" + esc(v.label) + badge + "</button>";
    }).join("");
  }

  // ---------------------------------------------------------------- 결재함

  function renderHome() {
    var play = byStage("playtest").sort(queueOrder);
    var held = byStage("held").sort(queueOrder);
    var wip = count(WIP_STAGES);
    var asks = pendingDecisions();
    var tiles = [
      { n: play.length, l: "플레이할 게임", h: "해 보고 판정", go: "home", attn: play.length > 0 },
      { n: asks.length + held.length, l: "결정·판단 필요", h: "부서가 올린 건", go: "home", attn: asks.length + held.length > 0 },
      { n: wip, l: "제작 중", h: "디자인 → 검수", go: "games", attn: false }
    ];
    $("tiles").innerHTML = tiles.map(function (t) {
      return '<button class="tile' + (t.attn ? " attn" : t.n ? "" : " zero") + '" type="button" data-go="' + t.go + '"' + (t.go === "games" ? ' data-filter="wip"' : "") +
        '><span class="n num">' + t.n + '</span><span class="l">' + esc(t.l) + '</span><span class="h">' + esc(t.h) + "</span></button>";
    }).join("");

    // 플레이테스트: 라이브러리와 같은 카드. 눌러서 게임 상세에서 플레이하고 판정한다
    $("playtest").innerHTML = play.length ? play.map(gameCard).join("")
      : '<div class="empty" style="grid-column:1/-1">플레이할 게임이 없어요. 검수를 통과하면 여기에 와요.</div>';

    $("askSec").hidden = !asks.length;
    // 같은 게임의 요청끼리 붙여서, 오래된 것부터
    asks.sort(function (a, b) { return a.game_id === b.game_id ? new Date(a.created_at) - new Date(b.created_at) : (a.game_id < b.game_id ? -1 : 1); });
    $("askSide").innerHTML = asks.length + "건 · 고르기 전에는 추천안으로 진행해요" +
      (asks.length > 1 ? ' <button class="btn small ghost" type="button" data-decide-all="1"' + dis() + ">전부 추천대로</button>" : "");
    $("asks").innerHTML = asks.map(function (d) { return decisionHtml(d, true); }).join("");

    $("heldSec").hidden = !held.length;
    $("held").innerHTML = held.map(function (g) {
      return '<article class="card bad"><div class="card-title">' + esc(g.title) + '<span class="mono">' + esc(versionText(g)) + "</span></div>" +
        (g.fix_notes ? '<div class="note">' + esc(g.fix_notes) + "</div>" : '<div class="p">' + esc(g.pitch) + "</div>") +
        '<div class="acts">' + docButton(g) + '<button class="btn go" type="button" data-tri="go" data-id="' + g.id + '"' + dis() + ">다시 진행</button>" +
        '<button class="btn bad" type="button" data-tri="drop" data-id="' + g.id + '"' + dis() + ">버리기</button></div></article>";
    }).join("");

    $("homeDots").innerHTML = ROLES.map(function (role) {
      var info = deptInfo(role);
      return '<span><span class="dot ' + info.dot + '"></span>' + esc(role.name) + " · " + esc(info.short) + "</span>";
    }).join("");
  }

  // ---------------------------------------------------------------- 게임 (라이브러리 → 상세)

  var LIB_STAGES = WIP_STAGES.concat(["playtest", "kept", "held", "dropped"]);
  var GAME_FILTERS = [
    { id: "all", label: "전체", stages: WIP_STAGES.concat(["playtest", "kept", "done"]) },
    { id: "playtest", label: "플레이 대기", stages: ["playtest"] },
    { id: "wip", label: "제작 중", stages: WIP_STAGES },
    { id: "kept", label: "합격·완료", stages: ["kept", "done"] },
    { id: "off", label: "보류·버림", stages: ["held", "dropped"] }
  ];

  function gameUrl(g, file) {
    return "https://raw.githubusercontent.com/" + CFG.repo + "/main/games/" + encodeURIComponent(g.slug) + "/" + file;
  }
  function artOf(g, id) {
    if (!g.art || !g.art.directions) return null;
    return g.art.directions.find(function (d) { return d.id === id; }) || null;
  }
  // 카드 썸네일: 대표가 고른 방향 → A안 → 없음
  function thumbOf(g) {
    var d = artOf(g, g.art_pick || "A");
    return d ? gameUrl(g, d.image) : null;
  }
  // 한 번이라도 합격한 게임(2차 이상)은 다음 차수를 만드는 동안에도 직전 빌드를 플레이할 수 있다
  function hasBuild(g) { return g.stage === "playtest" || g.stage === "kept" || g.stage === "done" || g.milestone > 1; }
  function canPlay(g) { return hasBuild(g) && playable(g.slug) !== false; }
  function stepsHtml(g) {
    var step = STEP_OF[g.stage];
    var stopped = g.stage === "held" || g.stage === "dropped";
    var out = "";
    for (var k = 0; k < 6; k++) {
      out += '<i class="' + (stopped ? (k === 0 ? "stop" : "") : k < step || g.stage === "kept" || g.stage === "done" ? "done" : k === step ? "now" : "") + '"></i>';
    }
    return '<span class="steps" aria-hidden="true">' + out + "</span>";
  }

  function renderGames() {
    var detail = ui.game ? state.games.find(function (g) { return g.slug === ui.game; }) : null;
    $("gameLib").hidden = !!detail;
    $("gameDetail").hidden = !detail;
    if (detail) { renderGameDetail(detail); return; }

    $("gameFilters").innerHTML = GAME_FILTERS.map(function (f) {
      return '<button type="button" data-filter="' + f.id + '" aria-pressed="' + (f.id === ui.filter) + '">' + esc(f.label) + ' <span class="num">' + count(f.stages) + "</span></button>";
    }).join("");
    var filter = GAME_FILTERS.find(function (f) { return f.id === ui.filter; }) || GAME_FILTERS[0];
    var order = ["playtest", "kept", "done", "qa", "building", "ready", "planning", "designed", "designing", "held", "dropped"];
    var games = state.games.filter(function (g) { return filter.stages.indexOf(g.stage) >= 0; })
      .sort(function (a, b) { return order.indexOf(a.stage) - order.indexOf(b.stage) || new Date(b.stage_changed_at) - new Date(a.stage_changed_at); });
    if (!games.length) { $("games").innerHTML = '<div class="empty" style="grid-column:1/-1">여기에 해당하는 게임이 없어요.</div>'; return; }

    $("games").innerHTML = games.map(gameCard).join("");
  }

  // 게임 카드(라이브러리와 결재함의 플레이테스트가 같이 쓴다). 누르면 게임 상세로 간다.
  function gameCard(g) {
    var thumb = thumbOf(g);
    return '<button class="gcard" type="button" data-game="' + esc(g.slug) + '"><span class="thumb">' +
      (thumb ? '<img loading="lazy" alt="" src="' + esc(thumb) + '">' : '<span class="ph">' + (WIP_STAGES.indexOf(g.stage) >= 0 ? "제작 중 · 아트 전" : "아트 방향 준비 전") + "</span>") +
      '</span><span class="body"><span class="row"><span class="chips">' + stageChip(g) + "</span>" + (canPlay(g) ? '<span class="playable">▶ 플레이 가능</span>' : "") + "</span>" +
      '<span class="t">' + esc(g.title) + '</span><span class="d">' + esc(g.pitch) + '</span><span class="open">게임 열기 ↗</span></span></button>';
  }

  function renderGameDetail(g) {
    var html = '<button class="back" type="button" data-game="">← 게임 라이브러리</button>';
    html += '<div class="ghead"><h2>' + esc(g.title) + stageChip(g) + "</h2>" + '<div class="p">' + esc(g.pitch) + "</div>" +
      '<div class="chips">' + stepsHtml(g) + (versionText(g) ? '<span class="mono">' + esc(versionText(g)) + "</span>" : "") + "</div></div>";

    // 플레이
    var play = canPlay(g);
    html += '<div class="playbar"><div><div class="label">게임 플레이</div><div class="p">' +
      (play ? (g.milestone > 1 && WIP_STAGES.indexOf(g.stage) >= 0 ? "지금 플레이되는 것은 직전 차수 빌드예요. " + g.milestone + "차를 만드는 중이에요." : "웹에서 바로 플레이할 수 있어요.")
        : hasBuild(g) ? (g.milestone > 1 && WIP_STAGES.indexOf(g.stage) >= 0 ? g.milestone + "차 검사를 먼저 올려 둔 상태라 Web 빌드가 잠시 내려가 있어요. 개발실 빌드가 올라오면 다시 열려요." : "Web 빌드를 준비 중이에요.")
        : "아직 빌드 전이에요. 검수를 통과하면 플레이할 수 있어요.") +
      '</div></div><div class="acts">' + (play ? '<button class="btn go" type="button" data-play="' + g.id + '">▶ 웹에서 플레이</button>' : "") + docButton(g) + "</div></div>";

    // 대표 판정 (플레이 대기일 때)
    if (g.stage === "playtest") {
      html += '<div class="acts"><button class="btn" type="button" data-pt="keep" data-id="' + g.id + '"' + dis() + ">합격</button>" +
        '<button class="btn warn" type="button" data-pt="fix" data-id="' + g.id + '"' + dis() + ">고쳐서 다시</button>" +
        '<button class="btn bad" type="button" data-pt="drop" data-id="' + g.id + '"' + dis() + ">버리기</button>" +
        '<button class="btn ghost" type="button" data-finish="' + g.id + '"' + dis() + ">여기까지</button></div>";
    }
    if (g.stage === "kept") {
      html += '<div class="playbar"><div><div class="label">다음 차수</div><div class="p">프로덕션 디자인실이 ' + ((g.milestone || 1) + 1) + '차를 설계할 차례예요. 더 키우지 않으려면 여기까지로 끝낼 수 있어요.</div></div>' +
        '<div class="acts"><button class="btn ghost" type="button" data-finish="' + g.id + '"' + dis() + ">여기까지</button></div></div>";
    }
    if (g.keep_notes) html += '<div class="sec"><div class="label">대표 메모</div><div class="summary">' + esc(g.keep_notes) + "</div></div>";
    var ds = state.decisions.filter(function (d) { return d.game_id === g.id; });
    if (ds.length) {
      html += '<div class="sec"><div class="sec-head"><h2>대표 결정</h2><span>' + (ds.some(function (d) { return !d.chosen; }) ? "결정 전에는 부서 추천안으로 진행해요" : "결정한 뒤에도 바꿀 수 있어요") + "</span></div>" +
        '<div class="list">' + ds.map(function (d) { return decisionHtml(d, false); }).join("") + "</div></div>";
    }
    if (g.fix_notes) html += '<div class="note">' + esc(g.fix_notes) + "</div>";

    // 아트 방향
    html += '<div class="sec"><div class="sec-head"><h2>아트 방향</h2><span>' +
      (g.art ? (g.art_pick ? g.art_pick + "안을 골랐어요. 다시 고를 수 있어요" : "마음에 드는 방향을 골라 주세요") : "") + "</span></div>";
    if (g.art && g.art.directions) {
      html += '<div class="arts">' + g.art.directions.map(function (d) {
        var picked = g.art_pick === d.id;
        return '<div class="art' + (picked ? " picked" : "") + '"><button class="pic" type="button" data-img="' + esc(gameUrl(g, d.image)) + '" data-title="' + esc(d.id + " · " + d.name) +
          '"><img loading="lazy" alt="' + esc(d.id + "안: " + d.name) + '" src="' + esc(gameUrl(g, d.image)) + '"></button><div class="cap"><div class="nm"><b>' + esc(d.id) + "</b>" + esc(d.name) +
          '</div><div class="ds">' + esc(d.description) + '</div><div class="acts"><button class="btn small' + (picked ? " go" : "") + '" type="button" data-pick="' + d.id + '" data-id="' + g.id + '"' + dis() + ">" +
          (picked ? "✓ 고른 방향" : "이 방향으로") + "</button></div></div></div>";
      }).join("") + "</div>";
      if (g.art.key_screen) {
        html += '<div class="keyshot"><img loading="lazy" alt="핵심 화면" src="' + esc(gameUrl(g, g.art.key_screen)) + '" data-img="' + esc(gameUrl(g, g.art.key_screen)) +
          '" data-title="핵심 화면(실제 빌드)"><div><div class="label">핵심 화면 · 실제 빌드</div><div class="p">' + esc(g.art.key_reason || "") + "</div></div></div>";
      }
    } else {
      html += '<div class="empty">' + (hasBuild(g) ? "아트실이 아직 작업하지 않았어요." : "빌드가 검수를 통과하면 아트실이 방향 3가지를 만들어요.") + "</div>";
    }
    html += "</div>";

    // 설계 요약
    if (g.design_summary) {
      html += '<div class="sec"><div class="sec-head"><h2>설계 요약</h2><span></span></div><div class="summary">' + esc(g.design_summary) + "</div></div>";
    }
    $("gameDetail").innerHTML = html;
  }

  function openGame(slug) {
    ui.game = slug || null;
    renderGames();
    var hash = "#games" + (ui.game ? "/" + ui.game : "");
    if (location.hash !== hash) history.pushState(null, "", hash);
    window.scrollTo(0, 0);
  }

  // ---------------------------------------------------------------- 아이디어

  var SCORE_LABEL = { hook: "훅", core_loop: "반복", depth: "깊이", growth: "성장", mobile_fit: "모바일", visual: "화면", prototype: "시제품", asset: "에셋" };
  // 디자인실이 가져갈 순서: ★ → 들어온 순
  function designerOrder(a, b) {
    if (a.starred !== b.starred) return a.starred ? -1 : 1;
    return new Date(a.created_at) - new Date(b.created_at);
  }

  function renderIdeas() {
    var all = byStage("idea").sort(designerOrder);
    var starCount = all.filter(function (g) { return g.starred; }).length;
    $("ideaCount").textContent = "디자인실이 ★ 먼저, 그다음 들어온 순서로 가져가요";
    $("ideaAll").innerHTML = '전체 <b class="num">' + all.length + "</b>";
    $("ideaAll").setAttribute("aria-pressed", !ui.onlyStar);
    $("ideaStar").innerHTML = '★ 우선 <b class="num">' + starCount + "</b>";
    $("ideaStar").setAttribute("aria-pressed", ui.onlyStar);
    var turn = {};  // 디자인실 차례. 검색·필터와 상관없이 전체 줄에서의 순번
    all.forEach(function (g, i) { turn[g.id] = i + 1; });
    var items = all;
    if (ui.onlyStar) items = items.filter(function (g) { return g.starred; });
    if (ui.query) {
      var q = ui.query.toLowerCase();
      items = items.filter(function (g) { return (g.title + " " + g.pitch + " " + g.core_verb + " " + (g.genre || "") + " " + g.slug).toLowerCase().indexOf(q) >= 0; });
    }
    var visible = items.slice(0, ui.shown);
    $("more").hidden = items.length <= ui.shown;
    $("more").textContent = "더 보기 (" + (items.length - ui.shown) + "개 남음)";
    ui.ideaIds = items.map(function (g) { return g.id; });
    $("ideas").innerHTML = visible.length ? visible.map(function (g) {
      return '<div class="icard' + (g.starred ? " on" : "") + '"><button class="ic-main" type="button" data-idea="' + g.id + '"><span class="t">' + esc(g.title) +
        '</span><span class="d">' + esc(g.pitch) + '</span><span class="tags"><span class="chip">' + esc(g.core_verb) + "</span>" +
        (turn[g.id] === 1 ? '<span class="chip next">다음 디자인</span>' : "") + '</span></button><button class="star" type="button" data-star="' + g.id +
        '" aria-pressed="' + !!g.starred + '" aria-label="먼저 디자인하기"' + dis() + ">" + (g.starred ? "★" : "☆") + "</button></div>";
    }).join("") : '<div class="empty">' + (ui.query ? "검색 결과가 없어요." : ui.onlyStar ? "★ 표시한 아이디어가 없어요." : "대기 중인 아이디어가 없어요.") + "</div>";
    renderIdeaDlg(items, turn);
  }

  // 카드를 누르면 뜨는 상세 창. ‹ › 로 옆 아이디어로 넘긴다
  function renderIdeaDlg(items, turn) {
    var dlg = $("ideaDlg");
    if (!ui.idea) { if (dlg.open) dlg.close(); return; }
    var i = ui.ideaIds.indexOf(ui.idea);
    if (i < 0) {  // 버렸거나 필터에서 빠졌다 → 그 자리의 다음 아이디어로
      if (!items.length) { ui.idea = null; if (dlg.open) dlg.close(); return; }
      i = Math.min(ui.ideaIdx || 0, items.length - 1);
      ui.idea = items[i].id;
    }
    ui.ideaIdx = i;
    var g = items[i];
    function fact(label, html) { return html ? "<div><dt>" + label + "</dt><dd>" + html + "</dd></div>" : ""; }
    function nav(to, label, text) { return '<button class="btn ghost small" type="button" aria-label="' + label + '"' + (to ? ' data-idea="' + to.id + '"' : " disabled") + ">" + text + "</button>"; }
    // depth는 연구소 v3부터 들어온다. 없는 축은 그리지 않는다
    var bars = g.idea_scores ? '<div class="bars">' + Object.keys(SCORE_LABEL).filter(function (k) { return g.idea_scores[k] != null; }).map(function (k) {
      var v = Number(g.idea_scores[k]) || 0;
      return "<div" + (v < 70 ? ' class="low"' : "") + "><span>" + SCORE_LABEL[k] + '</span><i><b style="width:' + Math.max(0, Math.min(100, v)) + '%"></b></i><span class="n num">' + v + "</span></div>";
    }).join("") + "</div>" : "";
    var why = g.why_promoted && g.why_promoted.length ? "<ul>" + g.why_promoted.map(function (w) { return "<li>" + esc(w) + "</li>"; }).join("") + "</ul>" : "";
    // 아이디어 요약은 연구소가 입고 뒤에 붙인다. 예전 아이디어에는 없다
    var b = g.idea_brief || {};
    var play = b.play && b.play.length ? "<ol>" + b.play.map(function (s) { return "<li>" + esc(s) + "</li>"; }).join("") + "</ol>" : "";
    $("ideaBody").innerHTML =
      '<div class="iv-top"><span class="iv-turn">' + (turn[g.id] === 1 ? "다음 디자인 차례" : turn[g.id] + "번째 차례") + (g.genre ? " · " + esc(g.genre) : "") +
      '</span><span class="iv-nav">' + nav(items[i - 1], "이전 아이디어", "‹") + '<span class="num">' + (i + 1) + " / " + items.length + "</span>" + nav(items[i + 1], "다음 아이디어", "›") +
      '<button class="btn ghost small" type="button" data-close>닫기</button></span></div>' +
      "<h3>" + esc(g.title) + '</h3><p class="iv-pitch">' + esc(g.pitch) + '</p><dl class="iv-facts">' +
      fact("조작", esc(g.core_verb)) + fact("한 판의 흐름", play) + fact("재미", esc(g.fun_hypothesis)) +
      fact("한 판 안에서", esc(b.in_run)) + fact("판과 판 사이", esc(b.between_runs)) + fact("맞물리는 것", esc(b.systems)) + fact("열 번째 판", esc(b.tenth_run)) +
      fact("먼저 검증할 것", esc(g.next_test)) + fact("승격 이유", why) + fact("연구소 평가", bars) +
      '</dl><div class="acts"><button class="btn small istar" type="button" data-star="' + g.id + '" aria-pressed="' + !!g.starred + '"' + dis() +
      '>★ 먼저 디자인</button><button class="btn bad small" type="button" data-tri="drop" data-id="' + g.id + '"' + dis() + ">버리기</button></div>";
    if (!dlg.open) dlg.showModal();
  }

  // ---------------------------------------------------------------- 공장

  function deptInfo(role) {
    var run = state.runs.find(function (r) { return r.role === role.id; });
    if (!run) return { dot: "", short: "기록 없음", when: "아직 출근 기록 없음", summary: "" };
    var stale = run.status === "running" && Date.now() - new Date(run.started_at) > 90 * 60000;
    var label = stale ? "멈춤 의심" : (RUN_LABEL[run.status] || run.status);
    return { dot: stale ? "failed" : run.status, short: label, when: ago(run.finished_at || run.started_at) + " · " + label, summary: run.summary || "" };
  }

  function renderFactory() {
    $("depts").innerHTML = ROLES.map(function (role) {
      var info = deptInfo(role);
      return '<div class="dept"><div class="name"><span class="dot ' + info.dot + '"></span>' + esc(role.name) + '</div><div class="when">' + esc(info.when) +
        '</div><div class="sum" title="' + esc(info.summary) + '">' + esc(info.summary) + "</div></div>";
    }).join("");

    $("line").innerHTML = STATIONS.map(function (st) {
      var list = byStage(st.stage).sort(queueOrder);
      var cap = state.limits[st.stage];
      var full = cap && list.length >= cap;
      var names = list.slice(0, 4).map(function (g) { return g.title + (g.milestone > 1 ? "(" + g.milestone + "차)" : ""); }).join(", ") + (list.length > 4 ? " 외 " + (list.length - 4) : "");
      if (cap) names = (names ? names + " · " : "") + "상한 " + cap + (full ? "(꽉 참)" : "");
      return '<div class="lrow' + (list.length ? "" : " zero") + (full ? " full" : "") + (st.goal ? " goal" : "") + '"><span class="who">' + esc(st.who || "완료") +
        '</span><span>' + esc(st.nm) + '</span><span class="ct num">' + list.length + '</span><span class="names" title="' + esc(names) + '">' + esc(names) + "</span></div>";
    }).join("");
    $("lineSide").textContent = "판단 필요 " + count(["held"]) + " · 버림 " + count(["dropped"]) + " · 전체 " + state.games.length;

    $("evCount").textContent = state.events.length;
    $("events").innerHTML = state.events.length ? state.events.map(function (e) {
      return '<div class="ev"><span class="tm num">' + stamp(e.created_at) + "</span><span>" + esc(e.message) + "</span></div>";
    }).join("") : '<div class="p">아직 사건이 없어요.</div>';
  }

  // ---------------------------------------------------------------- 문서 뷰어

  function rawUrl(g, file) {
    return "https://raw.githubusercontent.com/" + CFG.repo + "/main/games/" + encodeURIComponent(g.slug) + "/" + file;
  }

  async function showDoc(tab) {
    var g = docState.game;
    docState.tab = tab;
    var docs = docsOf(g);
    var doc = docs.find(function (d) { return d.id === tab; }) || docs[0];
    tab = docState.tab = doc.id;
    $("docTabs").innerHTML = docs.map(function (d) {
      return '<button type="button" data-doctab="' + d.id + '" aria-selected="' + (d.id === tab) + '">' + esc(d.label) + "</button>";
    }).join("");
    $("docGithub").href = "https://github.com/" + CFG.repo + "/" + (doc.dir ? "tree" : "blob") + "/main/games/" + encodeURIComponent(g.slug) + "/" + (doc.dir || doc.file);
    $("docBody").innerHTML = '<div class="empty">불러오는 중…</div>';
    if (doc.dir) { showShots(g, doc, tab); return; }
    try {
      var r = await fetch(rawUrl(g, doc.file), { cache: "no-store" });
      if (docState.game !== g || docState.tab !== tab) return;
      if (r.status === 404) { $("docBody").innerHTML = '<div class="empty">아직 이 문서가 없어요. 해당 부서가 작업을 마치면 생겨요.</div>'; return; }
      if (!r.ok) throw new Error("HTTP " + r.status);
      var md = await r.text();
      var html = window.marked ? window.marked.parse(md, { gfm: true, breaks: false }) : "<pre>" + esc(md) + "</pre>";
      $("docBody").innerHTML = window.DOMPurify ? window.DOMPurify.sanitize(html) : "<pre>" + esc(md) + "</pre>";
      $("docBody").scrollTop = 0;
    } catch (e) {
      $("docBody").innerHTML = '<div class="empty">문서를 불러오지 못했어요: ' + esc(e.message || e) + "</div>";
    }
  }

  async function showShots(g, doc, tab) {
    try {
      var r = await fetch("https://api.github.com/repos/" + CFG.repo + "/contents/games/" + encodeURIComponent(g.slug) + "/" + doc.dir + "?ref=main");
      if (docState.game !== g || docState.tab !== tab) return;
      if (r.status === 404) { $("docBody").innerHTML = '<div class="empty">아직 스크린샷이 없어요. 빌드실이 빌드하면서 찍어요.</div>'; return; }
      if (!r.ok) throw new Error("HTTP " + r.status);
      var files = (await r.json()).filter(function (f) { return /\.png$/i.test(f.name); });
      if (!files.length) { $("docBody").innerHTML = '<div class="empty">아직 스크린샷이 없어요.</div>'; return; }
      $("docBody").innerHTML = '<div class="shots">' + files.map(function (f) {
        return '<figure><img loading="lazy" alt="' + esc(f.name) + '" src="' + esc(rawUrl(g, doc.dir + "/" + f.name)) + '"><figcaption>' + esc(f.name.replace(/\.png$/i, "")) + "</figcaption></figure>";
      }).join("") + "</div>";
    } catch (e) {
      $("docBody").innerHTML = '<div class="empty">스크린샷을 불러오지 못했어요: ' + esc(e.message || e) + "</div>";
    }
  }

  function openDoc(g) {
    docState.game = g;
    $("docTitle").textContent = g.title;
    $("docDlg").showModal();
    showDoc(g.milestone > 1 ? "prod" + g.milestone : "design");
  }

  // ---------------------------------------------------------------- 대화상자

  function askNote(title, hint, required) {
    return new Promise(function (resolve) {
      var dlg = $("noteDlg");
      $("noteTitle").textContent = title;
      $("noteHint").textContent = hint;
      $("noteText").value = "";
      $("noteText").required = !!required;
      dlg.onclose = function () { resolve(dlg.returnValue === "ok" ? $("noteText").value.trim() : null); };
      dlg.returnValue = "";
      dlg.showModal();
    });
  }

  function openPlayer(g) {
    $("playTitle").textContent = g.title;
    var ok = playable(g.slug);
    var landscape = g.spec && g.spec.orientation === "landscape";
    $("playBody").innerHTML = ok
      ? '<iframe class="' + (landscape ? "landscape" : "") + '" src="play/' + encodeURIComponent(g.slug) + '/index.html" title="' + esc(g.title) + '" allow="autoplay; fullscreen"></iframe>'
      : '<div class="noplay">' + (ok === false ? "최신 커밋에서 자동 검사를 통과하지 못해 Web 빌드가 없어요." : "아직 Web 빌드가 배포되지 않았어요. CI가 끝나면 플레이할 수 있어요.") + "</div>";
    $("playDlg").onclose = function () { $("playBody").innerHTML = ""; };
    $("playDlg").showModal();
  }

  // ---------------------------------------------------------------- 이벤트

  function openImage(src, title) {
    $("imgTitle").textContent = title || "";
    $("imgBig").src = src;
    $("imgDlg").showModal();
  }

  document.addEventListener("click", async function (e) {
    var el = e.target.closest("button, img[data-img]");
    if (!el || el.disabled) return;
    var d = el.dataset;
    var g = d.id ? state.games.find(function (x) { return x.id === d.id; }) : null;

    if ("close" in d) { el.closest("dialog").close("cancel"); return; }
    if (d.filter) { ui.filter = d.filter; ui.game = null; renderGames(); if (!d.go) return; }
    if (d.go) { setView(d.go); return; }
    if ("game" in d) { if (ui.view !== "games") setView("games"); openGame(d.game); return; }
    if (d.img) { openImage(d.img, d.title); return; }
    if (d.pick && g) {
      var same = g.art_pick === d.pick;
      await act("ceo_pick_art", { p_game: g.id, p_pick: same ? null : d.pick }, g.title + " · " + (same ? "아트 방향 선택 취소" : "아트 방향 " + d.pick + " 선택"));
      return;
    }
    if (d.decideAll) {
      var todo = pendingDecisions();
      if (!state.ceo) { toast("대표 로그인이 필요합니다", true); return; }
      if (!confirm("결정 요청 " + todo.length + "건을 전부 부서 추천대로 정할까요?")) return;
      for (var i = 0; i < todo.length; i++) {
        if (LIVE) {
          var rr = await sb.rpc("ceo_decide", { p_decision: todo[i].id, p_choice: todo[i].recommended, p_note: null });
          if (rr.error) { toast(rr.error.message, true); break; }
        } else todo[i].chosen = todo[i].recommended;
      }
      toast(todo.length + "건을 추천대로 정했어요");
      if (LIVE) await load(); else render();
      return;
    }
    if (d.decide) {
      e.preventDefault();  // 접힌 줄 안의 "추천대로"를 눌러도 줄이 펼쳐지지 않게
      var dec = state.decisions.find(function (x) { return x.id === d.decide; });
      if (!dec) return;
      var opt = (dec.options || []).find(function (o) { return o.id === d.choice; });
      await act("ceo_decide", { p_decision: dec.id, p_choice: d.choice, p_note: null }, "결정: " + (opt ? opt.label : d.choice));
      return;
    }
    if (d.finish) {
      var fg = gameOf(d.finish);
      var fnote = await askNote(fg.title + " · 여기까지", "더 키우지 않고 끝내요. 이유를 남겨도 돼요(선택).", false);
      if (fnote === null) return;
      await act("ceo_finish", { p_game: fg.id, p_note: fnote || null }, fg.title + " · 완료");
      return;
    }
    if (d.doc) { openDoc(state.games.find(function (x) { return x.id === d.doc; })); return; }
    if (d.doctab) { showDoc(d.doctab); return; }
    if (d.play) { openPlayer(state.games.find(function (x) { return x.id === d.play; })); return; }
    if ("idea" in d) { ui.idea = d.idea || null; renderIdeas(); return; }
    if (d.star) {
      var sg = state.games.find(function (x) { return x.id === d.star; });
      await act("ceo_star", { p_game: sg.id, p_starred: !sg.starred }, sg.starred ? "별표 해제" : "우선 처리로 지정");
      return;
    }
    if (d.tri && g) {
      var labels = { go: "다시 진행", hold: "보류", drop: "버림" };
      await act("ceo_triage", { p_game: g.id, p_decision: d.tri, p_note: null }, g.title + " · " + labels[d.tri]);
      return;
    }
    if (d.pt && g) {
      var note = null;
      if (d.pt === "fix") {
        note = await askNote(g.title + " · 고쳐서 다시", "빌드실이 다음 빌드에서 고칠 것을 적어 주세요. 이 메모가 그대로 전달돼요.", true);
        if (!note) return;
      } else if (d.pt === "keep") {
        note = await askNote(g.title + " · 합격", "좋았던 점, 아쉬운 점, 다음에 키울 방향을 적어 주세요. 프로덕션 디자인실이 이 메모를 가장 먼저 읽어요(선택).", false);
        if (note === null) return;
      }
      var msgs = { keep: "합격", fix: "수정 요청 보냄", drop: "버림" };
      await act("ceo_playtest", { p_game: g.id, p_verdict: d.pt, p_notes: note || null }, g.title + " · " + msgs[d.pt]);
      return;
    }
  });

  // 접힌 줄을 펼친 상태는 새로고침(1분마다 자동) 뒤에도 유지한다
  document.addEventListener("toggle", function (e) {
    var key = e.target.dataset && e.target.dataset.fold;
    if (key) ui.open[key] = e.target.open;
  }, true);
  // 아이디어 상세 창: ← → 로 옆 아이디어로 넘긴다
  document.addEventListener("keydown", function (e) {
    if (!$("ideaDlg").open || (e.key !== "ArrowRight" && e.key !== "ArrowLeft") || e.altKey || e.ctrlKey || e.metaKey) return;
    var to = (ui.ideaIds || [])[(ui.ideaIdx || 0) + (e.key === "ArrowRight" ? 1 : -1)];
    if (!to) return;
    e.preventDefault();
    ui.idea = to;
    renderIdeas();
  });
  $("ideaDlg").addEventListener("close", function () { ui.idea = null; });
  $("ideaDlg").addEventListener("click", function (e) { if (e.target === e.currentTarget) e.currentTarget.close(); });
  window.addEventListener("hashchange", function () { setView(location.hash.slice(1)); });

  $("search").addEventListener("input", function (e) { ui.query = e.target.value.trim(); ui.shown = PAGE; renderIdeas(); });
  $("ideaAll").addEventListener("click", function () { ui.onlyStar = false; ui.shown = PAGE; renderIdeas(); });
  $("ideaStar").addEventListener("click", function () { ui.onlyStar = true; ui.shown = PAGE; renderIdeas(); });
  $("more").addEventListener("click", function () { ui.shown += PAGE; renderIdeas(); });
  $("refresh").addEventListener("click", load);
  $("login").addEventListener("click", async function () {
    if (!LIVE) return;
    if (state.email) {
      if (confirm("로그아웃할까요?")) { await sb.auth.signOut(); await refreshAuth(); render(); }
      return;
    }
    $("loginDlg").showModal();
  });
  $("loginDlg").addEventListener("close", async function () {
    if ($("loginDlg").returnValue !== "ok") return;
    var email = $("loginEmail").value.trim();
    if (!email) return;
    var r = await sb.auth.signInWithOtp({ email: email, options: { emailRedirectTo: location.origin + location.pathname, shouldCreateUser: true } });
    toast(r.error ? r.error.message : "로그인 링크를 보냈어요. 메일을 확인해 주세요.", !!r.error);
  });

  if (LIVE) {
    sb.auth.onAuthStateChange(function () { refreshAuth().then(render); });
  }
  setView(location.hash.slice(1) || "home");
  refreshAuth().then(load);
  setInterval(function () { if (!document.hidden) load(); }, 60000);

  // ---------------------------------------------------------------- 예시 데이터 (Supabase 연결 전)

  function demoData() {
    var now = Date.now();
    var t = function (min) { return new Date(now - min * 60000).toISOString(); };
    var G = function (id, slug, title, pitch, verb, fun, stage, extra) {
      return Object.assign({ id: id, slug: slug, title: title, pitch: pitch, core_verb: verb, fun_hypothesis: fun, stage: stage, attempt: 0, starred: false, spec: { orientation: "portrait" }, fix_notes: null, created_at: t(3000), stage_changed_at: t(600) }, extra || {});
    };
    var games = [
      G("g1", "first-lantern", "First Lantern", "꺼지기 전에 등불을 눌러 밝힌다.", "탭", "점점 빨라지는 불빛을 놓치지 않으려는 긴장감", "playtest", { attempt: 1, stage_changed_at: t(40), design_version: 1, spec_version: 1, design_summary: "한 손가락 타이밍 게임.\n핵심 판단: 어느 등불부터 누를까." }),
      G("g2", "night-bus-driver", "밤버스 기사", "졸린 승객을 정류장에 맞춰 깨운다.", "길게 누르기", "타이밍을 재는 손맛", "building", { attempt: 1, lease_until: new Date(now + 30 * 60000).toISOString() }),
      G("g3", "moon-crane", "달 크레인", "흔들리는 달 조각을 쌓아 탑을 만든다.", "드래그", "무너질 듯 말 듯한 아슬아슬함", "ready", { starred: true }),
      G("g4", "paper-boat-post", "종이배 우체국", "물길을 그어 편지 배를 집까지 보낸다.", "선 긋기", "내가 그린 길로 배가 흘러가는 쾌감", "planning"),
      G("g5", "tiny-weather-desk", "작은 기상청", "하늘을 돌려 마을에 맞는 날씨를 보낸다.", "회전", "작은 조작으로 마을 전체가 바뀌는 만족", "held", { attempt: 3, fix_notes: "빌드 3회 실패: 회전 입력이 웹에서 인식되지 않음. 조작을 탭 두 번으로 바꿀지 결정 필요" }),
      G("g6", "echo-thief", "메아리 도둑", "소리가 돌아오기 전에 보물을 훔쳐 나온다.", "탭", "소리를 듣고 타이밍을 맞추는 긴장", "idea", { stage_changed_at: t(200) }),
      G("g7", "ghost-train-coupler", "유령 기차 연결", "흔들리는 객차를 정확히 맞물려 연결한다.", "드래그", "딱 맞물릴 때의 손맛", "idea", { stage_changed_at: t(180) }),
      G("g8", "rooftop-laundry", "옥상 빨래 조련사", "바람이 불기 전에 빨래를 집게로 고정한다.", "탭", "바람 패턴을 읽는 재미", "idea", { stage_changed_at: t(150) }),
      G("g9", "pocket-canal", "주머니 운하", "수문을 열고 닫아 배를 통과시킨다.", "탭", "물 높이를 맞추는 퍼즐", "kept", { attempt: 2, stage_changed_at: t(4000) })
    ];
    return {
      games: games,
      limits: { building: 1 },
      builds: [
        { game_id: "g1", attempt: 1, commit_sha: "a1b2c3d4e5", smoke_passed: true, created_at: t(70) },
        { game_id: "g9", attempt: 2, commit_sha: "9f8e7d6c5b", smoke_passed: true, created_at: t(4100) }
      ],
      runs: [
        { role: "qa", status: "success", started_at: t(42), finished_at: t(40), summary: "First Lantern 검수 pass" },
        { role: "builder", status: "running", started_at: t(12), finished_at: null, summary: null },
        { role: "planner", status: "noop", started_at: t(55), finished_at: t(54), summary: "기획할 아이디어 없음" },
        { role: "idea_lab", status: "success", started_at: t(300), finished_at: t(296), summary: "아이디어 5개 등록" }
      ],
      events: [
        { created_at: t(40), message: "First Lantern: qa → playtest" },
        { created_at: t(70), message: "First Lantern 빌드 1회차 · a1b2c3d" },
        { created_at: t(12), message: "밤버스 기사: ready → building" },
        { created_at: t(300), message: "새 아이디어: 메아리 도둑" }
      ].sort(function (a, b) { return new Date(b.created_at) - new Date(a.created_at); })
    };
  }

  function demoAct(fn, a) {
    if (fn === "ceo_decide") { var dd = state.decisions.find(function (x) { return x.id === a.p_decision; }); if (dd) dd.chosen = a.p_choice; return; }
    var g = state.games.find(function (x) { return x.id === a.p_game; });
    if (!g) return;
    if (fn === "ceo_finish") g.stage = "done";
    if (fn === "ceo_star") g.starred = a.p_starred;
    if (fn === "ceo_pick_art") { g.art_pick = a.p_pick; return; }
    if (fn === "ceo_triage") { if (a.p_decision === "go" && g.stage === "idea") g.starred = true; else g.stage = a.p_decision === "go" ? "ready" : a.p_decision === "hold" ? "held" : "dropped"; }
    if (fn === "ceo_playtest") g.stage = a.p_verdict === "keep" ? "kept" : a.p_verdict === "fix" ? "ready" : "dropped";
    g.stage_changed_at = new Date().toISOString();
    state.events.unshift({ created_at: g.stage_changed_at, message: g.title + ": " + fn + " (예시)" });
  }
})();
