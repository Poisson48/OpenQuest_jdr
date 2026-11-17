/**
 * dice_engine.ts — Moteur de dés OpenQuest (miroir TypeScript du moteur GDScript).
 *
 * Même grammaire et même arbre de résultat que `game/scripts/core/rules/dice_engine.gd` ;
 * les deux implémentations sont validées par les cas partagés
 * `game/data/tests/dice_cases.json`.
 *
 * Grammaire v1 :
 *   expression  = comparison ;
 *   comparison  = sum { ( ">=" | "<=" | ">" | "<" | "=" | "!=" ) sum [ weights ] } ;
 *   weights     = "{" integer ":" integer { "," integer ":" integer } "}" ;
 *   sum         = term { ( "+" | "-" ) term } ;
 *   term        = unary { ( "*" | "/" ) unary } ;
 *   unary       = { "-" } primary ;
 *   primary     = dice | integer | "(" expression ")" ;
 *   dice        = [ integer ] "d" ( integer | "%" ) { modifier } [ "[" tags "]" ] ;
 *   modifier    = "keeph" n | "keepl" n | "adv" | "disadv" | "expl"
 *               | "reroll" | "min" n | "max" n ;
 *
 * RNG injectable : `opts.rng`, `opts.seed` ou `opts.rolls` (valeurs imposées).
 */

export const MAX_DICE_TOTAL = 500;
export const MAX_DICE_COUNT = 100;
export const MAX_SIDES = 1000;
export const MAX_FORMULA_LENGTH = 255;
export const MAX_EXPLOSIONS_PER_DIE = 20;
export const MAX_PARSE_DEPTH = 32;
export const MAX_WEIGHT_ENTRIES = 64;

const MODIFIER_NAMES = ["keeph", "keepl", "adv", "disadv", "expl", "reroll", "min", "max"] as const;
const COMPARISON_OPS = [">=", "<=", ">", "<", "=", "==", "!="] as const;

export type DiceKind = "number" | "dice" | "comparison";
export type Rng = (min: number, max: number) => number;

export interface RollOptions {
  rng?: Rng;
  seed?: number;
  rolls?: number[];
}

/** Résultat d'un nœud évalué (interne, puis aplati en `DiceRollResult`). */
interface NodeResult {
  kind: DiceKind;
  total: number;
  tags?: string[];
  children?: NodeResult[];
  op?: string;
  sides?: number;
  count?: number;
  values?: number[];
  kept?: number[];
  dropped?: number[];
  left?: NodeResult;
  right?: NodeResult;
  success?: number;
  failure?: number;
  weights?: Record<number, number>;
}

export interface DiceRollResult extends NodeResult {
  ok: true;
  formula: string;
  tags: string[];
  rolls: number[];
  modifier: number;
}

export interface DiceRollError {
  ok: false;
  error: string;
  formula: string;
}

export type DiceRollOutcome = DiceRollResult | DiceRollError;

interface EvalContext {
  rng: Rng;
  rolled: number;
  error: string;
}

interface Modifier {
  name: string;
  value: number;
}

type Token =
  | { t: "int"; v: number }
  | { t: "word"; v: string }
  | { t: "op"; v: string }
  | { t: "eof"; v: string };

interface Parser {
  toks: Token[];
  i: number;
  error: string;
  depth: number;
}

type Ast =
  | { t: "num"; v: number }
  | { t: "neg"; v: Ast }
  | { t: "bin"; op: string; l: Ast; r: Ast }
  | { t: "dice"; count: number; sides: number; mods: Modifier[]; tags: string[] }
  | { t: "cmp"; op: string; l: Ast; r: Ast; weights: Record<number, number> };

// ===========================================================================
// API publique
// ===========================================================================

