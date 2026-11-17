/**
 * test_dice_engine.ts — Vérifie le moteur TS contre les cas partagés
 * `game/data/tests/dice_cases.json` (les mêmes que le test GDScript).
 *
 * ARCHIVÉ (phase 5.2 / ADR-005) : ce test n'est plus exécuté par `npm test`
 * (le serveur n'a plus de moteur de dés exécutable ; seule l'implémentation
 * GDScript de `game/scripts/core/rules/dice_engine.gd` est active).
 * Il reste exécutable manuellement depuis `server/` :
 *
 *   npx tsx legacy/scripts/test_dice_engine.ts
 *
 * Restauration complète : voir `server/legacy/README.md`.
 */

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { formatDiceResult, rollDice, type DiceRollOutcome } from "../rules/dice_engine.js";
import { Dice, isDiceError } from "../dice.js";

interface SharedCase {
  name: string;
  formula: string;
  rolls?: number[];
  expect: Record<string, unknown>;
}

const scriptDir = dirname(fileURLToPath(import.meta.url));
const casesPath = resolve(scriptDir, "..", "..", "..", "game", "data", "tests", "dice_cases.json");

let checks = 0;
let failures = 0;

function fail(message: string): void {
  failures += 1;
  console.log(`dice_engine_test:FAIL ${message}`);
}

function check(label: string, actual: unknown, expected: unknown): void {
  checks += 1;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    fail(`${label} attendu=${e} obtenu=${a}`);
  }
}

function main(): void {
  const raw = readFileSync(casesPath, "utf8");
  const parsed = JSON.parse(raw) as { cases?: SharedCase[] };
  const cases = parsed.cases ?? [];
  if (cases.length === 0) {
    fail(`aucun cas dans ${casesPath}`);
    finish();
    return;
  }

  for (const testCase of cases) {
    const outcome = rollDice(testCase.formula, { rolls: testCase.rolls ?? [] });
    const expect = testCase.expect ?? {};

    for (const key of Object.keys(expect)) {
      const expected = expect[key];
      switch (key) {
        case "ok":
          check(`${testCase.name}.ok`, outcome.ok, expected);
          break;
        case "kind":
          check(`${testCase.name}.kind`, outcome.ok ? outcome.kind : "", expected);
          break;
        case "total":
          check(`${testCase.name}.total`, outcome.ok ? outcome.total : null, expected);
          break;
        case "modifier":
          check(`${testCase.name}.modifier`, outcome.ok ? outcome.modifier : null, expected);
          break;
        case "success":
          check(`${testCase.name}.success`, outcome.ok ? outcome.success ?? null : null, expected);
          break;
        case "failure":
          check(`${testCase.name}.failure`, outcome.ok ? outcome.failure ?? null : null, expected);
          break;
        case "rolls":
          check(`${testCase.name}.rolls`, outcome.ok ? outcome.rolls : [], expected);
          break;
        case "kept":
          check(`${testCase.name}.kept`, outcome.ok ? outcome.kept ?? [] : [], expected);
          break;
        case "dropped":
          check(`${testCase.name}.dropped`, outcome.ok ? outcome.dropped ?? [] : [], expected);
          break;
        case "tags":
          check(`${testCase.name}.tags`, outcome.ok ? outcome.tags : [], expected);
          break;
        default:
          check(`${testCase.name}.${key}`, null, expected);
      }
    }

    if (expect.ok === false) {
      checks += 1;
      const hasMessage = !outcome.ok && outcome.error.length > 0;
      if (!hasMessage) {
        fail(`${testCase.name}.message d'erreur manquant`);
      }
    }
  }

  checkDeterminism();
  checkFormat();
  checkFacade();
  finish();
}

function checkDeterminism(): void {
  const a = rollDice("4d6keeph3[degats]", { rolls: [3, 5, 1, 6] });
  const b = rollDice("4d6keeph3[degats]", { rolls: [3, 5, 1, 6] });
  check("determinism.scripted", a, b);

  const seededA = rollDice("10d100", { seed: 4242 });
  const seededB = rollDice("10d100", { seed: 4242 });
  check("determinism.seed", seededA, seededB);
  check("determinism.seed.size", seededA.ok ? (seededA.values ?? []).length : 0, 10);

  const empty = rollDice("1d6", { rolls: [] });
  check("determinism.empty_sequence", empty.ok, false);
}

function checkFormat(): void {
  const outcome = rollDice("4d6keeph3", { rolls: [3, 5, 1, 6] });
  const text = formatDiceResult(outcome);
  checks += 3;
  if (!text.includes("14")) {
    fail(`format.total manquant dans "${text}"`);
  }
  if (!text.includes("3, 5, 6")) {
    fail(`format.dés retenus manquants dans "${text}"`);
  }
  if (!text.includes("défaussés : 1")) {
    fail(`format.défaussés manquants dans "${text}"`);
  }

  const sumCmp = formatDiceResult(rollDice("1d20+5>=15", { rolls: [10] }));
  checks += 2;
  if (!sumCmp.includes("réussite")) {
    fail(`format.comparaison de sommes (réussite) manquante dans "${sumCmp}"`);
  }
  if (sumCmp.includes("succès")) {
    fail(`format.comparaison de sommes : faux succès dans "${sumCmp}"`);
  }

  const pool = formatDiceResult(rollDice("5d10>=6", { rolls: [1, 6, 7, 10, 3] }));
  checks += 1;
  if (!pool.includes("3 succès")) {
    fail(`format.test de dés (succès) manquant dans "${pool}"`);
  }

  const invalid = rollDice("abc");
  checks += 1;
  if (!formatDiceResult(invalid).startsWith("Erreur : ")) {
    fail(`format.erreur inattendue : "${formatDiceResult(invalid)}"`);
  }
}

function checkFacade(): void {
  const legacy = Dice.roll("2d6+3");
  checks += 3;
  if (isDiceError(legacy)) {
    fail(`façade.roll en erreur : ${legacy.error}`);
    return;
  }
  if (typeof legacy.total !== "number" || legacy.rolls.length !== 2) {
    fail(`façade.roll résultat inattendu : ${JSON.stringify(legacy)}`);
  }
  if (!Dice.formatResult(legacy).includes(String(legacy.total))) {
    fail("façade.formatResult sans total");
  }

  const invalid = Dice.roll("pas un dé");
  checks += 1;
  if (!isDiceError(invalid)) {
    fail("façade.roll devrait échouer sur une formule invalide");
  }
}

function finish(): void {
  if (failures > 0) {
    console.log(`dice_engine_test:FAIL ${failures} échec(s) sur ${checks} vérifications`);
    process.exitCode = 1;
    return;
  }
  console.log(`dice_engine_test:PASS ${checks} vérifications`);
}

main();
