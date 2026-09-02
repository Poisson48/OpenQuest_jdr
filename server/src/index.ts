import "dotenv/config";

const LEGACY_MODE = process.env.LEGACY_MODE === "1";

if (LEGACY_MODE) {
  await import("./legacy/server.js");
} else {
  await import("./lobby/server.js");
}
