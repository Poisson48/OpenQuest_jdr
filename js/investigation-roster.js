/**
 * investigation-roster.js — Espace dédié personnages & bots pour le mode enquête.
 */

const InvestigationRoster = {
  INVESTIGATOR_PRESETS: [
    {
      name: 'Inspecteur Vale',
      race: 'Humain',
      class: 'Enquêteur',
      stats: { str: 11, dex: 12, con: 12, int: 15, wis: 14, cha: 13 },
      hp: 11,
      ac: 13,
      backstory: 'Ancien de la garde de la ville, spécialisé dans les affaires non résolues. Méthode, patience et instinct.',
      specialty: 'Interrogatoires & recoupements',
    },
    {
      name: 'Clara Noir',
      race: 'Demi-elfe',
      class: 'Profiler',
      stats: { str: 9, dex: 13, con: 10, int: 16, wis: 15, cha: 14 },
      hp: 9,
      ac: 12,
      backstory: 'Lectrice d\'âmes et de mensonges. Reconstitue les motivations avant même d\'entrer sur une scène de crime.',
      specialty: 'Profilage & incohérences',
    },
    {
      name: 'Marcus Chen',
      race: 'Humain',
      class: 'Expert légiste',
      stats: { str: 10, dex: 11, con: 13, int: 16, wis: 13, cha: 10 },
      hp: 10,
      ac: 12,
      backstory: 'Chimiste et archiviste. Aucune trace ne lui échappe — poussière, encre, sang ou poison.',
      specialty: 'Analyse de traces',
    },
    {
      name: 'Sasha Reed',
      race: 'Halfeline',
      class: 'Enquêteur privé',
      stats: { str: 8, dex: 16, con: 10, int: 13, wis: 12, cha: 15 },
      hp: 9,
      ac: 13,
      backstory: 'Discret, efficace, habituée à glisser dans les interstices des grandes maisons sans se faire remarquer.',
      specialty: 'Discrétion & filature',
    },
  ],

  init() {
    this.bindEvents();
    this.render();
  },

  bindEvents() {
    document.getElementById('btn-inv-new-character')?.addEventListener('click', () => {
      this.showCharacterForm();
    });
    document.getElementById('btn-inv-new-bot')?.addEventListener('click', () => {
      this.showBotForm();
    });
    document.getElementById('btn-inv-launch')?.addEventListener('click', () => {
      App.showApp('play', { quest: 'investigation', gm: 'ai' });
    });
    document.getElementById('btn-inv-launch-long')?.addEventListener('click', () => {
      App.showApp('play', {
        quest: 'investigation',
        gm: 'ai',
        scenario: Scenarios.getInvestigationLongScenarios()[0]?.id,
      });
    });
    document.getElementById('btn-inv-new-scenario')?.addEventListener('click', () => {
      App.showApp('adventures');
      Scenarios.showForm(null, { roster: 'investigation', questFormat: 'oneshot' });
    });
    document.getElementById('btn-inv-new-scenario-long')?.addEventListener('click', () => {
      App.showApp('adventures');
      Scenarios.showForm(null, { roster: 'investigation', questFormat: 'long' });
    });
    document.getElementById('inv-character-form-el')?.addEventListener('submit', (e) => {
      this.handleCharacterSubmit(e);
    });
    document.getElementById('btn-inv-cancel-character')?.addEventListener('click', () => {
      this.hideCharacterForm();
    });
    document.getElementById('inv-bot-form-el')?.addEventListener('submit', (e) => {
      this.handleBotSubmit(e);
    });
    document.getElementById('btn-inv-cancel-bot')?.addEventListener('click', () => {
      this.hideBotForm();
    });
  },

  render() {
    Characters.load();
    Bots.load();
    Scenarios.load();
    Scenarios.ensureDemoScenario();
    this.renderScenarios();
    this.renderCharacters();
    this.renderBots();
    this.renderPresets();
  },

  renderScenarioCards(scenarios, emptyMessage) {
    if (scenarios.length === 0) {
      return `
        <div class="empty-state">
          <p>${emptyMessage}</p>
        </div>`;
    }

    return scenarios.map((s) => {
      const isLong = s.questFormat === 'long';
      const badge = isLong ? '📁 Enquête longue' : '🔍 Affaire';
      return `
      <div class="card card-investigation" data-id="${s.id}">
        <span class="bot-badge inv-badge">${badge}</span>
        <h3>${Scenarios.escape(s.title)}</h3>
        <p class="card-meta">${s.scenes.length} scène(s) · ${s.npcs.length} PNJ / suspects</p>
        ${s.mystery ? `<p class="inv-scenario-mystery"><strong>Mystère :</strong> ${Scenarios.escape(s.mystery)}</p>` : ''}
        <p class="inv-preset-desc">${Scenarios.escape((s.synopsis || '').slice(0, 120))}${(s.synopsis || '').length > 120 ? '…' : ''}</p>
        <div class="card-actions">
          <button type="button" class="btn btn-primary btn-small btn-inv-play-scenario" data-id="${s.id}">Jouer cette enquête</button>
          <button type="button" class="btn btn-secondary btn-small btn-inv-edit-scenario" data-id="${s.id}">Modifier</button>
          <button type="button" class="btn btn-danger btn-small btn-inv-delete-scenario" data-id="${s.id}">Supprimer</button>
        </div>
      </div>`;
    }).join('');
  },

  bindScenarioCardEvents(container) {
    if (!container) return;

    container.querySelectorAll('.btn-inv-play-scenario').forEach((btn) => {
      btn.addEventListener('click', () => {
        App.showApp('play', { quest: 'investigation', gm: 'ai', scenario: btn.dataset.id });
      });
    });
    container.querySelectorAll('.btn-inv-edit-scenario').forEach((btn) => {
      btn.addEventListener('click', () => {
        App.showApp('adventures');
        Scenarios.showForm(btn.dataset.id);
      });
    });
    container.querySelectorAll('.btn-inv-delete-scenario').forEach((btn) => {
      btn.addEventListener('click', () => {
        Scenarios.delete(btn.dataset.id);
      });
    });
  },

  renderScenarios() {
    const oneshotContainer = document.getElementById('inv-scenario-list-oneshot');
    const longContainer = document.getElementById('inv-scenario-list-long');
    if (!oneshotContainer || !longContainer) return;

    const oneshot = Scenarios.getInvestigationOneshotScenarios();
    const long = Scenarios.getInvestigationLongScenarios();

    oneshotContainer.innerHTML = this.renderScenarioCards(
      oneshot,
      'Aucune affaire one-shot. Les enquêtes courtes apparaîtront ici.',
    );
    longContainer.innerHTML = this.renderScenarioCards(
      long,
      'Aucune enquête longue. Crée une affaire multi-sessions pour ce format.',
    );

    this.bindScenarioCardEvents(oneshotContainer);
    this.bindScenarioCardEvents(longContainer);
  },

  getInvestigationCharacters() {
    return Characters.list.filter((c) => c.roster === 'investigation');
  },

  renderPresets() {
    const container = document.getElementById('inv-preset-list');
    if (!container) return;

    container.innerHTML = this.INVESTIGATOR_PRESETS.map((preset, index) => `
      <article class="inv-preset-card">
        <h4>${Characters.escape(preset.name)}</h4>
        <p class="card-meta">${Characters.escape(preset.race)} · ${Characters.escape(preset.class)}</p>
        <p class="inv-preset-specialty">🔍 ${Characters.escape(preset.specialty)}</p>
        <p class="inv-preset-desc">${Characters.escape(preset.backstory.slice(0, 90))}…</p>
        <button type="button" class="btn btn-secondary btn-small inv-preset-btn" data-preset="${index}">Ajouter à l'équipe</button>
      </article>
    `).join('');

    container.querySelectorAll('.inv-preset-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.addPresetCharacter(parseInt(btn.dataset.preset, 10));
      });
    });
  },

  addPresetCharacter(index) {
    const preset = this.INVESTIGATOR_PRESETS[index];
    if (!preset) return;

    const exists = Characters.list.some(
      (c) => c.roster === 'investigation' && c.name.toLowerCase() === preset.name.toLowerCase(),
    );
    if (exists) {
      alert(`« ${preset.name} » est déjà dans ton équipe d'enquête.`);
      return;
    }

    Characters.list.push({
      id: Characters.generateId(),
      ...preset,
      roster: 'investigation',
    });
    Characters.save();
    this.renderCharacters();
  },

  renderCharacters() {
    const container = document.getElementById('inv-character-list');
    if (!container) return;

    const chars = this.getInvestigationCharacters();
    if (chars.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Aucun enquêteur pour l'instant.</p>
          <p>Ajoute un modèle ci-dessous ou crée ton propre personnage.</p>
        </div>`;
      return;
    }

    container.innerHTML = chars.map((c) => `
      <div class="card card-investigation" data-id="${c.id}">
        <span class="bot-badge inv-badge">🔍 Enquêteur</span>
        <h3>${Characters.escape(c.name)}</h3>
        <p class="card-meta">${Characters.escape(c.race || '?')} · ${Characters.escape(c.class || '?')}</p>
        ${c.specialty ? `<p class="inv-preset-specialty">${Characters.escape(c.specialty)}</p>` : ''}
        <div class="card-stats">
          <span class="stat-badge">PV ${c.hp}</span>
          <span class="stat-badge">CA ${c.ac}</span>
          <span class="stat-badge">INT ${c.stats.int}</span>
          <span class="stat-badge">SAG ${c.stats.wis}</span>
        </div>
        <div class="card-actions">
          <button type="button" class="btn btn-secondary btn-inv-edit-char" data-id="${c.id}">Modifier</button>
          <button type="button" class="btn btn-danger btn-inv-delete-char" data-id="${c.id}">Supprimer</button>
        </div>
      </div>
    `).join('');

    container.querySelectorAll('.btn-inv-edit-char').forEach((btn) => {
      btn.addEventListener('click', () => this.showCharacterForm(btn.dataset.id));
    });
    container.querySelectorAll('.btn-inv-delete-char').forEach((btn) => {
      btn.addEventListener('click', () => this.deleteCharacter(btn.dataset.id));
    });
  },

  renderBots() {
    const container = document.getElementById('inv-bot-list');
    if (!container) return;

    const bots = Bots.getInvestigationArchetypes();
    if (bots.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Aucun compagnon d'enquête disponible.</p>
          <p>Crée un bot spécialisé pour t'aider en solo.</p>
        </div>`;
      return;
    }

    container.innerHTML = bots.map((b) => {
      const isCustom = Bots.isInvestigationCustomBot(b.id);
      const customizedDefault = !isCustom && Bots.isInvestigationCustomized(b.id);
      return `
      <div class="card card-bot card-investigation ${Bots.isInvestigationCustomized(b.id) ? 'is-customized' : ''} ${isCustom ? 'is-user-bot' : ''}" data-id="${b.id}">
        <span class="bot-badge inv-badge">${isCustom ? '✨ Bot enquête perso' : '🔍 Compagnon enquête'}</span>
        <h3>${Bots.escape(b.name)}</h3>
        <p class="card-meta">${Bots.escape(b.race)} · ${Bots.escape(b.class)}</p>
        <p class="card-personality">${Bots.escape(Bots.personalityLabel(b.personality))}</p>
        ${b.role ? `<p class="inv-bot-role">${Bots.escape(b.role)}</p>` : ''}
        <div class="card-stats">
          <span class="stat-badge">PV ${b.hp}</span>
          <span class="stat-badge">CA ${b.ac}</span>
          <span class="stat-badge">INT ${b.stats.int}</span>
          <span class="stat-badge">CHA ${b.stats.cha}</span>
        </div>
        <p class="card-traits">${b.traits.map((t) => Bots.escape(t)).join(' · ') || '—'}</p>
        <div class="card-actions">
          <button type="button" class="btn btn-secondary btn-inv-edit-bot" data-id="${b.id}">Modifier</button>
          ${customizedDefault ? `<button type="button" class="btn btn-secondary btn-inv-reset-bot" data-id="${b.id}">Réinitialiser</button>` : ''}
          <button type="button" class="btn btn-danger btn-inv-delete-bot" data-id="${b.id}">Supprimer</button>
        </div>
      </div>`;
    }).join('');

    container.querySelectorAll('.btn-inv-edit-bot').forEach((btn) => {
      btn.addEventListener('click', () => this.showBotForm(btn.dataset.id));
    });
    container.querySelectorAll('.btn-inv-reset-bot').forEach((btn) => {
      btn.addEventListener('click', () => this.resetBot(btn.dataset.id));
    });
    container.querySelectorAll('.btn-inv-delete-bot').forEach((btn) => {
      btn.addEventListener('click', () => this.deleteBot(btn.dataset.id));
    });
  },

  showCharacterForm(id = null) {
    document.getElementById('inv-bot-form')?.classList.add('hidden');
    const form = document.getElementById('inv-character-form');
    const title = document.getElementById('inv-character-form-title');
    form.classList.remove('hidden');

    if (id) {
      const char = Characters.list.find((c) => c.id === id);
      if (!char) return;
      title.textContent = 'Modifier l\'enquêteur';
      document.getElementById('inv-char-id').value = char.id;
      document.getElementById('inv-char-name').value = char.name;
      document.getElementById('inv-char-race').value = char.race || '';
      document.getElementById('inv-char-class').value = char.class || '';
      document.getElementById('inv-char-specialty').value = char.specialty || '';
      document.getElementById('inv-char-str').value = char.stats.str;
      document.getElementById('inv-char-dex').value = char.stats.dex;
      document.getElementById('inv-char-con').value = char.stats.con;
      document.getElementById('inv-char-int').value = char.stats.int;
      document.getElementById('inv-char-wis').value = char.stats.wis;
      document.getElementById('inv-char-cha').value = char.stats.cha;
      document.getElementById('inv-char-hp').value = char.hp;
      document.getElementById('inv-char-ac').value = char.ac;
      document.getElementById('inv-char-backstory').value = char.backstory || '';
    } else {
      title.textContent = 'Nouvel enquêteur';
      document.getElementById('inv-character-form-el').reset();
      document.getElementById('inv-char-id').value = '';
      document.getElementById('inv-char-str').value = 10;
      document.getElementById('inv-char-dex').value = 12;
      document.getElementById('inv-char-con').value = 10;
      document.getElementById('inv-char-int').value = 14;
      document.getElementById('inv-char-wis').value = 13;
      document.getElementById('inv-char-cha').value = 12;
      document.getElementById('inv-char-hp').value = 10;
      document.getElementById('inv-char-ac').value = 12;
      document.getElementById('inv-char-class').value = 'Enquêteur';
    }

    form.scrollIntoView({ behavior: 'smooth' });
  },

  hideCharacterForm() {
    document.getElementById('inv-character-form')?.classList.add('hidden');
  },

  handleCharacterSubmit(e) {
    e.preventDefault();

    const id = document.getElementById('inv-char-id').value;
    const character = {
      id: id || Characters.generateId(),
      name: document.getElementById('inv-char-name').value.trim(),
      race: document.getElementById('inv-char-race').value.trim(),
      class: document.getElementById('inv-char-class').value.trim(),
      specialty: document.getElementById('inv-char-specialty').value.trim(),
      stats: {
        str: parseInt(document.getElementById('inv-char-str').value, 10),
        dex: parseInt(document.getElementById('inv-char-dex').value, 10),
        con: parseInt(document.getElementById('inv-char-con').value, 10),
        int: parseInt(document.getElementById('inv-char-int').value, 10),
        wis: parseInt(document.getElementById('inv-char-wis').value, 10),
        cha: parseInt(document.getElementById('inv-char-cha').value, 10),
      },
      hp: parseInt(document.getElementById('inv-char-hp').value, 10),
      ac: parseInt(document.getElementById('inv-char-ac').value, 10),
      backstory: document.getElementById('inv-char-backstory').value.trim(),
      roster: 'investigation',
    };

    if (!character.name) {
      alert('Donne un nom à ton enquêteur.');
      return;
    }

    if (id) {
      const index = Characters.list.findIndex((c) => c.id === id);
      if (index !== -1) Characters.list[index] = character;
    } else {
      Characters.list.push(character);
    }

    Characters.save();
    this.renderCharacters();
    this.hideCharacterForm();
  },

  deleteCharacter(id) {
    const char = Characters.list.find((c) => c.id === id);
    if (!char) return;
    if (!confirm(`Supprimer l'enquêteur « ${char.name} » ?`)) return;
    Characters.list = Characters.list.filter((c) => c.id !== id);
    Characters.save();
    this.renderCharacters();
  },

  showBotForm(id = null) {
    document.getElementById('inv-character-form')?.classList.add('hidden');
    const form = document.getElementById('inv-bot-form');
    const title = document.getElementById('inv-bot-form-title');
    form.classList.remove('hidden');

    if (id) {
      const bot = Bots.getInvestigationArchetype(id);
      if (!bot) return;
      title.textContent = Bots.isInvestigationCustomBot(id)
        ? 'Modifier le bot enquête perso'
        : 'Modifier le compagnon d\'enquête';
      document.getElementById('inv-bot-id').value = bot.id;
      document.getElementById('inv-bot-name').value = bot.name;
      document.getElementById('inv-bot-race').value = bot.race;
      document.getElementById('inv-bot-class').value = bot.class;
      document.getElementById('inv-bot-role').value = bot.role || '';
      document.getElementById('inv-bot-personality').value = bot.personality;
      document.getElementById('inv-bot-str').value = bot.stats.str;
      document.getElementById('inv-bot-dex').value = bot.stats.dex;
      document.getElementById('inv-bot-con').value = bot.stats.con;
      document.getElementById('inv-bot-int').value = bot.stats.int;
      document.getElementById('inv-bot-wis').value = bot.stats.wis;
      document.getElementById('inv-bot-cha').value = bot.stats.cha;
      document.getElementById('inv-bot-hp').value = bot.hp;
      document.getElementById('inv-bot-ac').value = bot.ac;
      document.getElementById('inv-bot-traits').value = (bot.traits || []).join(', ');

      const selected = new Set(bot.preferredActions || []);
      form.querySelectorAll('input[name="inv-bot-action"]').forEach((input) => {
        input.checked = selected.has(input.value);
      });
    } else {
      title.textContent = 'Nouveau compagnon d\'enquête';
      document.getElementById('inv-bot-form-el').reset();
      document.getElementById('inv-bot-id').value = '';
      document.getElementById('inv-bot-str').value = 10;
      document.getElementById('inv-bot-dex').value = 12;
      document.getElementById('inv-bot-con').value = 10;
      document.getElementById('inv-bot-int').value = 14;
      document.getElementById('inv-bot-wis').value = 13;
      document.getElementById('inv-bot-cha').value = 12;
      document.getElementById('inv-bot-hp').value = 10;
      document.getElementById('inv-bot-ac').value = 12;
      document.getElementById('inv-bot-personality').value = 'diplomatic';
      document.getElementById('inv-bot-class').value = 'Enquêteur';
      form.querySelectorAll('input[name="inv-bot-action"]').forEach((input) => {
        input.checked = input.value === 'talk' || input.value === 'explore';
      });
    }

    form.scrollIntoView({ behavior: 'smooth' });
  },

  hideBotForm() {
    document.getElementById('inv-bot-form')?.classList.add('hidden');
  },

  botPayloadFromForm() {
    const preferredActions = [...document.querySelectorAll('input[name="inv-bot-action"]:checked')]
      .map((el) => el.value);
    if (preferredActions.length === 0) return null;

    const traitsRaw = document.getElementById('inv-bot-traits').value.trim();
    const traits = traitsRaw
      ? traitsRaw.split(/[,;]+/).map((t) => t.trim()).filter(Boolean)
      : [];

    const name = document.getElementById('inv-bot-name').value.trim();
    if (!name) return null;

    return {
      name,
      race: document.getElementById('inv-bot-race').value.trim() || 'Inconnu',
      class: document.getElementById('inv-bot-class').value.trim() || 'Enquêteur',
      role: document.getElementById('inv-bot-role').value.trim(),
      personality: document.getElementById('inv-bot-personality').value,
      preferredActions,
      stats: {
        str: parseInt(document.getElementById('inv-bot-str').value, 10),
        dex: parseInt(document.getElementById('inv-bot-dex').value, 10),
        con: parseInt(document.getElementById('inv-bot-con').value, 10),
        int: parseInt(document.getElementById('inv-bot-int').value, 10),
        wis: parseInt(document.getElementById('inv-bot-wis').value, 10),
        cha: parseInt(document.getElementById('inv-bot-cha').value, 10),
      },
      hp: parseInt(document.getElementById('inv-bot-hp').value, 10),
      ac: parseInt(document.getElementById('inv-bot-ac').value, 10),
      traits,
    };
  },

  handleBotSubmit(e) {
    e.preventDefault();
    const id = document.getElementById('inv-bot-id').value;
    const data = this.botPayloadFromForm();
    if (!data) {
      alert('Remplis au moins le nom et choisis une action préférée.');
      return;
    }
    Bots.saveInvestigationBot(id, data);
    this.renderBots();
    this.hideBotForm();
  },

  resetBot(id) {
    if (Bots.isInvestigationCustomBot(id)) return;
    const bot = Bots.getInvestigationArchetype(id);
    if (!bot) return;
    if (!confirm(`Réinitialiser « ${bot.name} » aux valeurs d'origine ?`)) return;
    Bots.resetInvestigationCustomization(id);
    this.renderBots();
    this.hideBotForm();
  },

  deleteBot(id) {
    const bot = Bots.getInvestigationArchetype(id);
    if (!bot) return;
    const label = Bots.isInvestigationCustomBot(id) ? 'bot enquête perso' : 'compagnon d\'enquête';
    if (!confirm(`Supprimer le ${label} « ${bot.name} » ?`)) return;
    Bots.deleteInvestigationBot(id);
    this.renderBots();
    this.hideBotForm();
    if (typeof Game !== 'undefined') {
      Game.refreshSetupCharacters();
    }
  },
};