export function rollDice(formula: string, opts: RollOptions = {}): DiceRollOutcome {
  const src = formula.trim();
  if (src.length === 0) {
    return { ok: false, error: "Formule vide.", formula };
  }
  if (src.length > MAX_FORMULA_LENGTH) {
    return { ok: false, error: `Formule trop longue (max ${MAX_FORMULA_LENGTH}).`, formula };
  }

  const toks = lex(src.toLowerCase());
  if (toks.length === 0) {
    return { ok: false, error: "Formule invalide.", formula };
  }

  const p: Parser = { toks, i: 0, error: "", depth: 0 };
  const ast = parseExpression(p);
  if (p.error !== "") {
    return { ok: false, error: p.error, formula };
  }
  if (p.i < toks.length) {
    const leftover = toks[p.i];
    return { ok: false, error: `Symbole inattendu : '${tokenText(leftover)}'.`, formula };
  }

  const ctx: EvalContext = { rng: makeRng(opts), rolled: 0, error: "" };
  const node = evalNode(ast, ctx);
  if (ctx.error !== "") {
    return { ok: false, error: ctx.error, formula };
  }

  const rolls = collectRolls(node);
  const rollsSum = rolls.reduce((acc, v) => acc + v, 0);
  return {
    ...node,
    ok: true,
    formula: src,
    tags: node.tags ?? [],
    rolls,
    modifier: node.kind === "comparison" ? 0 : node.total - rollsSum,
  };
}

export function formatDiceResult(result: DiceRollOutcome): string {
  if (!result.ok) {
    return `Erreur : ${result.error}`;
  }
  let text: string;
  if (result.kind === "comparison") {
    const isPoolTest = result.left?.kind === "dice";
    if (isPoolTest) {
      text = `🎲 **${result.total} succès**`;
      if ((result.failure ?? 0) > 0) {
        text += ` / ${result.failure} échec(s)`;
      }
      text += ` (${result.formula})`;
    } else {
      const target = result.right?.total ?? 0;
      const verdict = (result.success ?? 0) >= 1 ? "réussite" : "échec";
      text = `🎲 **${result.total}** vs ${target} — ${verdict} (${result.formula})`;
    }
  } else {
    text = `🎲 **${result.total}** (${result.formula})`;
  }
  text += formatDiceDetail(result);
  if (result.tags.length > 0) {
    text += ` [${result.tags.join(", ")}]`;
  }
  return text;
}

// ===========================================================================
// Lexer
// ===========================================================================

function isDigit(ch: string): boolean {
  return ch >= "0" && ch <= "9";
}

function isAlpha(ch: string): boolean {
  return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch === "_";
}

function tokenText(tok: Token): string {
  return String(tok.v);
}

function lex(src: string): Token[] {
  const toks: Token[] = [];
  let i = 0;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r") {
      i += 1;
      continue;
    }
    if (isDigit(ch)) {
      const start = i;
      while (i < n && isDigit(src[i])) {
        i += 1;
      }
      toks.push({ t: "int", v: parseInt(src.slice(start, i), 10) });
      continue;
    }
    if (isAlpha(ch)) {
      const start = i;
      while (i < n && isAlpha(src[i])) {
        i += 1;
      }
      toks.push({ t: "word", v: src.slice(start, i) });
      continue;
    }
    const two = src.slice(i, i + 2);
    if (two === ">=" || two === "<=" || two === "!=" || two === "==") {
      toks.push({ t: "op", v: two });
      i += 2;
      continue;
    }
    if ("+-*/><=()[]{} ,:%".includes(ch)) {
      toks.push({ t: "op", v: ch });
      i += 1;
      continue;
    }
    return [];
  }
  return toks;
}

// ===========================================================================
// Parser
// ===========================================================================

function peek(p: Parser): Token {
  return p.toks[p.i] ?? { t: "eof", v: "" };
}

function advance(p: Parser): Token {
  const tok = peek(p);
  p.i += 1;
  return tok;
}

function isOp(p: Parser, v: string): boolean {
  const tok = peek(p);
  return tok.t === "op" && tok.v === v;
}

function parseExpression(p: Parser): Ast {
  if (p.depth > MAX_PARSE_DEPTH) {
    p.error = "Expression trop profonde.";
    return { t: "num", v: 0 };
  }
  p.depth += 1;
  const left = parseSum(p);
  if (p.error !== "") {
    p.depth -= 1;
    return left;
  }
  const tok = peek(p);
  if (tok.t === "op" && (COMPARISON_OPS as readonly string[]).includes(tok.v)) {
    const op = String(advance(p).v);
    const right = parseSum(p);
    if (p.error !== "") {
      p.depth -= 1;
      return left;
    }
    const weights: Record<number, number> = {};
    if (isOp(p, "{")) {
      advance(p);
      let entries = 0;
      while (!isOp(p, "}")) {
        const keyTok = advance(p);
        if (keyTok.t !== "int") {
          p.error = "Poids invalide : {face:poids} attendu.";
          p.depth -= 1;
          return left;
        }
        if (!isOp(p, ":")) {
          p.error = "Poids invalide : ':' attendu.";
          p.depth -= 1;
          return left;
        }
        advance(p);
        const valTok = advance(p);
        if (valTok.t !== "int") {
          p.error = "Poids invalide : poids entier attendu.";
          p.depth -= 1;
          return left;
        }
        weights[keyTok.v] = valTok.v;
        entries += 1;
        if (entries > MAX_WEIGHT_ENTRIES) {
          p.error = `Trop d'entrées de poids (max ${MAX_WEIGHT_ENTRIES}).`;
          p.depth -= 1;
          return left;
        }
        if (isOp(p, ",")) {
          advance(p);
          continue;
        }
        break;
      }
      if (!isOp(p, "}")) {
        p.error = "Poids non fermés : '}' attendu.";
        p.depth -= 1;
        return left;
      }
      advance(p);
    }
    p.depth -= 1;
    return { t: "cmp", op, l: left, r: right, weights };
  }
  p.depth -= 1;
  return left;
}

