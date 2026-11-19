import { test } from "node:test";
import assert from "node:assert/strict";
import * as E from "../engine";

const A = "uidA";
const B = "uidB";

function playingRoom(overs = 2): E.Room {
  const r = E.newRoom("123456", A, "Ann", 1000, overs);
  r.players[B] = { name: "Ben", ready: true, connected: true, joinedAt: 2000 };
  r.status = "toss";
  r.toss = { winnerUid: A };
  E.chooseBatBowl(r, A, "bat", 3000);
  return r;
}

/** Plays one delivery with both moves in before the deadline. */
function play(r: E.Room, bat: number | null, bowl: number | null, late = false) {
  const m = r.match!;
  const moves: Record<string, unknown> = {};
  if (bat !== null) moves[m.batterUid] = bat;
  if (bowl !== null) moves[m.bowlerUid] = bowl;
  const now = late || bat === null || bowl === null ? m.deadlineAt + E.SETTLE_MS + 1 : m.startAt + 500;
  return E.resolveRound(r, m.roundKey, moves, now);
}

test("evaluateDelivery covers every rule", () => {
  assert.deepEqual(E.evaluateDelivery(4, 2), { type: "runs", batterRuns: 4, extras: 0, legal: true, wicket: false });
  assert.equal(E.evaluateDelivery(7, 1).batterRuns, 7);
  assert.equal(E.evaluateDelivery(6, 6).type, "wicket");
  assert.equal(E.evaluateDelivery(3, null).type, "noBall");
  assert.equal(E.evaluateDelivery(3, null).extras, 1);
  assert.equal(E.evaluateDelivery(3, null).legal, false);
  assert.equal(E.evaluateDelivery(null, 3).type, "dot");
  assert.equal(E.evaluateDelivery(null, 3).legal, true);
  assert.equal(E.evaluateDelivery(null, null).type, "retry");
});

test("formatOvers", () => {
  assert.deepEqual([0, 5, 6, 8, 12].map(E.formatOvers), ["0.0", "0.5", "1.0", "1.2", "2.0"]);
});

test("spec example: 2,4,NB,1,W = 8/1 in 0.4", () => {
  const r = playingRoom();
  play(r, 2, 5);
  play(r, 4, 1);
  play(r, 3, null); // bowler timeout
  play(r, 1, 6);
  play(r, 5, 5); // OUT
  const m = r.match!;
  assert.equal(r.status, "innings_break");
  assert.equal(m.score, 8);
  assert.equal(m.wickets, 1);
  assert.equal(E.formatOvers(m.legalBalls), "0.4");
  assert.equal(m.noBalls, 1);
  assert.deepEqual(m.balls, ["2", "4", "NB", "1", "W"]);
});

test("pending before deadline, stale after resolution (idempotent)", () => {
  const r = playingRoom();
  const key = r.match!.roundKey;
  assert.equal(E.resolveRound(r, key, { [A]: 3 }, r.match!.deadlineAt), "pending");
  assert.equal(E.resolveRound(r, key, { [A]: 3, [B]: 1 }, r.match!.startAt + 10), "resolved");
  assert.equal(E.resolveRound(r, key, { [A]: 3, [B]: 1 }, r.match!.startAt + 10), "stale");
  assert.equal(r.match!.score, 3);
});

test("both timeout retries without counting", () => {
  const r = playingRoom();
  const key = r.match!.roundKey;
  play(r, null, null);
  assert.notEqual(r.match!.roundKey, key);
  assert.equal(r.match!.legalBalls, 0);
  assert.equal(r.match!.score, 0);
  assert.equal(r.match!.lastResult!.type, "retry");
});

test("innings ends after 12 legal balls; no-balls don't count", () => {
  const r = playingRoom(2);
  for (let i = 0; i < 11; i++) play(r, 1, 2);
  play(r, 2, null); // no-ball
  assert.equal(r.status, "playing");
  play(r, 1, 2);
  assert.equal(r.status, "innings_break");
  assert.equal(r.match!.score, 13);
  assert.equal(r.match!.legalBalls, 12);
});

test("chase: wins as soon as target passed, with message", () => {
  const r = playingRoom(2);
  play(r, 6, 1);
  play(r, 6, 6); // A: 6/1
  r.breakReady = { [A]: true, [B]: true };
  E.startSecondInnings(r, 99999);
  assert.equal(r.match!.batterUid, B);
  assert.equal(r.match!.target, 7);
  play(r, 4, 1);
  play(r, 3, 1);
  assert.equal(r.status, "completed");
  assert.equal(r.result!.winnerUid, B);
  assert.equal(r.result!.text, "Ben won by 1 wicket with 10 balls remaining");
});

test("tie and defend", () => {
  const tie = playingRoom(1);
  play(tie, 5, 1);
  play(tie, 2, 2);
  E.startSecondInnings(tie, 99999);
  play(tie, 5, 1);
  play(tie, 3, 3);
  assert.equal(tie.result!.tie, true);

  const def = playingRoom(1);
  play(def, 7, 1);
  play(def, 2, 2);
  E.startSecondInnings(def, 99999);
  play(def, 4, 4);
  assert.equal(def.result!.winnerUid, A);
  assert.equal(def.result!.text, "Ann won by 7 runs");
});

test("repeated inactivity forfeits", () => {
  const r = playingRoom();
  for (let i = 0; i < E.MAX_MISSES; i++) play(r, 1, null);
  assert.equal(r.status, "completed");
  assert.equal(r.result!.winnerUid, A);
  assert.equal(r.result!.reason, "forfeit");
  assert.equal(r.match!.noBalls, E.MAX_MISSES - 1);
});

test("rematch resets counters", () => {
  const r = playingRoom(1);
  play(r, 2, 2);
  E.startSecondInnings(r, 1);
  play(r, 1, 1);
  E.resetForRematch(r, () => 0.9);
  assert.equal(r.status, "toss");
  assert.equal(r.match, null);
  assert.equal(r.toss!.winnerUid, B);
  E.chooseBatBowl(r, B, "bowl", 5);
  assert.equal(r.match!.batterUid, A);
  assert.equal(r.match!.score, 0);
});

test("normalizeRoom survives RTDB shapes and toDb strips undefined", () => {
  const r = playingRoom();
  play(r, 2, 1);
  const raw = E.toDb(r) as any;
  raw.match.balls = { "0": "2" };
  delete raw.match.misses;
  const n = E.normalizeRoom(raw);
  assert.deepEqual(n.match!.balls, ["2"]);
  assert.deepEqual(n.match!.misses, {});
  assert.equal(E.sanitizeName("  Super   Long Name Indeed!!  "), "Super Long Name ");
});
