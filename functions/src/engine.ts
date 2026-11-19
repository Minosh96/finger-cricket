/**
 * Finger Cricket – authoritative game engine (pure functions, no Firebase).
 * Everything that decides a score lives here so it can be unit-tested.
 */

// ---- Timing constants (milliseconds) ------------------------------------
export const SELECT_MS = 3000; // decision window per delivery
export const PREP_MS = 1800; // "get ready" pause before the first ball of an innings
export const REVEAL_MS = 2200; // time the reveal is shown before the next ball opens
export const LOCK_GRACE_MS = 400; // MUST match the "+ 400" in database.rules.json
export const SETTLE_MS = 1000; // resolver waits this long after the deadline (> LOCK_GRACE_MS)
export const MAX_MISSES = 4; // consecutive missed deliveries before forfeit
export const ROOM_TTL_MS = 3 * 60 * 60 * 1000; // a room code can be reused after 3 h
export const JOIN_TTL_MS = 60 * 60 * 1000; // a waiting room can be joined for 1 h
export const MIN_OVERS = 1;
export const MAX_OVERS = 10;

export type Status =
  | "waiting" // 1 player, waiting for opponent
  | "lobby" // 2 players, ready-up + overs
  | "toss" // toss done, winner choosing bat/bowl
  | "playing"
  | "innings_break"
  | "completed"
  | "abandoned";

export type DeliveryType = "runs" | "wicket" | "dot" | "noBall" | "retry";

export interface DeliveryResult {
  type: DeliveryType;
  batterRuns: number;
  extras: number;
  legal: boolean;
  wicket: boolean;
}

export interface Player {
  name: string;
  ready: boolean;
  connected: boolean;
  joinedAt: number;
  left?: boolean;
}

export interface InningsSummary {
  batterUid: string;
  bowlerUid: string;
  score: number;
  wickets: number;
  legalBalls: number;
  noBalls: number;
  balls: string[];
}

export interface LastResult {
  roundKey: string;
  batterUid: string;
  bowlerUid: string;
  batterMove: number | null;
  bowlerMove: number | null;
  type: DeliveryType;
  batterRuns: number;
  extras: number;
}

export interface MatchState extends InningsSummary {
  innings: 1 | 2;
  roundKey: string;
  startAt: number;
  deadlineAt: number;
  target: number | null;
  first: InningsSummary | null;
  lastResult: LastResult | null;
  misses: Record<string, number>;
  startedAt: number;
}

export interface MatchResult {
  winnerUid: string | null;
  tie: boolean;
  reason: "normal" | "forfeit" | "left" | "inactive";
  text: string;
  endedAt: number;
}

export interface Room {
  code: string;
  hostUid: string;
  createdAt: number;
  status: Status;
  settings: { overs: number; wickets: number; selectionMs: number };
  players: Record<string, Player>;
  roundSeq: number;
  matchNo: number;
  toss: { winnerUid: string } | null;
  match: MatchState | null;
  result: MatchResult | null;
  breakReady: Record<string, boolean> | null;
  rematch: Record<string, boolean> | null;
  locks: Record<string, Record<string, boolean>> | null;
}

// ---- Core rules ----------------------------------------------------------

export function isValidMove(v: unknown): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= 7;
}

/** Gestures 1–5 = fingers, 6 = thumb, 7 = thumb + pinky. Match = OUT. */
export function evaluateDelivery(
  batterMove: number | null,
  bowlerMove: number | null,
): DeliveryResult {
  if (batterMove === null && bowlerMove === null) {
    return { type: "retry", batterRuns: 0, extras: 0, legal: false, wicket: false };
  }
  if (bowlerMove === null) {
    // Bowler timed out -> no-ball, +1 extra, not a legal ball, no wicket possible.
    return { type: "noBall", batterRuns: 0, extras: 1, legal: false, wicket: false };
  }
  if (batterMove === null) {
    // Batter timed out -> legal dot ball.
    return { type: "dot", batterRuns: 0, extras: 0, legal: true, wicket: false };
  }
  if (batterMove === bowlerMove) {
    return { type: "wicket", batterRuns: 0, extras: 0, legal: true, wicket: true };
  }
  return { type: "runs", batterRuns: batterMove, extras: 0, legal: true, wicket: false };
}

