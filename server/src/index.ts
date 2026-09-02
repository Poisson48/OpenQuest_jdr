import "dotenv/config";

const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST ?? "0.0.0.0";

const { startPoolingServer } = await import("./pooling/server.js");
startPoolingServer({ port: PORT, host: HOST });
