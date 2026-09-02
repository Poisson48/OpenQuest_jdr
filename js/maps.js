/**
 * maps.js — Création et gestion de cartes pour les parties.
 */

const Maps = {
  list: [],
  editingId: null,
  editingRoster: 'general',
  editingMapKind: 'local',
  selectedTile: 'grass',
  selectedMarker: 'party',
  tool: 'tile',
  sessionTool: null,
  sessionActiveMapId: null,
  sessionMapZoom: {},
  sessionMapPan: null,
  sessionMapSuppressClick: false,
  sessionMapNavAnim: null,
  selectedLinkTarget: '',

  ZOOM_WHEEL_SENSITIVITY: 0.0018,

  MEMBER_COLORS: ['#e8c547', '#47a8e8', '#e86a47', '#47e88a', '#b847e8', '#e89247'],
  MEMBER_PLAYER_EMOJIS: {
    general: ['⚔️', '🛡️', '🏹', '🗡️', '🪄', '🦅'],
    investigation: ['🔍', '🕵️', '📋', '🧢', '👤', '🗝️'],
  },

  TILES: {
    grass: { label: 'Herbe', color: '#3a6b45' },
    forest: { label: 'Forêt', color: '#1f4228' },
    stone: { label: 'Pierre', color: '#5c5c62' },
    sand: { label: 'Sable', color: '#c4a35a' },
    water: { label: 'Eau', color: '#2a5a8a' },
    wall: { label: 'Mur', color: '#2a2520' },
    road: { label: 'Route', color: '#6b5344' },
    floor: { label: 'Sol int.', color: '#4a4035' },
  },

  INVESTIGATION_TILES: {
    street: { label: 'Rue', color: '#3d3d42' },
    building: { label: 'Bâtiment', color: '#6b4a3a' },
    office: { label: 'Intérieur', color: '#5a5048' },
    alley: { label: 'Ruelle', color: '#2a2830' },
  },

  MARKERS: {
    party: { label: 'Héros', emoji: '⚔️' },
    npc: { label: 'PNJ', emoji: '🎭' },
    poi: { label: 'Point d\'intérêt', emoji: '📍' },
    danger: { label: 'Danger', emoji: '⚠️' },
    treasure: { label: 'Trésor', emoji: '💎' },
    exit: { label: 'Sortie', emoji: '🚪' },
  },

  INVESTIGATION_MARKERS: {
    detective: { label: 'Enquêteur', emoji: '🔍' },
    suspect: { label: 'Suspect', emoji: '🕵️' },
    evidence: { label: 'Indice', emoji: '📎' },
    witness: { label: 'Témoin', emoji: '🗣️' },
    crime: { label: 'Scène de crime', emoji: '🩸' },
  },

  INVESTIGATION_VISIBLE_MARKERS: ['detective', 'party', 'camp'],
  INVESTIGATION_HIDDEN_LOCAL: ['evidence', 'witness', 'suspect', 'crime', 'poi', 'danger'],
  INVESTIGATION_HIDDEN_WORLD: ['city', 'capital', 'quest', 'dungeon', 'ruin'],

  isInvestigationMapContext(map, questFormat) {
    return questFormat === 'investigation' || map?.roster === 'investigation';
  },

  isInvestigationHiddenMarker(type, map, questFormat) {
    if (!this.isInvestigationMapContext(map, questFormat)) return false;
    if (this.INVESTIGATION_VISIBLE_MARKERS.includes(type)) return false;
    if (this.isWorldMap(map)) return this.INVESTIGATION_HIDDEN_WORLD.includes(type);
    return this.INVESTIGATION_HIDDEN_LOCAL.includes(type);
  },

  isInvestigationHiddenLink(map, questFormat) {
    return this.isInvestigationMapContext(map, questFormat) && this.isWorldMap(map);
  },

  shouldShowSessionMarker(map, marker, questFormat, revealedSet) {
    if (!marker) return false;
    if (!this.isInvestigationHiddenMarker(marker.type, map, questFormat)) return true;
    return revealedSet.has(`${marker.x},${marker.y}`);
  },

  shouldShowSessionLink(map, x, y, questFormat, revealedLinkSet) {
    const link = this.getLocationLinkAt(map, x, y);
    if (!link?.targetMapId) return false;
    if (!this.isInvestigationHiddenLink(map, questFormat)) return true;
    return revealedLinkSet.has(`${x},${y}`);
  },

  WORLD_TILES: {
    ocean: { label: 'Océan', color: '#1a3a6a' },
    coast: { label: 'Côte', color: '#c4a35a' },
    plains: { label: 'Plaines', color: '#5a8a45' },
    hills: { label: 'Collines', color: '#6b7a4a' },
    mountain: { label: 'Montagnes', color: '#6b6b72' },
    desert: { label: 'Désert', color: '#d4b86a' },
    snow: { label: 'Neige', color: '#e8eef5' },
    swamp: { label: 'Marais', color: '#3a5a40' },
    city: { label: 'Ville', color: '#8a7a62' },
  },

  WORLD_MARKERS: {
    capital: { label: 'Capitale', emoji: '👑' },
    city: { label: 'Ville', emoji: '🏙️' },
    dungeon: { label: 'Donjon', emoji: '🏰' },
    quest: { label: 'Quête', emoji: '❗' },
    camp: { label: 'Camp', emoji: '⛺' },
    ruin: { label: 'Ruines', emoji: '🏛️' },
  },

  MERGEABLE_MARKERS: ['city', 'capital', 'camp', 'ruin', 'dungeon'],

  DEFAULT_SIZE: { width: 16, height: 12 },
  DEFAULT_WORLD_SIZE: { width: 48, height: 32 },

  SIZE_LIMITS_LOCAL: { min: 4, maxWidth: 40, maxHeight: 30 },
  SIZE_LIMITS_WORLD: { min: 16, maxWidth: 96, maxHeight: 64 },

  load() {
    this.list = Storage.loadArray(Storage.KEYS.maps);
    let changed = false;
    this.list.forEach((map) => {
      if (!map.roster) {
        map.roster = 'general';
        changed = true;
      }
      if (!map.mapKind) {
        map.mapKind = 'local';
        changed = true;
      }
      if (this.isWorldMap(map) && !Array.isArray(map.locationLinks)) {
        map.locationLinks = [];
        changed = true;
      }
    });
    if (changed) this.save();
  },

  save() {
    Storage.save(Storage.KEYS.maps, this.list);
  },

  generateId() {
    return `map-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  },

  escape(text) {
    const div = document.createElement('div');
    div.textContent = text ?? '';
    return div.innerHTML;
  },

  createEmptyMapData(width, height, roster = 'general', mapKind = 'local') {
    const { min, maxWidth, maxHeight } = this.getSizeLimits(mapKind);
    const w = Math.max(min, Math.min(maxWidth, width));
    const h = Math.max(min, Math.min(maxHeight, height));
    const defaultTile = this.getDefaultTile(roster, mapKind);
    return {
      tiles: Array(w * h).fill(defaultTile),
      markers: [],
      locationLinks: mapKind === 'world' ? [] : undefined,
      width: w,
      height: h,
    };
  },

  getLocationLinkAt(map, x, y) {
    if (!map?.locationLinks?.length) return null;
    return map.locationLinks.find((l) => l.x === x && l.y === y) || null;
  },

  getLinkedLocalMapIds(worldMap) {
    if (!worldMap?.locationLinks?.length) return [];
    return [...new Set(worldMap.locationLinks.map((l) => l.targetMapId).filter(Boolean))];
  },

  getLocalMapsForLinking(roster = 'general') {
    if (this.isInvestigationRoster(roster)) return this.getLocalInvestigationMaps();
    return this.getLocalAdventureMaps();
  },

  isWorldMap(mapOrKind) {
    const kind = typeof mapOrKind === 'string' ? mapOrKind : mapOrKind?.mapKind;
    return kind === 'world';
  },

  getSizeLimits(mapKind = 'local') {
    return this.isWorldMap(mapKind) ? this.SIZE_LIMITS_WORLD : this.SIZE_LIMITS_LOCAL;
  },

  isInvestigationRoster(roster) {
    return roster === 'investigation';
  },

  getDefaultTile(roster = 'general', mapKind = 'local') {
    if (this.isWorldMap(mapKind)) return 'ocean';
    return this.isInvestigationRoster(roster) ? 'street' : 'grass';
  },

  getDefaultMarker(roster = 'general', mapKind = 'local') {
    if (this.isWorldMap(mapKind)) return 'camp';
    return this.isInvestigationRoster(roster) ? 'detective' : 'party';
  },

  getTileDef(tile) {
    return this.TILES[tile]
      || this.INVESTIGATION_TILES[tile]
      || this.WORLD_TILES[tile]
      || { label: tile };
  },

  getMarkerDef(type) {
    return this.MARKERS[type]
      || this.INVESTIGATION_MARKERS[type]
      || this.WORLD_MARKERS[type]
      || { label: type, emoji: '•' };
  },

  isMergeableMarker(type) {
    return this.MERGEABLE_MARKERS.includes(type);
  },

  getMarkerClusterInfo(map) {
    const markerAt = (x, y) => map.markers?.find((mk) => mk.x === x && mk.y === y);
    const visited = new Set();
    const cellInfo = {};

    map.markers?.forEach((mk) => {
      const key = `${mk.x},${mk.y}`;
      if (visited.has(key) || !this.isMergeableMarker(mk.type)) return;
      const stack = [[mk.x, mk.y]];
      const cluster = [];
      while (stack.length) {
        const [cx, cy] = stack.pop();
        const ck = `${cx},${cy}`;
        if (visited.has(ck)) continue;
        const cellMarker = markerAt(cx, cy);
        if (!cellMarker || cellMarker.type !== mk.type) continue;
        visited.add(ck);
        cluster.push([cx, cy]);
        stack.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
      }
      if (cluster.length < 2) return;
      cluster.sort((a, b) => (a[1] - b[1]) || (a[0] - b[0]));
      const [anchorX, anchorY] = cluster[0];
      cluster.forEach(([cx, cy]) => {
        cellInfo[`${cx},${cy}`] = {
          cluster: true,
          anchor: cx === anchorX && cy === anchorY,
          size: cluster.length,
          type: mk.type,
        };
      });
    });
    return cellInfo;
  },

  getLocalAdventureMaps() {
    return this.list.filter((m) => !this.isInvestigationRoster(m.roster) && !this.isWorldMap(m));
  },

  getLocalInvestigationMaps() {
    return this.list.filter((m) => this.isInvestigationRoster(m.roster) && !this.isWorldMap(m));
  },

  getWorldMaps() {
    return this.list.filter((m) => this.isWorldMap(m));
  },

  getAdventureMaps() {
    return this.getLocalAdventureMaps();
  },

  getInvestigationMaps() {
    return this.getLocalInvestigationMaps();
  },

  getMapsForFormat(questFormat) {
    const isInvestigation = questFormat === 'investigation';
    const local = isInvestigation ? this.getLocalInvestigationMaps() : this.getLocalAdventureMaps();
    const world = this.getWorldMaps().filter((m) => (
      isInvestigation ? this.isInvestigationRoster(m.roster) : !this.isInvestigationRoster(m.roster)
    ));
    return [...world, ...local];
  },

  getEditorCellSize(width, height) {
    const maxDim = Math.max(width, height);
    if (maxDim <= 24) return 24;
    if (maxDim <= 40) return 18;
    if (maxDim <= 60) return 14;
    if (maxDim <= 80) return 11;
    return 9;
  },

  getSizeFromInputs() {
    const width = parseInt(document.getElementById('map-width')?.value, 10);
    const height = parseInt(document.getElementById('map-height')?.value, 10);
    const mapKind = document.getElementById('map-kind')?.value || this.editingMapKind || 'local';
    const defaults = this.isWorldMap(mapKind) ? this.DEFAULT_WORLD_SIZE : this.DEFAULT_SIZE;
    const { min, maxWidth, maxHeight } = this.getSizeLimits(mapKind);
    return {
      width: Math.max(min, Math.min(maxWidth, Number.isNaN(width) ? defaults.width : width)),
      height: Math.max(min, Math.min(maxHeight, Number.isNaN(height) ? defaults.height : height)),
    };
  },

  updateSizeControls() {
    const mapKind = this.editingMapKind || document.getElementById('map-kind')?.value || 'local';
    const isWorld = this.isWorldMap(mapKind);
    const { min, maxWidth, maxHeight } = this.getSizeLimits(mapKind);
    const widthInput = document.getElementById('map-width');
    const heightInput = document.getElementById('map-height');
    const intro = document.getElementById('map-size-intro');

    if (widthInput) {
      widthInput.min = min;
      widthInput.max = maxWidth;
    }
    if (heightInput) {
      heightInput.min = min;
      heightInput.max = maxHeight;
    }

    document.getElementById('map-size-presets-local')?.classList.toggle('hidden', isWorld);
    document.getElementById('map-size-presets-world')?.classList.toggle('hidden', !isWorld);

    if (intro) {
      intro.textContent = isWorld
        ? `Carte du monde — jusqu'à ${maxWidth}×${maxHeight} carrés. Peins les océans, continents et royaumes.`
        : 'Définis le nombre de carrés en largeur et en hauteur. La grille se met à jour automatiquement.';
    }
  },

  updateSizeSummary() {
    const el = document.getElementById('map-size-summary');
    if (!el) return;
    const { width, height } = this.getSizeFromInputs();
    const total = width * height;
    el.textContent = `${width} × ${height} = ${total} carré${total > 1 ? 's' : ''}`;

    document.querySelectorAll('.map-preset-btn').forEach((btn) => {
      const w = parseInt(btn.dataset.mapW, 10);
      const h = parseInt(btn.dataset.mapH, 10);
      const presetWorld = btn.closest('#map-size-presets-world') != null;
      const isWorld = this.isWorldMap(this.editingMapKind);
      if (presetWorld !== isWorld) {
        btn.classList.remove('active');
        return;
      }
      btn.classList.toggle('active', w === width && h === height);
    });
  },

  applySizePreset(width, height) {
    const widthInput = document.getElementById('map-width');
    const heightInput = document.getElementById('map-height');
    if (widthInput) widthInput.value = width;
    if (heightInput) heightInput.value = height;
    this.applyEditorSize();
  },

  ensureDemoMap() {
    if (this.list.some((m) => m.id === 'demo-taverne')) {
      const taverne = this.getById('demo-taverne');
      if (taverne && !taverne.markers.some((m) => m.type === 'exit')) {
        taverne.markers.push({ x: 1, y: 5, type: 'exit', label: 'Sortie' });
        this.save();
      }
      return;
    }

    const { width, height, tiles } = this.createEmptyMapData(14, 10, 'general', 'local');
    const set = (x, y, tile) => {
      tiles[y * width + x] = tile;
    };

    for (let x = 0; x < width; x += 1) {
      set(x, 0, 'wall');
      set(x, height - 1, 'wall');
    }
    for (let y = 0; y < height; y += 1) {
      set(0, y, 'wall');
      set(width - 1, y, 'wall');
    }
    for (let x = 2; x < width - 2; x += 1) {
      for (let y = 2; y < height - 2; y += 1) {
        set(x, y, 'floor');
      }
    }
    set(1, 5, 'floor');
    set(width - 2, 4, 'floor');
    set(6, 1, 'floor');
    set(3, 3, 'water');
    set(4, 3, 'water');
    set(9, 6, 'stone');
    set(10, 6, 'stone');

    this.list.push({
      id: 'demo-taverne',
      title: 'Taverne du Vieux Port',
      description: 'Plan de la taverne et de la cave — idéal pour une scene d\'introduction ou une embuscade.',
      roster: 'general',
      mapKind: 'local',
      scenarioId: '',
      width,
      height,
      tiles,
      markers: [
        { x: 2, y: 5, type: 'party', label: 'Entrée' },
        { x: 1, y: 5, type: 'exit', label: 'Sortie' },
        { x: 7, y: 5, type: 'npc', label: 'Tavernier' },
        { x: 10, y: 3, type: 'poi', label: 'Cave' },
      ],
      updatedAt: Date.now(),
    });
    this.save();
  },

  ensureDemoInvestigationMap() {
    if (this.list.some((m) => m.id === 'demo-quartier-serpent')) return;

    const { width, height, tiles } = this.createEmptyMapData(16, 12, 'investigation', 'local');
    const set = (x, y, tile) => {
      tiles[y * width + x] = tile;
    };

    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        set(x, y, 'street');
      }
    }

    for (let x = 3; x <= 12; x += 1) set(x, 3, 'building');
    for (let x = 3; x <= 12; x += 1) set(x, 8, 'building');
    for (let y = 4; y <= 7; y += 1) {
      set(3, y, 'building');
      set(12, y, 'building');
    }
    for (let x = 5; x <= 10; x += 1) {
      for (let y = 5; y <= 6; y += 1) set(x, y, 'office');
    }
    set(1, 5, 'alley');
    set(2, 5, 'alley');
    set(14, 6, 'alley');
    set(7, 1, 'road');
    set(8, 1, 'road');
    set(7, 10, 'road');
    set(8, 10, 'road');
    set(0, 5, 'wall');
    set(15, 6, 'wall');

    this.list.push({
      id: 'demo-quartier-serpent',
      title: 'Quartier du Serpent Noir',
      description: 'Plan du quartier dockland — commissariat, ruelles et entrepôts pour l\'affaire du Serpent Noir.',
      roster: 'investigation',
      mapKind: 'local',
      scenarioId: 'inv-demo-serpent-noir',
      width,
      height,
      tiles,
      markers: [
        { x: 7, y: 6, type: 'detective', label: 'Équipe' },
        { x: 10, y: 5, type: 'evidence', label: 'Indice' },
        { x: 1, y: 5, type: 'crime', label: 'Corps' },
        { x: 14, y: 6, type: 'suspect', label: 'Fuyard' },
        { x: 4, y: 4, type: 'witness', label: 'Témoin' },
      ],
      updatedAt: Date.now(),
    });
    this.save();
  },

  ensureDemoWorldMap() {
    if (this.list.some((m) => m.id === 'demo-monde-couronne')) {
      const existing = this.getById('demo-monde-couronne');
      if (existing && (!existing.locationLinks || !existing.locationLinks.length)) {
        existing.locationLinks = [
          { x: 12, y: 13, targetMapId: 'demo-taverne', label: 'Port' },
          { x: 24, y: 16, targetMapId: 'demo-taverne', label: 'Capitale' },
        ];
        this.save();
      }
      return;
    }

    const width = 48;
    const height = 32;
    const tiles = Array(width * height).fill('ocean');
    const set = (x, y, tile) => {
      if (x >= 0 && x < width && y >= 0 && y < height) {
        tiles[y * width + x] = tile;
      }
    };
    const fillEllipse = (cx, cy, rx, ry, tile) => {
      for (let y = 0; y < height; y += 1) {
        for (let x = 0; x < width; x += 1) {
          const dx = (x - cx) / rx;
          const dy = (y - cy) / ry;
          if ((dx * dx) + (dy * dy) <= 1) set(x, y, tile);
        }
      }
    };

    fillEllipse(24, 17, 15, 9, 'plains');
    fillEllipse(10, 12, 6, 5, 'forest');
    fillEllipse(36, 14, 5, 4, 'hills');
    fillEllipse(24, 8, 10, 3, 'mountain');
    fillEllipse(24, 6, 8, 2, 'snow');
    fillEllipse(38, 22, 4, 3, 'desert');
    fillEllipse(8, 22, 3, 2, 'swamp');

    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const tile = tiles[y * width + x];
        if (tile === 'plains' || tile === 'forest' || tile === 'hills') {
          const nearOcean = [
            [x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1],
          ].some(([nx, ny]) => nx >= 0 && nx < width && ny >= 0 && ny < height
            && tiles[ny * width + nx] === 'ocean');
          if (nearOcean) set(x, y, 'coast');
        }
      }
    }

    set(22, 16, 'city');
    set(24, 16, 'city');
    set(26, 15, 'city');
    set(12, 13, 'city');
    set(35, 14, 'city');

    this.list.push({
      id: 'demo-monde-couronne',
      title: 'Les Terres de la Couronne Fracturée',
      description: 'Carte du monde — royaumes en guerre, chaîne de montagnes au nord et cités disputées au centre.',
      roster: 'general',
      mapKind: 'world',
      scenarioId: 'demo-couronne-fracturee',
      width,
      height,
      tiles,
      markers: [
        { x: 24, y: 16, type: 'capital', label: 'Capitale' },
        { x: 12, y: 13, type: 'city', label: 'Port' },
        { x: 35, y: 14, type: 'city', label: 'Mine' },
        { x: 24, y: 8, type: 'dungeon', label: 'Pics' },
        { x: 38, y: 22, type: 'quest', label: 'Quête' },
        { x: 22, y: 18, type: 'party', label: 'Groupe' },
        { x: 8, y: 22, type: 'ruin', label: 'Ruines' },
      ],
      locationLinks: [
        { x: 12, y: 13, targetMapId: 'demo-taverne', label: 'Port' },
        { x: 24, y: 16, targetMapId: 'demo-taverne', label: 'Capitale' },
      ],
      updatedAt: Date.now(),
    });
    this.save();
  },

  getById(id) {
    return this.list.find((m) => m.id === id) || null;
  },

  init() {
    this.load();
    this.ensureDemoMap();
    this.ensureDemoInvestigationMap();
    this.ensureDemoWorldMap();
    this.bindEvents();
    this.renderList();
  },

  bindEvents() {
    document.getElementById('btn-new-map-adventure')?.addEventListener('click', () => {
      this.showEditor(null, { roster: 'general', mapKind: 'local' });
    });
    document.getElementById('btn-new-map-investigation')?.addEventListener('click', () => {
      this.showEditor(null, { roster: 'investigation', mapKind: 'local' });
    });
    document.getElementById('btn-new-map-world')?.addEventListener('click', () => {
      this.showEditor(null, { roster: 'general', mapKind: 'world' });
    });
    document.getElementById('btn-cancel-map')?.addEventListener('click', () => this.hideEditor());
    document.getElementById('map-form-el')?.addEventListener('submit', (e) => this.handleSubmit(e));
    document.getElementById('btn-map-apply-size')?.addEventListener('click', () => this.applyEditorSize());
    document.getElementById('btn-map-clear')?.addEventListener('click', () => this.clearEditorGrid());

    ['map-width', 'map-height'].forEach((id) => {
      const input = document.getElementById(id);
      input?.addEventListener('input', () => this.updateSizeSummary());
      input?.addEventListener('change', () => this.applyEditorSize());
    });

    document.querySelectorAll('.map-preset-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.applySizePreset(parseInt(btn.dataset.mapW, 10), parseInt(btn.dataset.mapH, 10));
      });
    });

    document.querySelectorAll('[data-map-tool]').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.tool = btn.dataset.mapTool;
        document.querySelectorAll('[data-map-tool]').forEach((b) => {
          b.classList.toggle('active', b.dataset.mapTool === this.tool);
        });
      });
    });

    document.getElementById('map-link-target')?.addEventListener('change', (e) => {
      this.selectedLinkTarget = e.target.value;
      this.tool = 'link';
      document.querySelectorAll('[data-map-tool]').forEach((b) => {
        b.classList.toggle('active', b.dataset.mapTool === 'link');
      });
    });

    document.querySelectorAll('[data-map-tile]').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.selectedTile = btn.dataset.mapTile;
        this.tool = 'tile';
        document.querySelectorAll('[data-map-tool]').forEach((b) => {
          b.classList.toggle('active', b.dataset.mapTool === 'tile');
        });
        document.querySelectorAll('[data-map-tile]').forEach((b) => {
          b.classList.toggle('active', b.dataset.mapTile === this.selectedTile);
        });
      });
    });

    document.querySelectorAll('[data-map-marker]').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.selectedMarker = btn.dataset.mapMarker;
        this.tool = 'marker';
        document.querySelectorAll('[data-map-tool]').forEach((b) => {
          b.classList.toggle('active', b.dataset.mapTool === 'marker');
        });
        document.querySelectorAll('[data-map-marker]').forEach((b) => {
          b.classList.toggle('active', b.dataset.mapMarker === this.selectedMarker);
        });
      });
    });
  },

  renderList() {
    this.renderMapList('map-list-world', this.getWorldMaps(), {
      emptyTitle: 'Aucune carte du monde.',
      emptyHint: 'Crée une carte complète avec continents, royaumes et villes pour ta campagne longue.',
      world: true,
    });
    this.renderMapList('map-list-adventure', this.getAdventureMaps(), {
      emptyTitle: 'Aucune scène aventure.',
      emptyHint: 'Crée un donjon, une taverne ou une zone d\'exploration locale.',
    });
    this.renderMapList('map-list-investigation', this.getInvestigationMaps(), {
      emptyTitle: 'Aucune scène enquête.',
      emptyHint: 'Crée un quartier, un commissariat ou une scène de crime locale.',
      investigation: true,
    });
  },

  renderMapList(containerId, maps, options = {}) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (maps.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>${options.emptyTitle || 'Aucune carte.'}</p>
          <p>${options.emptyHint || ''}</p>
        </div>`;
      return;
    }

    container.innerHTML = maps.map((m) => {
      const badge = options.world ? '🌍' : (options.investigation ? '🔍' : '⚔️');
      const cardClass = options.world
        ? ' card-map-world'
        : (options.investigation ? ' card-map-investigation' : '');
      const badgeClass = options.world
        ? ' map-badge-world'
        : (options.investigation ? ' map-badge-investigation' : '');
      const previewCells = options.world ? 200 : 120;
      const previewCellSize = options.world ? 6 : 10;
      return `
      <article class="card card-map${cardClass}" data-id="${m.id}">
        <span class="bot-badge map-badge${badgeClass}">${badge} ${m.width}×${m.height}</span>
        <h3>${this.escape(m.title)}</h3>
        <p class="card-meta">${m.markers?.length || 0} marqueur(s) · ${m.width * m.height} carrés</p>
        <p class="map-card-desc">${this.escape((m.description || 'Sans description').slice(0, 100))}${(m.description || '').length > 100 ? '…' : ''}</p>
        <div class="map-card-preview">${this.renderGridHtml(m, { cellSize: previewCellSize, maxCells: previewCells })}</div>
        <div class="card-actions">
          <button type="button" class="btn btn-secondary btn-small btn-edit-map" data-id="${m.id}">Modifier</button>
          <button type="button" class="btn btn-danger btn-small btn-delete-map" data-id="${m.id}">Supprimer</button>
        </div>
      </article>`;
    }).join('');

    container.querySelectorAll('.btn-edit-map').forEach((btn) => {
      btn.addEventListener('click', () => this.showEditor(btn.dataset.id));
    });
    container.querySelectorAll('.btn-delete-map').forEach((btn) => {
      btn.addEventListener('click', () => this.delete(btn.dataset.id));
    });
  },

  renderGridHtml(map, options = {}) {
    if (!map?.tiles?.length) return '';
    const cellSize = options.cellSize || 24;
    const maxCells = options.maxCells || Infinity;
    const interactive = options.interactive || false;
    const editor = options.editor || false;
    const showLabels = options.showLabels !== false;
    const clusterInfo = options.editor ? this.getMarkerClusterInfo(map) : {};

    let html = `<div class="map-grid${interactive ? ' map-grid-interactive' : ''}${editor ? ' map-grid-editor' : ''}"
      style="--map-cell-size:${cellSize}px;grid-template-columns:repeat(${map.width},var(--map-cell-size))">`;

    for (let y = 0; y < map.height; y += 1) {
      for (let x = 0; x < map.width; x += 1) {
        if ((y * map.width + x) >= maxCells) break;
        const tile = map.tiles[y * map.width + x] || this.getDefaultTile(map.roster, map.mapKind);
        const marker = map.markers?.find((mk) => mk.x === x && mk.y === y);
        const link = map.locationLinks?.find((lk) => lk.x === x && lk.y === y);
        const cluster = clusterInfo[`${x},${y}`];
        const targetTitle = link?.targetMapId ? (this.getById(link.targetMapId)?.title || link.label || 'Lieu') : '';
        const title = link
          ? `Lien → ${targetTitle} (${x},${y})`
          : (marker
            ? `${marker.label || this.getMarkerDef(marker.type).label || marker.type} (${x},${y})`
            : `${this.getTileDef(tile).label || tile} (${x},${y})`);

        html += `<button type="button" class="map-cell map-cell-${tile}${marker ? ' has-marker' : ''}${link ? ' has-location-link' : ''}${cluster ? ' map-marker-cluster' : ''}${cluster?.anchor ? ' map-marker-cluster-anchor' : ''}"
          data-x="${x}" data-y="${y}" title="${this.escape(title)}"${interactive ? '' : ' tabindex="-1"'}>`;
        if (link) {
          html += '<span class="map-location-link-icon" aria-hidden="true">🌀</span>';
          if (showLabels && cellSize >= 20 && targetTitle) {
            html += `<span class="map-location-link-label">${this.escape(targetTitle.slice(0, 6))}</span>`;
          }
        } else if (marker) {
          const emoji = this.getMarkerDef(marker.type).emoji || '•';
          if (cluster && !cluster.anchor) {
            html += `<span class="map-marker map-marker-cluster-part">${emoji}</span>`;
          } else {
            const clusterClass = cluster?.anchor ? ` map-marker-merged map-marker-merged-${Math.min(cluster.size, 9)}` : '';
            html += `<span class="map-marker${clusterClass}">${emoji}</span>`;
          }
          if (showLabels && cellSize >= 20 && marker.label && !cluster) {
            html += `<span class="map-marker-label">${this.escape(marker.label.slice(0, 6))}</span>`;
          }
        }
        html += '</button>';
      }
    }

    html += '</div>';
    return html;
  },

  getEditorData() {
    const { width, height } = this.getSizeFromInputs();
    return this.editorData || this.createEmptyMapData(
      width,
      height,
      this.editingRoster,
      this.editingMapKind,
    );
  },

  getEditorTitle(mapKind, roster, isEdit = false) {
    const prefix = isEdit ? 'Modifier' : 'Nouvelle';
    if (this.isWorldMap(mapKind)) return `${prefix} carte du monde`;
    if (this.isInvestigationRoster(roster)) return `${prefix} scène enquête`;
    return `${prefix} scène aventure`;
  },

  showEditor(id = null, options = {}) {
    const form = document.getElementById('map-form');
    const titleEl = document.getElementById('map-form-title');
    form?.classList.remove('hidden');

    if (id) {
      const map = this.getById(id);
      if (!map) return;
      this.editingId = id;
      this.editingRoster = this.isInvestigationRoster(map.roster) ? 'investigation' : 'general';
      this.editingMapKind = this.isWorldMap(map) ? 'world' : 'local';
      titleEl.textContent = this.getEditorTitle(this.editingMapKind, this.editingRoster, true);
      document.getElementById('map-id').value = map.id;
      document.getElementById('map-roster').value = this.editingRoster;
      document.getElementById('map-kind').value = this.editingMapKind;
      document.getElementById('map-title').value = map.title;
      document.getElementById('map-description').value = map.description || '';
      document.getElementById('map-scenario').value = map.scenarioId || '';
      document.getElementById('map-width').value = map.width;
      document.getElementById('map-height').value = map.height;
      this.editorData = {
        width: map.width,
        height: map.height,
        tiles: [...map.tiles],
        markers: map.markers.map((m) => ({ ...m })),
        locationLinks: (map.locationLinks || []).map((l) => ({ ...l })),
      };
    } else {
      this.editingId = null;
      this.editingRoster = this.isInvestigationRoster(options.roster) ? 'investigation' : 'general';
      this.editingMapKind = this.isWorldMap(options.mapKind) ? 'world' : 'local';
      titleEl.textContent = this.getEditorTitle(this.editingMapKind, this.editingRoster, false);
      document.getElementById('map-form-el')?.reset();
      document.getElementById('map-id').value = '';
      document.getElementById('map-roster').value = this.editingRoster;
      document.getElementById('map-kind').value = this.editingMapKind;
      const defaults = this.isWorldMap(this.editingMapKind) ? this.DEFAULT_WORLD_SIZE : this.DEFAULT_SIZE;
      document.getElementById('map-width').value = defaults.width;
      document.getElementById('map-height').value = defaults.height;
      this.editorData = this.createEmptyMapData(
        defaults.width,
        defaults.height,
        this.editingRoster,
        this.editingMapKind,
      );
    }

    this.updateSizeControls();
    this.updateEditorPalette();
    this.renderScenarioSelect();
    if (id) {
      document.getElementById('map-scenario').value = this.getById(id)?.scenarioId || '';
    }
    this.updateSizeSummary();
    this.renderEditorGrid();
    form?.scrollIntoView({ behavior: 'smooth' });
  },

  updateEditorPalette() {
    const isInvestigation = this.isInvestigationRoster(this.editingRoster);
    const isWorld = this.isWorldMap(this.editingMapKind);
    const form = document.getElementById('map-form');
    form?.classList.toggle('map-form-investigation', isInvestigation && !isWorld);
    form?.classList.toggle('map-form-world', isWorld);

    document.querySelectorAll('.map-palette-adventure').forEach((el) => {
      el.classList.toggle('hidden', isInvestigation || isWorld);
    });
    document.querySelectorAll('.map-palette-investigation').forEach((el) => {
      el.classList.toggle('hidden', !isInvestigation || isWorld);
    });
    document.querySelectorAll('.map-palette-world').forEach((el) => {
      el.classList.toggle('hidden', !isWorld);
    });

    this.selectedTile = this.getDefaultTile(this.editingRoster, this.editingMapKind);
    this.selectedMarker = this.getDefaultMarker(this.editingRoster, this.editingMapKind);
    this.tool = 'tile';

    document.querySelectorAll('[data-map-tool]').forEach((b) => {
      b.classList.toggle('active', b.dataset.mapTool === 'tile');
    });

    let paletteSelector = '.map-palette-adventure';
    if (isWorld) paletteSelector = '.map-palette-world';
    else if (isInvestigation) paletteSelector = '.map-palette-investigation';

    document.querySelectorAll(`${paletteSelector} [data-map-tile]`).forEach((b) => {
      b.classList.toggle('active', b.dataset.mapTile === this.selectedTile);
    });
    document.querySelectorAll(`${paletteSelector} [data-map-marker]`).forEach((b) => {
      b.classList.toggle('active', b.dataset.mapMarker === this.selectedMarker);
    });

    const titleInput = document.getElementById('map-title');
    if (titleInput && !titleInput.value) {
      if (isWorld) titleInput.placeholder = 'Ex : Les Terres de la Couronne Fracturée';
      else if (isInvestigation) titleInput.placeholder = 'Ex : Commissariat central — aile nord';
      else titleInput.placeholder = 'Ex : Taverne du Vieux Port';
    }

    const hint = document.getElementById('map-editor-hint');
    if (hint) {
      hint.textContent = isWorld
        ? 'Peins les continents, place des marqueurs, puis utilise « Lien lieu » pour relier une case à une scène locale.'
        : 'Clique sur une case pour peindre ou placer un marqueur. Place une sortie 🚪 pour revenir à la carte du monde.';
    }

    document.getElementById('map-editor-grid')?.classList.toggle('map-editor-grid-world', isWorld);

    const linkToolBtn = document.querySelector('[data-map-tool="link"]');
    const linkFieldset = document.getElementById('map-palette-links');
    linkToolBtn?.classList.toggle('hidden', !isWorld);
    linkFieldset?.classList.toggle('hidden', !isWorld);
    if (isWorld) {
      this.renderLinkTargetSelect();
    }
  },

  renderLinkTargetSelect() {
    const select = document.getElementById('map-link-target');
    if (!select) return;
    const localMaps = this.getLocalMapsForLinking(this.editingRoster);
    const current = this.selectedLinkTarget || select.value;
    select.innerHTML = `
      <option value="">— Choisir une scène locale —</option>
      ${localMaps.map((m) => `<option value="${m.id}"${m.id === current ? ' selected' : ''}>${this.escape(m.title)}</option>`).join('')}`;
    if (current && localMaps.some((m) => m.id === current)) {
      select.value = current;
    }
  },

  hideEditor() {
    document.getElementById('map-form')?.classList.add('hidden');
    this.editorData = null;
    this.editingId = null;
    this.editingRoster = 'general';
    this.editingMapKind = 'local';
  },

  renderScenarioSelect() {
    const select = document.getElementById('map-scenario');
    if (!select) return;
    Scenarios.load();
    const isInvestigation = this.isInvestigationRoster(this.editingRoster);
    let scenarios = Scenarios.list.filter((s) => (
      isInvestigation ? s.roster === 'investigation' : s.roster !== 'investigation'
    ));

    if (this.isWorldMap(this.editingMapKind) && !isInvestigation) {
      const longScenarios = scenarios.filter((s) => s.questFormat === 'long');
      if (longScenarios.length) scenarios = longScenarios;
    }

    const current = select.value || document.getElementById('map-scenario')?.value;

    select.innerHTML = `
      <option value="">— Aucun scénario lié —</option>
      ${scenarios.map((s) => {
        const tag = isInvestigation ? '🔍 ' : '';
        return `<option value="${s.id}">${tag}${this.escape(s.title)}</option>`;
      }).join('')}`;

    if (current) select.value = current;
  },

  applyEditorSize() {
    const { width, height } = this.getSizeFromInputs();
    const widthInput = document.getElementById('map-width');
    const heightInput = document.getElementById('map-height');
    if (widthInput) widthInput.value = width;
    if (heightInput) heightInput.value = height;
    this.updateSizeSummary();

    if (this.editorData?.width === width && this.editorData?.height === height) {
      return;
    }

    const next = this.createEmptyMapData(width, height, this.editingRoster, this.editingMapKind);
    const prev = this.editorData || next;

    for (let y = 0; y < next.height; y += 1) {
      for (let x = 0; x < next.width; x += 1) {
        if (x < prev.width && y < prev.height) {
          next.tiles[y * next.width + x] = prev.tiles[y * prev.width + x]
            || this.getDefaultTile(this.editingRoster, this.editingMapKind);
        }
      }
    }

    next.markers = (prev.markers || []).filter((m) => m.x < next.width && m.y < next.height);
    if (this.isWorldMap(this.editingMapKind)) {
      next.locationLinks = (prev.locationLinks || []).filter((l) => l.x < next.width && l.y < next.height);
    }
    this.editorData = next;
    this.renderEditorGrid();
  },

  clearEditorGrid() {
    if (!confirm('Effacer toute la carte (tuiles par défaut, marqueurs supprimés) ?')) return;
    const { width, height } = this.getEditorData();
    this.editorData = this.createEmptyMapData(width, height, this.editingRoster, this.editingMapKind);
    this.renderEditorGrid();
  },

  renderEditorGrid() {
    const container = document.getElementById('map-editor-grid');
    if (!container || !this.editorData) return;

    container.innerHTML = this.renderGridHtml(this.editorData, {
      cellSize: this.getEditorCellSize(this.editorData.width, this.editorData.height),
      interactive: true,
      editor: true,
      showLabels: false,
    });

    const paintFromCell = (cell, rerender = true) => {
      if (!cell) return;
      const x = parseInt(cell.dataset.x, 10);
      const y = parseInt(cell.dataset.y, 10);
      this.paintCell(x, y);
      if (rerender) {
        this.renderEditorGrid();
      } else {
        this._editorDragDirty = true;
      }
    };

    if (!['tile', 'marker', 'erase'].includes(this.tool)) {
      container.querySelectorAll('.map-cell').forEach((cell) => {
        cell.addEventListener('click', () => paintFromCell(cell));
      });
      return;
    }

    if (!this._editorDragBound) {
      this._editorDragBound = true;
      document.addEventListener('mouseup', () => {
        if (this._editorDragDirty) {
          this._editorDragDirty = false;
          this.renderEditorGrid();
        }
        this._editorDragPainting = false;
      });
    }
    this._editorDragPainting = false;
    this._editorDragDirty = false;

    container.onmousedown = (e) => {
      if (e.button !== 0) return;
      this._editorDragPainting = true;
      paintFromCell(e.target.closest('.map-cell'), false);
      this._editorDragDirty = true;
      this.renderEditorGrid();
    };

    container.onmouseover = (e) => {
      if (!this._editorDragPainting || e.buttons !== 1) return;
      paintFromCell(e.target.closest('.map-cell'), false);
    };
  },

  paintCell(x, y) {
    if (!this.editorData) return;
    const idx = y * this.editorData.width + x;

    if (this.tool === 'erase') {
      this.editorData.tiles[idx] = this.getDefaultTile(this.editingRoster, this.editingMapKind);
      this.editorData.markers = this.editorData.markers.filter((m) => !(m.x === x && m.y === y));
      if (this.editorData.locationLinks) {
        this.editorData.locationLinks = this.editorData.locationLinks.filter((l) => !(l.x === x && l.y === y));
      }
      return;
    }

    if (this.tool === 'link') {
      if (!this.isWorldMap(this.editingMapKind)) return;
      const targetId = document.getElementById('map-link-target')?.value || this.selectedLinkTarget;
      if (!targetId) {
        alert('Choisis d\'abord une scène locale dans la liste « Lien vers une scène ».');
        return;
      }
      const targetMap = this.getById(targetId);
      if (!targetMap || this.isWorldMap(targetMap)) {
        alert('La cible doit être une scène locale.');
        return;
      }
      if (!this.editorData.locationLinks) this.editorData.locationLinks = [];
      this.editorData.locationLinks = this.editorData.locationLinks.filter((l) => !(l.x === x && l.y === y));
      const label = prompt('Nom du lieu (optionnel) :', targetMap.title || '') ?? '';
      if (label === null) return;
      this.editorData.locationLinks.push({
        x,
        y,
        targetMapId: targetId,
        label: label.trim(),
      });
      return;
    }

    if (this.tool === 'marker') {
      const existing = this.editorData.markers.find((m) => m.x === x && m.y === y);
      if (existing && existing.type !== this.selectedMarker) return;
      this.editorData.markers = this.editorData.markers.filter((m) => !(m.x === x && m.y === y));
      this.editorData.markers.push({
        x,
        y,
        type: this.selectedMarker,
        label: this.getMarkerDef(this.selectedMarker).label || '',
      });
      return;
    }

    this.editorData.tiles[idx] = this.selectedTile;
  },

  handleSubmit(e) {
    e.preventDefault();
    this.applyEditorSize();
    const id = document.getElementById('map-id')?.value;
    const title = document.getElementById('map-title')?.value.trim();
    if (!title) {
      alert('Donne un titre à ta carte.');
      return;
    }
    if (!this.editorData) {
      alert('La grille de la carte est vide.');
      return;
    }

    const roster = document.getElementById('map-roster')?.value || this.editingRoster || 'general';
    const mapKind = document.getElementById('map-kind')?.value || this.editingMapKind || 'local';
    const map = {
      id: id || this.generateId(),
      title,
      description: document.getElementById('map-description')?.value.trim() || '',
      roster: this.isInvestigationRoster(roster) ? 'investigation' : 'general',
      mapKind: this.isWorldMap(mapKind) ? 'world' : 'local',
      scenarioId: document.getElementById('map-scenario')?.value || '',
      width: this.editorData.width,
      height: this.editorData.height,
      tiles: [...this.editorData.tiles],
      markers: this.editorData.markers.map((m) => ({ ...m })),
      updatedAt: Date.now(),
    };
    if (this.isWorldMap(mapKind)) {
      map.locationLinks = (this.editorData.locationLinks || []).map((l) => ({ ...l }));
    }

    const index = this.list.findIndex((m) => m.id === map.id);
    if (index !== -1) {
      this.list[index] = map;
    } else {
      this.list.push(map);
    }

    this.save();
    this.renderList();
    this.hideEditor();
    if (typeof Game !== 'undefined') {
      Game.refreshSetupMaps();
    }
  },

  delete(id) {
    const map = this.getById(id);
    if (!map) return;
    if (!confirm(`Supprimer la carte « ${map.title} » ?`)) return;
    this.list = this.list.filter((m) => m.id !== id);
    this.save();
    this.renderList();
    if (typeof Game !== 'undefined') {
      Game.refreshSetupMaps();
    }
  },

  mapOptions(selectedId = '', scenarioId = null, questFormat = null) {
    const selected = Array.isArray(selectedId) ? selectedId : (selectedId ? [selectedId] : []);
    return this.renderSetupMapPicker(selected, scenarioId, questFormat);
  },

  getSetupMapPool(scenarioId, questFormat) {
    const isInvestigation = questFormat === 'investigation';
    const pool = this.getMapsForFormat(questFormat).filter((m) => {
      if (isInvestigation && this.isWorldMap(m)) return false;
      if (questFormat === 'oneshot' && this.isWorldMap(m)) return false;
      const linked = m.scenarioId || '';
      if (linked && linked !== scenarioId) return false;
      return true;
    });
    return pool.sort((a, b) => {
      const aLinked = a.scenarioId && a.scenarioId === scenarioId ? 0 : 1;
      const bLinked = b.scenarioId && b.scenarioId === scenarioId ? 0 : 1;
      if (aLinked !== bLinked) return aLinked - bLinked;
      const aWorld = this.isWorldMap(a) ? 0 : 1;
      const bWorld = this.isWorldMap(b) ? 0 : 1;
      if (aWorld !== bWorld) return aWorld - bWorld;
      return a.title.localeCompare(b.title, 'fr');
    });
  },

  getDefaultSelectedMapIds(scenarioId, questFormat) {
    const linked = this.getSetupMapPool(scenarioId, questFormat)
      .filter((m) => m.scenarioId === scenarioId)
      .map((m) => m.id);
    if (linked.length) return linked;
    if (questFormat === 'investigation' || String(scenarioId || '').startsWith('inv-')) {
      const demo = this.getById('demo-quartier-serpent');
      return demo?.id ? [demo.id] : [];
    }
    if (scenarioId === 'demo-couronne-fracturee') {
      return ['demo-monde-couronne', 'demo-taverne'].filter((id) => this.getById(id));
    }
    const tavern = this.getById('demo-taverne');
    return tavern?.id ? [tavern.id] : [];
  },

  renderSetupMapPicker(selectedIds = [], scenarioId = null, questFormat = null) {
    const selected = new Set(Array.isArray(selectedIds) ? selectedIds : (selectedIds ? [selectedIds] : []));
    const pool = this.getSetupMapPool(scenarioId, questFormat);
    const isInvestigation = questFormat === 'investigation';

    if (pool.length === 0) {
      return `<p class="setup-maps-empty">${isInvestigation
        ? 'Aucune carte enquête pour ce scénario — crée-en une dans l\'onglet Cartes.'
        : 'Aucune carte pour ce mode et ce scénario — crée-en une dans l\'onglet Cartes.'}</p>`;
    }

    const worldMaps = pool.filter((m) => this.isWorldMap(m));
    const localMaps = pool.filter((m) => !this.isWorldMap(m));

    const renderCheckbox = (map) => {
      const tag = this.isWorldMap(map) ? '🌍' : (isInvestigation ? '🔍' : '⚔️');
      const linked = map.scenarioId === scenarioId && scenarioId ? ' · liée au scénario' : '';
      const checked = selected.has(map.id) ? 'checked' : '';
      return `
        <label class="setup-map-option checkbox-label">
          <input type="checkbox" name="setup-map" value="${map.id}" ${checked}>
          <span class="setup-map-label">${tag} <strong>${this.escape(map.title)}</strong>
            <span class="setup-map-meta">(${map.width}×${map.height}${linked})</span></span>
        </label>`;
    };

    const renderGroup = (title, maps) => {
      if (!maps.length) return '';
      return `
        <fieldset class="setup-maps-group">
          <legend>${title}</legend>
          ${maps.map(renderCheckbox).join('')}
        </fieldset>`;
    };

    return `
      ${renderGroup('Cartes du monde', worldMaps)}
      ${renderGroup(isInvestigation ? 'Scènes enquête' : 'Scènes locales', localMaps)}`;
  },

  renderSessionMap(mapId) {
    this.renderSessionMaps(mapId ? [mapId] : [], typeof Game !== 'undefined' ? Game.state : null);
  },

  getSessionMarkerTypes(questFormat, map) {
    if (questFormat === 'investigation') {
      return Object.entries(this.INVESTIGATION_MARKERS);
    }
    if (this.isWorldMap(map)) {
      return Object.entries(this.WORLD_MARKERS);
    }
    return Object.entries(this.MARKERS).filter(([key]) => key !== 'party' && key !== 'exit');
  },

  getMemberColor(memberId, party) {
    const index = party.findIndex((m) => m.id === memberId);
    return this.MEMBER_COLORS[(index >= 0 ? index : 0) % this.MEMBER_COLORS.length];
  },

  isPlayableMember(member) {
    if (!member || member.isBot) return false;
    return member.isPlayer || member.isHuman;
  },

  getPlayerMembers(party) {
    return (party || []).filter((m) => this.isPlayableMember(m));
  },

  getMemberEmoji(member, questFormat = 'oneshot', party = []) {
    if (member?.isBot) return '🤖';
    if (!this.isPlayableMember(member)) {
      return questFormat === 'investigation' ? '🔍' : '⚔️';
    }
    const players = this.getPlayerMembers(party);
    const index = players.findIndex((m) => m.id === member.id);
    const pool = questFormat === 'investigation'
      ? this.MEMBER_PLAYER_EMOJIS.investigation
      : this.MEMBER_PLAYER_EMOJIS.general;
    return pool[(index >= 0 ? index : 0) % pool.length];
  },

  getTokenDisplay(token, party, questFormat) {
    if (token.kind === 'member') {
      const member = party.find((m) => m.id === token.memberId);
      return {
        emoji: this.getMemberEmoji(member, questFormat, party),
        label: token.label || member?.name || 'Héros',
        color: this.getMemberColor(token.memberId, party),
      };
    }
    const def = this.getMarkerDef(token.markerType);
    return {
      emoji: def.emoji || '•',
      label: token.label || def.label || token.markerType,
      color: null,
    };
  },

  initSessionTool(gameState) {
    if (!gameState?.party?.length) {
      this.sessionTool = { mode: 'erase' };
      return;
    }
    if (!this.sessionTool) {
      this.sessionTool = { mode: 'member', memberId: gameState.party[0].id };
    }
  },

  isSessionToolActive(toolSpec) {
    const t = this.sessionTool;
    if (!t || t.mode !== toolSpec.mode) return false;
    if (toolSpec.mode === 'member') return t.memberId === toolSpec.memberId;
    if (toolSpec.mode === 'marker') return t.markerType === toolSpec.markerType;
    return true;
  },

  setSessionToolFromElement(el) {
    const mode = el.dataset.sessionTool;
    if (mode === 'erase') {
      this.sessionTool = { mode: 'erase' };
    } else if (mode === 'member') {
      this.sessionTool = { mode: 'member', memberId: el.dataset.memberId };
    } else if (mode === 'marker') {
      this.sessionTool = { mode: 'marker', markerType: el.dataset.markerType };
    }
  },

  getSessionActiveMapId(mapIds) {
    const ids = (mapIds || []).filter(Boolean);
    if (!ids.length) return null;
    if (this.sessionActiveMapId && ids.includes(this.sessionActiveMapId)) {
      return this.sessionActiveMapId;
    }
    this.sessionActiveMapId = ids[0];
    return ids[0];
  },

  getSessionDisplayContext(gameState, activeId) {
    const activeMap = this.getById(activeId);
    if (!activeMap || !gameState) {
      return { displayMap: activeMap, navContext: null };
    }

    const nav = gameState.mapNavigation;
    if (nav?.view === 'local' && nav.worldMapId === activeId && nav.localMapId) {
      const localMap = this.getById(nav.localMapId);
      if (localMap) {
        return {
          displayMap: localMap,
          navContext: {
            mode: 'local',
            worldMap: activeMap,
            worldCell: nav.worldCell,
            localMap,
          },
        };
      }
    }

    return { displayMap: activeMap, navContext: null };
  },

  renderSessionNavBar(navContext) {
    if (!navContext) return '';
    const worldTitle = navContext.worldMap?.title || 'Monde';
    const localTitle = navContext.localMap?.title || 'Scène';
    return `
      <div class="session-map-nav-bar">
        <button type="button" class="btn btn-small session-map-back-btn" data-session-map-back title="Revenir à la carte du monde">← Monde</button>
        <span class="session-map-breadcrumb">${this.escape(worldTitle)} › ${this.escape(localTitle)}</span>
      </div>`;
  },

  handleSessionNavigationClick(mapId, x, y, gameState) {
    if (!gameState || typeof Game === 'undefined') return false;

    const map = this.getById(mapId);
    if (!map) return false;

    const nav = gameState.mapNavigation;
    const exitMarker = map.markers?.find((m) => m.x === x && m.y === y && m.type === 'exit');

    if (exitMarker && nav?.view === 'local' && nav.localMapId === mapId) {
      Game.exitToWorldMap();
      this.sessionMapNavAnim = 'exit-local';
      return true;
    }

    if (this.isWorldMap(map)) {
      const link = this.getLocationLinkAt(map, x, y);
      if (link?.targetMapId) {
        Game.enterLocalMap(mapId, x, y, link.targetMapId);
        this.sessionMapNavAnim = 'enter-local';
        return true;
      }
    }

    return false;
  },

  scheduleClearSessionNavAnim() {
    if (!this.sessionMapNavAnim) return;
    const anim = this.sessionMapNavAnim;
    setTimeout(() => {
      if (this.sessionMapNavAnim === anim) {
        this.sessionMapNavAnim = null;
      }
    }, 400);
  },

  getSessionCellSize(map) {
    const panel = document.getElementById('session-maps-panel');
    const availW = Math.max(300, (panel?.clientWidth || 680) - 56);
    const availH = Math.max(280, Math.min(420, Math.floor(window.innerHeight * 0.42)));
    const byW = Math.floor(availW / map.width);
    const byH = Math.floor(availH / map.height);
    const fit = Math.min(byW, byH);

    if (this.isWorldMap(map)) {
      return Math.max(4, Math.min(10, fit));
    }
    return Math.max(8, Math.min(22, fit));
  },

  getSessionMapZoom(mapId) {
    const zoom = this.sessionMapZoom[mapId];
    return typeof zoom === 'number' && zoom > 0 ? zoom : 1;
  },

  setSessionMapZoom(mapId, zoom) {
    const map = this.getById(mapId);
    const isWorld = map && this.isWorldMap(map);
    const min = isWorld ? 0.5 : 0.65;
    const max = isWorld ? 5 : 4;
    this.sessionMapZoom[mapId] = Math.max(min, Math.min(max, zoom));
  },

  adjustSessionMapZoom(mapId, direction) {
    const current = this.getSessionMapZoom(mapId);
    const step = direction === 'in' ? 1.12 : direction === 'out' ? 1 / 1.12 : null;
    if (step) {
      this.setSessionMapZoom(mapId, current * step);
    } else {
      this.setSessionMapZoom(mapId, 1);
    }
  },

  applySessionMapWheelZoom(mapId, deltaY) {
    const factor = Math.exp(-deltaY * this.ZOOM_WHEEL_SENSITIVITY);
    const current = this.getSessionMapZoom(mapId);
    this.setSessionMapZoom(mapId, current * factor);
  },

  lockPageScrollDuringMapZoom(x, y) {
    const restore = () => window.scrollTo(x, y);
    restore();
    requestAnimationFrame(() => {
      restore();
      requestAnimationFrame(restore);
    });
  },

  applyZoomToGrid(mapId) {
    const panel = document.getElementById('session-maps-panel');
    const map = this.getById(mapId);
    if (!map || !panel) return false;

    const gridEl = panel.querySelector(
      `.session-map-grid[data-map-grid-id="${mapId}"] .map-grid-session`,
    );
    if (!gridEl) return false;

    const baseCellSize = this.getSessionCellSize(map);
    const zoom = this.getSessionMapZoom(mapId);
    const cellSize = Math.max(3, Math.round(baseCellSize * zoom));
    gridEl.style.setProperty('--map-cell-size', `${cellSize}px`);

    const zoomLabel = panel.querySelector('.session-map-zoom-label');
    if (zoomLabel) {
      zoomLabel.textContent = `${Math.round(zoom * 100)}%`;
    }
    return true;
  },

  zoomMapAtPoint(mapId, deltaY, clientX, clientY, grid) {
    const pageX = window.scrollX;
    const pageY = window.scrollY;
    const rect = grid.getBoundingClientRect();
    const offsetX = clientX - rect.left + grid.scrollLeft;
    const offsetY = clientY - rect.top + grid.scrollTop;
    const oldZoom = this.getSessionMapZoom(mapId);

    this.applySessionMapWheelZoom(mapId, deltaY);
    const newZoom = this.getSessionMapZoom(mapId);
    if (Math.abs(newZoom - oldZoom) < 0.0005) return;

    if (!this.applyZoomToGrid(mapId)) {
      if (typeof Game !== 'undefined' && Game.state) {
        this.renderSessionMaps(Game.state.mapIds, Game.state);
      }
      return;
    }

    const ratio = newZoom / oldZoom;
    grid.scrollLeft = Math.max(0, offsetX * ratio - (clientX - rect.left));
    grid.scrollTop = Math.max(0, offsetY * ratio - (clientY - rect.top));

    window.scrollTo(pageX, pageY);
    this.lockPageScrollDuringMapZoom(pageX, pageY);
  },

  handleSessionMapWheel(e) {
    const grid = e.target.closest('.session-map-grid');
    if (!grid) return false;

    const mapId = grid.dataset.mapGridId
      || grid.querySelector('[data-session-map-id]')?.dataset.sessionMapId;
    if (!mapId) return false;

    e.preventDefault();
    e.stopPropagation();
    if (typeof e.stopImmediatePropagation === 'function') {
      e.stopImmediatePropagation();
    }

    this.zoomMapAtPoint(mapId, e.deltaY, e.clientX, e.clientY, grid);
    return true;
  },

  captureSessionScrollState(panel) {
    if (!panel) return null;
    return {
      windowX: window.scrollX,
      windowY: window.scrollY,
      panelScrollTop: panel.scrollTop,
      grids: [...panel.querySelectorAll('.session-map-grid')].map((grid) => ({
        id: grid.dataset.mapGridId,
        scrollTop: grid.scrollTop,
        scrollLeft: grid.scrollLeft,
      })),
    };
  },

  restoreSessionScrollState(state, panel) {
    if (!state) return;
    window.scrollTo(state.windowX, state.windowY);
    if (panel && state.panelScrollTop != null) {
      panel.scrollTop = state.panelScrollTop;
    }
    state.grids.forEach(({ id, scrollTop, scrollLeft }) => {
      const grid = panel?.querySelector(`.session-map-grid[data-map-grid-id="${id}"]`);
      if (grid) {
        grid.scrollTop = scrollTop;
        grid.scrollLeft = scrollLeft;
      }
    });
  },

  getSessionMapStageMeta(map, tokens, gameState, readonly) {
    const tokenCount = tokens.length;
    const explorePct = (this.isWorldMap(map) && gameState && typeof Game !== 'undefined' && !readonly)
      ? Game.getWorldExplorationPercent(map.id, map)
      : null;
    return `${map.width}×${map.height}${tokenCount ? ` · ${tokenCount} jeton${tokenCount > 1 ? 's' : ''}` : ''}${explorePct != null ? ` · 🌫️ ${explorePct}% exploré` : ''}`;
  },

  refreshActiveMapGrid(gameState) {
    if (!gameState) return false;
    const panel = document.getElementById('session-maps-panel');
    if (!panel) return false;

    const activeId = this.getSessionActiveMapId(gameState.mapIds || []);
    const { displayMap, navContext } = this.getSessionDisplayContext(gameState, activeId);
    const map = displayMap;
    const gridInner = panel.querySelector('.session-map-grid-inner');
    if (!map || !gridInner) return false;

    const scrollState = this.captureSessionScrollState(panel);
    const party = gameState.party || [];
    const questFormat = gameState.questFormat || 'oneshot';
    const readonly = gameState.status === 'completed';
    const tokens = typeof Game !== 'undefined' ? Game.getMapPlayTokens(map.id) : [];
    const baseCellSize = this.getSessionCellSize(map);
    const zoom = this.getSessionMapZoom(map.id);
    const cellSize = Math.max(3, Math.round(baseCellSize * zoom));
    const worldMap = navContext?.worldMap || (this.isWorldMap(map) ? map : null);
    const exploredCells = (worldMap && !navContext && typeof Game !== 'undefined' && !readonly)
      ? Game.getExploredCells(worldMap.id)
      : null;
    const linkWorld = !navContext && this.isWorldMap(map) ? map : null;
    const revealedMarkers = typeof Game !== 'undefined' ? Game.getRevealedMarkers(map.id) : [];
    const revealedLinks = typeof Game !== 'undefined' ? Game.getRevealedLinks(map.id) : [];

    gridInner.innerHTML = this.renderSessionGridHtml(
      map, tokens, party, questFormat, cellSize, exploredCells, readonly, linkWorld, revealedMarkers, revealedLinks,
    );

    const meta = panel.querySelector('.session-map-stage-meta');
    if (meta) {
      meta.textContent = this.getSessionMapStageMeta(map, tokens, gameState, readonly);
    }

    const zoomLabel = panel.querySelector('.session-map-zoom-label');
    if (zoomLabel) {
      zoomLabel.textContent = `${Math.round(zoom * 100)}%`;
    }

    requestAnimationFrame(() => this.restoreSessionScrollState(scrollState, panel));
    return true;
  },

  renderSessionZoomControls(map) {
    const zoom = this.getSessionMapZoom(map.id);
    const hint = this.isWorldMap(map) ? 'Molette sur la carte pour zoomer' : 'Zoom';
    return `
      <div class="session-map-zoom" data-map-zoom-id="${map.id}" title="${hint}">
        <button type="button" class="session-map-zoom-btn" data-session-zoom="out" data-map-id="${map.id}" aria-label="Dézoomer">−</button>
        <span class="session-map-zoom-label">${Math.round(zoom * 100)}%</span>
        <button type="button" class="session-map-zoom-btn" data-session-zoom="in" data-map-id="${map.id}" aria-label="Zoomer">+</button>
        <button type="button" class="session-map-zoom-btn session-map-zoom-reset" data-session-zoom="reset" data-map-id="${map.id}" aria-label="Réinitialiser le zoom" title="Réinitialiser">⟲</button>
      </div>`;
  },

  renderSessionMapTabs(maps, activeId) {
    if (maps.length <= 1) return '';

    return `
      <div class="session-map-tabs" role="tablist" aria-label="Cartes de la partie">
        ${maps.map((map) => {
          const isWorld = this.isWorldMap(map);
          const kind = isWorld ? 'Monde' : (map.roster === 'investigation' ? 'Enquête' : 'Scène');
          const active = map.id === activeId ? ' active' : '';
          const invClass = map.roster === 'investigation' ? ' session-map-tab-investigation' : '';
          return `<button type="button" class="session-map-tab${active}${invClass}" role="tab" aria-selected="${map.id === activeId}"
            data-session-map-tab="${map.id}">
            <span class="session-map-tab-kind">${kind}</span>
            <span class="session-map-tab-title">${this.escape(map.title)}</span>
          </button>`;
        }).join('')}
      </div>`;
  },

  renderSessionToolbarGlobal(gameState, map) {
    if (!gameState || gameState.status === 'completed' || !map) return '';

    const party = gameState.party || [];
    const questFormat = gameState.questFormat || 'oneshot';
    const markerTypes = this.getSessionMarkerTypes(questFormat, map);

    const memberButtons = party.map((m) => {
      const active = this.isSessionToolActive({ mode: 'member', memberId: m.id }) ? ' active' : '';
      const color = this.getMemberColor(m.id, party);
      const badge = this.getMemberEmoji(m, questFormat, party);
      return `<button type="button" class="session-map-tool-btn session-map-tool-member${active}" data-session-tool="member" data-member-id="${m.id}" style="--member-color:${color}" title="${this.escape(m.name)}">${badge} <span class="session-map-tool-btn-label">${this.escape(m.name)}</span></button>`;
    }).join('');

    const markerButtons = markerTypes.map(([type, def]) => {
      const active = this.isSessionToolActive({ mode: 'marker', markerType: type }) ? ' active' : '';
      return `<button type="button" class="session-map-tool-btn session-map-tool-marker${active}" data-session-tool="marker" data-marker-type="${type}" title="${this.escape(def.label)}">${def.emoji} <span class="session-map-tool-btn-label">${this.escape(def.label)}</span></button>`;
    }).join('');

    const eraseActive = this.isSessionToolActive({ mode: 'erase' }) ? ' active' : '';
    const activeToolLabel = this.getActiveSessionToolLabel(party);

    return `
      <div class="session-map-toolbar session-map-toolbar-global">
        <div class="session-map-toolbar-top">
          <p class="session-map-toolbar-hint">Sélectionne un élément, puis clique sur la carte pour le placer.</p>
          <p class="session-map-active-tool">Outil actif : <strong>${this.escape(activeToolLabel)}</strong></p>
        </div>
        <div class="session-map-toolbar-panels">
          <div class="session-map-tool-group">
            <span class="session-map-tool-label">Personnages</span>
            <div class="session-map-tool-row">${memberButtons || '<span class="session-map-tool-empty">Aucun personnage</span>'}</div>
          </div>
          <div class="session-map-tool-group">
            <span class="session-map-tool-label">${questFormat === 'investigation' ? 'Marqueurs enquête' : 'Marqueurs'}</span>
            <div class="session-map-tool-row session-map-tool-row-markers">${markerButtons}</div>
          </div>
          <div class="session-map-tool-group session-map-tool-group-actions">
            <span class="session-map-tool-label">Actions</span>
            <button type="button" class="session-map-tool-btn session-map-tool-erase${eraseActive}" data-session-tool="erase">🧹 Effacer</button>
          </div>
        </div>
      </div>`;
  },

  getActiveSessionToolLabel(party) {
    const t = this.sessionTool;
    if (!t) return '—';
    if (t.mode === 'erase') return 'Effacer une case';
    if (t.mode === 'member') {
      const member = party.find((m) => m.id === t.memberId);
      return member ? member.name : 'Personnage';
    }
    if (t.mode === 'marker') {
      const def = this.getMarkerDef(t.markerType);
      return def.label || t.markerType;
    }
    return '—';
  },

  renderSessionMapStage(map, tokens, party, questFormat, readonly, gameState, navContext = null) {
    const baseCellSize = this.getSessionCellSize(map);
    const zoom = this.getSessionMapZoom(map.id);
    const cellSize = Math.max(3, Math.round(baseCellSize * zoom));
    const isWorld = this.isWorldMap(map) && !navContext;
    const isInvestigation = map.roster === 'investigation';
    const kindLabel = navContext ? 'Scène locale' : (isWorld ? 'Monde' : (isInvestigation ? 'Scène enquête' : 'Scène'));
    const exploredCells = (isWorld && gameState && typeof Game !== 'undefined')
      ? Game.getExploredCells(map.id)
      : null;
    const fogActive = isWorld && exploredCells && gameState?.status !== 'completed'
      && exploredCells.length < map.width * map.height;
    const animClass = this.sessionMapNavAnim ? ` session-map-nav-${this.sessionMapNavAnim}` : '';
    const gridMapId = map.id;
    const linkWorld = !navContext && isWorld ? map : null;
    const revealedMarkers = typeof Game !== 'undefined' ? Game.getRevealedMarkers(map.id) : [];
    const revealedLinks = typeof Game !== 'undefined' ? Game.getRevealedLinks(map.id) : [];

    return `
      <div class="session-map-stage${isWorld ? ' session-map-stage-world' : ''}${isInvestigation ? ' session-map-stage-investigation' : ''}${readonly ? ' session-map-stage-readonly' : ''}${fogActive ? ' session-map-stage-fog' : ''}${navContext ? ' session-map-stage-local-view' : ''}${animClass}">
        ${navContext ? this.renderSessionNavBar(navContext) : ''}
        <div class="session-map-stage-head">
          <div class="session-map-stage-title">
            <span class="session-map-kind">${kindLabel}</span>
            <strong>${this.escape(map.title)}</strong>
          </div>
          <div class="session-map-stage-controls">
            <span class="session-map-stage-meta">${this.getSessionMapStageMeta(map, tokens, gameState, readonly)}</span>
            ${this.renderSessionZoomControls(map)}
          </div>
        </div>
        ${fogActive ? '<p class="session-map-fog-hint">Clique sur une ville liée 🌀 pour entrer · clique-glisse pour déplacer · molette pour zoomer.</p>' : (navContext ? '<p class="session-map-fog-hint">Clique sur la sortie 🚪 ou « Monde » pour revenir à la carte du monde.</p>' : (isWorld ? '<p class="session-map-fog-hint">Clique-glisse pour déplacer la carte · molette pour zoomer.</p>' : '<p class="session-map-fog-hint">Clique-glisse pour déplacer la carte.</p>'))}
        <div class="session-map-grid session-map-grid-scrollable${fogActive ? ' session-map-grid-fog' : ''}${isWorld ? ' session-map-grid-world' : ' session-map-grid-local'}" data-map-grid-id="${gridMapId}">
          <div class="session-map-grid-inner">
            ${this.renderSessionGridHtml(map, tokens, party, questFormat, cellSize, exploredCells, readonly, linkWorld, revealedMarkers, revealedLinks)}
          </div>
        </div>
      </div>`;
  },

  renderSessionGridHtml(map, tokens, party, questFormat, cellSize, exploredCells = null, readonly = false, worldMapForLinks = null, revealedMarkers = null, revealedLinks = null) {
    if (!map?.tiles?.length) return '';

    const useFog = this.isWorldMap(map) && Array.isArray(exploredCells) && !readonly;
    const exploredSet = useFog ? new Set(exploredCells) : null;
    const linkSource = worldMapForLinks || (this.isWorldMap(map) ? map : null);
    const revealedMarkerSet = new Set(revealedMarkers ?? (typeof Game !== 'undefined' ? Game.getRevealedMarkers(map.id) : []));
    const revealedLinkSet = new Set(revealedLinks ?? (typeof Game !== 'undefined' ? Game.getRevealedLinks(map.id) : []));

    let html = `<div class="map-grid map-grid-interactive map-grid-session${useFog ? ' map-grid-fog' : ''}"
      data-session-map-id="${map.id}"
      style="--map-cell-size:${cellSize}px;grid-template-columns:repeat(${map.width},var(--map-cell-size))">`;

    for (let y = 0; y < map.height; y += 1) {
      for (let x = 0; x < map.width; x += 1) {
        const tile = map.tiles[y * map.width + x] || this.getDefaultTile(map.roster, map.mapKind);
        const staticMarker = map.markers?.find((mk) => mk.x === x && mk.y === y);
        const locationLink = linkSource ? this.getLocationLinkAt(linkSource, x, y) : null;
        const dynamicToken = tokens.find((t) => t.x === x && t.y === y);
        const isExplored = !useFog || exploredSet.has(`${x},${y}`);
        const fogClass = useFog && !isExplored ? ' map-cell-fogged' : '';
        const showMarker = !staticMarker || this.shouldShowSessionMarker(map, staticMarker, questFormat, revealedMarkerSet);
        const showLink = this.shouldShowSessionLink(linkSource || map, x, y, questFormat, revealedLinkSet);
        const isPortal = isExplored && showLink && locationLink?.targetMapId;
        const isExit = isExplored && showMarker && staticMarker?.type === 'exit';
        const parts = [];

        if (isExplored) {
          if (isPortal) {
            const targetTitle = this.getById(locationLink.targetMapId)?.title || locationLink.label || 'Lieu';
            parts.push(`Entrer : ${targetTitle}`);
          }
          if (showMarker && staticMarker) {
            const sDef = this.getMarkerDef(staticMarker.type);
            parts.push(`${sDef.label} (fixe)`);
          }
          if (dynamicToken) {
            const dDef = this.getTokenDisplay(dynamicToken, party, questFormat);
            parts.push(`${dDef.label} (posé)`);
          }
        }
        const title = !isExplored
          ? `Territoire inexploré (${x},${y})`
          : (parts.length
            ? `${parts.join(' · ')} (${x},${y})`
            : `${this.getTileDef(tile).label} (${x},${y})`);

        html += `<button type="button" class="map-cell map-cell-${tile} map-cell-session${dynamicToken && isExplored ? ' has-token' : ''}${showMarker && staticMarker && isExplored ? ' has-static-marker' : ''}${isPortal ? ' map-cell-portal' : ''}${isExit ? ' map-cell-exit' : ''}${fogClass}"
          data-x="${x}" data-y="${y}" title="${this.escape(title)}"${!isExplored ? ' disabled' : ''}>`;

        if (isExplored) {
          if (isPortal && !dynamicToken) {
            const targetTitle = this.getById(locationLink.targetMapId)?.title || locationLink.label || '';
            html += '<span class="map-marker map-marker-portal">🌀</span>';
            if (targetTitle) {
              html += `<span class="map-marker-label map-marker-label-portal">${this.escape(targetTitle.slice(0, 6))}</span>`;
            }
          } else if (showMarker && staticMarker && !dynamicToken) {
            html += `<span class="map-marker map-marker-static map-marker-${staticMarker.type}${isExit ? ' map-marker-exit' : ''}">${this.getMarkerDef(staticMarker.type).emoji || '•'}</span>`;
            if (staticMarker.label) {
              html += `<span class="map-marker-label map-marker-label-static">${this.escape(staticMarker.label.slice(0, 6))}</span>`;
            }
          }

          if (dynamicToken) {
            const display = this.getTokenDisplay(dynamicToken, party, questFormat);
            const style = display.color ? ` style="--token-color:${display.color}"` : '';
            html += `<span class="map-marker map-marker-token map-token-${dynamicToken.kind}${dynamicToken.kind === 'member' ? ' map-token-member' : ''}${dynamicToken.kind === 'marker' && dynamicToken.markerType === 'npc' ? ' map-token-npc' : ''}"${style}>${display.emoji}</span>`;
            if (display.label) {
              html += `<span class="map-marker-label">${this.escape(display.label.slice(0, 8))}</span>`;
            }
          }
        } else {
          html += '<span class="map-fog-overlay" aria-hidden="true"></span>';
        }

        html += '</button>';
      }
    }

    html += '</div>';
    return html;
  },

  startSessionMapPan(e, grid) {
    const point = e.touches?.[0] || e;
    this.sessionMapPan = {
      active: true,
      grid,
      startX: point.clientX,
      startY: point.clientY,
      scrollLeft: grid.scrollLeft,
      scrollTop: grid.scrollTop,
      moved: false,
    };
  },

  handleSessionMapPanMove(e) {
    const pan = this.sessionMapPan;
    if (!pan?.active) return;

    const point = e.touches?.[0] || e;
    const dx = point.clientX - pan.startX;
    const dy = point.clientY - pan.startY;

    if (!pan.moved && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
      pan.moved = true;
      pan.grid.classList.add('is-panning');
    }

    if (!pan.moved) return;

    pan.grid.scrollLeft = pan.scrollLeft - dx;
    pan.grid.scrollTop = pan.scrollTop - dy;
    if (e.cancelable) e.preventDefault();
  },

  endSessionMapPan() {
    const pan = this.sessionMapPan;
    if (!pan) return;

    if (pan.moved) {
      this.sessionMapSuppressClick = true;
    }
    pan.grid?.classList.remove('is-panning');
    this.sessionMapPan = null;
  },

  bindSessionMapPanel(panel) {
    if (!panel || panel.dataset.mapsBound === '1') return;
    panel.dataset.mapsBound = '1';

    if (!document.body.dataset.sessionMapPanBound) {
      document.body.dataset.sessionMapPanBound = '1';
      document.addEventListener('mousemove', (e) => this.handleSessionMapPanMove(e));
      document.addEventListener('mouseup', () => this.endSessionMapPan());
      document.addEventListener('touchmove', (e) => this.handleSessionMapPanMove(e), { passive: false });
      document.addEventListener('touchend', () => this.endSessionMapPan());
      document.addEventListener('touchcancel', () => this.endSessionMapPan());
    }

    if (!document.body.dataset.sessionMapWheelBound) {
      document.body.dataset.sessionMapWheelBound = '1';
      document.addEventListener('wheel', (e) => {
        if (e.target.closest('#session-maps-panel .session-map-grid')) {
          this.handleSessionMapWheel(e);
        }
      }, { passive: false, capture: true });
    }

    panel.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      const grid = e.target.closest('.session-map-grid');
      if (!grid) return;
      this.startSessionMapPan(e, grid);
    });

    panel.addEventListener('touchstart', (e) => {
      const grid = e.target.closest('.session-map-grid');
      if (!grid || e.touches.length !== 1) return;
      this.startSessionMapPan(e, grid);
    }, { passive: true });

    panel.addEventListener('click', (e) => {
      if (this.sessionMapSuppressClick) {
        this.sessionMapSuppressClick = false;
        return;
      }

      const zoomBtn = e.target.closest('[data-session-zoom]');
      if (zoomBtn) {
        const mapId = zoomBtn.dataset.mapId;
        const grid = panel.querySelector(`.session-map-grid[data-map-grid-id="${mapId}"]`);
        const pageX = window.scrollX;
        const pageY = window.scrollY;
        this.adjustSessionMapZoom(mapId, zoomBtn.dataset.sessionZoom);
        if (!this.applyZoomToGrid(mapId) && typeof Game !== 'undefined' && Game.state) {
          this.renderSessionMaps(Game.state.mapIds, Game.state);
        }
        window.scrollTo(pageX, pageY);
        if (grid) {
          grid.scrollLeft = grid.scrollLeft;
        }
        return;
      }

      const tabBtn = e.target.closest('[data-session-map-tab]');
      if (tabBtn) {
        this.sessionActiveMapId = tabBtn.dataset.sessionMapTab;
        if (typeof Game !== 'undefined' && Game.state?.mapNavigation) {
          Game.state.mapNavigation.view = 'world';
          Game.state.mapNavigation.localMapId = null;
          Game.save();
        }
        this.sessionMapNavAnim = null;
        if (typeof Game !== 'undefined' && Game.state) {
          this.renderSessionMaps(Game.state.mapIds, Game.state);
        }
        return;
      }

      const backBtn = e.target.closest('[data-session-map-back]');
      if (backBtn && typeof Game !== 'undefined' && Game.state) {
        Game.exitToWorldMap();
        this.sessionMapNavAnim = 'exit-local';
        this.renderSessionMaps(Game.state.mapIds, Game.state);
        return;
      }

      const toolBtn = e.target.closest('[data-session-tool]');
      if (toolBtn) {
        this.setSessionToolFromElement(toolBtn);
        if (typeof Game !== 'undefined' && Game.state) {
          this.renderSessionMaps(Game.state.mapIds, Game.state);
        }
        return;
      }

      const cell = e.target.closest('.map-cell-session');
      if (!cell || typeof Game === 'undefined' || !Game.state) return;
      if (Game.state.status === 'completed') return;
      if (cell.disabled) return;

      const mapEl = cell.closest('[data-session-map-id]');
      const mapId = mapEl?.dataset.sessionMapId;
      if (!mapId) return;

      const x = parseInt(cell.dataset.x, 10);
      const y = parseInt(cell.dataset.y, 10);
      e.preventDefault();
      e.stopPropagation();

      if (this.handleSessionNavigationClick(mapId, x, y, Game.state)) {
        Game.save();
        this.renderSessionMaps(Game.state.mapIds, Game.state);
        return;
      }

      Game.applyMapPlayAction(mapId, x, y, this.sessionTool);
      if (!this.refreshActiveMapGrid(Game.state)) {
        this.renderSessionMaps(Game.state.mapIds, Game.state);
      }
    });
  },

  handleSessionCellClick(gameState, mapId, x, y) {
    if (typeof Game === 'undefined') return;
    Game.applyMapPlayAction(mapId, x, y, this.sessionTool);
    this.renderSessionMaps(gameState.mapIds, gameState);
  },

  renderSessionMaps(mapIds, gameState = null) {
    const panel = document.getElementById('session-maps-panel');
    if (!panel) return;

    this.load();
    const ids = Array.isArray(mapIds) ? mapIds.filter(Boolean) : (mapIds ? [mapIds] : []);
    const maps = ids.map((id) => this.getById(id)).filter(Boolean);
    const readonly = gameState?.status === 'completed';

    panel.classList.toggle('hidden', maps.length === 0);
    if (!maps.length) {
      panel.innerHTML = '';
      return;
    }

    if (gameState && !readonly) {
      this.initSessionTool(gameState);
    }

    if (gameState && typeof Game !== 'undefined') {
      Game.initAllWorldMapFog();
    }

    this.bindSessionMapPanel(panel);

    const party = gameState?.party || [];
    const questFormat = gameState?.questFormat || 'oneshot';
    const activeId = this.getSessionActiveMapId(ids);
    const { displayMap, navContext } = this.getSessionDisplayContext(gameState, activeId);
    const activeMap = displayMap;
    const activeTokens = activeMap && gameState && typeof Game !== 'undefined'
      ? Game.getMapPlayTokens(activeMap.id)
      : [];
    const scrollState = this.captureSessionScrollState(panel);
    panel.innerHTML = `
      <div class="session-maps-shell">
        <div class="session-maps-header">
          <h3>🗺️ Carte${maps.length > 1 ? 's' : ''}${readonly ? '' : ' interactive'}</h3>
          ${this.renderSessionMapTabs(maps, activeId)}
        </div>
        <div class="session-maps-body">
          ${readonly ? '' : this.renderSessionToolbarGlobal(gameState, activeMap)}
          ${activeMap ? this.renderSessionMapStage(activeMap, activeTokens, party, questFormat, readonly, gameState, navContext) : ''}
        </div>
      </div>`;
    requestAnimationFrame(() => this.restoreSessionScrollState(scrollState, panel));
    this.scheduleClearSessionNavAnim();
  },
};
