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

    const rawState = Storage.load(Storage.KEYS.activeGame);
    this.state = this.normalizeSavedState(rawState);
    if (rawState && !this.state) {
      Storage.save(Storage.KEYS.activeGame, null);
    }

    this.bindSetupEvents();
    this.bindSessionEvents();
    this.renderSetup();
  },

  normalizeSavedState(state) {
    if (!state || typeof state !== 'object') return null;
    if (!Array.isArray(state.party) || state.party.length === 0) return null;
    if (!Array.isArray(state.log)) state.log = [];
    if (state.status !== 'playing' && state.status !== 'completed') return null;
    if (!state.scenarioId) return null;
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
      radio.addEventListener('change', () => this.refreshSetupCharacters());
    });

    document.getElementById('setup-scenario')?.addEventListener('change', () => {
      if (typeof Maps !== 'undefined') {
        Maps.load();
        const scenarioId = document.getElementById('setup-scenario')?.value || '';
        const questFormat = this.getSetupQuestFormat();
        const linked = Maps.getSetupMapPool(scenarioId, questFormat)
          .filter((m) => m.scenarioId === scenarioId)
          .map((m) => m.id);
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
      this.refreshSetupMaps();
    }
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

      const mapIds = this.expandMapIdsWithLinkedLocals(this.getSelectedSetupMapIds());

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
    Storage.save(Storage.KEYS.activeGame, this.state);
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

    if (this.state.gmType === 'ai') {
      this.processAiResponse(action, actor);
    } else {
      if (/explor|fouill|inspect|cherch|cartograph|voyage|carte|déplacement|deplacement/i.test(action)) {
        this.revealWorldOnExplore(4);
      }
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
    log.scrollTop = log.scrollHeight;
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
