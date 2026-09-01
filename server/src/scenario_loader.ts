import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { Scenario } from "./game_types.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCENARIOS_DIR = path.resolve(__dirname, "../../data/scenarios");

let cache: Scenario[] | null = null;

export async function loadAllScenarios(): Promise<Scenario[]> {
  if (cache) return cache;
  const files = await fs.readdir(SCENARIOS_DIR);
  const scenarios: Scenario[] = [];
  for (const file of files) {
    if (!file.endsWith(".json")) continue;
    const raw = await fs.readFile(path.join(SCENARIOS_DIR, file), "utf-8");
    scenarios.push(JSON.parse(raw) as Scenario);
  }
  cache = scenarios;
  return scenarios;
}

export async function loadScenario(id: string): Promise<Scenario | null> {
  const all = await loadAllScenarios();
  return all.find((s) => s.id === id) ?? null;
}
