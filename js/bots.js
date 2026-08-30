/**
 * bots.js — Compagnons bots : actions précises, ancrées dans la scène.
 */

const Bots = {
  PERSONALITIES: [
    { id: 'cautious', label: 'Prudent·e' },
    { id: 'curious', label: 'Curieux·se' },
    { id: 'bold', label: 'Audacieux·se' },
    { id: 'diplomatic', label: 'Diplomate' },
    { id: 'fierce', label: 'Féroce' },
    { id: 'cheerful', label: 'Enjoué·e' },
    { id: 'mystic', label: 'Mystique' },
  ],

  ACTION_TYPES: [
    { id: 'explore', label: 'Explorer / fouiller' },
    { id: 'talk', label: 'Parler / négocier' },
    { id: 'combat', label: 'Combattre' },
    { id: 'stealth', label: 'Discrétion' },
    { id: 'support', label: 'Soutien / soins' },
  ],

  /** Profils de comportement bot selon le format de quête */
  QUEST_FORMAT_PROFILES: {
    investigation: {
      label: 'Mode enquête',
      actionBoosts: { talk: 4, explore: 3, stealth: 2, support: 1, combat: 0 },
      companionPersonalities: ['diplomatic', 'curious', 'cheerful', 'mystic'],
      companionIds: ['bot-inv-elise', 'bot-inv-noah', 'bot-inv-jade', 'bot-inv-oscar', 'bot-inv-luna'],
    },
    oneshot: {
      label: 'One-shot',
      actionBoosts: { combat: 3, explore: 2, stealth: 2, talk: 1, support: 1 },
      companionPersonalities: ['bold', 'fierce', 'cautious'],
      companionIds: ['bot-rook', 'bot-thorn', 'bot-kael'],
    },
    long: {
      label: 'Campagne longue',
      actionBoosts: { explore: 2, talk: 2, support: 2, stealth: 1, combat: 1 },
      companionPersonalities: ['cautious', 'diplomatic', 'curious', 'mystic'],
      companionIds: ['bot-kael', 'bot-sera', 'bot-lyra', 'bot-zara'],
    },
  },

  customizations: {},
  customBots: [],
  removedDefaults: [],

  DEFAULT_ARCHETYPES: [
    {
      id: 'bot-kael', name: 'Kael', race: 'Nain', class: 'Guerrier', personality: 'cautious',
      preferredActions: ['explore', 'stealth', 'support'],
      stats: { str: 16, dex: 10, con: 14, int: 8, wis: 12, cha: 10 },
      hp: 14, ac: 16, traits: ['protecteur', 'méfiant'],
    },
    {
      id: 'bot-lyra', name: 'Lyra', race: 'Elfe', class: 'Mage', personality: 'curious',
      preferredActions: ['explore', 'talk'],
      stats: { str: 8, dex: 14, con: 10, int: 16, wis: 12, cha: 10 },
      hp: 8, ac: 12, traits: ['curieuse', 'analytique'],
    },
    {
      id: 'bot-rook', name: 'Rook', race: 'Humain', class: 'Rôdeur', personality: 'bold',
      preferredActions: ['explore', 'stealth', 'combat'],
      stats: { str: 10, dex: 16, con: 12, int: 10, wis: 12, cha: 14 },
      hp: 10, ac: 14, traits: ['impulsif', 'courageux'],
    },
    {
      id: 'bot-sera', name: 'Sera', race: 'Demi-elfe', class: 'Clerc', personality: 'diplomatic',
      preferredActions: ['talk', 'support'],
      stats: { str: 10, dex: 10, con: 12, int: 12, wis: 16, cha: 14 },
      hp: 11, ac: 15, traits: ['bienveillante', 'persuasive'],
    },
    {
      id: 'bot-thorn', name: 'Thorn', race: 'Orc', class: 'Barbare', personality: 'fierce',
      preferredActions: ['combat', 'explore'],
      stats: { str: 18, dex: 12, con: 16, int: 8, wis: 10, cha: 8 },
      hp: 16, ac: 14, traits: ['brutal', 'têtu'],
    },
    {
      id: 'bot-mira', name: 'Mira', race: 'Halfelin', class: 'Barde', personality: 'cheerful',
      preferredActions: ['talk', 'explore'],
      stats: { str: 8, dex: 14, con: 10, int: 12, wis: 10, cha: 16 },
      hp: 9, ac: 13, traits: ['drôle', 'observatrice'],
    },
    {
      id: 'bot-zara', name: 'Zara', race: 'Tieffelin', class: 'Occultiste', personality: 'mystic',
      preferredActions: ['explore', 'talk'],
      stats: { str: 8, dex: 12, con: 12, int: 14, wis: 14, cha: 16 },
      hp: 10, ac: 13, traits: ['énigmatique', 'secrète'],
    },
  ],

  /** Compagnons bots dédiés au mode enquête */
  INVESTIGATION_ARCHETYPES: [
    {
      id: 'bot-inv-elise', name: 'Élise', race: 'Humaine', class: 'Inspectrice',
      personality: 'diplomatic', preferredActions: ['talk', 'explore'],
      stats: { str: 10, dex: 12, con: 11, int: 14, wis: 15, cha: 16 },
      hp: 10, ac: 13, traits: ['méthodique', 'à l\'écoute'],
      role: 'Mène les interrogatoires et recoupe les témoignages.',
    },
    {
      id: 'bot-inv-noah', name: 'Noah', race: 'Nain', class: 'Expert légiste',
      personality: 'curious', preferredActions: ['explore', 'support'],
      stats: { str: 12, dex: 10, con: 14, int: 16, wis: 14, cha: 9 },
      hp: 12, ac: 14, traits: ['rigoureux', 'obsessionnel'],
      role: 'Analyse les traces, objets et scènes de crime.',
    },
    {
      id: 'bot-inv-jade', name: 'Jade', race: 'Tieffeline', class: 'Interrogatrice',
      personality: 'bold', preferredActions: ['talk', 'stealth'],
      stats: { str: 9, dex: 14, con: 11, int: 13, wis: 12, cha: 17 },
      hp: 9, ac: 12, traits: ['perspicace', 'implacable'],
      role: 'Déstabilise les suspects et fait parler les témoins réticents.',
    },
    {
      id: 'bot-inv-oscar', name: 'Oscar', race: 'Humain', class: 'Profiler',
      personality: 'mystic', preferredActions: ['talk', 'explore'],
      stats: { str: 9, dex: 11, con: 10, int: 16, wis: 15, cha: 12 },
      hp: 9, ac: 11, traits: ['intuitif', 'froid'],
      role: 'Reconstitue les motivations et les incohérences du dossier.',
    },
    {
      id: 'bot-inv-luna', name: 'Luna', race: 'Elfe', class: 'Photographe de scène',
      personality: 'cheerful', preferredActions: ['explore', 'talk'],
      stats: { str: 8, dex: 16, con: 10, int: 13, wis: 14, cha: 13 },
      hp: 8, ac: 12, traits: ['minutieuse', 'discrete'],
      role: 'Documente les lieux et repère les détails que les autres manquent.',
    },
  ],

  investigationCustomizations: {},
  investigationCustomBots: [],
  investigationRemovedDefaults: [],

  /** @deprecated utiliser getArchetypes() */
  get ARCHETYPES() {
    return this.getArchetypes();
  },

  load() {
    const raw = Storage.load(Storage.KEYS.bots);
    if (raw?.customBots || raw?.customizations || raw?.removedDefaults) {
      this.customizations = raw.customizations || {};
      this.customBots = raw.customBots || [];
      this.removedDefaults = raw.removedDefaults || [];
    } else if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
      this.customizations = raw;
      this.customBots = [];
      this.removedDefaults = [];
    } else {
      this.customizations = {};
      this.customBots = [];
      this.removedDefaults = [];
    }

    const inv = raw?.investigation || {};
    this.investigationCustomizations = inv.customizations || {};
    this.investigationCustomBots = inv.customBots || [];
    this.investigationRemovedDefaults = inv.removedDefaults || [];
  },

  save() {
    Storage.save(Storage.KEYS.bots, {
      customizations: this.customizations,
      customBots: this.customBots,
      removedDefaults: this.removedDefaults,
      investigation: {
        customizations: this.investigationCustomizations,
        customBots: this.investigationCustomBots,
        removedDefaults: this.investigationRemovedDefaults,
      },
    });
  },

  generateBotId() {
    return `bot-custom-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  },

  isDefaultBot(id) {
    return this.DEFAULT_ARCHETYPES.some((b) => b.id === id);
  },

  isInvestigationDefaultBot(id) {
    return this.INVESTIGATION_ARCHETYPES.some((b) => b.id === id);
  },

  isInvestigationBot(id) {
    return this.isInvestigationDefaultBot(id)
      || this.investigationCustomBots.some((b) => b.id === id);
  },

  isCustomBot(id) {
    return this.customBots.some((b) => b.id === id);
  },

  isInvestigationCustomBot(id) {
    return this.investigationCustomBots.some((b) => b.id === id);
  },

  isRemovedDefault(id) {
    return this.removedDefaults.includes(id);
  },

  isInvestigationRemovedDefault(id) {
    return this.investigationRemovedDefaults.includes(id);
  },

  getArchetype(id) {
    if (this.isInvestigationBot(id)) {
      return this.getInvestigationArchetype(id);
    }
    if (this.isRemovedDefault(id)) return null;

    const customBot = this.customBots.find((b) => b.id === id);
    if (customBot) {
      return {
        ...customBot,
        stats: { ...customBot.stats },
        preferredActions: [...(customBot.preferredActions || ['explore'])],
        traits: [...(customBot.traits || [])],
      };
    }

    const base = this.DEFAULT_ARCHETYPES.find((b) => b.id === id);
    if (!base) return null;
    const custom = this.customizations[id] || {};
    return {
      ...base,
      ...custom,
      stats: { ...base.stats, ...(custom.stats || {}) },
      preferredActions: custom.preferredActions?.length
        ? [...custom.preferredActions]
        : [...base.preferredActions],
      traits: custom.traits?.length ? [...custom.traits] : [...(base.traits || [])],
    };
  },

  getArchetypes() {
    const defaults = this.DEFAULT_ARCHETYPES
      .filter((b) => !this.isRemovedDefault(b.id))
      .map((b) => this.getArchetype(b.id));
    const customs = this.customBots.map((b) => this.getArchetype(b.id)).filter(Boolean);
    return [...defaults, ...customs];
  },

  getInvestigationArchetype(id) {
    if (this.isInvestigationRemovedDefault(id)) return null;

    const customBot = this.investigationCustomBots.find((b) => b.id === id);
    if (customBot) {
      return {
        ...customBot,
        stats: { ...customBot.stats },
        preferredActions: [...(customBot.preferredActions || ['talk', 'explore'])],
        traits: [...(customBot.traits || [])],
        roster: 'investigation',
      };
    }

    const base = this.INVESTIGATION_ARCHETYPES.find((b) => b.id === id);
    if (!base) return null;
    const custom = this.investigationCustomizations[id] || {};
    return {
      ...base,
      ...custom,
      stats: { ...base.stats, ...(custom.stats || {}) },
      preferredActions: custom.preferredActions?.length
        ? [...custom.preferredActions]
        : [...base.preferredActions],
      traits: custom.traits?.length ? [...custom.traits] : [...(base.traits || [])],
      roster: 'investigation',
    };
  },

  getInvestigationArchetypes() {
    const defaults = this.INVESTIGATION_ARCHETYPES
      .filter((b) => !this.isInvestigationRemovedDefault(b.id))
      .map((b) => this.getInvestigationArchetype(b.id));
    const customs = this.investigationCustomBots
      .map((b) => this.getInvestigationArchetype(b.id))
      .filter(Boolean);
    return [...defaults, ...customs];
  },

  personalityLabel(id) {
    return this.PERSONALITIES.find((p) => p.id === id)?.label || id;
  },

  botPayloadFromForm() {
    const preferredActions = [...document.querySelectorAll('input[name="bot-action"]:checked')]
      .map((el) => el.value);

    if (preferredActions.length === 0) {
      return null;
    }

    const traitsRaw = document.getElementById('bot-traits').value.trim();
    const traits = traitsRaw
      ? traitsRaw.split(/[,;]+/).map((t) => t.trim()).filter(Boolean)
      : [];

    const name = document.getElementById('bot-name').value.trim();
    if (!name) return null;

    return {
      name,
      race: document.getElementById('bot-race').value.trim() || 'Inconnu',
      class: document.getElementById('bot-class').value.trim() || 'Aventurier',
      personality: document.getElementById('bot-personality').value,
      preferredActions,
      stats: {
        str: parseInt(document.getElementById('bot-str').value, 10),
        dex: parseInt(document.getElementById('bot-dex').value, 10),
        con: parseInt(document.getElementById('bot-con').value, 10),
        int: parseInt(document.getElementById('bot-int').value, 10),
        wis: parseInt(document.getElementById('bot-wis').value, 10),
        cha: parseInt(document.getElementById('bot-cha').value, 10),
      },
      hp: parseInt(document.getElementById('bot-hp').value, 10),
      ac: parseInt(document.getElementById('bot-ac').value, 10),
      traits,
    };
  },

  saveBot(id, data) {
    if (this.isCustomBot(id) || !this.isDefaultBot(id)) {
      const index = this.customBots.findIndex((b) => b.id === id);
      const bot = { id: id || this.generateBotId(), ...data, isCustom: true };
      if (index >= 0) {
        this.customBots[index] = bot;
      } else {
        this.customBots.push(bot);
      }
      this.save();
      return bot.id;
    }

    this.customizations[id] = { ...data };
    this.save();
    return id;
  },

  generateInvestigationBotId() {
    return `bot-inv-custom-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  },

  saveInvestigationBot(id, data) {
    const payload = { ...data, roster: 'investigation' };

    if (this.isInvestigationCustomBot(id) || !this.isInvestigationDefaultBot(id)) {
      const index = this.investigationCustomBots.findIndex((b) => b.id === id);
      const bot = { id: id || this.generateInvestigationBotId(), ...payload, isCustom: true };
      if (index >= 0) {
        this.investigationCustomBots[index] = bot;
      } else {
        this.investigationCustomBots.push(bot);
      }
      this.save();
      return bot.id;
    }

    this.investigationCustomizations[id] = { ...payload };
    this.save();
    return id;
  },

  resetInvestigationCustomization(id) {
    if (this.isInvestigationCustomBot(id)) return;
    delete this.investigationCustomizations[id];
    this.save();
  },

  deleteInvestigationBot(id) {
    if (this.isInvestigationCustomBot(id)) {
      this.investigationCustomBots = this.investigationCustomBots.filter((b) => b.id !== id);
    } else if (this.isInvestigationDefaultBot(id) && !this.isInvestigationRemovedDefault(id)) {
      this.investigationRemovedDefaults.push(id);
      delete this.investigationCustomizations[id];
    }
    this.save();
  },

  isInvestigationCustomized(id) {
    if (this.isInvestigationCustomBot(id)) return true;
    return Boolean(this.investigationCustomizations[id]);
  },

  resetCustomization(id) {
    if (this.isCustomBot(id)) return;
    delete this.customizations[id];
    this.save();
  },

  deleteBot(id) {
    if (this.isCustomBot(id)) {
      this.customBots = this.customBots.filter((b) => b.id !== id);
    } else if (this.isDefaultBot(id) && !this.isRemovedDefault(id)) {
      this.removedDefaults.push(id);
      delete this.customizations[id];
    }
    this.save();
  },

  isCustomized(id) {
    if (this.isCustomBot(id)) return true;
    return Boolean(this.customizations[id]);
  },

  escape(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },

  renderList() {
    const container = document.getElementById('bot-list');
    if (!container) return;

    const bots = this.getArchetypes();
    if (bots.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Aucun compagnon bot pour l'instant.</p>
          <p>Clique sur « + Nouveau bot » pour en créer un.</p>
        </div>`;
      return;
    }

    container.innerHTML = bots.map((b) => {
      const isCustom = this.isCustomBot(b.id);
      const customizedDefault = !isCustom && Boolean(this.customizations[b.id]);
      return `
      <div class="card card-bot ${this.isCustomized(b.id) ? 'is-customized' : ''} ${isCustom ? 'is-user-bot' : ''}" data-id="${b.id}">
        <span class="bot-badge">${isCustom ? '✨ Bot perso' : '🤖 Compagnon IA'}</span>
        <h3>${this.escape(b.name)}</h3>
        <p class="card-meta">${this.escape(b.race)} · ${this.escape(b.class)}</p>
        <p class="card-personality">${this.escape(this.personalityLabel(b.personality))}</p>
        <div class="card-stats">
          <span class="stat-badge">PV ${b.hp}</span>
          <span class="stat-badge">CA ${b.ac}</span>
          <span class="stat-badge">FOR ${b.stats.str}</span>
          <span class="stat-badge">DEX ${b.stats.dex}</span>
        </div>
        <p class="card-traits">${b.traits.map((t) => this.escape(t)).join(' · ') || '—'}</p>
        <div class="card-actions">
          <button type="button" class="btn btn-secondary btn-edit-bot" data-id="${b.id}">Modifier</button>
          ${customizedDefault ? `<button type="button" class="btn btn-secondary btn-reset-bot" data-id="${b.id}">Réinitialiser</button>` : ''}
          <button type="button" class="btn btn-danger btn-delete-bot" data-id="${b.id}">Supprimer</button>
        </div>
      </div>`;
    }).join('');

    container.querySelectorAll('.btn-edit-bot').forEach((btn) => {
      btn.addEventListener('click', () => this.showForm(btn.dataset.id));
    });
    container.querySelectorAll('.btn-reset-bot').forEach((btn) => {
      btn.addEventListener('click', () => this.resetBot(btn.dataset.id));
    });
    container.querySelectorAll('.btn-delete-bot').forEach((btn) => {
      btn.addEventListener('click', () => this.deleteBotConfirm(btn.dataset.id));
    });
  },

  showForm(id = null) {
    document.getElementById('character-form')?.classList.add('hidden');
    const form = document.getElementById('bot-form');
    const title = document.getElementById('bot-form-title');
    form.classList.remove('hidden');

    if (id) {
      const bot = this.getArchetype(id);
      if (!bot) return;
      title.textContent = this.isCustomBot(id) ? 'Modifier le bot perso' : 'Modifier le compagnon bot';
      document.getElementById('bot-id').value = bot.id;
      document.getElementById('bot-name').value = bot.name;
      document.getElementById('bot-race').value = bot.race;
      document.getElementById('bot-class').value = bot.class;
      document.getElementById('bot-personality').value = bot.personality;
      document.getElementById('bot-str').value = bot.stats.str;
      document.getElementById('bot-dex').value = bot.stats.dex;
      document.getElementById('bot-con').value = bot.stats.con;
      document.getElementById('bot-int').value = bot.stats.int;
      document.getElementById('bot-wis').value = bot.stats.wis;
      document.getElementById('bot-cha').value = bot.stats.cha;
      document.getElementById('bot-hp').value = bot.hp;
      document.getElementById('bot-ac').value = bot.ac;
      document.getElementById('bot-traits').value = (bot.traits || []).join(', ');

      const selected = new Set(bot.preferredActions || []);
      form.querySelectorAll('input[name="bot-action"]').forEach((input) => {
        input.checked = selected.has(input.value);
      });
    } else {
      title.textContent = 'Nouveau compagnon bot';
      document.getElementById('bot-form-el').reset();
      document.getElementById('bot-id').value = '';
      document.getElementById('bot-str').value = 10;
      document.getElementById('bot-dex').value = 10;
      document.getElementById('bot-con').value = 10;
      document.getElementById('bot-int').value = 10;
      document.getElementById('bot-wis').value = 10;
      document.getElementById('bot-cha').value = 10;
      document.getElementById('bot-hp').value = 10;
      document.getElementById('bot-ac').value = 10;
      document.getElementById('bot-personality').value = 'curious';
      form.querySelectorAll('input[name="bot-action"]').forEach((input) => {
        input.checked = input.value === 'explore' || input.value === 'talk';
      });
    }

    form.scrollIntoView({ behavior: 'smooth' });
  },

  hideForm() {
    document.getElementById('bot-form')?.classList.add('hidden');
  },

  handleSubmit(e) {
    e.preventDefault();

    const id = document.getElementById('bot-id').value;
    const data = this.botPayloadFromForm();

    if (!data) {
      alert('Remplis au moins le nom et choisis une action préférée.');
      return;
    }

    this.saveBot(id, data);
    this.renderList();
    this.hideForm();
  },

  resetBot(id) {
    if (this.isCustomBot(id)) return;
    const bot = this.getArchetype(id);
    if (!bot) return;
    if (!confirm(`Réinitialiser « ${bot.name} » aux valeurs d'origine ?`)) return;
    this.resetCustomization(id);
    this.renderList();
    this.hideForm();
  },

  deleteBotConfirm(id) {
    const bot = this.getArchetype(id);
    if (!bot) return;
    const label = this.isCustomBot(id) ? 'bot perso' : 'compagnon bot';
    if (!confirm(`Supprimer le ${label} « ${bot.name} » ?`)) return;
    this.deleteBot(id);
    this.renderList();
    this.hideForm();
  },

  initEditor() {
    this.load();
    this.renderList();

    document.getElementById('btn-new-bot')?.addEventListener('click', () => this.showForm());
    document.getElementById('bot-form-el')?.addEventListener('submit', (e) => this.handleSubmit(e));
    document.getElementById('btn-cancel-bot')?.addEventListener('click', () => this.hideForm());
  },

  getFormatProfile(questFormat) {
    return this.QUEST_FORMAT_PROFILES[questFormat] || this.QUEST_FORMAT_PROFILES.oneshot;
  },

  scoreArchetypeForFormat(archetype, profile) {
    let score = 0;
    if (profile.companionIds.includes(archetype.id)) score += 3;
    if (profile.companionPersonalities.includes(archetype.personality)) score += 2;
    (archetype.preferredActions || []).forEach((pref) => {
      score += (profile.actionBoosts[pref] || 0) * 0.5;
    });
    return score;
  },

  /** Extrait des éléments concrets du texte de la scène */
  extractSceneDetails(scene, scenario, context = {}) {
    const content = scene?.content || '';
    const title = scene?.title || 'la zone';
    const full = `${title}. ${content}`.toLowerCase();

    const allNpcs = context.allNpcs || scenario?.npcs || [];
    const details = {
      title,
      clauses: content.split(/[,;.] /).map((s) => s.trim()).filter((s) => s.length > 12),
      objects: [],
      npc: allNpcs[0] || null,
      allNpcs,
    };

    const objectPatterns = [
      { re: /porte[^.,;]{0,30}/i, label: (m) => m[0].trim() },
      { re: /escalier[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /runes?[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /symboles?[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /autel[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /passage[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /couloir[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /puits[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /coffre[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /grimoire[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /journal[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /torches?[^.,;]{0,20}/i, label: (m) => m[0].trim() },
      { re: /murs?[^.,;]{0,20}/i, label: (m) => m[0].trim() },
      { re: /silhouette[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /créature[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /gardien[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /offrandes?[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /tapisserie[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /bibliothèque[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /fenêtre[^.,;]{0,25}/i, label: (m) => m[0].trim() },
      { re: /dunes?[^.,;]{0,20}/i, label: (m) => m[0].trim() },
      { re: /ruines?[^.,;]{0,25}/i, label: (m) => m[0].trim() },
    ];

    objectPatterns.forEach(({ re, label }) => {
      const m = content.match(re);
      if (m) {
        const item = label(m);
        if (!details.objects.find((o) => o.toLowerCase() === item.toLowerCase())) {
          details.objects.push(item.charAt(0).toLowerCase() + item.slice(1));
        }
      }
    });

    if (details.objects.length === 0 && details.clauses.length > 0) {
      details.objects.push(details.clauses[0].charAt(0).toLowerCase() + details.clauses[0].slice(1));
    }

    if (/ennemi|menace|danger|combat|attaq/i.test(full)) details.hasThreat = true;

    return details;
  },

  /** Actions précises selon la classe du bot et le format de quête */
  classActions(bot, details, questFormat = 'oneshot') {
    const obj = details.objects[0] || `les lieux de ${details.title}`;
    const obj2 = details.objects[1] || obj;
    const npc = details.npc;
    const clause = details.clauses[0] || details.title;

    const investigationExtras = {
      Guerrier: [
        `Je vérifie si ${obj} a été forcé récemment — preuve d'effraction ou fausse piste ?`,
        `Je protège ${npc ? npc.name : 'le témoin'} pendant l'interrogatoire pour qu'il parle sans crainte.`,
      ],
      Mage: [
        `Je cherche une trace magique sur ${obj} — sortilège, illusion ou simple supercherie ?`,
        `Je dresse une chronologie des événements en recoupant ${clause} avec nos notes.`,
      ],
      Rôdeur: [
        `Je repère les traces dissimulées près de ${obj} : sang, cendres, empreintes.`,
        `Je surveille ${npc ? npc.name : 'le suspect'} discrètement pendant qu'il répond aux questions.`,
      ],
      Clerc: [
        `Je demande à ${npc ? npc.name : 'le témoin'} de jurer sur sa version des faits.`,
        `Je cherche des signes de mensonge ou de peur chez ${npc ? npc.name : 'l\'interlocuteur'}.`,
      ],
      Barbare: [
        `Je intimide ${npc ? npc.name : 'le suspect'} pour qu'il lâche une contradiction dans son récit.`,
        `Je force l'accès à ${obj} si c'est là que se cache la preuve.`,
      ],
      Barde: [
        `J'écoute le ton de ${npc ? npc.name : 'l\'interlocuteur'} — hésitation, colère, trop de détails ?`,
        `Je compare les témoignages : qui contredit qui sur ${obj} ?`,
      ],
      Occultiste: [
        `Je sonde ${obj} pour détecter un enchantement de dissimulation.`,
        `Je relève une empreinte occulte qui pourrait trahir le coupable.`,
      ],
    };

    const oneshotExtras = {
      Guerrier: [`Je fonce vers ${obj} — on règle ça maintenant, pas demain.`],
      Mage: [`Je lance le sort le plus direct pour débloquer ${obj} immédiatement.`],
      Rôdeur: [`Je contourne par ${obj2} pour surprendre l'adversaire avant qu'il réagisse.`],
      Clerc: [`Je galvanise le groupe : « Plus de temps à perdre, on avance ! »`],
      Barbare: [`Je charge ${obj} sans hésiter — la scène doit tourner, vite.`],
      Barde: [`Je pousse ${npc ? npc.name : 'le PNJ'} à parler tout de suite, sans détour.`],
      Occultiste: [`J'invoque une aide rapide pour percer ${obj} sans longues incantations.`],
    };

    const longExtras = {
      Guerrier: [
        `Je cartographie les accès de ${obj} pour les sessions à venir.`,
        `Je note les défenses de ${details.title} dans mon carnet de campagne.`,
      ],
      Mage: [
        `Je consigne mes recherches sur ${obj} — ce détail pourra servir plus tard.`,
        `Je théorise un lien entre ${clause} et les événements des sessions passées.`,
      ],
      Rôdeur: [
        `Je marque discrètement ${obj} pour y revenir si la quête nous ramène ici.`,
        `Je surveille ${details.title} sur la durée : qui va et vient, et quand ?`,
      ],
      Clerc: [
        `Je prends le temps d'écouter ${npc ? npc.name : 'les habitants'} — les relations comptent sur le long terme.`,
        `Je bénis le campement près de ${obj} : on reviendra peut-être.`,
      ],
      Barbare: [
        `Je teste ${obj} sans précipitation — une campagne, ça se joue sur plusieurs jours.`,
        `Je laisse une marque au groupe sur ${obj2} pour ne pas oublier ce lieu.`,
      ],
      Barde: [
        `Je transforme ce qu'on apprend sur ${obj} en une ballade pour la chronique du groupe.`,
        `Je retourne voir ${npc ? npc.name : 'le PNJ'} — la confiance se construit avec le temps.`,
      ],
      Occultiste: [
        `J'archive mes observations sur ${obj} — le fil occulte se dévoile lentement.`,
        `Je laisse une rune discrète sur ${obj2} pour la retrouver à notre prochain passage.`,
      ],
    };

    const templates = {
      Guerrier: [
        `Je teste la solidité de ${obj} avec mon épée — piège ou passage sûr ?`,
        `Je me poste devant ${obj2} pour couvrir le groupe pendant qu'on fouille.`,
        `Je frappe ${obj} pour voir si un mécanisme se déclenche.`,
        `Je sécurise l'approche de ${obj} avant que les autres avancent.`,
      ],
      Mage: [
        `Je lance un sort de lumière pour éclairer ${obj} et révéler ce qui est caché.`,
        `J'analyse la magie résiduelle autour de ${obj2}.`,
        `Je décrypte les inscriptions sur ${obj} avec mes connaissances arcaniques.`,
        `Je compare ${clause} avec ce que je sais des légendes locales.`,
      ],
      Rôdeur: [
        `Je cherche des traces de pas et de sang près de ${obj}.`,
        `Je désamorce un éventuel piège sur ${obj2} avant qu'on s'approche.`,
        `Je grimpe pour observer ${obj} sous un angle différent.`,
        `Je fouille discrètement ${obj} sans alerter qui que ce soit.`,
      ],
      Clerc: [
        `Je prie et cherche une présence divine près de ${obj}.`,
        `Je bénis ${obj2} pour repousser une éventuelle malédiction.`,
        npc ? `Je demande à ${npc.name} s'il a besoin d'aide ou de soins.` : `Je cherche des blessés ou des traces de violence près de ${obj}.`,
        `Je récite un psaume de protection en approchant de ${obj}.`,
      ],
      Barbare: [
        `Je force ${obj} à l'aide de ma force brute.`,
        `Je défie bruyamment quiconque se cache derrière ${obj2} !`,
        `Je casse un obstacle bloquant l'accès à ${obj}.`,
        `Je prépare mon arme en fixant ${obj} — prêt au combat.`,
      ],
      Barde: [
        `Je questionne ${npc ? npc.name : 'les gens du coin'} sur l'histoire de ${obj}.`,
        `J'observe les réactions des PNJ quand je mentionne ${obj2} — qui ment ?`,
        `Je cherche une chanson ou une légende qui parlerait de ${obj}.`,
        `Je retiens chaque mot de la scène « ${details.title} » pour repérer un indice dans : « ${clause} ».`,
        `Je fais semblant de nettoyer ${obj} pour le toucher et l'inspecter de près.`,
      ],
      Occultiste: [
        `Je murmure une incantation pour détecter des entités près de ${obj}.`,
        `Je trace un cercle protecteur autour de ${obj2}.`,
        `Je consulte mon grimoire sur les symboles ressemblant à ceux de ${obj}.`,
        `Je tends la main vers ${obj} pour sentir l'énergie occulte qui s'en dégage.`,
      ],
      Inspectrice: [
        `Je relève méthodiquement chaque détail autour de ${obj} et je le note dans mon registre.`,
        `J'interroge ${npc ? npc.name : 'le témoin'} sur son alibi et je compare avec nos notes.`,
        `Je demande à ${npc ? npc.name : 'l\'interlocuteur'} de répéter sa version — je cherche les incohérences.`,
        `Je recoupe ce qu'on sait de ${obj} avec les témoignages déjà recueillis.`,
      ],
      'Expert légiste': [
        `Je prélève des traces sur ${obj} : poussière, fibre, résidu — tout est une preuve.`,
        `J'analyse ${obj2} avec mes outils pour dater ou identifier l'origine du geste.`,
        `Je documente ${obj} photographiquement avant qu'on ne perturbe la scène.`,
        `Je compare ${clause} avec les rapports d'autopsie ou d'archives disponibles.`,
      ],
      Interrogatrice: [
        `Je pousse ${npc ? npc.name : 'le suspect'} dans ses contradictions sur ${obj}.`,
        `Je change soudain de sujet pour surprendre ${npc ? npc.name : 'le témoin'} sur son alibi.`,
        `Je laisse un silence pesant après la question sur ${obj} — qui craque le premier ?`,
        `Je feins de connaître la vérité sur ${obj2} pour provoquer une réaction.`,
      ],
      Profiler: [
        `Je reconstitue le profil psychologique de celui qui a manipulé ${obj}.`,
        `Je cherche le mobile derrière ${clause} — passion, argent ou vengeance ?`,
        `J'identifie qui bénéficie le plus de ce qui s'est passé près de ${obj}.`,
        `Je dresse une chronologie des actes probables autour de ${details.title}.`,
      ],
      'Photographe de scène': [
        `Je capture sous tous les angles ${obj} — un détail invisible à l'œil nu peut tout changer.`,
        `Je compare mes clichés précédents de ${obj2} avec l'état actuel des lieux.`,
        `Je repère une trace légère sur ${obj} que personne n'a encore mentionnée.`,
        `Je note l'éclairage et la disposition de ${details.title} pour la reconstitution.`,
      ],
      Enquêteur: [
        `Je dresse la liste des suspects liés à ${obj} et je priorise les interrogatoires.`,
        `Je vérifie les accès à ${obj2} — qui pouvait être sur place cette nuit-là ?`,
        `Je recoupe les témoignages sur ${obj} et je signale les contradictions au groupe.`,
        `Je fouille ${obj} en respectant la chaîne de custody des preuves.`,
      ],
    };

    let actions = [...(templates[bot.class] || templates.Rôdeur)];

    if (questFormat === 'investigation') {
      actions = [...(investigationExtras[bot.class] || []), ...actions];
    } else if (questFormat === 'oneshot') {
      actions = [...(oneshotExtras[bot.class] || []), ...actions];
    } else if (questFormat === 'long') {
      actions = [...(longExtras[bot.class] || []), ...actions];
    }

    return actions;
  },

  /** Actions liées à chaque objet détecté dans la scène */
  objectActions(bot, details) {
    const actions = [];
    details.objects.forEach((obj) => {
      actions.push(
        `J'examine ${obj} en détail — traces, odeurs, mécanismes.`,
        `Je fouille ${obj} à la recherche d'un indice ou d'un objet caché.`,
        `Je teste ${obj} avec prudence avant de signaler mes trouvailles au groupe.`,
      );
      if (/porte|passage|escalier|puits/i.test(obj)) {
        actions.push(`Je tente d'ouvrir ou de descendre via ${obj}.`);
      }
      if (/runes|symboles|inscriptions/i.test(obj)) {
        actions.push(`Je tente de traduire ${obj} mot par mot.`);
      }
      if (/autel|coffre|offrandes/i.test(obj)) {
        actions.push(`Je cherche un compartiment secret dans ${obj}.`);
      }
    });
    return actions;
  },

  /** Actions de dialogue avec PNJ nommés */
  npcActions(details) {
    if (!details.allNpcs.length) return [];
    const actions = [];
    details.allNpcs.forEach((npc) => {
      actions.push(
        `Je m'approche de ${npc.name} (${npc.role || 'PNJ'}) et je lui demande : « Que savez-vous sur ${details.title} ? »`,
        `Je questionne ${npc.name} sur son rôle ici : « ${(npc.description || '').split('.')[0]} » — est-ce vrai ?`,
        `Je tente de gagner la confiance de ${npc.name} pour qu'il nous guide vers la suite.`,
      );
    });
    return actions;
  },

  /** Si le joueur a échoué, le bot tente une approche différente et précise */
  /** Réagit aux faits du monde et aux changements de scène */
  worldAwareActions(bot, context, details) {
    const actions = [];
    const facts = context.worldFacts || [];
    const flags = context.worldFlags || {};
    const changes = context.sceneChanges || [];

    if (facts.length) {
      const last = facts[facts.length - 1];
      actions.push(
        `Je reprends la piste laissée par ${last.actorName} : ${last.text} — et j'approfondis.`,
        `En me basant sur ce qu'on sait déjà (« ${last.text.slice(0, 60)}… »), j'examine ${details.objects[0] || details.title}.`,
      );
    }

    changes.forEach((change) => {
      actions.push(`Je réagis à ce changement dans la scène : ${change}`);
    });

    if (flags.passage_trouve) {
      actions.push(`Je tente de franchir le passage repéré — prudemment, épée ou sort prêt.`);
    }
    if (flags.runes_lues) {
      actions.push(`Je réutilise ce qu'on a appris sur les runes pour décrypter un nouveau symbole ici.`);
    }
    if (flags.alerte) {
      actions.push(`Le lieu est alerté — je cherche une cachette ou une route de repli près de ${details.objects[0] || details.title}.`);
    }
    if (flags.combat_lieu) {
      actions.push(`Le combat a laissé des traces : je fouille la zone pour des indices ou des objets abandonnés.`);
    }

    return actions;
  },

  complementActions(bot, details, humanActionType) {
    const obj = details.objects[0] || details.title;
    const npc = details.npc;
    const map = {
      explore: [
        `Puisque la fouille a échoué, j'interroge ${npc ? npc.name : 'un témoin'} sur ${obj}.`,
        `J'essaie une autre zone : ${details.objects[1] || obj2Fallback(details)}.`,
      ],
      talk: [
        `La conversation n'a rien donné — j'inspecte plutôt ${obj} physiquement.`,
        `Je fouille ${obj} pendant que le PNJ est distrait.`,
      ],
      combat: [
        `Le combat tourne mal — je bande les blessures du groupe et je cherche une retraite vers ${obj}.`,
      ],
      stealth: [
        `On nous a repérés — j'attaque de front ${obj} pour créer une diversion.`,
      ],
    };
    function obj2Fallback(d) {
      return d.objects[1] || d.clauses[0] || d.title;
    }
    return map[humanActionType] || [];
  },

  normalizeId(id) {
    if (!id) return '';
    return id.startsWith('bot:') ? id.replace('bot:', '') : id;
  },

  createPartyMember(archetypeOrId, index = 0) {
    const archetype = typeof archetypeOrId === 'string'
      ? this.getArchetype(archetypeOrId)
      : archetypeOrId;
    const a = { ...archetype, stats: { ...archetype.stats } };
    return {
      id: `party-${a.id}-${Date.now()}-${index}`,
      characterId: a.id, name: a.name, race: a.race, class: a.class,
      stats: a.stats, hp: a.hp, maxHp: a.hp, ac: a.ac,
      isBot: true, isHuman: false, playerName: null,
      personality: a.personality, preferredActions: a.preferredActions || ['explore'],
      traits: a.traits || [],
    };
  },

  shuffle(array) {
    const arr = [...array];
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  },

  generateCompanions(count = 2, excludeIds = [], questFormat = null) {
    const excludeSet = new Set(excludeIds.map((id) => this.normalizeId(id)).filter(Boolean));
    const useInvestigation = questFormat === 'investigation';
    let available = (useInvestigation ? this.getInvestigationArchetypes() : this.getArchetypes())
      .filter((a) => !excludeSet.has(a.id));

    const profile = questFormat ? this.QUEST_FORMAT_PROFILES[questFormat] : null;
    if (profile?.companionIds?.length && available.length > count) {
      const prioritized = [];
      const rest = [];
      available.forEach((bot) => {
        if (profile.companionIds.includes(bot.id)) prioritized.push(bot);
        else rest.push(bot);
      });
      available = [...this.shuffle(prioritized), ...this.shuffle(rest)];
    } else {
      available = this.shuffle(available);
    }

    return available.slice(0, Math.min(count, available.length))
      .map((a, i) => this.createPartyMember(a, i));
  },

  usedIdsFromParty(party) {
    return party.map((m) => m.characterId).filter(Boolean);
  },

  pickUniqueAction(pool, recentActions) {
    const recent = new Set(recentActions || []);
    let available = pool.filter((a) => !recent.has(a));
    if (available.length === 0) available = pool;
    return available[Math.floor(Math.random() * available.length)];
  },

  actionMatchesPreference(action, pref) {
    const t = action.toLowerCase();
    const map = {
      explore: /fouill|examin|inspect|cherch|décrypt|traduit|analyse|runes|symboles|compartiment/,
      talk: /parl|question|interroge|confiance|chanson|légende|demande|pnj/,
      combat: /attaq|frapp|défie|arme|combat|force|menace|protège le groupe/,
      stealth: /discr|cache|silenc|sans alerter|repli|cachette/,
      support: /soin|prie|bénis|bande|aide|moral|remonte/,
    };
    return map[pref]?.test(t) || false;
  },

  pickPreferredAction(pool, bot, recentActions) {
    const recent = new Set(recentActions || []);
    let available = pool.filter((a) => !recent.has(a));
    if (available.length === 0) available = pool;

    const prefs = bot.preferredActions || [];
    if (!prefs.length) return this.pickUniqueAction(pool, recentActions);

    const weighted = [];
    available.forEach((action) => {
      const weight = prefs.some((p) => this.actionMatchesPreference(action, p)) ? 3 : 1;
      for (let i = 0; i < weight; i += 1) weighted.push(action);
    });

    return weighted[Math.floor(Math.random() * weighted.length)];
  },

  buildActionPool(bot, context) {
    const { scene, scenario, humanFailed, humanActionType, questFormat } = context;
    const details = this.extractSceneDetails(scene, scenario, context);

    let pool = [
      ...this.classActions(bot, details, questFormat || 'oneshot'),
      ...this.objectActions(bot, details),
      ...this.npcActions(details),
      ...this.worldAwareActions(bot, context, details),
    ];

    if (questFormat === 'investigation') {
      const npc = details.npc?.name || details.allNpcs?.[0]?.name || 'le témoin';
      const obj = details.objects[0] || details.title;
      pool.unshift(
        `J'interroge ${npc} sur son alibi et ce qu'il a vu cette nuit-là.`,
        `Je recoupe les indices trouvés jusqu'ici avec ce qu'on sait de ${obj}.`,
        `J'examine ${obj} en cherchant une preuve ou une trace laissée par le suspect.`,
        `Je demande à ${npc} de confirmer ou infirmer la version des faits du groupe.`,
      );
    }

    if (questFormat === 'oneshot') {
      pool.unshift(
        `J'agis vite et directement sur ${details.objects[0] || details.title} — pas de temps à perdre.`,
      );
    }

    if (questFormat === 'long') {
      pool.push(
        `Je prends des notes détaillées sur ${details.title} pour ne rien oublier d'ici la prochaine session.`,
      );
    }

    if (humanFailed && humanActionType) {
      pool = this.complementActions(bot, details, humanActionType).concat(pool);
    }

    if (details.hasThreat && (bot.preferredActions || []).includes('combat')) {
      const threat = details.objects.find((o) => /silhouette|créature|gardien/i.test(o)) || 'la menace';
      pool.unshift(`J'attaque ${threat} pour protéger le groupe !`);
    }

    pool = pool.filter((a) => a.length > 25 && !/quelque chose|inattendu|imprévu|d'une façon/i.test(a));
    return [...new Set(pool)];
  },

  chooseAction(bot, context) {
    const pool = this.buildActionPool(bot, context);

    if (pool.length === 0) {
      const details = this.extractSceneDetails(context.scene, context.scenario, context);
      const fallback = `J'examine minutieusement ${details.objects[0] || context.scene?.title || 'la scène'} pour trouver un indice.`;
      return this.pickPreferredAction([fallback], bot, context.recentActions);
    }

    return this.pickPreferredAction(pool, bot, context.recentActions);
  },

  getCompanions(party) {
    return party.filter((m) => m.isBot);
  },
};
