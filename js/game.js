/**
 * game.js — Session de jeu jouable (solo / multijoueur local).
 * MJ IA adaptatif ou MJ humain, avec bots compagnons.
 */

const Game = {
  state: null,
  MAX_PARTY_SIZE: 10,
  sessionTimerInterval: null,

  init() {
    Characters.load();
    Scenarios.load();
    Scenarios.ensureDemoScenario();
    Bots.load();

    this.migrateLegacyActiveGame();
    this.restoreInitialState();

    this.bindSetupEvents();
    this.bindSessionEvents();
    this.renderSetup();
  },

  migrateLegacyActiveGame() {
    const legacy = Storage.load(Storage.KEYS.activeGame);
    if (!legacy) return;
    const normalized = this.normalizeSavedState(legacy);
    if (!normalized) {
      Storage.save(Storage.KEYS.activeGame, null);
      return;
    }
    if (!normalized.id) normalized.id = `game-${Date.now()}`;
    const games = this.loadSavedGames();
    const idx = games.findIndex((g) => g.id === normalized.id);
    if (idx >= 0) games[idx] = normalized;
    else games.push(normalized);
    this.persistSavedGames(games);
    Storage.save(Storage.KEYS.activeGame, null);
  },

  loadSavedGames() {
    return Storage.loadArray(Storage.KEYS.savedGames)
      .filter((g) => g && typeof g === 'object')
      .map((g) => this.normalizeSavedState(g))
      .filter(Boolean);
  },

  persistSavedGames(games) {
    Storage.save(Storage.KEYS.savedGames, games);
  },

  getPlayingGames() {
    return this.loadSavedGames().filter((g) => g.status === 'playing');
  },

  getGamePartySummary(game) {
    const party = Array.isArray(game.party) ? game.party : [];
    if (party.length === 0) return 'Groupe vide';
    const names = party.map((m) => m.name || '?');
    if (names.length <= 3) return names.join(', ');
    return `${names[0]} + ${names.length - 1} autres`;
  },

  restoreInitialState() {
    const playing = this.getPlayingGames();
    const lastId = Storage.load(Storage.KEYS.lastActiveGameId);
    if (lastId && playing.some((g) => g.id === lastId)) {
      this.resumeGame(lastId, { silent: true });
      return;
    }
    if (playing.length === 1) {
      this.resumeGame(playing[0].id, { silent: true });
      return;
    }
    this.state = null;
  },

  resumeGame(gameId, options = {}) {
    const game = this.loadSavedGames().find((g) => g.id === gameId);
    if (!game) return false;
    this.state = game;
    Storage.save(Storage.KEYS.lastActiveGameId, gameId);
    this.initAllWorldMapFog();
    this.ensurePartyTokensOnWorldMaps();
    if (!options.silent) {
      this.showSession();
      this.renderSession();
    }
    return true;
  },

  deleteGame(gameId) {
    const games = this.loadSavedGames().filter((g) => g.id !== gameId);
    this.persistSavedGames(games);
    const lastId = Storage.load(Storage.KEYS.lastActiveGameId);
    if (lastId === gameId) {
      Storage.save(Storage.KEYS.lastActiveGameId, null);
    }
    if (this.state?.id === gameId) {
      this.stopSessionTimer();
      this.state = null;
      this.hideSession();
      this.renderSetup();
    }
  },

  normalizeSavedState(state) {
    if (!state || typeof state !== 'object') return null;
    if (!Array.isArray(state.party) || state.party.length === 0) return null;
    if (!Array.isArray(state.log)) state.log = [];
    if (state.status !== 'playing' && state.status !== 'completed') return null;
    if (!state.scenarioId) return null;
    if (!state.id) state.id = `game-${state.createdAt || Date.now()}`;
    if (!state.createdAt) state.createdAt = Date.now();
    if (!Array.isArray(state.mapIds)) {
      state.mapIds = state.mapId ? [state.mapId] : [];
    }
    state.mapIds = state.mapIds.filter(Boolean);
    delete state.mapId;
    if (!state.mapPlayState || typeof state.mapPlayState !== 'object') {
      state.mapPlayState = {};
    }
    if (!state.mapNavigation || typeof state.mapNavigation !== 'object') {
      state.mapNavigation = { view: 'world', worldMapId: null, localMapId: null, worldCell: null };
    }
    return state;
  },

  enterLocalMap(worldMapId, x, y, targetMapId) {
    if (!this.state || !targetMapId) return;
    if (!this.state.mapIds.includes(targetMapId)) {
      this.state.mapIds.push(targetMapId);
    }
    this.state.mapNavigation = {
      view: 'local',
      worldMapId,
      localMapId: targetMapId,
      worldCell: { x, y },
    };
    this.save();
  },

  exitToWorldMap() {
    if (!this.state?.mapNavigation) return;
    this.state.mapNavigation.view = 'world';
    this.state.mapNavigation.localMapId = null;
    this.save();
  },

  expandMapIdsWithLinkedLocals(mapIds) {
    if (typeof Maps === 'undefined') return mapIds;
    Maps.load();
    const expanded = new Set(mapIds.filter(Boolean));
    mapIds.forEach((id) => {
      const map = Maps.getById(id);
      if (map && Maps.isWorldMap(map)) {
        Maps.getLinkedLocalMapIds(map).forEach((linkedId) => expanded.add(linkedId));
      }
    });
    return [...expanded];
  },

  ensureMapPlayState() {
    if (!this.state) return;
    if (!this.state.mapPlayState || typeof this.state.mapPlayState !== 'object') {
      this.state.mapPlayState = {};
    }
  },

  getMapPlayTokens(mapId) {
    return this.getMapPlayEntry(mapId).tokens;
  },

  getMapPlayEntry(mapId) {
    this.ensureMapPlayState();
    if (!this.state.mapPlayState[mapId]) {
      this.state.mapPlayState[mapId] = { tokens: [], explored: [] };
    }
    const entry = this.state.mapPlayState[mapId];
    if (!Array.isArray(entry.tokens)) entry.tokens = [];
    if (!Array.isArray(entry.explored)) entry.explored = [];
    if (entry.exploreLevel == null) entry.exploreLevel = 0;
    return entry;
  },

  cellKey(x, y) {
    return `${x},${y}`;
  },

  getExploredCells(mapId) {
    return this.getMapPlayEntry(mapId).explored;
  },

  revealCell(mapId, x, y) {
    const entry = this.getMapPlayEntry(mapId);
    const key = this.cellKey(x, y);
    if (!entry.explored.includes(key)) entry.explored.push(key);
  },

  revealRadius(mapId, map, cx, cy, radius) {
    if (!map) return;
    for (let y = cy - radius; y <= cy + radius; y += 1) {
      for (let x = cx - radius; x <= cx + radius; x += 1) {
        if (x < 0 || x >= map.width || y < 0 || y >= map.height) continue;
        if (Math.abs(x - cx) + Math.abs(y - cy) <= radius) {
          this.revealCell(mapId, x, y);
        }
      }
    }
  },

  getWorldMapIds() {
    if (!this.state?.mapIds?.length || typeof Maps === 'undefined') return [];
    Maps.load();
    return this.state.mapIds.filter((id) => {
      const map = Maps.getById(id);
      return map && Maps.isWorldMap(map);
    });
  },

  getWorldMapStartPoint(map) {
    const partyMarker = map.markers?.find((m) => m.type === 'party' || m.type === 'camp');
    if (partyMarker) return { x: partyMarker.x, y: partyMarker.y };
    const token = this.getMapPlayTokens(map.id).find((t) => t.kind === 'member');
    if (token) return { x: token.x, y: token.y };
    return { x: Math.floor(map.width / 2), y: Math.floor(map.height / 2) };
  },

  initWorldMapFog(mapId) {
    if (typeof Maps === 'undefined') return;
    const map = Maps.getById(mapId);
    if (!map || !Maps.isWorldMap(map)) return;

    const entry = this.getMapPlayEntry(mapId);
    if (entry.explored.length > 0) return;

    const start = this.getWorldMapStartPoint(map);
    entry.exploreAnchor = { x: start.x, y: start.y };
    entry.exploreLevel = 0;
    this.revealRadius(mapId, map, start.x, start.y, 2);
  },

  initAllWorldMapFog() {
    this.getWorldMapIds().forEach((mapId) => this.initWorldMapFog(mapId));
  },

  revealFrontierCells(mapId, map, count) {
    const entry = this.getMapPlayEntry(mapId);
    const explored = new Set(entry.explored);
    const candidates = new Map();
    const dirs = [[0, 1], [0, -1], [1, 0], [-1, 0], [1, 1], [-1, 1], [1, -1], [-1, -1]];

    entry.explored.forEach((key) => {
      const [cx, cy] = key.split(',').map(Number);
      dirs.forEach(([dx, dy]) => {
        const x = cx + dx;
        const y = cy + dy;
        const key = this.cellKey(x, y);
        if (x < 0 || x >= map.width || y < 0 || y >= map.height || explored.has(key)) return;
        if (!candidates.has(key)) candidates.set(key, { x, y });
      });
    });

    const anchor = entry.exploreAnchor || this.getWorldMapStartPoint(map);
    [...candidates.values()]
      .sort((a, b) => (
        Math.abs(a.x - anchor.x) + Math.abs(a.y - anchor.y)
        - (Math.abs(b.x - anchor.x) + Math.abs(b.y - anchor.y))
      ))
      .slice(0, count)
      .forEach(({ x, y }) => this.revealCell(mapId, x, y));
  },

  revealWorldOnExplore(extraCells = 5) {
    this.getWorldMapIds().forEach((mapId) => {
      const map = Maps.getById(mapId);
      if (!map) return;
      const entry = this.getMapPlayEntry(mapId);
      entry.exploreLevel += 1;
      const anchor = entry.exploreAnchor || this.getWorldMapStartPoint(map);
      const token = entry.tokens.find((t) => t.kind === 'member');
      const center = token ? { x: token.x, y: token.y } : anchor;
      entry.exploreAnchor = { ...center };
      const radius = 2 + Math.floor(entry.exploreLevel / 2);
      this.revealRadius(mapId, map, center.x, center.y, radius);
      this.revealFrontierCells(mapId, map, extraCells);
    });
    this.save();
  },

  revealWorldOnSceneAdvance() {
    this.getWorldMapIds().forEach((mapId) => {
      const map = Maps.getById(mapId);
      if (!map) return;
      const entry = this.getMapPlayEntry(mapId);
      entry.exploreLevel += 2;
      const anchor = entry.exploreAnchor || this.getWorldMapStartPoint(map);
      const radius = 2 + Math.floor(entry.exploreLevel / 2);
      this.revealRadius(mapId, map, anchor.x, anchor.y, radius);
      this.revealFrontierCells(mapId, map, 10 + Math.floor(Math.random() * 6));
    });
    this.save();
  },

  revealWorldAt(mapId, x, y, radius = 2) {
    const map = Maps.getById(mapId);
    if (!map || !Maps.isWorldMap(map)) return;
    const entry = this.getMapPlayEntry(mapId);
    entry.exploreAnchor = { x, y };
    this.revealRadius(mapId, map, x, y, radius);
    this.revealFrontierCells(mapId, map, 2);
    this.save();
  },

  revealAllWorldMaps() {
    this.getWorldMapIds().forEach((mapId) => {
      const map = Maps.getById(mapId);
      if (!map) return;
      for (let y = 0; y < map.height; y += 1) {
        for (let x = 0; x < map.width; x += 1) {
          this.revealCell(mapId, x, y);
        }
      }
    });
  },

  getWorldExplorationPercent(mapId, map) {
    const total = map.width * map.height;
    if (!total) return 0;
    return Math.min(100, Math.round((this.getExploredCells(mapId).length / total) * 100));
  },

  removeMapTokenAt(mapId, x, y) {
    const tokens = this.getMapPlayTokens(mapId);
    this.state.mapPlayState[mapId].tokens = tokens.filter((t) => !(t.x === x && t.y === y));
  },

  removeMemberTokens(mapId, memberId) {
    const tokens = this.getMapPlayTokens(mapId);
    this.state.mapPlayState[mapId].tokens = tokens.filter((t) => t.memberId !== memberId);
  },

  placeMemberToken(mapId, x, y, memberId) {
    if (!memberId) return;
    this.removeMemberTokens(mapId, memberId);
    this.removeMapTokenAt(mapId, x, y);
    const member = this.state.party.find((m) => m.id === memberId);
    if (!member) return;
    const tokens = this.getMapPlayTokens(mapId);
    tokens.push({
      id: `tok-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      x,
      y,
      kind: 'member',
      memberId,
      label: member.name,
    });
    if (typeof Maps !== 'undefined') {
      Maps.load();
      const map = Maps.getById(mapId);
      if (map && Maps.isWorldMap(map)) {
        this.revealWorldAt(mapId, x, y, 2);
      }
    }
  },

  placeMarkerToken(mapId, x, y, markerType) {
    if (!markerType) return;
    this.removeMapTokenAt(mapId, x, y);
    const tokens = this.getMapPlayTokens(mapId);
    tokens.push({
      id: `tok-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      x,
      y,
      kind: 'marker',
      markerType,
      label: '',
    });
  },

  getActivePlayMapId() {
    if (!this.state?.mapIds?.length) return '';
    const nav = this.state.mapNavigation || {};
    if (nav.view === 'local' && nav.localMapId) return nav.localMapId;
    if (typeof Maps !== 'undefined') {
      Maps.load();
      const worldId = this.state.mapIds.find((id) => {
        const map = Maps.getById(id);
        return map && Maps.isWorldMap(map);
      });
      if (worldId) return worldId;
    }
    return this.state.mapIds[0];
  },

  getMemberTokenPosition(mapId, memberId) {
    const token = this.getMapPlayTokens(mapId).find(
      (t) => t.kind === 'member' && t.memberId === memberId,
    );
    if (token) return { x: token.x, y: token.y };
    if (typeof Maps !== 'undefined') {
      Maps.load();
      const map = Maps.getById(mapId);
      if (map) return this.getWorldMapStartPoint(map);
    }
    return null;
  },

  normalizeActionText(actionText) {
    let text = actionText
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/['']/g, ' ')
      .replace(/-/g, ' ');
    ['jecoute', 'jevais', 'jemarche', 'jeme', 'jedirige', 'jerends', 'jsuis'].forEach((glued) => {
      if (text.includes(glued)) text = text.replace(glued, glued.replace('j', 'j '));
    });
    while (text.includes('  ')) text = text.replace('  ', ' ');
    return text.trim();
  },

  semanticPlaceKeywords() {
    return [
      'foret', 'bois', 'auberge', 'taverne', 'capitale', 'capital', 'ville',
      'port', 'ruine', 'donjon', 'forteresse', 'mine', 'quete', 'campement',
      'cave', 'tavernier', 'entree', 'sortie', 'hostellerie', 'bosquet',
      'palais', 'cite', 'bourg', 'ruines', 'pics', 'valdris',
    ];
  },

  hasSemanticDestinationIntent(text) {
    if (this.semanticPlaceKeywords().some((kw) => text.includes(kw))) return true;
    if (typeof Maps !== 'undefined') {
      Maps.load();
      for (const mapId of this.state?.mapIds || []) {
        const map = Maps.getById(mapId);
        for (const mk of map?.markers || []) {
          const label = this.normalizeActionText(mk.label || '');
          if (label.length >= 3 && text.includes(label)) return true;
        }
      }
    }
    return false;
  },

  hasExplicitCardinalDirection(text) {
    const explicit = [
      'nord-est', 'nord est', 'nord-ouest', 'nord ouest',
      'sud-est', 'sud est', 'sud-ouest', 'sud ouest',
      'vers le nord', 'vers le sud', 'vers l ouest', 'vers l est',
      'au nord', 'au sud', 'a l ouest', 'a l est',
      'direction nord', 'direction sud', 'direction ouest', 'direction est',
      ' vers nord', ' vers sud', ' vers ouest', ' vers est',
      'cap au nord', 'cap au sud', 'cap a l est', 'cap a l ouest',
    ];
    if (explicit.some((phrase) => text.includes(phrase))) return true;
    if (text.endsWith(' nord') || text.endsWith(' sud') || text.endsWith(' ouest')) return true;
    if (text.endsWith(' est') && !text.endsWith(' forest') && !text.endsWith(' ouest')) return true;
    return false;
  },

  npcLocationKeywords() {
    return {
      torval: ['fort', 'brume', 'dungeon', 'donjon', 'pics'],
      elwen: ['garde', 'muraille', 'fortin'],
      oldra: ['village', 'hameau', 'sans nom'],
      thrain: ['keldorm', 'nain', 'mine'],
      alaric: ['cathedrale', 'temple', 'valdris', 'capitale'],
      sylka: ['nord', 'brume'],
      harald: ['guerre', 'bataille', 'cendre'],
    };
  },

  findNpcMentionedInText(text) {
    if (typeof Scenarios === 'undefined') return null;
    Scenarios.load();
    const scenario = Scenarios.getById(this.state?.scenarioId);
    for (const npc of scenario?.npcs || []) {
      const fullName = this.normalizeActionText(npc.name || '');
      if (fullName.length >= 4 && text.includes(fullName)) return npc;
      for (const part of fullName.split(' ')) {
        if (part.length >= 4 && text.includes(part)) return npc;
      }
    }
    return null;
  },

  ensurePartyTokensOnWorldMaps() {
    if (!this.state) return;
    const worldIds = this.getWorldMapIds();
    if (!worldIds.length || typeof Maps === 'undefined') return;
    Maps.load();
    const mapId = worldIds[0];
    const map = Maps.getById(mapId);
    if (!map) return;
    const start = this.getWorldMapStartPoint(map);
    const human = this.state.party.find((m) => m.isHuman || m.isPlayer);
    if (!human?.id) return;
    const hasToken = this.getMapPlayTokens(mapId).some(
      (t) => t.kind === 'member' && t.memberId === human.id,
    );
    if (!hasToken) this.placeMemberToken(mapId, start.x, start.y, human.id);
  },

  looksLikeMovementAction(text) {
    const verbs = [
      'vais', 'va ', ' marche', 'deplace', 'deplac', 'avance', 'avancer',
      'cours', 'direction', 'vers le', 'vers la', 'vers un', 'vers l',
      'me dirige', 'me rends', 'aller ', 'chemin vers', 'cap sur', 'cap au', 'cap a',
      'ecoute', 'indications', 'conseils', 'suiv', 'dans l', 'dans la', 'dans le', 'jusqu',
    ];
    if (verbs.some((verb) => text.includes(verb))) return true;
    if (text.includes('nord') || text.includes('sud') || text.includes('ouest')) return true;
    if (text.includes("l'est") || text.includes('l est') || text.includes(' vers est')) return true;
    const places = [
      'foret', 'bois', 'auberge', 'taverne', 'capitale', 'capital', 'ville',
      'port', 'ruine', 'donjon', 'forteresse', 'mine', 'quete', 'campement',
      'cave', 'tavernier', 'entree', 'sortie',
    ];
    if (places.some((place) => text.includes(place))) return true;
    if (typeof Maps !== 'undefined') {
      Maps.load();
      for (const mapId of this.state?.mapIds || []) {
        const map = Maps.getById(mapId);
        for (const mk of map?.markers || []) {
          const label = this.normalizeActionText(mk.label || '');
          if (label.length >= 4 && text.includes(label)) return true;
        }
      }
    }
    return false;
  },

  manhattan(a, b) {
    return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
  },

  pickNearest(from, candidates) {
    let best = null;
    let bestDist = Infinity;
    candidates.forEach((c) => {
      const d = this.manhattan(from, c);
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    });
    return best;
  },

  stepTowards(from, to) {
    if (from.x === to.x && from.y === to.y) return from;
    const dx = Math.sign(to.x - from.x);
    const dy = Math.sign(to.y - from.y);
    return { x: from.x + dx, y: from.y + dy };
  },

  getTileIdAt(map, x, y) {
    const idx = y * map.width + x;
    return map.tiles?.[idx] || '';
  },

  findForestCells(map) {
    const result = [];
    for (let y = 0; y < map.height; y += 1) {
      for (let x = 0; x < map.width; x += 1) {
        const tile = this.getTileIdAt(map, x, y);
        if (tile.includes('forest') || tile.includes('tree') || tile === 'woods') {
          result.push({ x, y });
        }
      }
    }
    return result;
  },

  findForestCellsNearExplored(mapId, map) {
    const explored = new Set(this.getExploredCells(mapId));
    if (!explored.size) return [];
    const result = [];
    for (let y = 0; y < map.height; y += 1) {
      for (let x = 0; x < map.width; x += 1) {
        const tile = this.getTileIdAt(map, x, y);
        if (!tile.includes('forest') && !tile.includes('tree') && tile !== 'woods') continue;
        const key = this.cellKey(x, y);
        if (explored.has(key)) {
          result.push({ x, y });
          continue;
        }
        for (let ox = -1; ox <= 1; ox += 1) {
          for (let oy = -1; oy <= 1; oy += 1) {
            if (ox === 0 && oy === 0) continue;
            if (explored.has(this.cellKey(x + ox, y + oy))) {
              result.push({ x, y });
              break;
            }
          }
        }
      }
    }
    return result;
  },

  isTileWalkable(map, x, y) {
    const tile = this.getTileIdAt(map, x, y);
    if (!tile) return false;
    if (tile.includes('ocean') || tile.includes('water') || tile === 'wall' || tile.includes('mountain')) {
      return false;
    }
    return true;
  },

  isCellWalkableForMove(mapId, x, y) {
    if (!this.isCellAccessibleForMove(mapId, x, y)) return false;
    if (typeof Maps === 'undefined') return true;
    Maps.load();
    const map = Maps.getById(mapId);
    return map ? this.isTileWalkable(map, x, y) : false;
  },

  pickBestStepTowards(mapId, from, goal) {
    if (from.x === goal.x && from.y === goal.y) return from;
    if (typeof Maps === 'undefined') return null;
    Maps.load();
    const map = Maps.getById(mapId);
    if (!map) return null;
    const ordered = [];
    for (let dx = -1; dx <= 1; dx += 1) {
      for (let dy = -1; dy <= 1; dy += 1) {
        if (dx === 0 && dy === 0) continue;
        const n = { x: from.x + dx, y: from.y + dy };
        if (!this.isTileWalkable(map, n.x, n.y)) continue;
        ordered.push({ pos: n, dist: this.manhattan(n, goal) });
      }
    }
    ordered.sort((a, b) => a.dist - b.dist);
    for (const item of ordered) {
      if (this.prepareCellForMove(mapId, item.pos.x, item.pos.y)
        && this.isCellWalkableForMove(mapId, item.pos.x, item.pos.y)) {
        return item.pos;
      }
    }
    return null;
  },

  findAnchorPosition(map, text) {
    const proximityPrefixes = [
      'pres de la ', 'pres du ', 'pres de ', 'proche de la ', 'proche du ', 'proche de ',
      'a cote de la ', 'a cote du ', 'a cote de ', 'aux alentours de la ', 'aux alentours du ',
      'autour de la ', 'autour du ', 'autour de ',
    ];
    for (const prefix of proximityPrefixes) {
      const idx = text.indexOf(prefix);
      if (idx < 0) continue;
      const rest = text.slice(idx + prefix.length).trim();
      for (const mk of map.markers || []) {
        const label = this.normalizeActionText(mk.label || '');
        if (label.length >= 3 && (rest.startsWith(label) || rest.includes(` ${label}`))) {
          return { x: mk.x, y: mk.y };
        }
      }
      if (rest.startsWith('capitale') || rest.startsWith('capital') || rest.includes(' capitale')) {
        const capital = map.markers?.find((m) => m.type === 'capital');
        if (capital) return { x: capital.x, y: capital.y };
      }
      if (rest.startsWith('port') || rest.includes(' port')) {
        const port = map.markers?.find((m) => this.normalizeActionText(m.label || '').includes('port'));
        if (port) return { x: port.x, y: port.y };
      }
    }
    if (text.includes('capitale') || text.includes('capital') || text.includes('palais') || text.includes('valdris')) {
      const mk = map.markers?.find((m) => m.type === 'capital'
        || this.normalizeActionText(m.label || '').includes('capitale'));
      if (mk) return { x: mk.x, y: mk.y };
    }
    if (text.includes('port')) {
      const mk = map.markers?.find((m) => this.normalizeActionText(m.label || '').includes('port'));
      if (mk) return { x: mk.x, y: mk.y };
      const link = map.locationLinks?.find((l) => this.normalizeActionText(l.label || '').includes('port'));
      if (link) return { x: link.x, y: link.y };
    }
    if (text.includes('mine')) {
      const mk = map.markers?.find((m) => this.normalizeActionText(m.label || '').includes('mine'));
      if (mk) return { x: mk.x, y: mk.y };
    }
    return null;
  },

  mapTitleMatchesKeywords(mapId, keywords) {
    if (typeof Maps === 'undefined') return false;
    Maps.load();
    const title = this.normalizeActionText(Maps.getById(mapId)?.title || '');
    return keywords.some((kw) => title.includes(kw));
  },

  collectSemanticCandidates(mapId, map, text) {
    const candidates = [];
    const anchor = this.findAnchorPosition(map, text);

    const wantsTavern = text.includes('auberge') || text.includes('taverne')
      || text.includes('hostellerie') || text.includes('tavernier');
    const wantsForest = text.includes('foret') || text.includes('bois') || text.includes('bosquet');
    const wantsCapital = text.includes('capitale') || text.includes('capital') || text.includes('valdris');
    const wantsCity = text.includes('ville') || text.includes('cite') || text.includes('bourg');
    const wantsRuin = text.includes('ruine');
    const wantsDungeon = text.includes('donjon') || text.includes('forteresse')
      || text.includes('chateau') || text.includes('pics');
    const wantsQuest = text.includes('quete') || text.includes('mission');
    const wantsCave = text.includes('cave') || text.includes('cellier');
    const wantsExit = text.includes('sortie') || text.includes('exterieur');

    if (wantsTavern) {
      (map.locationLinks || []).forEach((link) => {
        if (this.mapTitleMatchesKeywords(link.targetMapId, ['taverne', 'auberge', 'hostellerie', 'port'])) {
          candidates.push({ x: link.x, y: link.y });
        }
      });
      (map.markers || []).forEach((mk) => {
        const label = this.normalizeActionText(mk.label || '');
        if (label.includes('tavernier') || label.includes('auberge') || label.includes('taverne')) {
          candidates.push({ x: mk.x, y: mk.y });
        }
      });
    }

    if (wantsForest) {
      const nearForest = this.findForestCellsNearExplored(mapId, map);
      if (nearForest.length) candidates.push(...nearForest);
      else candidates.push(...this.findForestCells(map));
    }

    if (wantsCapital && !wantsTavern) {
      (map.markers || []).filter((m) => m.type === 'capital').forEach((mk) => {
        candidates.push({ x: mk.x, y: mk.y });
      });
    }

    if (wantsCity || (text.includes('port') && !wantsTavern)) {
      (map.markers || []).filter((m) => m.type === 'city').forEach((mk) => {
        candidates.push({ x: mk.x, y: mk.y });
      });
    }

    if (wantsRuin) {
      (map.markers || []).forEach((mk) => {
        if (mk.type === 'ruin' || this.normalizeActionText(mk.label || '').includes('ruine')) {
          candidates.push({ x: mk.x, y: mk.y });
        }
      });
    }

    if (wantsDungeon) {
      (map.markers || []).filter((m) => m.type === 'dungeon').forEach((mk) => {
        candidates.push({ x: mk.x, y: mk.y });
      });
    }

    if (wantsQuest) {
      (map.markers || []).filter((m) => m.type === 'quest').forEach((mk) => {
        candidates.push({ x: mk.x, y: mk.y });
      });
    }

    if (wantsCave) {
      (map.markers || []).forEach((mk) => {
        const label = this.normalizeActionText(mk.label || '');
        if (label.includes('cave')) candidates.push({ x: mk.x, y: mk.y });
      });
    }

    if (wantsExit) {
      (map.markers || []).filter((m) => m.type === 'exit').forEach((mk) => {
        candidates.push({ x: mk.x, y: mk.y });
      });
    }

    (map.markers || []).forEach((mk) => {
      const label = this.normalizeActionText(mk.label || '');
      if (label.length >= 3 && text.includes(label)) candidates.push({ x: mk.x, y: mk.y });
    });

    (map.locationLinks || []).forEach((link) => {
      const label = this.normalizeActionText(link.label || '');
      if (label.length >= 3 && text.includes(label)) candidates.push({ x: link.x, y: link.y });
    });

    const hasPlaceIntent = wantsTavern || wantsForest || wantsCapital || wantsCity
      || wantsRuin || wantsDungeon || wantsQuest || wantsCave || wantsExit;
    if (!hasPlaceIntent) {
      const npc = this.findNpcMentionedInText(text);
      if (npc && (text.includes('ecoute') || text.includes('indications')
        || text.includes('conseils') || text.includes('suiv'))) {
        const keywords = this.npcLocationKeywords();
        for (const part of this.normalizeActionText(npc.name || '').split(' ')) {
          if (!keywords[part]) continue;
          keywords[part].forEach((kw) => {
            (map.markers || []).forEach((mk) => {
              const label = this.normalizeActionText(mk.label || '');
              if (label.includes(kw) || mk.type === kw || (kw === 'donjon' && mk.type === 'dungeon')) {
                candidates.push({ x: mk.x, y: mk.y });
              }
            });
          });
        }
      }
    }

    const unique = [];
    candidates.forEach((c) => {
      if (!unique.some((u) => u.x === c.x && u.y === c.y)) unique.push(c);
    });

    if (anchor && unique.length > 0) {
      if (wantsTavern) {
        const tavernOnly = unique.filter((c) => {
          const isLink = (map.locationLinks || []).some((l) => l.x === c.x && l.y === c.y);
          const isTavernMarker = (map.markers || []).some((mk) => {
            if (mk.x !== c.x || mk.y !== c.y) return false;
            const label = this.normalizeActionText(mk.label || '');
            return label.includes('tavernier') || label.includes('auberge') || label.includes('taverne');
          });
          return isLink || isTavernMarker;
        });
        if (tavernOnly.length) return [this.pickNearest(anchor, tavernOnly)];
      }
      return [this.pickNearest(anchor, unique)];
    }

    return unique;
  },

  resolveSemanticDestination(actionText, mapId, fromPos) {
    const text = this.normalizeActionText(actionText);
    if (!this.looksLikeMovementAction(text)) return null;
    if (typeof Maps === 'undefined') return null;
    Maps.load();
    const map = Maps.getById(mapId);
    if (!map) return null;

    const candidates = this.collectSemanticCandidates(mapId, map, text);
    if (candidates.length === 0) return null;
    if (candidates.length === 1) return candidates[0];
    return this.pickNearest(fromPos, candidates);
  },

  prepareCellForMove(mapId, x, y) {
    if (this.isCellAccessibleForMove(mapId, x, y)) return true;
    if (typeof Maps === 'undefined') return false;
    Maps.load();
    const map = Maps.getById(mapId);
    if (!map || !Maps.isWorldMap(map)) return false;
    const explored = new Set(this.getExploredCells(mapId));
    for (let ox = -1; ox <= 1; ox += 1) {
      for (let oy = -1; oy <= 1; oy += 1) {
        if (ox === 0 && oy === 0) continue;
        if (explored.has(this.cellKey(x + ox, y + oy))) {
          this.revealCell(mapId, x, y);
          this.revealWorldAt(mapId, x, y, 1);
          return this.isCellAccessibleForMove(mapId, x, y);
        }
      }
    }
    return false;
  },

  parseMovementDelta(actionText) {
    const text = this.normalizeActionText(actionText);
    if (!this.looksLikeMovementAction(text)) return null;
    if (this.hasSemanticDestinationIntent(text) && !this.hasExplicitCardinalDirection(text)) {
      return null;
    }

    if (text.includes('nord-est') || text.includes('nord est')) return { dx: 1, dy: -1 };
    if (text.includes('nord-ouest') || text.includes('nord ouest')) return { dx: -1, dy: -1 };
    if (text.includes('sud-est') || text.includes('sud est')) return { dx: 1, dy: 1 };
    if (text.includes('sud-ouest') || text.includes('sud ouest')) return { dx: -1, dy: 1 };
    if (text.includes('nord') || text.includes('north')) return { dx: 0, dy: -1 };
    if (text.includes('sud') || text.includes('south')) return { dx: 0, dy: 1 };
    if (text.includes('ouest') || text.includes('west')) return { dx: -1, dy: 0 };
    if (
      text.includes('l est')
      || text.includes(' vers est')
      || text.includes(' a l est')
      || text.includes(' au est')
      || text.includes(' east')
    ) {
      return { dx: 1, dy: 0 };
    }
    return null;
  },

  isCellAccessibleForMove(mapId, x, y) {
    if (typeof Maps === 'undefined') return true;
    Maps.load();
    const map = Maps.getById(mapId);
    if (!map) return false;
    if (x < 0 || y < 0 || x >= map.width || y >= map.height) return false;
    if (!Maps.isWorldMap(map)) return true;
    const nav = this.state?.mapNavigation || {};
    if (nav.view === 'local' || this.state?.status === 'completed') return true;
    return this.getExploredCells(mapId).includes(this.cellKey(x, y));
  },

  tryAutoMoveFromAction(actionText, memberId = null) {
    if (!this.state || this.state.status === 'completed') return false;
    const text = this.normalizeActionText(actionText);
    if (!this.looksLikeMovementAction(text)) return false;

    const actorId = memberId
      || this.getActiveMember()?.id
      || this.state.party.find((m) => m.isHuman)?.id
      || this.state.party[0]?.id;
    if (!actorId) return false;

    const mapId = this.getActivePlayMapId();
    if (!mapId) return false;

    const pos = this.getMemberTokenPosition(mapId, actorId);
    if (!pos) return false;

    let target = null;
    const delta = this.parseMovementDelta(actionText);
    if (delta) {
      target = { x: pos.x + delta.dx, y: pos.y + delta.dy };
      if (!this.prepareCellForMove(mapId, target.x, target.y)
        || !this.isCellWalkableForMove(mapId, target.x, target.y)) {
        target = null;
      }
    } else {
      const destination = this.resolveSemanticDestination(actionText, mapId, pos);
      if (destination) target = this.pickBestStepTowards(mapId, pos, destination);
    }

    if (!target || (target.x === pos.x && target.y === pos.y)) return false;

    this.placeMemberToken(mapId, target.x, target.y, actorId);
    this.save();
    return true;
  },

  applyMapPlayAction(mapId, x, y, tool) {
    if (!this.state || this.state.status === 'completed' || !tool) return;
    if (tool.mode === 'erase') {
      this.removeMapTokenAt(mapId, x, y);
    } else if (tool.mode === 'member') {
      this.placeMemberToken(mapId, x, y, tool.memberId);
    } else if (tool.mode === 'marker') {
      this.placeMarkerToken(mapId, x, y, tool.markerType);
    }
    this.save();
  },

  getSelectedSetupMapIds() {
    return [...document.querySelectorAll('#setup-maps-list input[name="setup-map"]:checked')]
      .map((el) => el.value)
      .filter(Boolean);
  },

  getSessionElapsedMs() {
    if (!this.state) return 0;
    if (this.state.status === 'completed' && this.state.playTimeMs != null) {
      return this.state.playTimeMs;
    }
    return Math.max(0, Date.now() - (this.state.createdAt || Date.now()));
  },

  formatSessionDuration(ms) {
    const totalSec = Math.floor(Math.max(0, ms) / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;

    if (h > 0) {
      return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    }
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  },

  formatSessionDurationLong(ms) {
    const totalSec = Math.floor(Math.max(0, ms) / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    const parts = [];
    if (h > 0) parts.push(`${h} h`);
    if (m > 0 || h > 0) parts.push(`${m} min`);
    parts.push(`${s} s`);
    return parts.join(' ');
  },

  updateSessionTimer() {
    const el = document.getElementById('session-timer');
    if (!el || !this.state) {
      el?.classList.add('hidden');
      return;
    }

    el.classList.remove('hidden');
    el.textContent = `⏱ ${this.formatSessionDuration(this.getSessionElapsedMs())}`;

    if (this.state.status === 'completed') {
      this.stopSessionTimer();
    }
  },

  startSessionTimer() {
    this.stopSessionTimer();
    this.updateSessionTimer();
    if (!this.state || this.state.status === 'completed') return;
    this.sessionTimerInterval = setInterval(() => this.updateSessionTimer(), 1000);
  },

  stopSessionTimer() {
    if (this.sessionTimerInterval) {
      clearInterval(this.sessionTimerInterval);
      this.sessionTimerInterval = null;
    }
  },

  bindSetupEvents() {
    document.getElementById('game-setup-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.startGame();
    });

    document.querySelectorAll('input[name="game-mode"]').forEach((radio) => {
      radio.addEventListener('change', () => this.updateSetupVisibility());
    });

    document.querySelectorAll('input[name="gm-type"]').forEach((radio) => {
      radio.addEventListener('change', () => this.updateSetupVisibility());
    });

    document.querySelectorAll('input[name="quest-format"]').forEach((radio) => {
      radio.addEventListener('change', () => {
        this.refreshSetupCharacters();
        if (typeof Maps !== 'undefined') {
          Maps.load();
          const scenarioId = document.getElementById('setup-scenario')?.value || '';
          const questFormat = this.getSetupQuestFormat();
          this.refreshSetupMaps(Maps.getDefaultSelectedMapIds(scenarioId, questFormat));
        }
      });
    });

    document.getElementById('setup-scenario')?.addEventListener('change', () => {
      const questFormat = this.getSetupQuestFormat();
      this.refreshSetupCharacters();
      if (typeof Maps !== 'undefined') {
        Maps.load();
        const scenarioId = document.getElementById('setup-scenario')?.value || '';
        const linked = Maps.getDefaultSelectedMapIds(scenarioId, questFormat);
        this.refreshSetupMaps(linked.length ? linked : null);
      } else {
        this.refreshSetupMaps();
      }
    });

    document.getElementById('setup-party-size')?.addEventListener('input', () => this.updateSetupVisibility());

    document.getElementById('btn-add-player-slot').addEventListener('click', () => {
      const slots = document.querySelectorAll('.player-slot');
      if (slots.length < this.getSetupPartySize()) this.addPlayerSlot(slots.length + 1);
    });
  },

  bindSessionEvents() {
    document.getElementById('btn-end-game').addEventListener('click', () => this.endGame());
    document.getElementById('btn-player-action').addEventListener('click', () => this.submitPlayerAction());
    document.getElementById('player-action-input').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') this.submitPlayerAction();
    });

    document.getElementById('btn-gm-narrate').addEventListener('click', () => this.gmNarrate());
    document.getElementById('btn-gm-next-scene').addEventListener('click', () => this.gmNextScene());

    this.bindSessionDiceEvents();

    document.getElementById('btn-game-help').addEventListener('click', () => this.openHelp());
    document.getElementById('btn-close-help').addEventListener('click', () => this.closeHelp());
    document.getElementById('help-modal-backdrop').addEventListener('click', () => this.closeHelp());

    document.getElementById('btn-download-summary').addEventListener('click', () => this.downloadAdventureSummary());
    document.getElementById('btn-close-summary').addEventListener('click', () => this.closeAdventureSummary());
    document.getElementById('btn-close-summary-alt').addEventListener('click', () => this.closeAdventureSummary());
    document.getElementById('summary-modal-backdrop').addEventListener('click', () => this.closeAdventureSummary());
    document.getElementById('btn-show-summary').addEventListener('click', () => this.showAdventureSummaryModal());

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        this.closeHelp();
        this.closeAdventureSummary();
      }
    });
  },

  openHelp() {
    this.renderHelp();
    document.getElementById('help-modal').classList.remove('hidden');
  },

  closeHelp() {
    document.getElementById('help-modal').classList.add('hidden');
  },

  showAdventureSummaryModal() {
    if (!this.state) return;

    if (!this.state.adventureSummary) {
      const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
      const summary = AiGM.buildAdventureSummary(this.state, scenario);
      this.state.adventureSummary = summary.markdown;
      this.state.adventureSummaryFilename = summary.filename;
      this.save();
    }

    const preview = document.getElementById('summary-preview');
    preview.textContent = this.state.adventureSummary;
    document.getElementById('summary-modal').classList.remove('hidden');
  },

  closeAdventureSummary() {
    document.getElementById('summary-modal')?.classList.add('hidden');
  },

  downloadAdventureSummary() {
    if (!this.state?.adventureSummary) return;

    const blob = new Blob([this.state.adventureSummary], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = this.state.adventureSummaryFilename || 'openquest-jdr-resume.md';
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  },

  completeAdventure() {
    if (!this.state || this.state.status === 'completed') return;

    const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
    this.state.status = 'completed';
    this.state.completedAt = Date.now();
    this.state.playTimeMs = this.getSessionElapsedMs();
    this.stopSessionTimer();
    this.updateSessionTimer();

    const summary = AiGM.buildAdventureSummary(this.state, scenario);
    this.state.adventureSummary = summary.markdown;
    this.state.adventureSummaryFilename = summary.filename;

    if (this.state.aiState) {
      AiGM.addChronicleEntry(
        this.state.aiState,
        this.state.currentSceneIndex,
        `Fin de l'aventure « ${scenario?.title || ''} » — le groupe a mené la quête à son terme.`,
      );
    }

    const author = this.state.gmType === 'ai' ? 'MJ IA' : this.state.gmName;
    this.addLog(
      'gm',
      author,
      '**🎉 Fin de l\'aventure !** Vous avez parcouru toutes les scènes. Un résumé complet est disponible au téléchargement.',
    );

    this.revealAllWorldMaps();
    this.save();
    this.showAdventureSummaryModal();
    this.renderSession();
  },

  getSetupPartySize() {
    const input = document.getElementById('setup-party-size');
    const val = parseInt(input?.value, 10);
    if (Number.isNaN(val)) return 3;
    return Math.max(2, Math.min(this.MAX_PARTY_SIZE, val));
  },

  updateSetupVisibility() {
    const mode = document.querySelector('input[name="game-mode"]:checked')?.value;
    const gmType = document.querySelector('input[name="gm-type"]:checked')?.value;
    const partySize = this.getSetupPartySize();

    const sizeInput = document.getElementById('setup-party-size');
    if (sizeInput) sizeInput.value = partySize;

    document.getElementById('setup-solo-char').classList.toggle('hidden', mode !== 'solo');
    document.getElementById('setup-multi-players').classList.toggle('hidden', mode !== 'multi');
    document.getElementById('setup-human-gm').classList.toggle('hidden', gmType !== 'human');

    const hint = document.getElementById('setup-party-size-hint');
    if (hint) {
      if (mode === 'solo') {
        const bots = Math.max(1, partySize - 1);
        hint.textContent = `Solo : toi + ${bots} compagnon${bots > 1 ? 's' : ''} bot${bots > 1 ? 's' : ''} (${partySize} participants).`;
      } else {
        hint.textContent = `Multijoueur : ${partySize} participants au total (au moins 2 — humains + bots).`;
      }
    }

    const addBtn = document.getElementById('btn-add-player-slot');
    if (addBtn && mode === 'multi') {
      const slots = document.querySelectorAll('.player-slot').length;
      addBtn.disabled = slots >= partySize;
      addBtn.title = slots >= partySize ? `Maximum ${partySize} joueur(s) humain(s)` : '';
    }

    if (mode === 'multi' && document.querySelectorAll('.player-slot').length === 0) {
      this.initMultiPlayerSlots();
    }

    this.trimMultiPlayerSlots(partySize);
  },

  getSetupQuestFormat() {
    return document.querySelector('input[name="quest-format"]:checked')?.value || 'oneshot';
  },

  updateSetupTheme(format = null) {
    const questFormat = format || this.getSetupQuestFormat();
    const play = document.getElementById('play');
    if (!play) return;

    play.classList.remove('setup-theme-long', 'setup-theme-oneshot', 'setup-theme-investigation');
    const themeClass = {
      long: 'setup-theme-long',
      oneshot: 'setup-theme-oneshot',
      investigation: 'setup-theme-investigation',
    }[questFormat] || 'setup-theme-oneshot';
    play.classList.add(themeClass);
  },

  refreshSetupCharacters() {
    const questFormat = this.getSetupQuestFormat();
    this.updateSetupTheme(questFormat);
    const playerCharSelect = document.getElementById('setup-player-char');
    if (playerCharSelect) {
      const current = this.isCharacterOptionValidForFormat(playerCharSelect.value, questFormat)
        ? playerCharSelect.value
        : this.getDefaultCharacterOption(questFormat);
      playerCharSelect.innerHTML = this.characterOptions(current, questFormat);
      const fallback = this.getDefaultCharacterOption(questFormat);
      playerCharSelect.value = [...playerCharSelect.options].some((o) => o.value === current)
        ? current
        : fallback;
    }

    document.querySelectorAll('.player-char').forEach((select) => {
      const current = this.isCharacterOptionValidForFormat(select.value, questFormat)
        ? select.value
        : this.getDefaultCharacterOption(questFormat);
      select.innerHTML = this.characterOptions(current, questFormat);
      const fallback = this.getDefaultCharacterOption(questFormat);
      select.value = [...select.options].some((o) => o.value === current)
        ? current
        : fallback;
    });

    this.refreshSetupScenarios();
    this.refreshSetupMaps();
    this.updateSetupVisibility();
  },

  refreshSetupMaps(selectedIds = null) {
    const container = document.getElementById('setup-maps-list');
    if (!container || typeof Maps === 'undefined') return;

    Maps.load();
    const scenarioId = document.getElementById('setup-scenario')?.value || '';
    const questFormat = this.getSetupQuestFormat();
    let current = selectedIds ?? this.getSelectedSetupMapIds();
    if (!Array.isArray(current)) current = current ? [current] : [];

    const pool = Maps.getSetupMapPool(scenarioId, questFormat);
    const validIds = new Set(pool.map((m) => m.id));
    current = current.filter((id) => validIds.has(id));
    if (!current.length) {
      current = Maps.getDefaultSelectedMapIds(scenarioId, questFormat).filter((id) => validIds.has(id));
    }

    container.innerHTML = Maps.renderSetupMapPicker(current, scenarioId, questFormat);
  },

  refreshSetupScenarios(selectedId = null) {
    const scenarioSelect = document.getElementById('setup-scenario');
    if (!scenarioSelect) return;

    const questFormat = this.getSetupQuestFormat();
    const currentRaw = selectedId || scenarioSelect.value;
    const current = this.isScenarioValidForFormat(currentRaw, questFormat)
      ? currentRaw
      : this.getDefaultScenarioId(questFormat);
    scenarioSelect.innerHTML = this.scenarioOptions(current, questFormat);
    scenarioSelect.value = scenarioSelect.querySelector(`option[value="${current}"]`)
      ? current
      : this.getDefaultScenarioId(questFormat);
  },

  getScenarioPool(questFormat) {
    if (questFormat === 'investigation') return Scenarios.getInvestigationScenarios();
    if (questFormat === 'long') return Scenarios.getLongScenarios();
    if (questFormat === 'oneshot') return Scenarios.getOneshotScenarios();
    return Scenarios.getGeneralScenarios();
  },

  isScenarioValidForFormat(scenarioId, questFormat) {
    if (!scenarioId) return false;
    const scenario = Scenarios.list.find((s) => s.id === scenarioId);
    if (!scenario) return false;
    if (questFormat === 'investigation') return scenario.roster === 'investigation';
    if (scenario.roster === 'investigation') return false;
    if (questFormat === 'long') return scenario.questFormat === 'long';
    if (questFormat === 'oneshot') return (scenario.questFormat || 'oneshot') !== 'long';
    return true;
  },

  getDefaultScenarioId(questFormat) {
    const pool = this.getScenarioPool(questFormat);
    if (questFormat === 'long') {
      const flagship = pool.find((s) => s.id === 'demo-couronne-fracturee');
      return flagship?.id || pool[0]?.id || '';
    }
    if (questFormat === 'investigation') {
      const flagship = pool.find((s) => s.id === 'inv-demo-serpent-noir');
      return flagship?.id || pool[0]?.id || '';
    }
    return pool[0]?.id || '';
  },

  scenarioOptions(selectedId = '', questFormat = null) {
    const format = questFormat || this.getSetupQuestFormat();
    const isInvestigation = format === 'investigation';

    const scenarios = this.getScenarioPool(format);

    if (scenarios.length === 0) {
      return isInvestigation
        ? '<option value="">Aucune enquête — crée-en une dans l\'onglet Enquête</option>'
        : '<option value="">Aucun scénario — crée-en un dans l\'onglet Aventures</option>';
    }

    const validSelected = this.isScenarioValidForFormat(selectedId, format) ? selectedId : '';

    return scenarios.map((s) => {
      const tag = s.roster === 'investigation' ? '🔍 ' : '';
      const selected = s.id === validSelected ? 'selected' : '';
      return `<option value="${s.id}" ${selected}>${tag}${s.title}</option>`;
    }).join('');
  },

  applySetupPreset(mode, gmType, questFormat, scenarioId) {
    if (mode) {
      const modeInput = document.querySelector(`input[name="game-mode"][value="${mode}"]`);
      if (modeInput) modeInput.checked = true;
    }
    if (gmType) {
      const gmInput = document.querySelector(`input[name="gm-type"][value="${gmType}"]`);
      if (gmInput) gmInput.checked = true;
    }
    if (questFormat) {
      const questInput = document.querySelector(`input[name="quest-format"][value="${questFormat}"]`);
      if (questInput) questInput.checked = true;
    }
    this.refreshSetupCharacters();
    if (scenarioId) {
      this.refreshSetupScenarios(scenarioId);
      const scenarioSelect = document.getElementById('setup-scenario');
      if (scenarioSelect) scenarioSelect.value = scenarioId;
    }
    if (typeof Maps !== 'undefined') {
      Maps.load();
      const format = questFormat || this.getSetupQuestFormat();
      const sid = scenarioId || document.getElementById('setup-scenario')?.value || '';
      this.refreshSetupMaps(Maps.getDefaultSelectedMapIds(sid, format));
    }
    this.updateSetupVisibility();
  },

  getQuestFormatLabel(format) {
    const labels = {
      long: 'Campagne longue',
      oneshot: 'One-shot',
      investigation: 'Mode enquête',
    };
    return labels[format] || 'One-shot';
  },

  trimMultiPlayerSlots(partySize) {
    const container = document.getElementById('multi-player-slots');
    if (!container) return;
    const slots = [...container.querySelectorAll('.player-slot')];
    while (slots.length > partySize) {
      slots.pop().remove();
    }
  },

  initMultiPlayerSlots() {
    const container = document.getElementById('multi-player-slots');
    if (!container) return;
    container.innerHTML = '';
    this.addPlayerSlot(1);
    this.addPlayerSlot(2);
  },

  addPlayerSlot(num) {
    const container = document.getElementById('multi-player-slots');
    if (!container) return;
    const max = this.getSetupPartySize();
    if (container.querySelectorAll('.player-slot').length >= max) return;

    const questFormat = this.getSetupQuestFormat();
    const div = document.createElement('div');
    div.className = 'player-slot sub-item';
    div.innerHTML = `
      <div class="form-row two-cols">
        <div>
          <label>Nom du joueur ${num}</label>
          <input type="text" class="player-name" placeholder="Joueur ${num}" value="Joueur ${num}">
        </div>
        <div>
          <label>Personnage</label>
          <select class="player-char">${this.characterOptions(this.getDefaultCharacterOption(questFormat), questFormat)}</select>
        </div>
      </div>
    `;
    container.appendChild(div);
  },

  isCharacterOptionValidForFormat(optionValue, questFormat) {
    if (!optionValue) return false;
    const isInvestigation = questFormat === 'investigation';

    if (optionValue.startsWith('bot:')) {
      const botId = optionValue.slice(4);
      return isInvestigation
        ? Bots.isInvestigationBot(botId)
        : !Bots.isInvestigationBot(botId);
    }

    const char = Characters.list.find((c) => c.id === optionValue);
    if (!char) return false;
    return questFormat === 'investigation'
      ? Characters.isInvestigation(char)
      : !Characters.isInvestigation(char);
  },

  getDefaultCharacterOption(questFormat) {
    const chars = Characters.getForQuestFormat(questFormat);

    if (chars.length > 0) return chars[0].id;

    const bots = Bots.getBotsForQuestFormat(questFormat);
    return bots[0] ? `bot:${bots[0].id}` : '';
  },

  characterOptions(selectedId = '', questFormat = null) {
    const format = questFormat || this.getSetupQuestFormat();
    const isInvestigation = format === 'investigation';
    const chars = Characters.getForQuestFormat(format);
    const bots = Bots.getBotsForQuestFormat(format);

    const validSelected = this.isCharacterOptionValidForFormat(selectedId, format)
      ? selectedId
      : '';

    const charOptions = chars
      .map((c) => `<option value="${c.id}" ${c.id === validSelected ? 'selected' : ''}>${isInvestigation ? '🔍 ' : ''}${c.name} (${c.class || '?'})</option>`)
      .join('');

    const botOptions = bots
      .map((b) => {
        const value = `bot:${b.id}`;
        return `<option value="${value}" ${value === validSelected ? 'selected' : ''}>${isInvestigation ? '🔍🤖 ' : '🤖 '}${b.name} (${b.class})</option>`;
      })
      .join('');

    if (chars.length === 0 && bots.length === 0) {
      return isInvestigation
        ? '<option value="">Aucun enquêteur — crée-en un dans l\'onglet Enquête</option>'
        : '<option value="">Aucun personnage — crée-en un dans l\'onglet Personnages</option>';
    }

    if (chars.length === 0) return botOptions;
    if (bots.length === 0) return charOptions;
    return charOptions + botOptions;
  },

  renderSetup() {
    Characters.load();
    Scenarios.load();
    Scenarios.ensureDemoScenario();
    Bots.load();

    if (typeof Maps !== 'undefined') {
      Maps.load();
      Maps.ensureDemoMap();
      Maps.ensureDemoInvestigationMap();
      Maps.ensureDemoWorldMap();
    }

    this.refreshSetupCharacters();
    this.refreshSetupMaps();
    this.updateSetupVisibility();
    this.renderSavedGamesInSetup();
  },

  renderSavedGamesInSetup() {
    const section = document.getElementById('play-saved-games');
    const list = document.getElementById('play-saved-games-list');
    if (!section || !list) return;

    const games = this.getPlayingGames();
    section.classList.toggle('hidden', games.length === 0);
    list.innerHTML = '';

    games.forEach((game) => {
      list.appendChild(this.buildSavedGameCard(game, {
        onResume: (id) => {
          this.resumeGame(id);
          if (typeof App !== 'undefined') App.renderSavedGamesList();
        },
        onDelete: (id) => {
          if (!confirm('Effacer cette partie ? Toute la progression sera perdue.')) return;
          this.deleteGame(id);
          this.renderSavedGamesInSetup();
          if (typeof App !== 'undefined') App.renderSavedGamesList();
        },
      }));
    });
  },

  buildSavedGameCard(game, handlers = {}) {
    const card = document.createElement('article');
    card.className = 'saved-game-card';

    const info = document.createElement('div');
    info.className = 'saved-game-info';

    const title = document.createElement('strong');
    title.textContent = `« ${Scenarios.list.find((s) => s.id === game.scenarioId)?.title || game.scenarioId || 'Aventure'} »`;
    info.appendChild(title);

    const meta = document.createElement('span');
    meta.textContent = this.getGamePartySummary(game);
    info.appendChild(meta);

    const actions = document.createElement('div');
    actions.className = 'saved-game-actions';

    const resumeBtn = document.createElement('button');
    resumeBtn.type = 'button';
    resumeBtn.className = 'btn btn-primary btn-sm';
    resumeBtn.textContent = '▶ Reprendre';
    resumeBtn.addEventListener('click', () => handlers.onResume?.(game.id));
    actions.appendChild(resumeBtn);

    const deleteBtn = document.createElement('button');
    deleteBtn.type = 'button';
    deleteBtn.className = 'btn btn-secondary btn-sm btn-danger';
    deleteBtn.textContent = '🗑 Effacer la partie';
    deleteBtn.addEventListener('click', () => handlers.onDelete?.(game.id));
    actions.appendChild(deleteBtn);

    card.appendChild(info);
    card.appendChild(actions);
    return card;
  },

  buildMemberFromCharId(charId, playerName = null, isHuman = true) {
    if (charId.startsWith('bot:')) {
      const botId = charId.replace('bot:', '');
      const archetype = Bots.getArchetype(botId) || Bots.getArchetypes()[0];
      const member = Bots.createPartyMember(archetype);
      member.isHuman = isHuman;
      member.playerName = playerName;
      return member;
    }

    const char = Characters.list.find((c) => c.id === charId);
    if (!char) return null;

    return {
      id: `party-${char.id}`,
      characterId: char.id,
      name: char.name,
      race: char.race,
      class: char.class,
      stats: { ...char.stats },
      hp: char.hp,
      maxHp: char.hp,
      ac: char.ac,
      isBot: !isHuman,
      isHuman,
      playerName,
      personality: null,
      traits: [],
      backstory: char.backstory,
    };
  },

  startGame() {
    try {
      const scenarioId = document.getElementById('setup-scenario').value;
      if (!scenarioId) {
        alert('Crée d\'abord un scénario dans l\'onglet Scénarios.');
        return;
      }

      let mapIds = this.expandMapIdsWithLinkedLocals(this.getSelectedSetupMapIds());
      if (!mapIds.length) {
        const questFormat = document.querySelector('input[name="quest-format"]:checked')?.value || 'oneshot';
        mapIds = this.expandMapIdsWithLinkedLocals(
          Maps.getDefaultSelectedMapIds(scenarioId, questFormat),
        );
      }

      const mode = document.querySelector('input[name="game-mode"]:checked').value;
      const gmType = document.querySelector('input[name="gm-type"]:checked').value;
      const questFormat = document.querySelector('input[name="quest-format"]:checked')?.value || 'oneshot';
      const gmName = document.getElementById('setup-gm-name').value.trim() || 'Maître du jeu';
      const partySize = this.getSetupPartySize();

      let party = [];

      if (mode === 'solo') {
        let charId = document.getElementById('setup-player-char').value;
        if (!charId || !this.isCharacterOptionValidForFormat(charId, questFormat)) {
          charId = this.getDefaultCharacterOption(questFormat) || (questFormat === 'investigation' ? 'bot:bot-inv-elise' : 'bot:bot-kael');
        }

        const hero = this.buildMemberFromCharId(charId, 'Toi', true);
        if (hero) {
          hero.isBot = false;
          party.push(hero);
        }

        const botCount = partySize - 1;
        if (botCount > 0) {
          const excludeIds = party.map((m) => m.characterId);
          const companions = Bots.generateCompanions(botCount, excludeIds, questFormat);
          if (companions.length < botCount) {
            alert(`Seulement ${companions.length} compagnon(s) bot disponible(s) — le groupe comptera ${party.length + companions.length} membres.`);
          }
          party = party.concat(companions);
        }
      } else {
        const slots = document.querySelectorAll('.player-slot');
        const selections = [...slots]
          .map((slot) => ({
            name: slot.querySelector('.player-name').value.trim(),
            charId: slot.querySelector('.player-char').value,
          }))
          .filter((s) => s.charId);

        if (selections.length > partySize) {
          alert(`Tu as ${selections.length} joueurs humains pour ${partySize} participants max. Réduis le nombre de joueurs ou augmente la taille du groupe.`);
          return;
        }

        const normalizedIds = selections.map((s) => Bots.normalizeId(s.charId));
        if (new Set(normalizedIds).size !== normalizedIds.length) {
          alert('Chaque joueur doit avoir un personnage différent.');
          return;
        }

        selections.forEach(({ name, charId }) => {
          const member = this.buildMemberFromCharId(charId, name, true);
          if (member) {
            member.isBot = false;
            party.push(member);
          }
        });

        if (document.getElementById('setup-fill-bots').checked && party.length < partySize) {
          const needed = partySize - party.length;
          const excludeIds = Bots.usedIdsFromParty(party);
          const companions = Bots.generateCompanions(needed, excludeIds, questFormat);
          if (companions.length < needed) {
            alert(`Seulement ${companions.length} bot(s) disponible(s) en complément — groupe de ${party.length + companions.length} membres.`);
          }
          party = party.concat(companions);
        }

        if (party.length > partySize) {
          party = party.slice(0, partySize);
        }
      }

      if (party.length === 0) {
        alert('Choisis au moins un personnage pour commencer.');
        return;
      }

      if (party.length < 2) {
        alert('Il faut au moins 2 participants pour jouer (toi + un compagnon, ou plusieurs joueurs).');
        return;
      }

      const scenario = Scenarios.list.find((s) => s.id === scenarioId);
      if (!scenario) {
        alert('Scénario introuvable. Recharge la page et réessaie.');
        return;
      }

      this.state = {
        id: 'game-' + Date.now(),
        scenarioId,
        mapIds,
        mapPlayState: {},
        mapNavigation: { view: 'world', worldMapId: null, localMapId: null, worldCell: null },
        mode,
        gmType,
        questFormat,
        gmName,
        party,
        partySizeTarget: partySize,
        currentSceneIndex: 0,
        turnIndex: 0,
        log: [],
        aiState: AiGM.createInitialState(),
        status: 'playing',
        createdAt: Date.now(),
      };

      this.save();
      this.showSession();

      if (gmType === 'ai') {
        const scene = scenario.scenes?.[0];
        AiGM.initWorld(this.state.aiState, scenario);
        AiGM.initQuestFormat(this.state.aiState, questFormat, scenario);
        AiGM.initTeamDynamics(this.state.aiState, party);
        AiGM.ensureSceneGoal(this.state, scene);
        const goal = AiGM.getSceneGoal(this.state.aiState);
        this.addLog('gm', 'MJ IA', AiGM.openingNarration(scenario, goal, this.state.aiState, this.state));
        const npcIntro = NpcAI.onSceneEnter(this.state, scenario, 0);
        if (npcIntro) this.addLog('gm', 'IA PNJ', npcIntro);
      } else {
        AiGM.initQuestFormat(this.state.aiState, questFormat, scenario);
        this.addLog('gm', this.state.gmName, AiGM.humanGmOpening(scenario, this.state));
      }

      this.renderSession();
      this.initAllWorldMapFog();
      this.ensurePartyTokensOnWorldMaps();
      this.renderSession();
    } catch (err) {
      console.error(err);
      alert('Erreur au lancement : ' + err.message);
    }
  },

  showSession() {
    document.getElementById('game-setup').classList.add('hidden');
    document.getElementById('game-session').classList.remove('hidden');
    if (this.state?.questFormat) {
      this.updateSetupTheme(this.state.questFormat);
    }
    this.startSessionTimer();
  },

  hideSession() {
    document.getElementById('game-setup').classList.remove('hidden');
    document.getElementById('game-session').classList.add('hidden');
    this.stopSessionTimer();
  },

  endGame() {
    if (!confirm('Quitter la partie en cours ?')) return;
    this.deleteGame(this.state?.id);
    if (typeof App !== 'undefined') App.renderSavedGamesList();
  },

  deleteActiveGame() {
    if (this.state?.id) {
      this.deleteGame(this.state.id);
      return;
    }
    this.stopSessionTimer();
    this.state = null;
    Storage.save(Storage.KEYS.activeGame, null);
    this.hideSession();
    this.renderSetup();
  },

  rememberAction(state, actionText) {
    if (!state.recentActions) state.recentActions = [];
    state.recentActions.push(actionText);
    if (state.recentActions.length > 15) state.recentActions.shift();
  },

  save() {
    if (!this.state) return;
    this.state.updatedAt = Date.now();
    const games = this.loadSavedGames();
    const idx = games.findIndex((g) => g.id === this.state.id);
    if (idx >= 0) games[idx] = this.state;
    else games.push(this.state);
    this.persistSavedGames(games);
    Storage.save(Storage.KEYS.lastActiveGameId, this.state.id);
  },

  addLog(type, author, text) {
    this.state.log.push({
      type,
      author,
      text,
      timestamp: new Date().toLocaleTimeString('fr-FR'),
    });
    this.save();
  },

  getActiveMember() {
    const heroes = this.state.party.filter((m) => m.isHuman || !this.state.party.some((p) => p.isHuman));
    if (this.state.mode === 'solo') {
      return heroes.find((m) => m.isHuman) || this.state.party[0];
    }
    const humanMembers = this.state.party.filter((m) => m.isHuman);
    if (humanMembers.length === 0) return this.state.party[this.state.turnIndex % this.state.party.length];
    return humanMembers[this.state.turnIndex % humanMembers.length];
  },

  nextTurn() {
    const humans = this.state.party.filter((m) => m.isHuman);
    if (humans.length > 1) {
      this.state.turnIndex = (this.state.turnIndex + 1) % humans.length;
    }
  },

  submitPlayerAction() {
    const input = document.getElementById('player-action-input');
    const action = input.value.trim();
    if (!action || !this.state || this.state.status === 'completed') return;

    const actor = this.getActiveMember();

    this.addLog('player', actor.name, action);
    input.value = '';

    this.tryAutoMoveFromAction(action, actor.id);

    if (this.state.gmType === 'ai') {
      this.processAiResponse(action, actor);
    } else {
      if (/explor|fouill|inspect|cherch|cartograph|voyage|carte|déplacement|deplacement/i.test(action)) {
        this.revealWorldOnExplore(4);
      }
      this.tryAutoMoveFromAction(action, actor.id);
      this.state.waitingForGm = true;
    }

    this.nextTurn();
    this.renderSession();
  },

  processAiResponse(playerAction, actor) {
    this.rememberAction(this.state.aiState, playerAction);
    const response = this.resolveAndLog(playerAction, actor);

    if (response.shouldAdvanceScene) {
      this.advanceScene(false);
    } else if (response.success && response.actionType === 'explore') {
      this.revealWorldOnExplore();
    }

    this.renderSession();

    this.runBotTurns({
      humanFailed: !response.success,
      humanActionType: response.actionType,
      excludeId: actor.id,
    });
  },

  /** Résout une action et l'ajoute au journal */
  resolveAndLog(actionText, actor) {
    const response = AiGM.resolveAction(this.state, actionText, actor);
    this.addLog('gm', 'MJ IA', response.gmText);
    this.save();
    return response;
  },

  /** Les bots jouent leur tour comme de vrais joueurs */
  runBotTurns(context) {
    const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
    const scene = scenario?.scenes?.[this.state.currentSceneIndex];
    const bots = Bots.getCompanions(this.state.party)
      .filter((b) => b.id !== context.excludeId);

    if (bots.length === 0) return;

    let delay = 600;

    bots.forEach((bot) => {
      setTimeout(() => {
        if (!this.state || this.state.gmType !== 'ai') return;

        const action = Bots.chooseAction(bot, {
          scene,
          scenario,
          humanFailed: context.humanFailed,
          humanActionType: context.humanActionType,
          recentActions: this.state.aiState.recentActions,
          storyBeat: this.state.aiState.storyBeat,
          worldFacts: this.state.aiState.world?.facts || [],
          worldFlags: this.state.aiState.world?.openFlags || {},
          sceneChanges: this.state.aiState.world?.sceneChanges?.[this.state.currentSceneIndex] || [],
          allNpcs: NpcAI.getAllNpcs(this.state, scenario),
          questFormat: this.state.questFormat || this.state.aiState?.questFormat,
        });

        this.rememberAction(this.state.aiState, action);

        this.addLog('player', bot.name, action);
        this.tryAutoMoveFromAction(action, bot.id);
        const response = AiGM.resolveAction(this.state, action, bot);
        this.addLog('gm', 'MJ IA', response.gmText);
        this.save();

        if (response.shouldAdvanceScene) {
          this.advanceScene(false);
        } else if (response.success && response.actionType === 'explore') {
          this.revealWorldOnExplore(3);
        }

        this.renderSession();
      }, delay);

      delay += 1200;
    });
  },

  gmNarrate() {
    const text = document.getElementById('gm-narration').value.trim();
    if (!text) return;
    this.addLog('gm', this.state.gmName, text);
    document.getElementById('gm-narration').value = '';
    this.state.waitingForGm = false;
    this.renderSession();
  },

  gmNextScene() {
    this.advanceScene(true);
    this.renderSession();
  },

  advanceScene(manual) {
    const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
    const nextIndex = this.state.currentSceneIndex + 1;

    if (!scenario?.scenes?.[nextIndex]) {
      this.completeAdventure();
      return;
    }

    this.state.currentSceneIndex = nextIndex;
    const scene = scenario.scenes[nextIndex];
    if (this.state.aiState) {
      AiGM.resetSceneMemory(this.state.aiState);
      this.state.aiState.lastSceneIndex = nextIndex;
      AiGM.ensureSceneGoal(this.state, scene);
      if (this.state.gmType === 'ai') {
        AiGM.addChronicleEntry(
          this.state.aiState,
          nextIndex,
          `Le groupe entre dans « ${scene.title} » — l'histoire continue.`,
        );
      }
    }

    const author = this.state.gmType === 'ai' ? 'MJ IA' : this.state.gmName;
    const goal = this.state.aiState ? AiGM.getSceneGoal(this.state.aiState) : 2;
    const text = this.state.gmType === 'ai'
      ? AiGM.formatSceneTransition(scenario, nextIndex, goal, this.state.aiState, this.state)
      : AiGM.formatSceneTransition(scenario, nextIndex, goal, null, this.state);

    this.addLog('gm', author, text);

    if (this.state.gmType === 'ai') {
      const npcIntro = NpcAI.onSceneEnter(this.state, scenario, nextIndex);
      if (npcIntro) this.addLog('gm', 'IA PNJ', npcIntro);
    }

    this.revealWorldOnSceneAdvance();
    this.save();
  },

  bindSessionDiceEvents() {
    const session = document.getElementById('game-session');
    if (!session || session.dataset.diceBound) return;
    session.dataset.diceBound = '1';

    session.addEventListener('click', (e) => {
      const btn = e.target.closest('.session-dice-btn');
      if (!btn) return;
      this.performSessionRoll(btn.dataset.roll);
    });

    document.getElementById('btn-session-dice-roll')?.addEventListener('click', () => {
      const input = document.getElementById('session-dice-input');
      this.performSessionRoll(input?.value?.trim() || '1d20');
    });
    document.getElementById('session-dice-input')?.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        this.performSessionRoll(e.target.value.trim() || '1d20');
      }
    });
  },

  getDiceRollAuthor() {
    if (this.state.waitingForGm) {
      return { author: this.state.gmName, type: 'gm' };
    }
    const actor = this.getActiveMember();
    return { author: actor?.name || 'Joueur', type: 'player' };
  },

  performSessionRoll(formula) {
    if (!this.state || this.state.gmType !== 'human' || this.state.status === 'completed') return;

    const result = Dice.roll(formula || '1d20');
    if (result.error) {
      alert(result.error);
      return;
    }

    const { author, type } = this.getDiceRollAuthor();
    const message = Dice.formatResult(result);
    this.addLog(type, author, message);
    this.showDiceFeedback(result, author);
    this.renderSession();
  },

  showDiceFeedback(result, author) {
    const el = document.getElementById('session-dice-feedback');
    if (!el) return;
    el.classList.remove('hidden');
    el.textContent = `Dernier jet (${author}) : ${result.total} (${result.formula})`;
  },

  renderSessionDice() {
    const panel = document.getElementById('session-dice-panel');
    const show = this.state?.gmType === 'human' && this.state?.status !== 'completed';
    panel?.classList.toggle('hidden', !show);
  },

  getHelpContent() {
    const ai = this.state?.gmType === 'ai';
    const solo = this.state?.mode === 'solo';

    let modeBlock = '';
    if (ai && solo) {
      modeBlock = '<p><strong>Ton mode :</strong> solo avec MJ IA. Tu joues ton héros, l\'IA raconte le reste.</p>';
    } else if (ai && !solo) {
      modeBlock = '<p><strong>Ton mode :</strong> multijoueur local avec MJ IA. Chaque joueur agit à son tour.</p>';
    } else if (!ai && solo) {
      modeBlock = '<p><strong>Ton mode :</strong> solo avec MJ joueur. Tu narres (panneau doré) et tu joues ton héros (zone du bas).</p>';
    } else {
      modeBlock = '<p><strong>Ton mode :</strong> multijoueur avec MJ joueur. Le MJ narre, les autres jouent leurs personnages.</p>';
    }

    const rules = ai ? `
      <h4>En pratique</h4>
      <ol>
        <li>Lis la scène dans la fenêtre <strong>Histoire</strong>.</li>
        <li>Écris ton action en bas, puis clique <strong>Agir</strong> (ou Entrée).</li>
        <li>Le MJ IA répond et lance les dés pour toi.</li>
        <li>Tes compagnons bots <strong>jouent après toi</strong> : action, jet de dé, réussite ou échec.</li>
        <li>Chaque scène demande un nombre variable de <strong>réussites</strong> (explorer ou parler) pour avancer — affiché dans le panneau Groupe.</li>
        <li>Le MJ IA <strong>construit le monde en direct</strong> : découvertes, relations PNJ, quêtes secondaires improvisées et tensions dans l'équipe (panneau <strong>Monde</strong>).</li>
        <li>À la <strong>fin de l'aventure</strong>, un résumé complet est généré et téléchargeable (📥).</li>
      </ol>
      <h4>Ce que le MJ IA improvise</h4>
      <ul>
        <li><strong>Quêtes secondaires</strong> — objectifs annexes pendant la quête principale (📜 dans l'histoire)</li>
        <li><strong>IA PNJ</strong> — génère et gère des personnages improvisés (👤 panneau PNJ)</li>
        <li><strong>Relations PNJ</strong> — confiance qui monte ou descend selon vos dialogues (💬)</li>
        <li><strong>Désaccords d'équipe</strong> — vos compagnons peuvent contester vos choix (⚡)</li>
        <li><strong>Fin d'aventure</strong> — résumé complet téléchargeable (📥)</li>
      </ul>
      <h4>Exemples d'actions</h4>
      <p>« J'examine la porte », « Je parle au fossoyeur », « J'attaque le gardien », « Je me cache ».</p>
      <h4>Les dés (automatiques)</h4>
      <ul>
        <li>Parler → charisme</li>
        <li>Explorer / fouiller → intelligence</li>
        <li>Combattre → force</li>
        <li>Se cacher → dextérité</li>
      </ul>
      <p>Les scènes avancent après un nombre variable de réussites (1 à 5 selon la scène) — visible sous « Objectif X/Y réussites ».</p>
    ` : `
      <h4>Rôle du MJ</h4>
      <ul>
        <li><strong>Publier la narration</strong> — décris une scène, un PNJ ou une conséquence</li>
        <li><strong>Scène suivante</strong> — passe au chapitre suivant</li>
        <li><strong>Lanceur de dés</strong> — un seul lanceur partagé (d4 à d20, formule libre) : attribué au MJ en attente de réponse, sinon au joueur actif</li>
      </ul>
      <h4>Rôle des joueurs</h4>
      <p>Chacun écrit son action puis clique <strong>Agir</strong>. Les jets de dés passent par le lanceur unique — le résultat s'affiche dans l'histoire.</p>
    `;

    return modeBlock + rules;
  },

  renderSession() {
    if (!this.state) return;

    if (this.state.questFormat) {
      this.updateSetupTheme(this.state.questFormat);
    }

    if (this.state.aiState && this.state.questFormat) {
      this.state.aiState.questFormat = this.state.questFormat;
    }

    const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
    document.getElementById('game-scenario-title').textContent = scenario?.title || 'Partie';

    const modeLabel = this.state.mode === 'solo' ? 'Solo' : 'Multijoueur local';
    const gmLabel = this.state.gmType === 'ai' ? 'MJ IA adaptatif' : `MJ : ${this.state.gmName}`;
    const questLabel = this.getQuestFormatLabel(this.state.questFormat || 'oneshot');
    const sizeLabel = `${this.state.party.length} participant${this.state.party.length > 1 ? 's' : ''}`;
    document.getElementById('game-mode-info').textContent = `${questLabel} · ${modeLabel} · ${gmLabel} · ${sizeLabel}`;

    this.renderParty();
    this.renderNpcPanel();
    this.renderLog();
    this.renderTurnIndicator();
    this.renderActionHint();
    this.renderGmPanel();
    this.renderSessionDice();
    if (typeof Maps !== 'undefined') {
      Maps.load();
      Maps.renderSessionMaps(this.state.mapIds, this.state);
    }
    this.updateSessionTimer();
    this.renderCompletedState();
    this.renderSuggestions();
    this.renderHelp();
  },

  renderNpcPanel() {
    const panel = document.getElementById('npc-info');
    const list = document.getElementById('npc-panel-list');
    if (!panel || !list || !this.state) return;

    const show = this.state.gmType === 'ai';
    panel.classList.toggle('hidden', !show);
    if (!show) return;

    list.innerHTML = NpcAI.renderPanelList(this.state, Scenarios.list.find((s) => s.id === this.state.scenarioId));
  },

  renderParty() {
    const list = document.getElementById('party-list');
    if (!list || !this.state?.party) return;

    list.innerHTML = this.state.party.map((m) => {
      const badge = typeof Maps !== 'undefined'
        ? Maps.getMemberEmoji(m, this.state?.questFormat)
        : (m.isBot ? '🤖' : '⚔️');
      const role = m.isHuman && m.playerName ? ` (${m.playerName})` : '';
      return `
        <li class="party-member ${m.isBot ? 'is-bot' : 'is-human'}">
          <span class="party-name">${badge} ${this.escape(m.name)}${role}</span>
          <span class="party-meta">${m.race || '?'} · ${m.class || '?'}</span>
          <span class="party-hp">❤️ ${m.hp}/${m.maxHp} · 🛡️ ${m.ac}</span>
        </li>`;
    }).join('');

    const gmBadge = document.getElementById('gm-status');
    if (this.state.gmType === 'ai') {
      gmBadge.textContent = 'MJ IA — raconte et lance les dés';
    } else {
      gmBadge.textContent = `MJ : ${this.state.gmName}`;
    }

    const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
    const scene = scenarioScene(this.state);
    const total = scenario?.scenes?.length || 1;
    const current = this.state.currentSceneIndex + 1;

    if (this.state.gmType === 'ai' && scene) {
      AiGM.ensureWorld(this.state.aiState);
      if (!this.state.aiState.world.initialized) {
        AiGM.initWorld(this.state.aiState, scenario);
      }
      AiGM.ensureSceneGoal(this.state, scene);
    }
    const goal = this.state.aiState?.sceneGoalRequired || 2;
    const progress = this.state.aiState?.sceneProgress || 0;

    document.getElementById('scene-progress').textContent =
      `Scène ${current}/${total} · Objectif ${progress}/${goal} réussites`;
    document.getElementById('current-scene-title').textContent = scene?.title || '—';

    const worldEl = document.getElementById('world-summary');
    const worldPanel = document.getElementById('world-info');
    if (worldPanel) {
      worldPanel.classList.toggle('hidden', this.state.gmType !== 'ai');
    }
    if (worldEl && this.state.gmType === 'ai') {
      worldEl.textContent = AiGM.getWorldSummary(this.state.aiState);
    }
  },

  renderLog() {
    const log = document.getElementById('game-log');
    const entries = this.state.log.filter((e) => e.type !== 'system');
    log.innerHTML = entries.map((entry) => `
      <div class="log-entry log-${entry.type}">
        <span class="log-author">${this.escape(entry.author)}</span>
        <span class="log-time">${entry.timestamp}</span>
        <div class="log-text">${this.formatLogText(entry.text)}</div>
      </div>
    `).join('');
    const layout = document.querySelector('#game-session .game-layout');
    if (layout) {
      layout.scrollTop = layout.scrollHeight;
    }
  },

  formatLogText(text) {
    return this.escape(text)
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/\n/g, '<br>');
  },

  renderTurnIndicator() {
    const el = document.getElementById('turn-indicator');
    const actor = this.getActiveMember();

    if (this.state.gmType === 'human' && this.state.mode === 'solo') {
      el.innerHTML = '<strong>Ton personnage :</strong> ' + this.escape(actor.name);
      return;
    }

    if (this.state.mode === 'solo') {
      el.innerHTML = `<strong>À ton tour</strong> — tu joues <em>${this.escape(actor.name)}</em>`;
      return;
    }

    el.innerHTML = `<strong>Tour de ${this.escape(actor.playerName || actor.name)}</strong> — personnage : <em>${this.escape(actor.name)}</em>`;
  },

  renderActionHint() {
    const el = document.getElementById('action-hint');
    if (!el) return;

    if (this.state.status === 'completed') {
      el.textContent = 'Aventure terminée — télécharge ton résumé ou quitte la partie.';
      return;
    }

    if (this.state.gmType === 'human') {
      if (this.state.waitingForGm) {
        el.textContent = `En attente : le MJ ${this.state.gmName} doit répondre via le panneau doré.`;
        return;
      }
      const isGmSolo = this.state.mode === 'solo';
      el.textContent = isGmSolo
        ? 'Zone joueur : décris l\'action de ton héros. Panneau doré = tu racontes l\'histoire.'
        : 'Chaque joueur écrit son action ici. Le MJ répond dans le panneau doré.';
      return;
    }

    el.textContent = 'Décris ton action, puis clique Agir. Tes compagnons bots joueront ensuite leur tour.';
  },

  renderHelp() {
    const content = document.getElementById('ingame-help-content');
    if (!content || !this.state) return;
    content.innerHTML = this.getHelpContent();
  },

  renderGmPanel() {
    const panel = document.getElementById('human-gm-panel');
    const show = this.state.gmType === 'human' && this.state.status !== 'completed';
    panel.classList.toggle('hidden', !show);
  },

  renderCompletedState() {
    const completed = this.state.status === 'completed';
    const actionPanel = document.getElementById('player-action-panel');
    const summaryBtn = document.getElementById('btn-show-summary');
    const input = document.getElementById('player-action-input');
    const actBtn = document.getElementById('btn-player-action');

    if (actionPanel) {
      actionPanel.classList.toggle('is-completed', completed);
    }
    if (summaryBtn) {
      summaryBtn.classList.toggle('hidden', !completed);
    }
    if (input) input.disabled = completed;
    if (actBtn) actBtn.disabled = completed;
  },

  renderSuggestions() {
    const container = document.getElementById('action-suggestions');
    if (this.state.gmType !== 'ai' || this.state.status === 'completed') {
      container.innerHTML = '';
      return;
    }

    const scenario = Scenarios.list.find((s) => s.id === this.state.scenarioId);
    const scene = scenario?.scenes?.[this.state.currentSceneIndex];
    const hooks = AiGM.getSceneHooks(scenario, scene, this.state);
    const obj = hooks.objects[0] || 'les alentours';
    const allNpcs = NpcAI.getAllNpcs(this.state, scenario);
    const npc = allNpcs[0]?.name;

    const suggestions = [
      `J'examine ${obj}`,
      npc ? `Je questionne ${npc}` : 'Je m\'approche et je parle',
      `J'avance prudemment dans ${hooks.title}`,
      /porte|passage/i.test(obj) ? `Je tente d'ouvrir ${obj}` : `Je fouille ${obj}`,
    ];

    const worldFacts = this.state.aiState?.world?.facts || [];
    if (worldFacts.length) {
      suggestions.unshift(`Je suis la piste : ${worldFacts[worldFacts.length - 1].text.slice(0, 50)}…`);
    }

    container.innerHTML = suggestions.map((s) =>
      `<button type="button" class="suggestion-btn">${s}</button>`
    ).join('');

    container.querySelectorAll('.suggestion-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        document.getElementById('player-action-input').value = btn.textContent;
      });
    });
  },

  escape(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
};

function scenarioScene(gameState) {
  const scenario = Scenarios.list.find((s) => s.id === gameState.scenarioId);
  return scenario?.scenes?.[gameState.currentSceneIndex];
}
