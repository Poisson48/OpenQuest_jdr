import "dotenv/config";

const LEGACY_MODE = process.env.LEGACY_MODE === "1";
const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST ?? "0.0.0.0";

if (LEGACY_MODE) {
  await import("./legacy/server.js");
} else {
  const { startPoolingServer } = await import("./pooling/server.js");
  startPoolingServer({ port: PORT, host: HOST });
}
