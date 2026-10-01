// supabase/migrations/*.sql을 PGlite(메모리 Postgres)에 올려 제작 흐름과 권한을 검사한다.
// 실행: npm test
import { PGlite } from "@electric-sql/pglite";
import fs from "fs";

const db = new PGlite();
const mig = fs.readdirSync(new URL("../supabase/migrations/", import.meta.url)).filter(f => f.endsWith(".sql")).sort()
  .map(f => fs.readFileSync(new URL("../supabase/migrations/" + f, import.meta.url), "utf8")).join("\n");

// Supabase 흉내: 역할과 auth.jwt()
await db.exec(`
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create role authenticator login;
grant anon, authenticated, service_role to authenticator;
create schema auth;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.jwt() to public;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
`);
await db.exec(mig);
await db.exec(`grant select on all tables in schema public to anon, authenticated;
               `); // Supabase 기본 grant 흉내

let pass = 0, fail = 0, e;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log("FAIL:", m); } };
const q = async (sql, p) => (await db.query(sql, p)).rows;
const err = async (sql, p) => { try { await db.query(sql, p); return null; } catch (e) { return e.message; } };
const stage = async id => (await q("select stage, attempt, fix_notes from games where id=$1", [id]))[0];

const spec = {
  one_liner: "등불을 눌러 밝힌다", orientation: "portrait", controls: "탭", win_lose: "3번 놓치면 끝",
  screens: [{ id: "title" }, { id: "play" }, { id: "result" }],
  must_work: [{ id: "M1", text: "타이틀", check: "시작 화면" }, { id: "M2", text: "탭 시작", check: "탭" }, { id: "M3", text: "점수", check: "+1" }],
  not_now: ["사운드"],
};

const [{ add_idea: g1 }] = await q("select add_idea('night-bus','밤버스','설명','탭','재밌다')");
const [{ add_idea: g2 }] = await q("select add_idea('moon-crane','달 크레인','설명','드래그','재밌다')");
for (let i = 0; i < 20; i++) await q(`select add_idea('idea-${i}','아이디어 ${i}','p','v','f')`);
ok((await q("select count(*)::int c from games where stage='idea'"))[0].c === 22, "아이디어 상한 없음");
ok(await err("select add_idea('night-bus','x','x','x','x')"), "slug 중복 거절");
ok(await err("select add_idea('Bad Slug','x','x','x','x')"), "slug 형식 거절");

// 아이디어 연구소 v2: 점수·승격 이유·다음 검증 질문
const scores = { hook: 82, core_loop: 78, mobile_fit: 90, prototype: 85, asset: 70, visual: 74, growth: 66 };
const [{ add_idea: g0 }] = await q(
  "select add_idea('scored-idea','점수 아이디어','한 줄','탭','판타지','퍼즐',$1::jsonb,$2::text[],'첫 판에서 규칙이 바로 읽히는가')",
  [JSON.stringify(scores), ["규칙이 한 문장", "조작이 손에 붙음"]]);
const sg = (await q("select genre, idea_scores, why_promoted, next_test from games where id=$1", [g0]))[0];
ok(sg.genre === "퍼즐" && sg.idea_scores.hook === 82 && sg.why_promoted.length === 2 && sg.next_test, "점수와 승격 이유 저장");
e = await err("select add_idea('bad-score','x','x','x','x',null,$1::jsonb)", [JSON.stringify({ ...scores, hook: 120 })]);
ok(e && e.includes("SCORES_INVALID"), "점수 범위 거절: " + e);
e = await err("select add_idea('bad-score2','x','x','x','x',null,$1::jsonb)", [JSON.stringify({ hook: 80 })]);
ok(e && e.includes("SCORES_INVALID"), "점수 항목 누락 거절: " + e);
e = await err("select add_idea('bad-why','x','x','x','x',null,null,$1::text[])", [["a", "b", "c", "d", "e"]]);
ok(e && e.includes("WHY_INVALID"), "승격 이유 5개 거절: " + e);
await q("select ceo_triage($1,'drop')", [g0]);