export function ballCode(r: DeliveryResult): string {
  switch (r.type) {
    case "runs":
      return String(r.batterRuns);
    case "wicket":
      return "W";
    case "dot":
      return "•";
    case "noBall":
      return "NB";
    default:
      return "R";
  }
}

export function formatOvers(legalBalls: number): string {
  return `${Math.floor(legalBalls / 6)}.${legalBalls % 6}`;
}

// ---- Normalisation (RTDB drops empty arrays / nulls) ----------------------

function toStringArray(v: unknown): string[] {
  if (Array.isArray(v)) return v.filter((x) => x !== null && x !== undefined).map(String);
  if (v && typeof v === "object") {
    return Object.keys(v as object)
      .sort((a, b) => Number(a) - Number(b))
      .map((k) => String((v as Record<string, unknown>)[k]));
  }
  return [];
}

function num(v: unknown, d = 0): number {
  return typeof v === "number" && Number.isFinite(v) ? v : d;
}

function normInnings(raw: any): InningsSummary {
  return {
    batterUid: String(raw?.batterUid ?? ""),
    bowlerUid: String(raw?.bowlerUid ?? ""),
    score: num(raw?.score),
    wickets: num(raw?.wickets),
    legalBalls: num(raw?.legalBalls),
    noBalls: num(raw?.noBalls),
    balls: toStringArray(raw?.balls),
  };
}

export function normalizeRoom(raw: any): Room {
  const players: Record<string, Player> = {};
  for (const [uid, p] of Object.entries<any>(raw?.players ?? {})) {
    if (!p || typeof p !== "object" || typeof p.name !== "string") continue;
    players[uid] = {
      name: p.name,
      ready: p.ready === true,
      connected: p.connected !== false,
      joinedAt: num(p.joinedAt),
      ...(p.left === true ? { left: true } : {}),
    };
  }
  let match: MatchState | null = null;
  if (raw?.match && typeof raw.match === "object") {
    const m = raw.match;
    match = {
      ...normInnings(m),
      innings: m.innings === 2 ? 2 : 1,
      roundKey: String(m.roundKey ?? ""),
      startAt: num(m.startAt),
      deadlineAt: num(m.deadlineAt),
      target: typeof m.target === "number" ? m.target : null,
      first: m.first ? normInnings(m.first) : null,
      lastResult: m.lastResult
        ? {
            roundKey: String(m.lastResult.roundKey ?? ""),
            batterUid: String(m.lastResult.batterUid ?? ""),
            bowlerUid: String(m.lastResult.bowlerUid ?? ""),
            batterMove: isValidMove(m.lastResult.batterMove) ? m.lastResult.batterMove : null,
            bowlerMove: isValidMove(m.lastResult.bowlerMove) ? m.lastResult.bowlerMove : null,
            type: m.lastResult.type,
            batterRuns: num(m.lastResult.batterRuns),
            extras: num(m.lastResult.extras),
          }
        : null,
      misses: { ...(m.misses ?? {}) },
      startedAt: num(m.startedAt),
    };
  }
  return {
    code: String(raw?.code ?? ""),
    hostUid: String(raw?.hostUid ?? ""),
    createdAt: num(raw?.createdAt),
    status: (raw?.status ?? "waiting") as Status,
    settings: {
      overs: num(raw?.settings?.overs, 2),
      wickets: num(raw?.settings?.wickets, 1),
      selectionMs: num(raw?.settings?.selectionMs, SELECT_MS),
    },
    players,
    roundSeq: num(raw?.roundSeq),
    matchNo: num(raw?.matchNo, 1),
    toss: raw?.toss?.winnerUid ? { winnerUid: String(raw.toss.winnerUid) } : null,
    match,
    result: raw?.result ?? null,
    breakReady: raw?.breakReady ?? null,
    rematch: raw?.rematch ?? null,
    locks: raw?.locks ?? null,
  };
}

/** Removes `undefined` so the object can be written to RTDB. */
export function toDb<T>(v: T): T {
  return JSON.parse(JSON.stringify(v));
}

