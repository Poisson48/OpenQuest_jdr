/**
 * dice.ts — Façade historique du moteur de dés (interface conservée pour
 * `ai-gm.ts`, `game_session.ts` et `types.ts`).
 *
 * La logique vit dans `./rules/dice_engine.ts` : grammaire enrichie
 * (modificateurs, tests de dés à poids, tags), RNG injectable, miroir du moteur
 * GDScript `game/scripts/core/rules/dice_engine.gd`.
 */

import { formatDiceResult, rollDice, type DiceRollOutcome } from "./rules/dice_engine.js";

export interface DiceRollResult {
  formula: string;
  rolls: number[];
  modifier: number;
  total: number;
  /** Champs enrichis (arbre de résultat) — optionnels pour la compatibilité. */
  kind?: "number" | "dice" | "comparison";
  tags?: string[];
  values?: number[];
  kept?: number[];
  dropped?: number[];
  success?: number;
  failure?: number;
}

export interface DiceRollError {
  error: string;
}

export type DiceResult = DiceRollResult | DiceRollError;

export function isDiceError(result: DiceResult): result is DiceRollError {
  return "error" in result;
}

export const Dice = {
  /**
   * Parse une formule de dés et retourne le résultat.
   * Formules de base : "1d20", "2d6+3", "1d8-1", "d%".
   * Extensions : "4d6keeph3", "1d20adv", "2d6expl", "5d10>=6{6:2}", tags "[degats]".
   */
  roll(formula: string): DiceResult {
    const outcome = rollDice(formula);
    if (!outcome.ok) {
      return { error: outcome.error };
    }
    return {
      formula: outcome.formula,
      rolls: outcome.rolls,
      modifier: outcome.modifier,
      total: outcome.total,
      kind: outcome.kind,
      tags: outcome.tags,
      values: outcome.values,
      kept: outcome.kept,
      dropped: outcome.dropped,
      success: outcome.success,
      failure: outcome.failure,
    };
  },

  formatResult(result: DiceResult): string {
    if (isDiceError(result)) {
      return result.error;
    }
    const outcome: DiceRollOutcome = {
      ok: true,
      formula: result.formula,
      kind: result.kind ?? "number",
      total: result.total,
      tags: result.tags ?? [],
      rolls: result.rolls,
      modifier: result.modifier,
      values: result.values,
      kept: result.kept,
      dropped: result.dropped,
      success: result.success,
      failure: result.failure,
    };
    return formatDiceResult(outcome);
  },
};