// 기획 대기 없으면 planner는 빈손
ok((await q("select * from claim('planner','p1')")).length === 0, "기획할 것 없으면 빈손");
await q("select ceo_triage($1,'go','짧게')", [g1]);
ok((await stage(g1)).stage === "planning", "go → planning");
await q("select ceo_star($1,true)", [g2]);
await q("select ceo_triage($1,'go')", [g2]);

const c1 = await q("select * from claim('planner','p1')");
ok(c1.length === 1 && c1[0].id === g2, "별표 우선");
ok((await q("select * from claim('planner','p2')")).length === 1, "다른 기획자는 다른 건");
ok((await q("select * from claim('planner','p3')")).length === 0, "임대 중인 건은 안 줌");
e = await err("select submit_spec($1,'p1',$2)", [g2, JSON.stringify({ ...spec, must_work: spec.must_work.slice(0, 2) })]);
ok(e && e.includes("must_work는 3~10개"), "must_work 2개 거절: " + e);
e = await err("select submit_spec($1,'p1',$2)", [g2, JSON.stringify({ ...spec, must_work: [...spec.must_work, { id: "M1", text: "x", check: "y" }] })]);
ok(e && e.includes("중복"), "id 중복 거절: " + e);
ok(await err("select submit_spec($1,'p9',$2)", [g2, JSON.stringify(spec)]), "남의 임대로 제출 거절");
await q("select submit_spec($1,'p1',$2)", [g2, JSON.stringify(spec)]);
await q("select submit_spec($1,'p2',$2)", [g1, JSON.stringify(spec)]);
ok((await stage(g2)).stage === "ready", "기획 → ready");

// 빌드: 한 번에 하나
const b1 = await q("select * from claim('builder','b1')");
ok(b1[0].id === g2 && b1[0].stage === "building" && b1[0].attempt === 1, "빌드 시작 attempt 1");
ok((await q("select * from claim('builder','b2')")).length === 0, "빌드 상한 1");
await q("select submit_build($1,'b1','abcdef1',true,'첫 빌드')", [g2]);
ok((await stage(g2)).stage === "qa", "빌드 → qa");

// 검수
await q("select * from claim('qa','q1')");
e = await err("select submit_qa($1,'q1','pass',true,$2,null)", [g2, JSON.stringify([{ id: "M1", ok: true }])]);
ok(e && e.includes("CHECKS_MISSING"), "누락 항목 거절: " + e);
e = await err("select submit_qa($1,'q1','pass',true,$2,null)", [g2, JSON.stringify([{ id: "M1", ok: true }, { id: "M2", ok: false }, { id: "M3", ok: true }])]);
ok(e && e.includes("실패 항목"), "실패 있는 pass 거절: " + e);
await q("select submit_qa($1,'q1','fail',true,$2,'M2: 탭해도 시작 안 됨')", [g2, JSON.stringify([{ id: "M1", ok: true }, { id: "M2", ok: false }, { id: "M3", ok: true }])]);
let s = await stage(g2);
ok(s.stage === "ready" && s.fix_notes.includes("M2"), "불합격 → ready + 수리 메모");

// 두 번째 빌드는 별표 g2가 다시 먼저. 자동 검사 실패 빌드는 qa로 안 감
await q("select * from claim('builder','b1')");
await q("select submit_build($1,'b1','abcdef2',false,'smoke 실패')", [g2]);
s = await stage(g2);
ok(s.stage === "ready" && s.attempt === 2, "smoke 실패 → ready");
await q("select * from claim('builder','b1')");
await q("select submit_build($1,'b1','abcdef3',null,null)", [g2]);
ok((await stage(g2)).stage === "qa", "CI 미확인 빌드도 검수로");
await q("select * from claim('qa','q1')");
const allOk = JSON.stringify(spec.must_work.map(m => ({ id: m.id, ok: true })));
e = await err("select submit_qa($1,'q1','pass',null,$2,null)", [g2, allOk]);
ok(e && e.includes("CI 결과"), "CI 미확인 제출 거절: " + e);
e = await err("select submit_qa($1,'q1','pass',false,$2,null)", [g2, allOk]);
ok(e && e.includes("CI를 통과하지"), "CI 실패 pass 거절: " + e);
await q("select submit_qa($1,'q1','pass',true,$2,null)", [g2, JSON.stringify(spec.must_work.map(m => ({ id: m.id, ok: true })))]);
ok((await stage(g2)).stage === "playtest", "합격 → playtest");

