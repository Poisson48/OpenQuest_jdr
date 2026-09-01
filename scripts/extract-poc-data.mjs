#!/usr/bin/env node
/**
 * One-shot extractor: js/scenarios.js, js/bots.js, js/maps.js → data/*.json
 * for Godot migration (PoC data contract).
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

const ADVENTURE_DEMO_IDS = [
  'demo-crypte',
  'demo-manoir',
  'demo-kharak',
  'demo-couronne-fracturee',
];

/** Find `propName: [` or `propName: {` and return the raw JS literal slice. */
function extractJsLiteral(source, propName) {
  const marker = new RegExp(`\\b${propName}\\s*:\\s*`);
  const match = marker.exec(source);
  if (!match) {
    throw new Error(`Property not found: ${propName}`);
  }

  const openIdx = match.index + match[0].length;
  const openChar = source[openIdx];
  if (openChar !== '[' && openChar !== '{') {
    throw new Error(`Expected [ or { after ${propName}, got ${openChar}`);
  }

  const closeChar = openChar === '[' ? ']' : '}';
  let depth = 0;
  let inString = false;
  let stringQuote = null;
  let escaped = false;

  for (let i = openIdx; i < source.length; i += 1) {
    const ch = source[i];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === stringQuote) {
        inString = false;
        stringQuote = null;
      }
      continue;
    }

    if (ch === '"' || ch === "'" || ch === '`') {
      inString = true;
      stringQuote = ch;
      continue;
    }

    if (ch === openChar) depth += 1;
    else if (ch === closeChar) {
      depth -= 1;
      if (depth === 0) {
        return source.slice(openIdx, i + 1);
      }
    }
  }

  throw new Error(`Unclosed literal for ${propName}`);
}

/** Parse a JS object/array literal from trusted local source files. */
function parseJsLiteral(literal) {
  // eslint-disable-next-line no-new-func
  return new Function(`return (${literal});`)();
}

function ensureDir(dir) {
  mkdirSync(dir, { recursive: true });
}

function writeJson(path, data) {
  ensureDir(dirname(path));
  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
}

function normalizeScenario(scenario) {
  const out = { ...scenario };
  if (out.roster === 'investigation') {
    if (!out.questFormat) {
      out.questFormat = out.id === 'inv-demo-serpent-noir' ? 'long' : 'oneshot';
    }
  } else if (!out.questFormat) {
    out.questFormat = (out.id === 'demo-kharak' || out.id === 'demo-couronne-fracturee')
      ? 'long'
      : 'oneshot';
  }
  if (!out.roster && out.id?.startsWith('inv-')) {
    out.roster = 'investigation';
  }
  return out;
}

function extractTileSet(obj) {
  const tiles = {};
  for (const [key, value] of Object.entries(obj)) {
    tiles[key] = {
      label: value.label,
      color: value.color,
    };
  }
  return tiles;
}

function main() {
  const scenariosSrc = readFileSync(join(ROOT, 'js/scenarios.js'), 'utf8');
  const botsSrc = readFileSync(join(ROOT, 'js/bots.js'), 'utf8');
  const mapsSrc = readFileSync(join(ROOT, 'js/maps.js'), 'utf8');

  const demoScenarios = parseJsLiteral(extractJsLiteral(scenariosSrc, 'DEMO_SCENARIOS'));
  const investigationScenarios = parseJsLiteral(
    extractJsLiteral(scenariosSrc, 'INVESTIGATION_SCENARIOS'),
  );
  const archetypes = parseJsLiteral(extractJsLiteral(botsSrc, 'DEFAULT_ARCHETYPES'));

  const tiles = parseJsLiteral(extractJsLiteral(mapsSrc, 'TILES'));
  const worldTiles = parseJsLiteral(extractJsLiteral(mapsSrc, 'WORLD_TILES'));
  const investigationTiles = parseJsLiteral(extractJsLiteral(mapsSrc, 'INVESTIGATION_TILES'));

  const scenariosDir = join(ROOT, 'data/scenarios');
  const written = [];
  const skipped = [];
  const issues = [];

  for (const id of ADVENTURE_DEMO_IDS) {
    const scenario = demoScenarios.find((s) => s.id === id);
    if (!scenario) {
      issues.push(`Adventure demo not found: ${id}`);
      continue;
    }
    const file = join(scenariosDir, `${id}.json`);
    writeJson(file, normalizeScenario(scenario));
    written.push(file);
  }

  const extraDemos = demoScenarios
    .map((s) => s.id)
    .filter((id) => !ADVENTURE_DEMO_IDS.includes(id));
  if (extraDemos.length) {
    skipped.push(`Other DEMO_SCENARIOS not exported: ${extraDemos.join(', ')}`);
  }

  for (const scenario of investigationScenarios) {
    const file = join(scenariosDir, `${scenario.id}.json`);
    writeJson(file, normalizeScenario(scenario));
    written.push(file);
  }

  const botsFile = join(ROOT, 'data/bots/archetypes.json');
  writeJson(botsFile, archetypes);
  written.push(botsFile);

  const tilesFile = join(ROOT, 'data/tiles.json');
  writeJson(tilesFile, {
    local: extractTileSet(tiles),
    world: extractTileSet(worldTiles),
    investigation: extractTileSet(investigationTiles),
  });
  written.push(tilesFile);

  console.log('Extracted PoC data:');
  for (const f of written) {
    console.log(`  ${f.replace(`${ROOT}/`, '')}`);
  }
  if (skipped.length) {
    console.log('\nNotes:');
    for (const note of skipped) console.log(`  ${note}`);
  }
  if (issues.length) {
    console.error('\nIssues:');
    for (const issue of issues) console.error(`  ${issue}`);
    process.exitCode = 1;
  }
}

main();
