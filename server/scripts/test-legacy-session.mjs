/**
 * E2E legacy mode — host + player reach game_started (session screen path).
 * Run: LEGACY_MODE=1 npm run dev  (then) node scripts/test-legacy-session.mjs
 */
import WebSocket from "ws";

const URL = process.env.POOLING_URL ?? "ws://127.0.0.1:8080";
const SCENARIO_ID = "demo-crypte";

function connect(name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${URL}?name=${encodeURIComponent(name)}`);
    const inbox = [];
    ws.on("open", () => resolve({ ws, inbox, send: (m) => ws.send(JSON.stringify(m)) }));
    ws.on("message", (d) => inbox.push(JSON.parse(d.toString())));
    ws.on("error", reject);
  });
}

function waitFor(inbox, type, timeout = 8000) {
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

const CHAR = {
  name: "Hero",
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
  console.log("Legacy session E2E on", URL);

  const host = await connect("Host_Legacy");
  await waitFor(host.inbox, "welcome");
  host.send({ type: "join", playerName: "Host_Legacy" });
  await waitFor(host.inbox, "lobby_update");
  ok("Host connected to legacy lobby");

  const player = await connect("Player_Legacy");
  await waitFor(player.inbox, "welcome");
  player.send({ type: "join", playerName: "Player_Legacy" });
  const lobby = await waitFor(player.inbox, "lobby_update");
  if (lobby.players?.length === 2) ok("Player in legacy lobby (2 players)");
  else fail("Player in legacy lobby", `players=${lobby.players?.length}`);

  host.send({ type: "register_character", character: CHAR });
  player.send({ type: "register_character", character: { ...CHAR, name: "PlayerHero" } });
  await sleep(300);

  host.send({
    type: "start_game",
    scenarioId: SCENARIO_ID,
    party: [CHAR],
    mode: "multi",
    gmType: "ai",
    questFormat: "oneshot",
    partySizeTarget: 2,
    fillWithBots: false,
  });

  const hostStarted = await waitFor(host.inbox, "game_started");
  const playerStarted = await waitFor(player.inbox, "game_started");

  if (hostStarted.gameId && hostStarted.state?.party?.length >= 1) {
    ok(`Host received game_started (${hostStarted.state.party.length} party members)`);
  } else {
    fail("Host received game_started", JSON.stringify(hostStarted).slice(0, 200));
  }

  if (playerStarted.gameId === hostStarted.gameId) {
    ok("Player received same game_started");
  } else {
    fail("Player received same game_started", `host=${hostStarted.gameId} player=${playerStarted.gameId}`);
  }

  host.ws.close();
  player.ws.close();

  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

run().catch((e) => {
  console.error("Fatal:", e.message);
  console.error("Start server with: $env:LEGACY_MODE='1'; npm run dev");
  process.exit(1);
});
