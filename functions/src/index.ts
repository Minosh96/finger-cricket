/**
 * Finger Cricket – Cloud Functions entry point.
 *
 * A single callable function `api` handles every action. One function means
 * one warm instance serves the whole match, which keeps latency low.
 *
 * Moves are NOT sent through this function: players write them straight to
 * /moves/{code}/{roundKey}/{uid}. database.rules.json lets each player write
 * exactly once, only before the server deadline, and nobody can read /moves.
 */
import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { randomInt } from "node:crypto";
import * as E from "./engine";

// Keep this region in sync with kFunctionsRegion in lib/services/online_service.dart
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

initializeApp();
const db = () => getDatabase();
const rand = () => randomInt(0, 1_000_000) / 1_000_000;

function requireCode(v: unknown): string {
  if (typeof v !== "string" || !/^\d{6}$/.test(v)) {
    throw new HttpsError("invalid-argument", "Room code must be 6 digits.");
  }
  return v;
}

/**
 * Atomically read-modify-write a room. `fn` returns false to abort without
 * writing, or throws HttpsError to reject the request.
 */
async function mutateRoom(code: string, fn: (room: E.Room) => boolean): Promise<E.Room> {
  let failure: unknown = null;
  let missing = false;
  const res = await db()
    .ref(`rooms/${code}`)
    .transaction((cur) => {
      failure = null;
      missing = false;
      if (cur === null) {
        missing = true;
        return null; // server re-runs with real data if the room exists
      }
      try {
        const room = E.normalizeRoom(cur);
        return fn(room) ? E.toDb(room) : undefined;
      } catch (e) {
        failure = e;
        return undefined; // abort
      }
    });
  if (failure) {
    if (failure instanceof HttpsError) throw failure;
    throw new HttpsError("failed-precondition", (failure as Error).message ?? "Rejected");
  }
  if (missing || !res.snapshot.exists()) throw new HttpsError("not-found", "Room not found.");
  return E.normalizeRoom(res.snapshot.val());
}

function requireMember(room: E.Room, uid: string): void {
  if (!room.players[uid]) throw new HttpsError("permission-denied", "You are not in this room.");
}

// ---- Actions ---------------------------------------------------------------

async function createRoom(uid: string, data: any) {
  const name = E.sanitizeName(data?.name);
  if (!name) throw new HttpsError("invalid-argument", "Enter a nickname (1–16 characters).");
  for (let attempt = 0; attempt < 15; attempt++) {
    const code = String(randomInt(100000, 1000000));
    const now = Date.now();
    let reused = false;
    const res = await db()
      .ref(`rooms/${code}`)
      .transaction((cur) => {
        if (cur === null) return E.toDb(E.newRoom(code, uid, name, now));
        if (now - (cur.createdAt ?? 0) > E.ROOM_TTL_MS) {
          reused = true;
          return E.toDb(E.newRoom(code, uid, name, now));
        }
        return undefined; // code in use
      });
    if (res.committed) {
      if (reused) await db().ref(`moves/${code}`).remove();
      return { code };
    }
  }
  throw new HttpsError("resource-exhausted", "Could not allocate a room. Try again.");
}

async function joinRoom(uid: string, data: any) {
  const code = requireCode(data?.code);
  const name = E.sanitizeName(data?.name);
  if (!name) throw new HttpsError("invalid-argument", "Enter a nickname (1–16 characters).");
  const now = Date.now();
  await mutateRoom(code, (room) => {
    if (room.players[uid]) return false; // already in – rejoin is fine
    if (now - room.createdAt > E.JOIN_TTL_MS) throw new HttpsError("deadline-exceeded", "This room has expired.");
    if (room.status !== "waiting" || Object.keys(room.players).length >= 2) {
      throw new HttpsError("resource-exhausted", "This room is full.");
    }
    room.players[uid] = { name, ready: false, connected: true, joinedAt: now };
    room.status = "lobby";
    return true;
  });
  return { code };
}

async function setOvers(uid: string, data: any) {
  const code = requireCode(data?.code);
  const overs = data?.overs;
  if (!Number.isInteger(overs) || overs < E.MIN_OVERS || overs > E.MAX_OVERS) {
    throw new HttpsError("invalid-argument", `Overs must be ${E.MIN_OVERS}–${E.MAX_OVERS}.`);
  }
  await mutateRoom(code, (room) => {
    requireMember(room, uid);
    if (room.hostUid !== uid) throw new HttpsError("permission-denied", "Only the host can change overs.");
    if (room.status !== "waiting" && room.status !== "lobby") return false;
    room.settings.overs = overs;
    for (const p of Object.values(room.players)) p.ready = false; // re-confirm after a change
    return true;
  });
  return {};
}

