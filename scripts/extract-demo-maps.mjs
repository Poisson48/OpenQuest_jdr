#!/usr/bin/env node
/**
 * Génère les cartes démo JSON depuis la logique de js/maps.js
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, "../data/maps");
mkdirSync(OUT, { recursive: true });

function createEmpty(width, height, defaultTile = "grass") {
  return { width, height, tiles: Array(width * height).fill(defaultTile) };
}

function set(tiles, width, x, y, tile) {
  tiles[y * width + x] = tile;
}

// --- Taverne ---
{
  const width = 14, height = 10;
  const { tiles } = createEmpty(width, height, "grass");
  for (let x = 0; x < width; x++) { set(tiles, width, x, 0, "wall"); set(tiles, width, x, height - 1, "wall"); }
  for (let y = 0; y < height; y++) { set(tiles, width, 0, y, "wall"); set(tiles, width, width - 1, y, "wall"); }
  for (let x = 2; x < width - 2; x++) for (let y = 2; y < height - 2; y++) set(tiles, width, x, y, "floor");
  set(tiles, width, 1, 5, "floor"); set(tiles, width, width - 2, 4, "floor");
  set(tiles, width, 6, 1, "floor"); set(tiles, width, 3, 3, "water"); set(tiles, width, 4, 3, "water");
  set(tiles, width, 9, 6, "stone"); set(tiles, width, 10, 6, "stone");

  writeFileSync(join(OUT, "demo-taverne.json"), JSON.stringify({
    id: "demo-taverne",
    title: "Taverne du Vieux Port",
    description: "Plan de la taverne et de la cave — scène d'introduction.",
    roster: "general",
    mapKind: "local",
    scenarioId: "",
    width, height, tiles,
    markers: [
      { x: 2, y: 5, type: "party", label: "Entrée" },
      { x: 1, y: 5, type: "exit", label: "Sortie" },
      { x: 7, y: 5, type: "npc", label: "Tavernier" },
      { x: 10, y: 3, type: "poi", label: "Cave" },
    ],
    locationLinks: [],
  }, null, 2));
}

// --- Quartier enquête ---
{
  const width = 16, height = 12;
  const { tiles } = createEmpty(width, height, "street");
  for (let x = 3; x <= 12; x++) { set(tiles, width, x, 3, "building"); set(tiles, width, x, 8, "building"); }
  for (let y = 4; y <= 7; y++) { set(tiles, width, 3, y, "building"); set(tiles, width, 12, y, "building"); }
  for (let x = 5; x <= 10; x++) for (let y = 5; y <= 6; y++) set(tiles, width, x, y, "office");
  set(tiles, width, 1, 5, "alley"); set(tiles, width, 2, 5, "alley"); set(tiles, width, 14, 6, "alley");
  set(tiles, width, 7, 1, "road"); set(tiles, width, 8, 1, "road");
  set(tiles, width, 7, 10, "road"); set(tiles, width, 8, 10, "road");
  set(tiles, width, 0, 5, "wall"); set(tiles, width, 15, 6, "wall");

  writeFileSync(join(OUT, "demo-quartier-serpent.json"), JSON.stringify({
    id: "demo-quartier-serpent",
    title: "Quartier du Serpent Noir",
    description: "Dockland — commissariat, ruelles et entrepôts.",
    roster: "investigation",
    mapKind: "local",
    scenarioId: "inv-demo-serpent-noir",
    width, height, tiles,
    markers: [
      { x: 7, y: 6, type: "detective", label: "Équipe" },
      { x: 10, y: 5, type: "evidence", label: "Indice" },
      { x: 1, y: 5, type: "crime", label: "Corps" },
      { x: 14, y: 6, type: "suspect", label: "Fuyard" },
      { x: 4, y: 4, type: "witness", label: "Témoin" },
    ],
    locationLinks: [],
  }, null, 2));
}

// --- Monde ---
{
  const width = 48, height = 32;
  const tiles = Array(width * height).fill("ocean");
  const setW = (x, y, tile) => { if (x >= 0 && x < width && y >= 0 && y < height) tiles[y * width + x] = tile; };
  const fillEllipse = (cx, cy, rx, ry, tile) => {
    for (let y = 0; y < height; y++)
      for (let x = 0; x < width; x++)
        if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1) setW(x, y, tile);
  };
  fillEllipse(24, 17, 15, 9, "plains");
  fillEllipse(10, 12, 6, 5, "forest");
  fillEllipse(36, 14, 5, 4, "hills");
  fillEllipse(24, 8, 10, 3, "mountain");
  fillEllipse(24, 6, 8, 2, "snow");
  fillEllipse(38, 22, 4, 3, "desert");
  fillEllipse(8, 22, 3, 2, "swamp");
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const t = tiles[y * width + x];
    if (["plains", "forest", "hills"].includes(t)) {
      const near = [[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([nx,ny]) =>
        nx >= 0 && nx < width && ny >= 0 && ny < height && tiles[ny * width + nx] === "ocean");
      if (near) setW(x, y, "coast");
    }
  }
  setW(22, 16, "city"); setW(24, 16, "city"); setW(26, 15, "city");
  setW(12, 13, "city"); setW(35, 14, "city");

  writeFileSync(join(OUT, "demo-monde-couronne.json"), JSON.stringify({
    id: "demo-monde-couronne",
    title: "Les Terres de la Couronne Fracturée",
    description: "Carte du monde — royaumes en guerre.",
    roster: "general",
    mapKind: "world",
    scenarioId: "demo-couronne-fracturee",
    width, height, tiles,
    markers: [
      { x: 24, y: 16, type: "capital", label: "Capitale" },
      { x: 12, y: 13, type: "city", label: "Port" },
      { x: 35, y: 14, type: "city", label: "Mine" },
      { x: 24, y: 8, type: "dungeon", label: "Pics" },
      { x: 38, y: 22, type: "quest", label: "Quête" },
      { x: 22, y: 18, type: "party", label: "Groupe" },
      { x: 8, y: 22, type: "ruin", label: "Ruines" },
    ],
    locationLinks: [
      { x: 12, y: 13, targetMapId: "demo-taverne", label: "Port" },
      { x: 24, y: 16, targetMapId: "demo-taverne", label: "Capitale" },
    ],
  }, null, 2));
}

// Copie vers game/data/maps
import { cpSync, readdirSync } from "node:fs";
const gameOut = join(__dirname, "../game/data/maps");
mkdirSync(gameOut, { recursive: true });
for (const f of readdirSync(OUT)) {
  if (f.endsWith(".json")) cpSync(join(OUT, f), join(gameOut, f));
}

console.log("Cartes démo générées dans data/maps/ et game/data/maps/");
