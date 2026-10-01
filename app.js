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
    { id: "qa", name: "검수실" }
  ];
  var STATIONS = [
    { stage: "idea", who: "디자인실", nm: "디자인 대기" },
    { stage: "designing", who: "디자인실", nm: "디자인 중" },
    { stage: "designed", who: "기획실", nm: "기획 대기" },
    { stage: "planning", who: "기획실", nm: "기획 중" },
    { stage: "ready", who: "빌드실", nm: "빌드 대기" },
    { stage: "building", who: "빌드실", nm: "빌드 중" },
    { stage: "qa", who: "검수실", nm: "검수 대기" },
    { stage: "playtest", who: "대표", nm: "플레이 대기" },
    { stage: "kept", who: "", nm: "합격작", goal: true }
  ];
  var RUN_LABEL = { success: "진행", noop: "할 일 없음", running: "작업 중", blocked: "대표 판단 요청", failed: "운영 장애" };
  var PAGE = 20;

  var state = { games: [], runs: [], events: [], builds: [], limits: {}, play: null, ceo: false, email: null };
  var ui = { tab: null, query: "", shown: PAGE, sort: "queue" };

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
          sb.from("games").select("id,slug,title,pitch,core_verb,fun_hypothesis,genre,idea_scores,why_promoted,next_test,design_summary,sim_status,design_version,spec_version,stage,attempt,starred,spec,fix_notes,lease_owner,lease_until,created_at,stage_changed_at").order("stage_changed_at", { ascending: false }).limit(2000),
          sb.from("runs").select("*").order("started_at", { ascending: false }).limit(200),
          sb.from("events").select("*").order("id", { ascending: false }).limit(30),
          sb.from("builds").select("game_id,attempt,commit_sha,smoke_passed,created_at").order("created_at", { ascending: false }).limit(500),
          sb.from("wip_limits").select("*")
        ]);
        r.forEach(function (x) { if (x.error) throw x.error; });
        state.games = r[0].data; state.runs = r[1].data; state.events = r[2].data; state.builds = r[3].data;
        state.limits = {};
        r[4].data.forEach(function (l) { state.limits[l.stage] = l.max_items; });
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

  function render() {
    $("demoTag").hidden = LIVE;
    $("login").textContent = !LIVE ? "예시 모드" : state.email ? (state.ceo ? "대표 · " : "") + state.email : "대표 로그인";
    $("login").disabled = !LIVE;
    $("docLink").href = "https://github.com/" + (CFG.repo || "") + "/blob/main/docs/OPERATING_MODEL.md";
    renderDepts();
    renderInbox();
    renderWip();
    renderIdeas();
    renderShelf();
    renderLine();
    renderEvents();
  }

  function renderDepts() {
    $("depts").innerHTML = ROLES.map(function (role) {
      var run = state.runs.find(function (r) { return r.role === role.id; });
      var status = run ? run.status : "";
      var stale = run && run.status === "running" && Date.now() - new Date(run.started_at) > 90 * 60000;
      var label = !run ? "아직 출근 기록 없음" : stale ? "작업 중 멈춤 의심" : (RUN_LABEL[status] || status);
      return '<div class="dept"><div class="name"><span class="dot ' + (stale ? "failed" : esc(status)) + '"></span>' + esc(role.name) +
        '</div><div class="when">' + (run ? ago(run.finished_at || run.started_at) + " · " : "") + esc(label) +
        '</div><div class="sum" title="' + esc(run && run.summary) + '">' + esc((run && run.summary) || " ") + "</div></div>";
    }).join("");
  }

  function inboxTabs() {
    return [
      { id: "playtest", label: "플레이테스트", items: byStage("playtest").sort(queueOrder) },
      { id: "held", label: "판단 필요", items: byStage("held").sort(queueOrder) }
    ];
  }

  function renderInbox() {
    var tabs = inboxTabs();
    if (!ui.tab) {
      var first = tabs.find(function (t) { return t.items.length; });
      ui.tab = first ? first.id : "playtest";
    }
    $("tabs").innerHTML = tabs.map(function (t) {
      return '<button class="tab" role="tab" type="button" data-tab="' + t.id + '" aria-selected="' + (t.id === ui.tab) + '">' +
        esc(t.label) + '<b class="num' + (t.items.length ? "" : " zero") + '">' + t.items.length + "</b></button>";
    }).join("");

    var items = tabs.find(function (t) { return t.id === ui.tab; }).items;
    var dis = state.ceo ? "" : " disabled title=\"대표 로그인 필요\"";
    var empty = { playtest: "플레이할 게임이 아직 없어요. 검수를 통과하면 여기에 와요.", held: "판단할 건이 없어요." };
    if (!items.length) { $("inbox").innerHTML = '<div class="empty">' + empty[ui.tab] + "</div>"; return; }

    $("inbox").innerHTML = items.map(function (g) {
      var head = '<span class="bullet" aria-hidden="true"' + (ui.tab === "held" ? ' style="background:var(--red)"' : "") + "></span>";
      var meta = '<span class="chip verb">' + esc(g.core_verb) + "</span>";
      if (g.genre) meta += '<span class="chip">' + esc(g.genre) + "</span>";
      if (g.attempt) meta += '<span class="chip att">빌드 ' + g.attempt + "회차</span>";
      var b = latestBuild(g.id);
      if (b) meta += '<span class="chip mono">' + esc(b.commit_sha.slice(0, 7)) + "</span>";
      var body = '<div class="p">' + esc(g.pitch) + "</div>";
      if (g.design_summary) body += '<div class="summary">' + esc(g.design_summary) + "</div>";
      if (ui.tab === "held" && g.fix_notes) body += '<div class="note">' + esc(g.fix_notes) + "</div>";
      var acts = ui.tab === "playtest"
        ? '<button class="btn" type="button" data-play="' + g.id + '">▶ 플레이</button>' + docLink(g) +
          '<button class="btn go" type="button" data-pt="keep" data-id="' + g.id + '"' + dis + ">합격</button>" +
          '<button class="btn warn" type="button" data-pt="fix" data-id="' + g.id + '"' + dis + ">고쳐서 다시</button>" +
          '<button class="btn bad" type="button" data-pt="drop" data-id="' + g.id + '"' + dis + ">버리기</button>"
        : docLink(g) + '<button class="btn go" type="button" data-tri="go" data-id="' + g.id + '"' + dis + ">다시 진행</button>" +
          '<button class="btn bad" type="button" data-tri="drop" data-id="' + g.id + '"' + dis + ">버리기</button>";
      return '<div class="item' + (ui.tab === "playtest" ? " attn" : "") + '">' + head + '<div><div class="t">' + esc(g.title) +
        "</div>" + body + '<div class="meta">' + meta + '</div><div class="acts">' + acts + "</div></div></div>";
    }).join("");
  }

  function docLink(g) {
    if (!g.design_version) return "";
    return '<button class="btn ghost" type="button" data-doc="' + g.id + '">문서 보기</button>';
  }

  // ---------------------------------------------------------------- 제작 중인 게임 + 문서 뷰어

  var STAGE_LABEL = {
    designing: ["디자인 중", ""], designed: ["디자인 완료 · 기획 대기", "wait"], planning: ["기획 중", ""],
    ready: ["기획 완료 · 빌드 대기", "wait"], building: ["빌드 중", ""], qa: ["검수 대기", "wait"],
    playtest: ["플레이 대기", "warn"], kept: ["합격작", "done"], held: ["판단 필요", "warn"]
  };
  var DOCS = [
    { id: "design", label: "디자인", file: "design/GAME_DESIGN.md" },
    { id: "sim", label: "시뮬레이션 결과", file: "design/sim/RESULTS.md" },
    { id: "roadmap", label: "로드맵", file: "design/ROADMAP.md" },
    { id: "first", label: "첫 빌드 기획", file: "design/FIRST_BUILD.md" },
    { id: "screens", label: "화면", file: "design/SCREENS.md" },
    { id: "build", label: "빌드 기록", file: "BUILD.md" },
    { id: "shots", label: "스크린샷", dir: "shots" }
  ];
  var docState = { game: null, tab: "design" };

  function renderWip() {
    var order = ["playtest", "held", "qa", "building", "ready", "planning", "designed", "designing", "kept"];
    var games = state.games.filter(function (g) { return order.indexOf(g.stage) >= 0 && (g.design_version || g.stage === "designing"); })
      .sort(function (a, b) { return order.indexOf(a.stage) - order.indexOf(b.stage) || new Date(b.stage_changed_at) - new Date(a.stage_changed_at); });
    if (!games.length) { $("wip").innerHTML = '<div class="empty">아직 디자인이 시작된 게임이 없어요.</div>'; return; }
    $("wip").innerHTML = games.map(function (g) {
      var st = STAGE_LABEL[g.stage] || [g.stage, "wait"];
      var ver = (g.design_version ? "디자인 v" + g.design_version : "") + (g.spec_version ? " · 기획 v" + g.spec_version : "") +
        (g.sim_status === "passed" ? " · 시뮬레이션 검증" : g.sim_status === "skipped" ? " · 시뮬레이션 생략" : "");
      return '<div class="wip-row"><div><div class="t">' + esc(g.title) + '<span class="stage-chip ' + st[1] + '">' + esc(st[0]) + "</span>" +
        (ver ? '<span class="mono">' + esc(ver) + "</span>" : "") + "</div>" +
        (g.design_summary ? '<div class="summary">' + esc(g.design_summary) + "</div>" : '<div class="p">' + esc(g.pitch) + "</div>") +
        (g.fix_notes ? '<div class="note">' + esc(g.fix_notes) + "</div>" : "") + "</div>" +
        '<div class="acts" style="margin:0">' + (g.design_version ? '<button class="btn" type="button" data-doc="' + g.id + '">문서 보기</button>' : "") +
        (g.stage === "playtest" || g.stage === "kept" ? '<button class="btn go" type="button" data-play="' + g.id + '">▶ 플레이</button>' : "") + "</div></div>";
    }).join("");
  }

  function rawUrl(g, file) {
    return "https://raw.githubusercontent.com/" + CFG.repo + "/main/games/" + encodeURIComponent(g.slug) + "/" + file;
  }

  async function showDoc(tab) {
    var g = docState.game;
    docState.tab = tab;
    var doc = DOCS.find(function (d) { return d.id === tab; });
    $("docTabs").innerHTML = DOCS.map(function (d) {
      return '<button class="tab" type="button" data-doctab="' + d.id + '" aria-selected="' + (d.id === tab) + '">' + esc(d.label) + "</button>";
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
    showDoc("design");
  }

  // 아이디어 대기: 디자인실이 가져갈 순서(★ → 들어온 순)대로 보여 준다. 대표는 ★로 우선순위만 바꾼다.
  function plannerOrder(a, b) {
    if (a.starred !== b.starred) return a.starred ? -1 : 1;
    return new Date(a.created_at) - new Date(b.created_at);
  }

  function renderIdeas() {
    var all = byStage("idea").sort(plannerOrder);
    $("ideaCount").textContent = all.length + "개 · 디자인실이 위에서부터 가져가요";
    var items = all;
    if (ui.query) {
      var q = ui.query.toLowerCase();
      items = items.filter(function (g) { return (g.title + " " + g.pitch + " " + g.core_verb + " " + (g.genre || "") + " " + g.slug).toLowerCase().indexOf(q) >= 0; });
    }
    if (ui.sort === "score") {
      items = items.slice().sort(function (a, b) {
        if (a.starred !== b.starred) return a.starred ? -1 : 1;
        return (scoreAvg(b) || 0) - (scoreAvg(a) || 0);
      });
    }
    $("sortBtn").textContent = ui.sort === "score" ? "점수순 ✓" : "점수순";
    var visible = items.slice(0, ui.shown);
    $("more").hidden = items.length <= ui.shown;
    $("more").textContent = "더 보기 (" + (items.length - ui.shown) + "개 남음)";
    if (!visible.length) { $("ideas").innerHTML = '<div class="empty">' + (ui.query ? "검색 결과가 없어요." : "대기 중인 아이디어가 없어요.") + "</div>"; return; }

    var dis = state.ceo ? "" : " disabled title=\"대표 로그인 필요\"";
    var next = all[0] && all[0].id;
    $("ideas").innerHTML = visible.map(function (g) {
      var meta = '<span class="chip verb">' + esc(g.core_verb) + "</span>";
      if (g.genre) meta += '<span class="chip">' + esc(g.genre) + "</span>";
      if (g.id === next) meta += '<span class="chip att">다음 기획</span>';
      return '<div class="item"><button class="star" type="button" data-star="' + g.id + '" aria-pressed="' + !!g.starred +
        '" aria-label="우선 처리"' + dis + '>★</button><div><div class="t">' + esc(g.title) + '</div><div class="p">' + esc(g.pitch) +
        '</div><div class="p" style="color:var(--dim)">' + esc(g.fun_hypothesis) + "</div>" + ideaDetail(g) +
        '<div class="meta">' + meta + '</div><div class="acts"><button class="btn bad" type="button" data-tri="drop" data-id="' + g.id + '"' + dis +
        ">버리기</button></div></div></div>";
    }).join("");
  }

  var SCORE_LABEL = { hook: "훅", core_loop: "반복", mobile_fit: "모바일", prototype: "시제품", asset: "에셋", visual: "화면", growth: "성장" };
  function scoreAvg(g) {
    var s = g.idea_scores;
    if (!s) return null;
    var ks = Object.keys(SCORE_LABEL);
    return Math.round(ks.reduce(function (a, k) { return a + (s[k] || 0); }, 0) / ks.length);
  }
  function ideaDetail(g) {
    var out = "";
    if (g.idea_scores) {
      out += '<div class="scores"><span class="avg num">' + scoreAvg(g) + "</span>" + Object.keys(SCORE_LABEL).map(function (k) {
        var v = g.idea_scores[k];
        return '<span class="sc' + (v < 70 ? " low" : v >= 85 ? " high" : "") + '">' + SCORE_LABEL[k] + ' <b class="num">' + esc(v) + "</b></span>";
      }).join("") + "</div>";
    }
    if (g.why_promoted && g.why_promoted.length) {
      out += '<ul class="why">' + g.why_promoted.map(function (w) { return "<li>" + esc(w) + "</li>"; }).join("") + "</ul>";
    }
    if (g.next_test) out += '<div class="next">먼저 검증할 것 · ' + esc(g.next_test) + "</div>";
    return out;
  }

  function renderShelf() {
    var games = byStage("playtest").concat(byStage("kept"));
    if (!games.length) { $("shelf").innerHTML = '<div class="empty">아직 진열된 게임이 없어요.</div>'; return; }
    $("shelf").innerHTML = games.map(function (g) {
      var b = latestBuild(g.id);
      var kept = g.stage === "kept";
      return '<article class="card"><div class="cover' + (kept ? "" : " playtest") + '">' + esc(g.title) + '</div><div class="info">' +
        '<span class="mono">' + (kept ? "합격작" : "플레이 대기") + (b ? " · " + esc(b.commit_sha.slice(0, 7)) : "") + "</span>" +
        '<button class="btn go" type="button" data-play="' + g.id + '">▶ 플레이</button></div></article>';
    }).join("");
  }

  function renderLine() {
    $("line").innerHTML = STATIONS.map(function (s) {
      var list = byStage(s.stage).sort(queueOrder);
      var cap = state.limits[s.stage];
      var full = cap && list.length >= cap;
      var names = list.slice(0, 3).map(function (g) { return g.title; }).join(", ");
      if (s.stage === "building" && list[0] && list[0].lease_until) {
        var expired = new Date(list[0].lease_until) < Date.now();
        names = list[0].title + (expired ? " · 임대 만료(다음 실행이 이어받음)" : "");
      }
      return '<div class="station' + (full ? " full" : "") + (s.goal ? " goal" : "") + '"><div class="who">' + esc(s.who || "완료") +
        '</div><div class="nm">' + esc(s.nm) + '</div><div class="ct num">' + list.length + '</div><div class="cap">' +
        (cap ? "상한 " + cap + (full ? " · 꽉 참" : "") : "상한 없음") + '</div><div class="names" title="' + esc(names) + '">' + esc(names || " ") + "</div></div>";
    }).join("");
    $("side").innerHTML = "<span>판단 필요 <b>" + byStage("held").length + "</b></span><span>버림 <b>" + byStage("dropped").length +
      "</b></span><span>전체 <b>" + state.games.length + "</b></span>";
  }

  function renderEvents() {
    if (!state.events.length) { $("events").innerHTML = '<div class="empty">아직 사건이 없어요.</div>'; return; }
    $("events").innerHTML = state.events.map(function (e) {
      return '<div class="ev"><span class="tm num">' + stamp(e.created_at) + "</span><span>" + esc(e.message) + "</span></div>";
    }).join("");
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

  document.addEventListener("click", async function (e) {
    var el = e.target.closest("button");
    if (!el || el.disabled) return;
    var d = el.dataset;
    var g = d.id ? state.games.find(function (x) { return x.id === d.id; }) : null;

    if ("close" in d) { el.closest("dialog").close("cancel"); return; }
    if (d.tab) { ui.tab = d.tab; ui.shown = PAGE; renderInbox(); return; }
    if (d.doc) { openDoc(state.games.find(function (x) { return x.id === d.doc; })); return; }
    if (d.doctab) { showDoc(d.doctab); return; }
    if (d.play) { openPlayer(state.games.find(function (x) { return x.id === d.play; })); return; }
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
        note = await askNote(g.title + " · 합격", "좋았던 점이나 다음에 키울 방향을 남겨도 돼요(선택).", false);
        if (note === null) return;
      }
      var msgs = { keep: "합격", fix: "수정 요청 보냄", drop: "버림" };
      await act("ceo_playtest", { p_game: g.id, p_verdict: d.pt, p_notes: note || null }, g.title + " · " + msgs[d.pt]);
      return;
    }
  });

  $("search").addEventListener("input", function (e) { ui.query = e.target.value.trim(); ui.shown = PAGE; renderIdeas(); });
  $("sortBtn").addEventListener("click", function () { ui.sort = ui.sort === "score" ? "queue" : "score"; ui.shown = PAGE; renderIdeas(); });
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
      G("g1", "first-lantern", "First Lantern", "꺼지기 전에 등불을 눌러 밝힌다.", "탭", "점점 빨라지는 불빛을 놓치지 않으려는 긴장감", "playtest", { attempt: 1, stage_changed_at: t(40) }),
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
    var g = state.games.find(function (x) { return x.id === a.p_game; });
    if (!g) return;
    if (fn === "ceo_star") g.starred = a.p_starred;
    if (fn === "ceo_triage") { if (a.p_decision === "go" && g.stage === "idea") g.starred = true; else g.stage = a.p_decision === "go" ? "ready" : a.p_decision === "hold" ? "held" : "dropped"; }
    if (fn === "ceo_playtest") g.stage = a.p_verdict === "keep" ? "kept" : a.p_verdict === "fix" ? "ready" : "dropped";
    g.stage_changed_at = new Date().toISOString();
    state.events.unshift({ created_at: g.stage_changed_at, message: g.title + ": " + fn + " (예시)" });
  }
})();