async function ready(uid: string, data: any) {
  const code = requireCode(data?.code);
  const now = Date.now();
  await mutateRoom(code, (room) => {
    requireMember(room, uid);
    if (room.status === "lobby") {
      room.players[uid].ready = true;
      const uids = E.playerUids(room);
      if (uids.length === 2 && uids.every((u) => room.players[u].ready)) E.doToss(room, rand);
      return true;
    }
    if (room.status === "innings_break") {
      room.breakReady = { ...(room.breakReady ?? {}), [uid]: true };
      if (E.playerUids(room).every((u) => room.breakReady![u])) E.startSecondInnings(room, now);
      return true;
    }
    return false;
  });
  return {};
}

async function chooseBatBowl(uid: string, data: any) {
  const code = requireCode(data?.code);
  const choice = data?.choice;
  if (choice !== "bat" && choice !== "bowl") throw new HttpsError("invalid-argument", "Choose bat or bowl.");
  await mutateRoom(code, (room) => {
    requireMember(room, uid);
    if (room.status !== "toss") return false;
    if (room.toss?.winnerUid !== uid) throw new HttpsError("permission-denied", "Your opponent won the toss.");
    E.chooseBatBowl(room, uid, choice, Date.now());
    return true;
  });
  return {};
}

/** Called by either phone when both moves are locked or the deadline passed. */
async function tick(uid: string, data: any) {
  const code = requireCode(data?.code);
  const roundKey = typeof data?.roundKey === "string" ? data.roundKey : "";
  if (!/^r\d+$/.test(roundKey)) throw new HttpsError("invalid-argument", "Bad round.");
  // Moves are frozen once both exist or the (rules-enforced) deadline passed,
  // so reading them outside the room transaction is safe.
  const moves = ((await db().ref(`moves/${code}/${roundKey}`).get()).val() ?? {}) as Record<string, unknown>;
  let outcome: E.ResolveOutcome = "stale";
  await mutateRoom(code, (room) => {
    requireMember(room, uid);
    outcome = E.resolveRound(room, roundKey, moves, Date.now());
    return outcome === "resolved";
  });
  if ((outcome as E.ResolveOutcome) === "resolved") await db().ref(`moves/${code}/${roundKey}`).remove();
  return { outcome };
}

async function requestRematch(uid: string, data: any) {
  const code = requireCode(data?.code);
  await mutateRoom(code, (room) => {
    requireMember(room, uid);
    if (room.status !== "completed") return false;
    const uids = E.playerUids(room);
    if (uids.length !== 2 || uids.some((u) => room.players[u].left)) {
      throw new HttpsError("failed-precondition", "Your opponent has left.");
    }
    room.rematch = { ...(room.rematch ?? {}), [uid]: true };
    if (uids.every((u) => room.rematch![u])) E.resetForRematch(room, rand);
    return true;
  });
  return {};
}

async function leaveRoom(uid: string, data: any) {
  const code = requireCode(data?.code);
  let deleteRoom = false;
  try {
    await mutateRoom(code, (room) => {
      if (!room.players[uid]) return false;
      const now = Date.now();
      switch (room.status) {
        case "waiting":
          deleteRoom = true;
          room.status = "abandoned";
          return true;
        case "lobby": {
          delete room.players[uid];
          const rest = E.playerUids(room);
          room.hostUid = rest[0] ?? room.hostUid;
          for (const p of Object.values(room.players)) p.ready = false;
          room.status = "waiting";
          return true;
        }
        case "toss":
        case "playing":
        case "innings_break":
          room.players[uid].left = true;
          E.finishForfeit(room, uid, "left", now);
          return true;
        default:
          room.players[uid].left = true;
          room.rematch = null;
          return true;
      }
    });
  } catch (e) {
    if (!(e instanceof HttpsError && e.code === "not-found")) throw e;
  }
  if (deleteRoom) {
    await db().ref(`rooms/${code}`).remove();
    await db().ref(`moves/${code}`).remove();
  }
  return {};
}

// ---- Single callable entry point ---------------------------------------------

export const api = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const data = req.data ?? {};
  switch (data.action) {
    case "ping":
      return { now: Date.now() };
    case "createRoom":
      return createRoom(uid, data);
    case "joinRoom":
      return joinRoom(uid, data);
    case "setOvers":
      return setOvers(uid, data);
    case "ready":
      return ready(uid, data);
    case "chooseBatBowl":
      return chooseBatBowl(uid, data);
    case "tick":
      return tick(uid, data);
    case "requestRematch":
      return requestRematch(uid, data);
    case "leaveRoom":
      return leaveRoom(uid, data);
    default:
      throw new HttpsError("invalid-argument", "Unknown action.");
  }
});
