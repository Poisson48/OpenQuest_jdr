/**
 * phrase_pools.ts — Pools de phrases et mémoire anti-répétition.
 * Extrait de ai-gm.ts (Phase 5 refactor).
 */

import type { AiState } from "../game_types.js";

export const MAX_MEMORY = 12;

export type Vars = Record<string, string | number>;

/** Remplace les variables {nom} dans un texte. */
export function applyVars(text: string, vars: Vars): string {
  let result = text;
  Object.entries(vars).forEach(([k, v]) => {
    result = result.replace(new RegExp(`\\{${k}\\}`, "g"), String(v));
  });
  return result;
}

/** Choisit une phrase dans `pool` sans répéter les récentes pour cette catégorie. */
export function pick(state: AiState, category: string, pool: string[], vars: Vars = {}): string {
  if (!pool.length) return "";
  if (!state.narrativeMemory) state.narrativeMemory = {};
  if (!state.narrativeMemory[category]) state.narrativeMemory[category] = [];

  const used = state.narrativeMemory[category];
  let indices = pool.map((_, i) => i).filter((i) => !used.includes(i));
  if (indices.length === 0) {
    state.narrativeMemory[category] = [];
    indices = pool.map((_, i) => i);
  }

  const idx = indices[Math.floor(Math.random() * indices.length)];
  used.push(idx);
  if (used.length > MAX_MEMORY) used.shift();

  return applyVars(pool[idx], vars);
}