// ---- Helpers -------------------------------------------------------------

export function playerUids(room: Room): string[] {
  return Object.keys(room.players).sort(
    (a, b) => room.players[a].joinedAt - room.players[b].joinedAt,
  );
}

export function opponentOf(room: Room, uid: string): string | null {
  return playerUids(room).find((u) => u !== uid) ?? null;
}

export function nameOf(room: Room, uid: string | null): string {
  return (uid && room.players[uid]?.name) || "Player";
}

export function newRoom(code: string, hostUid: string, hostName: string, now: number, overs = 2): Room {
  return {
    code,
    hostUid,
    createdAt: now,
    status: "waiting",
    settings: { overs, wickets: 1, selectionMs: SELECT_MS },
    players: { [hostUid]: { name: hostName, ready: false, connected: true, joinedAt: now } },
    roundSeq: 0,
    matchNo: 1,
    toss: null,
    match: null,
    result: null,
    breakReady: null,
    rematch: null,
    locks: null,
  };
}

// ---- State transitions ---------------------------------------------------

export function doToss(room: Room, rand: () => number): void {
  const uids = playerUids(room);
  room.toss = { winnerUid: uids[rand() < 0.5 ? 0 : 1] };
  room.status = "toss";
  room.match = null;
  room.result = null;
}

export function startRound(room: Room, now: number, delayMs: number): void {
  const m = room.match!;
  room.roundSeq += 1;
  m.roundKey = `r${room.roundSeq}`;
  m.startAt = now + delayMs;
  m.deadlineAt = m.startAt + room.settings.selectionMs;
  room.locks = null;
}

export function beginInnings(
  room: Room,
  innings: 1 | 2,
  batterUid: string,
  now: number,
  first: InningsSummary | null,
): void {
  const bowlerUid = opponentOf(room, batterUid);
  if (!bowlerUid) throw new Error("Opponent missing");
  room.match = {
    innings,
    batterUid,
    bowlerUid,
    roundKey: "",
    startAt: 0,
    deadlineAt: 0,
    score: 0,
    wickets: 0,
    legalBalls: 0,
    noBalls: 0,
    balls: [],
    target: first ? first.score + 1 : null,
    first,
    lastResult: null,
    misses: room.match?.misses ?? {},
    startedAt: room.match?.startedAt || now,
  };
  room.status = "playing";
  room.breakReady = null;
  startRound(room, now, PREP_MS);
}

export function chooseBatBowl(room: Room, uid: string, choice: "bat" | "bowl", now: number): void {
  if (room.status !== "toss" || room.toss?.winnerUid !== uid) throw new Error("Not your choice");
  const batter = choice === "bat" ? uid : opponentOf(room, uid)!;
  room.match = null;
  beginInnings(room, 1, batter, now, null);
}

export function startSecondInnings(room: Room, now: number): void {
  const m = room.match!;
  const first: InningsSummary = {
    batterUid: m.batterUid,
    bowlerUid: m.bowlerUid,
    score: m.score,
    wickets: m.wickets,
    legalBalls: m.legalBalls,
    noBalls: m.noBalls,
    balls: m.balls,
  };
  beginInnings(room, 2, m.bowlerUid, now, first);
}

export function finishForfeit(
  room: Room,
  loserUid: string,
  reason: "forfeit" | "left",
  now: number,
): void {
  const winner = opponentOf(room, loserUid);
  room.status = "completed";
  room.locks = null;
  if (room.match) room.match.roundKey = "";
  room.result = {
    winnerUid: winner,
    tie: false,
    reason,
    text:
      reason === "left"
        ? `${nameOf(room, winner)} wins – ${nameOf(room, loserUid)} left the match`
        : `${nameOf(room, winner)} wins by forfeit – ${nameOf(room, loserUid)} missed ${MAX_MISSES} balls in a row`,
    endedAt: now,
  };
}

