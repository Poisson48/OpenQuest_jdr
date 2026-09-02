/**
 * Test E2E pooling MJ rules — run: node scripts/test-pooling.mjs
 * Requires server running: npm run dev (in server/)
 */
import WebSocket from "ws";

const URL = process.env.POOLING_URL ?? "ws://127.0.0.1:8080";

function connect(name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${URL}?name=${encodeURIComponent(name)}`);
    const inbox = [];
    ws.on("open", () => resolve({ ws, inbox, send: (m) => ws.send(JSON.stringify(m)) }));
    ws.on("message", (d) => inbox.push(JSON.parse(d.toString())));
    ws.on("error", reject);
  });
}

function waitFor(inbox, type, timeout = 3000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const check = () => {
      const idx = inbox.findIndex((m) => m.type === type);
      if (idx >= 0) return resolve(inbox.splice(idx, 1)[0]);
      if (Date.now() - start > timeout) return reject(new Error(`Timeout waiting for ${type}`));
      setTimeout(check, 50);
    };
    check();
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

let passed = 0;
let failed = 0;

function ok(label) {
  passed++;
  console.log(`  ✓ ${label}`);
}

function fail(label, err) {
  failed++;
  console.error(`  ✗ ${label}: ${err}`);
}

async function run() {
  console.log("Test pooling MJ rules on", URL);

  const mj = await connect("MJ_Test");
  await waitFor(mj.inbox, "welcome");
  ok("MJ connected");

  mj.send({ type: "create_room", role: "gm", roomName: "Test Partie" });
  const roomUpdate = await waitFor(mj.inbox, "room_update");
  const code = roomUpdate.room.code;
  if (!/^\d{4}$/.test(code)) throw new Error("Invalid room code: " + code);
  ok(`MJ created room ${code}`);

  const player = await connect("Joueur_Test");
  await waitFor(player.inbox, "welcome");
  ok("Player connected");

  player.send({ type: "create_room", role: "player" });
  const notGm = await waitFor(player.inbox, "error");
  if (notGm.code === "NOT_GM" || notGm.message.includes("MJ")) ok("Non-MJ create rejected");
  else fail("Non-MJ create rejected", JSON.stringify(notGm));

  player.send({ type: "join_room", code });
  const joined = await waitFor(player.inbox, "room_update");
  if (joined.room.players.length === 2) ok("Player joined room");
  else fail("Player joined room", `players=${joined.room.players.length}`);

  await sleep(200);
  mj.inbox.length = 0;
  player.inbox.length = 0;

  mj.ws.close();
  await sleep(300);

  try {
    const closed = await waitFor(player.inbox, "room_closed", 2000);
    if (closed.reason === "gm_disconnected" || closed.reason === "gm_left") {
      ok(`Room closed on MJ disconnect (${closed.reason})`);
    } else {
      fail("Room closed on MJ disconnect", closed.reason);
    }
  } catch (e) {
    fail("Room closed on MJ disconnect", e.message);
  }

  player.send({ type: "rejoin_room", code });
  try {
    await waitFor(player.inbox, "error", 1500);
    ok("Rejoin fails after MJ left (room gone)");
  } catch {
    fail("Rejoin fails after MJ left", "expected error");
  }

  player.ws.close();

  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

run().catch((e) => {
  console.error("Fatal:", e.message);
  console.error("Is the server running? cd server && npm run dev");
  process.exit(1);
});