ok(await err("select ceo_playtest($1,'fix','')", [g2]), "수정 요청엔 메모 필요");
await q("select ceo_playtest($1,'keep','좋다')", [g2]);
ok((await stage(g2)).stage === "kept", "keep → kept");

// 임대 만료된 빌드 이어받기 + 운영 장애 release
await q("select * from claim('builder','b1',0)");
ok((await stage(g1)).stage === "building", "g1 빌드 시작");
const r = await q("select * from claim('builder','b2')");
ok(r.length === 1 && r[0].id === g1 && r[0].lease_owner === "b2", "만료된 빌드 이어받기");
await q("select release($1,'b2','깃허브 장애')", [g1]);
s = await stage(g1);
ok(s.stage === "ready" && s.attempt === 0, "release → ready, attempt 되돌림: " + JSON.stringify(s));

// 3회 실패 → held
for (const sha of ["1111111", "2222222", "3333333"]) {
  await q("select * from claim('builder','b1')");
  await q("select submit_build($1,'b1',$2,false,'계속 실패')", [g1, sha]);
}
s = await stage(g1);
ok(s.stage === "held", "3회 실패 → held: " + JSON.stringify(s));
await q("select ceo_triage($1,'go','다시')", [g1]);
ok((await stage(g1)).stage === "ready", "held go → 기획서 있으면 ready");

// 출근부
const [{ run_start: run }] = await q("select run_start('builder')");
await q("select run_finish($1,'noop','할 일 없음')", [run]);
ok((await q("select status from runs where id=$1", [run]))[0].status === "noop", "출근부");
ok(await err("select run_finish($1,'weird','x')", [run]), "잘못된 status 거절");

// 권한: API 경유(authenticator)
await db.exec("insert into ceo_emails values ('boss@example.com')");
await db.exec("set session authorization authenticator");
await db.exec("set role anon");
ok((await q("select count(*)::int c from games"))[0].c > 0, "anon 읽기 가능");
ok(await err("insert into games(slug,title,pitch,core_verb,fun_hypothesis) values ('x','x','x','x','x')"), "anon 직접 쓰기 불가");
ok(await err("select * from claim('builder','hack')"), "anon 워커 함수 불가");
ok(await err("select ceo_triage($1,'drop')", [g1]), "anon 대표 함수 불가");
ok((await q("select count(*)::int c from ceo_emails").catch(() => [{ c: 0 }]))[0].c === 0, "anon은 대표 메일 못 봄");
await db.exec("reset role; set role authenticated");
await db.exec(`set request.jwt.claims = '{"email":"someone@example.com","role":"authenticated"}'`);
e = await err("select ceo_triage($1,'drop')", [g1]);
ok(e && e.includes("대표만"), "다른 사용자 거절: " + e);
ok(await err("update games set stage='kept'"), "authenticated 직접 수정 불가") ;
ok((await stage(g1)).stage === "ready", "직접 수정 안 됨");
await db.exec(`set request.jwt.claims = '{"email":"Boss@example.com","role":"authenticated"}'`);
await q("select ceo_triage($1,'hold')", [(await q("select id from games where slug='idea-3'"))[0].id]);
ok(true, "대표 메일로 분류 성공");
await db.exec("reset role; set role service_role");
await db.exec(`set request.jwt.claims = '{"role":"service_role"}'`);
ok((await q("select * from claim('planner','svc')")).length === 0, "service_role 워커 함수 가능");

await db.exec("reset role; reset session authorization");
console.log(`\n${pass} passed, ${fail} failed`);
console.log((await q("select kind, message from events order by id desc limit 5")).map(r => `  ${r.kind}: ${r.message}`).join("\n"));
process.exit(fail ? 1 : 0);