function parseSum(p: Parser): Ast {
  let left = parseTerm(p);
  while (p.error === "" && (isOp(p, "+") || isOp(p, "-"))) {
    const op = String(advance(p).v);
    const right = parseTerm(p);
    if (p.error !== "") {
      return left;
    }
    left = { t: "bin", op, l: left, r: right };
  }
  return left;
}

function parseTerm(p: Parser): Ast {
  let left = parseUnary(p);
  while (p.error === "" && (isOp(p, "*") || isOp(p, "/"))) {
    const op = String(advance(p).v);
    const right = parseUnary(p);
    if (p.error !== "") {
      return left;
    }
    left = { t: "bin", op, l: left, r: right };
  }
  return left;
}

function parseUnary(p: Parser): Ast {
  if (isOp(p, "-")) {
    advance(p);
    const inner = parseUnary(p);
    return { t: "neg", v: inner };
  }
  return parsePrimary(p);
}

function parsePrimary(p: Parser): Ast {
  const tok = peek(p);
  if (tok.t === "int") {
    const count = tok.v;
    advance(p);
    const nxt = peek(p);
    if (nxt.t === "word" && nxt.v === "d") {
      return parseDice(p, count);
    }
    return { t: "num", v: count };
  }
  if (tok.t === "word" && tok.v === "d") {
    return parseDice(p, 1);
  }
  if (isOp(p, "(")) {
    advance(p);
    const inner = parseExpression(p);
    if (p.error !== "") {
      return inner;
    }
    if (!isOp(p, ")")) {
      p.error = "Parenthèse non fermée.";
      return inner;
    }
    advance(p);
    return inner;
  }
  p.error = `Symbole inattendu : '${tokenText(tok)}'.`;
  return { t: "num", v: 0 };
}

function parseDice(p: Parser, count: number): Ast {
  advance(p); // 'd'
  const tok = peek(p);
  let sides = 0;
  if (tok.t === "int") {
    sides = advance(p).v as number;
  } else if (isOp(p, "%")) {
    advance(p);
    sides = 100;
  } else {
    p.error = "Dé sans nombre de faces (ex. 1d6).";
    return { t: "dice", count, sides: 0, mods: [], tags: [] };
  }

  const mods: Modifier[] = [];
  while (peek(p).t === "word" && (MODIFIER_NAMES as readonly string[]).includes(String(peek(p).v))) {
    const modName = String(advance(p).v);
    let modValue = 0;
    if (peek(p).t === "int") {
      modValue = advance(p).v as number;
    }
    if ((modName === "keeph" || modName === "keepl" || modName === "min" || modName === "max") && modValue <= 0) {
      p.error = `Modificateur '${modName}' : valeur positive attendue.`;
      return { t: "dice", count, sides, mods, tags: [] };
    }
    mods.push({ name: modName, value: modValue });
  }

  const tags: string[] = [];
  if (isOp(p, "[")) {
    advance(p);
    for (;;) {
      const tagTok = advance(p);
      if (tagTok.t !== "word") {
        p.error = "Tag invalide (identifiant attendu).";
        return { t: "dice", count, sides, mods, tags };
      }
      tags.push(tagTok.v);
      if (isOp(p, ",")) {
        advance(p);
        continue;
      }
      break;
    }
    if (!isOp(p, "]")) {
      p.error = "Tag non fermé : ']' attendu.";
      return { t: "dice", count, sides, mods, tags };
    }
    advance(p);
  }

  if (count < 1 || count > MAX_DICE_COUNT) {
    p.error = `Nombre de dés hors limites (1-${MAX_DICE_COUNT}).`;
    return { t: "dice", count, sides, mods, tags };
  }
  if (sides < 2 || sides > MAX_SIDES) {
    p.error = `Nombre de faces hors limites (2-${MAX_SIDES}).`;
    return { t: "dice", count, sides, mods, tags };
  }
  return { t: "dice", count, sides, mods, tags };
}

