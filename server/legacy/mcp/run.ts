/**
 * run.ts — Point d'entrée autonome du serveur MCP OpenQuest JDR.
 * Démarre `gm_server.ts` sur un transport stdio (compatible avec les clients
 * MCP standards : Claude Desktop, Cursor, etc.).
 *
 * Utilisation : `npm run mcp` (voir server/package.json).
 */

import "dotenv/config";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createGmServer, LLM_NARRATION_ENABLED } from "./gm_server.js";

async function main(): Promise<void> {
  const server = createGmServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // stdout est réservé au protocole JSON-RPC MCP : tout log applicatif doit
  // aller sur stderr pour ne pas corrompre le flux.
  console.error(
    `[openquest-mcp] Serveur MCP démarré (stdio). Narration LLM : ${LLM_NARRATION_ENABLED ? "activée" : "désactivée (rule-based uniquement)"}.`,
  );
}

main().catch((err) => {
  console.error("[openquest-mcp] Échec du démarrage du serveur MCP :", err);
  process.exit(1);
});
