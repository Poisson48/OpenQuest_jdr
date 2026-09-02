/**
 * Extended E2E pooling — room + characters + P2P address relay.
 * Run: node scripts/test-pooling-extended.mjs
 * Requires: npm run dev (pooling)
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

function waitFor(inbox, type, timeout = 5000) {
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

const SAMPLE_CHAR = {
  name: "TestHero",
  race: "Humain",
  class: "Guerrier",
  stats: { str: 14, dex: 12, con: 13, int: 10, wis: 11, cha: 10 },
  hp: 12,
  ac: 15,
  isPlayer: true,
  isHuman: true,
  isBot: false,
};

async function run() {
  console.log("Extended pooling E2E on", URL);

  const mj = await connect("MJ_Extended");
  await waitFor(mj.inbox, "welcome");
  ok("MJ connected");

  mj.send({ type: "create_room", role: "gm", roomName: "E2E Extended" });
  const hostAssigned = await waitFor(mj.inbox, "host_assigned");
  if (hostAssigned.hostId) ok("MJ received host_assigned");
  else fail("MJ received host_assigned", JSON.stringify(hostAssigned));

  const roomUpdate = await waitFor(mj.inbox, "room_update");
  const code = roomUpdate.room.code;
  if (!/^\d{4}$/.test(code)) throw new Error("Invalid room code: " + code);
  ok(`MJ created room ${code}`);

  mj.send({ type: "register_character", character: { ...SAMPLE_CHAR, name: "MJ_Char" } });
  await sleep(300);
  const mjCharUpdate = mj.inbox.find((m) => m.type === "room_update");
  if (mjCharUpdate?.room?.players?.some((p) => p.character?.name === "MJ_Char")) {
    ok("MJ character registered");
  } else {
    fail("MJ character registered", "character not in room_update");
  }

  mj.send({ type: "set_p2p_host", address: "127.0.0.1:7777" });
  await sleep(300);
  const p2pUpdate = mj.inbox.filter((m) => m.type === "room_update").pop();
  if (p2pUpdate?.room?.p2pHost === "127.0.0.1:7777") {
    ok("P2P host address published");
  } else {
    fail("P2P host address published", `p2pHost=${p2pUpdate?.room?.p2pHost}`);
  }

  const player = await connect("Player_Extended");
  await waitFor(player.inbox, "welcome");
  ok("Player connected");

  player.send({ type: "join_room", code });
  const joined = await waitFor(player.inbox, "room_update");
  if (joined.room.players.length === 2) ok("Player joined (2 in room)");
  else fail("Player joined", `players=${joined.room.players.length}`);

  if (joined.room.p2pHost === "127.0.0.1:7777") ok("Player sees P2P address");
  else fail("Player sees P2P address", `p2pHost=${joined.room.p2pHost}`);

  player.send({ type: "register_character", character: { ...SAMPLE_CHAR, name: "Player_Char" } });
  await sleep(300);
  const playerCharSeen = mj.inbox.some(
    (m) =>
      m.type === "room_update" &&
      m.room?.players?.some((p) => p.character?.name === "Player_Char"),
  );
  if (playerCharSeen) ok("Player character visible to MJ");
  else fail("Player character visible to MJ", "not in MJ inbox");

  mj.send({ type: "start_game", scenarioId: "demo-crypte", party: [], mode: "multi" });
  await sleep(300);
  const startErr = mj.inbox.find((m) => m.type === "error");
  if (startErr?.message?.includes("inconnu") || startErr?.message?.includes("start_game")) {
    ok("start_game rejected in pooling mode (expected — Phase 3)");
  } else if (startErr) {
    ok(`start_game rejected: ${startErr.message}`);
  } else {
    fail("start_game rejected in pooling mode", "no error received");
  }

  mj.ws.close();
  player.ws.close();
  await sleep(200);

  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

run().catch((e) => {
  console.error("Fatal:", e.message);
  console.error("Is the server running in pooling mode? cd server && npm run dev");
  process.exit(1);
});