// ===========================================================================
// Évaluation
// ===========================================================================

function evalNode(node: Ast, ctx: EvalContext): NodeResult {
  if (node.t === "num") {
    return { kind: "number", total: node.v };
  }
  if (node.t === "neg") {
    const inner = evalNode(node.v, ctx);
    return { kind: "number", total: -inner.total, children: [inner] };
  }
  if (node.t === "bin") {
    const left = evalNode(node.l, ctx);
    if (ctx.error !== "") {
      return { kind: "number", total: 0 };
    }
    const right = evalNode(node.r, ctx);
    if (ctx.error !== "") {
      return { kind: "number", total: 0 };
    }
    let total = 0;
    if (node.op === "+") {
      total = left.total + right.total;
    } else if (node.op === "-") {
      total = left.total - right.total;
    } else if (node.op === "*") {
      total = left.total * right.total;
    } else {
      if (right.total === 0) {
        ctx.error = "Division par zéro.";
        return { kind: "number", total: 0 };
      }
      total = Math.trunc(left.total / right.total);
    }
    return { kind: "number", total, children: [left, right], op: node.op };
  }
  if (node.t === "dice") {
    return evalDice(node, ctx);
  }
  const left = evalNode(node.l, ctx);
  if (ctx.error !== "") {
    return { kind: "number", total: 0 };
  }
  const right = evalNode(node.r, ctx);
  if (ctx.error !== "") {
    return { kind: "number", total: 0 };
  }
  return evalComparison(node.op, left, right, node.weights);
}

function evalDice(node: Extract<Ast, { t: "dice" }>, ctx: EvalContext): NodeResult {
  const count = node.count;
  const sides = node.sides;
  const mods = node.mods;

  const hasMod = (name: string): boolean => mods.some((m) => m.name === name);
  const hasAdv = hasMod("adv");
  const hasDisadv = hasMod("disadv");
  const rollCount = count * (hasAdv || hasDisadv ? 2 : 1);

  const values: number[] = [];
  for (let i = 0; i < rollCount; i += 1) {
    const v = rollOne(sides, ctx);
    if (ctx.error !== "") {
      return { kind: "dice", total: 0 };
    }
    values.push(v);
  }

  if (hasMod("expl")) {
    const queue: number[] = values.map((_v, i) => i);
    let q = 0;
    while (q < queue.length) {
      let dieIndex = queue[q];
      q += 1;
      let guard = 0;
      while (values[dieIndex] === sides && guard < MAX_EXPLOSIONS_PER_DIE) {
        const bonus = rollOne(sides, ctx);
        if (ctx.error !== "") {
          return { kind: "dice", total: 0 };
        }
        values.push(bonus);
        queue.push(values.length - 1);
        dieIndex = values.length - 1;
        guard += 1;
      }
    }
  }

  if (hasMod("reroll")) {
    for (let i = 0; i < values.length; i += 1) {
      if (values[i] === 1) {
        const rerolled = rollOne(sides, ctx);
        if (ctx.error !== "") {
          return { kind: "dice", total: 0 };
        }
        values[i] = rerolled;
      }
    }
  }

  for (const m of mods) {
    if (m.name === "min") {
      for (let i = 0; i < values.length; i += 1) {
        values[i] = Math.max(values[i], m.value);
      }
    } else if (m.name === "max") {
      for (let i = 0; i < values.length; i += 1) {
        values[i] = Math.min(values[i], m.value);
      }
    }
  }

  let keepCount = -1;
  let keepHigh = true;
  for (const m of mods) {
    if (m.name === "keeph") {
      keepCount = m.value;
      keepHigh = true;
    } else if (m.name === "keepl") {
      keepCount = m.value;
      keepHigh = false;
    }
  }
  if (hasAdv && !hasDisadv) {
    keepCount = count;
    keepHigh = true;
  } else if (hasDisadv && !hasAdv) {
    keepCount = count;
    keepHigh = false;
  }

  const kept: number[] = [];
  const dropped: number[] = [];
  if (keepCount >= 0 && keepCount < values.length) {
    const order = values.map((_v, i) => i);
    order.sort((a, b) => {
      if (values[a] === values[b]) {
        return a - b;
      }
      if (keepHigh) {
        return values[b] - values[a];
      }
      return values[a] - values[b];
    });
    const keepSet = new Set(order.slice(0, keepCount));
    for (let i = 0; i < values.length; i += 1) {
      if (keepSet.has(i)) {
        kept.push(values[i]);
      } else {
        dropped.push(values[i]);
      }
    }
  } else {
    kept.push(...values);
  }

  return {
    kind: "dice",
    sides,
    count,
    values: [...values],
    kept,
    dropped,
    tags: [...node.tags],
    total: kept.reduce((acc, v) => acc + v, 0),
  };
}