export function finishMatch(room: Room, now: number): void {
  const m = room.match!;
  const first = m.first!;
  const maxBalls = room.settings.overs * 6;
  const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;
  room.status = "completed";
  room.locks = null;
  m.roundKey = "";
  if (m.target !== null && m.score >= m.target) {
    room.result = {
      winnerUid: m.batterUid,
      tie: false,
      reason: "normal",
      text: `${nameOf(room, m.batterUid)} won by ${plural(room.settings.wickets - m.wickets, "wicket")} with ${plural(maxBalls - m.legalBalls, "ball")} remaining`,
      endedAt: now,
    };
  } else if (m.score === first.score) {
    room.result = { winnerUid: null, tie: true, reason: "normal", text: "Match tied!", endedAt: now };
  } else {
    room.result = {
      winnerUid: first.batterUid,
      tie: false,
      reason: "normal",
      text: `${nameOf(room, first.batterUid)} won by ${plural(first.score - m.score, "run")}`,
      endedAt: now,
    };
  }
}

export type ResolveOutcome = "stale" | "pending" | "resolved";

/**
 * Resolve the current delivery. Idempotent: it only acts when `roundKey`
 * is still the open round, so duplicate/late calls are harmless.
 */
export function resolveRound(
  room: Room,
  roundKey: string,
  moves: Record<string, unknown>,
  now: number,
): ResolveOutcome {
  const m = room.match;
  if (room.status !== "playing" || !m || !roundKey || m.roundKey !== roundKey) return "stale";

  const batterMove = isValidMove(moves[m.batterUid]) ? (moves[m.batterUid] as number) : null;
  const bowlerMove = isValidMove(moves[m.bowlerUid]) ? (moves[m.bowlerUid] as number) : null;
  const bothIn = batterMove !== null && bowlerMove !== null;
  if (!bothIn && now <= m.deadlineAt + SETTLE_MS) return "pending";

  const r = evaluateDelivery(batterMove, bowlerMove);
  m.lastResult = {
    roundKey,
    batterUid: m.batterUid,
    bowlerUid: m.bowlerUid,
    batterMove,
    bowlerMove,
    type: r.type,
    batterRuns: r.batterRuns,
    extras: r.extras,
  };

  // Inactivity tracking -> forfeit instead of endless no-balls.
  m.misses[m.batterUid] = batterMove === null ? (m.misses[m.batterUid] ?? 0) + 1 : 0;
  m.misses[m.bowlerUid] = bowlerMove === null ? (m.misses[m.bowlerUid] ?? 0) + 1 : 0;
  const batterOut = m.misses[m.batterUid] >= MAX_MISSES;
  const bowlerOut = m.misses[m.bowlerUid] >= MAX_MISSES;
  if (batterOut && bowlerOut) {
    room.status = "abandoned";
    room.locks = null;
    m.roundKey = "";
    room.result = {
      winnerUid: null,
      tie: false,
      reason: "inactive",
      text: "Match abandoned – both players inactive",
      endedAt: now,
    };
    return "resolved";
  }
  if (batterOut || bowlerOut) {
    finishForfeit(room, batterOut ? m.batterUid : m.bowlerUid, "forfeit", now);
    return "resolved";
  }

  if (r.type === "retry") {
    startRound(room, now, REVEAL_MS);
    return "resolved";
  }

  m.score += r.batterRuns + r.extras;
  if (r.type === "noBall") m.noBalls += 1;
  if (r.legal) m.legalBalls += 1;
  if (r.wicket) m.wickets += 1;
  m.balls.push(ballCode(r));

  const maxBalls = room.settings.overs * 6;
  if (m.innings === 2 && m.target !== null && m.score >= m.target) {
    finishMatch(room, now);
  } else if (m.wickets >= room.settings.wickets || m.legalBalls >= maxBalls) {
    if (m.innings === 1) {
      room.status = "innings_break";
      room.breakReady = {};
      room.locks = null;
      m.roundKey = "";
    } else {
      finishMatch(room, now);
    }
  } else {
    startRound(room, now, REVEAL_MS);
  }
  return "resolved";
}

export function resetForRematch(room: Room, rand: () => number): void {
  room.matchNo += 1;
  room.rematch = null;
  room.breakReady = null;
  room.locks = null;
  for (const p of Object.values(room.players)) p.ready = false;
  doToss(room, rand);
}

export function sanitizeName(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const s = v.replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim().slice(0, 16);
  return s.length >= 1 ? s : null;
}