function evalComparison(
  op: string,
  left: NodeResult,
  right: NodeResult,
  weights: Record<number, number>,
): NodeResult {
  const target = right.total;
  if (left.kind === "dice") {
    let success = 0;
    let failure = 0;
    for (const v of left.kept ?? []) {
      if (compare(v, op, target)) {
        success += weights[v] ?? 1;
      } else {
        failure += 1;
      }
    }
    return { kind: "comparison", op, left, right, success, failure, total: success };
  }
  const cond = compare(left.total, op, target);
  return {
    kind: "comparison",
    op,
    left,
    right,
    success: cond ? 1 : 0,
    failure: cond ? 0 : 1,
    total: left.total,
  };
}

function compare(a: number, op: string, b: number): boolean {
  switch (op) {
    case ">=":
      return a >= b;
    case "<=":
      return a <= b;
    case ">":
      return a > b;
    case "<":
      return a < b;
    case "=":
    case "==":
      return a === b;
    case "!=":
      return a !== b;
    default:
      return false;
  }
}

function rollOne(sides: number, ctx: EvalContext): number {
  if (ctx.rolled >= MAX_DICE_TOTAL) {
    ctx.error = `Trop de dés lancés (max ${MAX_DICE_TOTAL}).`;
    return 0;
  }
  const value = Math.trunc(ctx.rng(1, sides));
  ctx.rolled += 1;
  if (value < 1 || value > sides) {
    ctx.error = "Séquence de dés invalide ou épuisée.";
    return 0;
  }
  return value;
}

function makeRng(opts: RollOptions): Rng {
  if (typeof opts.rng === "function") {
    return opts.rng;
  }
  if (Array.isArray(opts.rolls)) {
    const queue = [...opts.rolls];
    let index = 0;
    return () => {
      if (index >= queue.length) {
        return 0;
      }
      const value = queue[index];
      index += 1;
      return value;
    };
  }
  if (typeof opts.seed === "number") {
    return makeSeededRng(opts.seed);
  }
  return (min, max) => min + Math.floor(Math.random() * (max - min + 1));
}

/** PRNG déterministe (mulberry32) pour les tests reproductibles côté Node. */
function makeSeededRng(seed: number): Rng {
  let state = seed >>> 0;
  return (min: number, max: number): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    const unit = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    return min + Math.floor(unit * (max - min + 1));
  };
}

// ===========================================================================
// Assemblage / formatage
// ===========================================================================

function collectRolls(node: NodeResult): number[] {
  if (node.kind === "dice") {
    return [...(node.kept ?? [])];
  }
  if (node.kind === "comparison") {
    return [...collectRolls(node.left as NodeResult), ...collectRolls(node.right as NodeResult)];
  }
  const out: number[] = [];
  for (const child of node.children ?? []) {
    out.push(...collectRolls(child));
  }
  return out;
}

function formatDiceDetail(node: NodeResult): string {
  if (node.kind === "dice") {
    const dropped = node.dropped ?? [];
    const shown = dropped.length > 0 ? node.kept ?? [] : node.values ?? [];
    if (shown.length === 0) {
      return "";
    }
    let text = ` — dés : ${shown.join(", ")}`;
    if (dropped.length > 0) {
      text += ` (défaussés : ${dropped.join(", ")})`;
    }
    return text;
  }
  if (node.kind === "comparison") {
    return formatDiceDetail(node.left as NodeResult);
  }
  return (node.children ?? []).map((child) => formatDiceDetail(child)).join("");
}
