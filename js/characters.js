/**
 * characters.js — Gestion des fiches de personnages.
 */

const Characters = {
  list: [],

  load() {
    this.list = Storage.loadArray(Storage.KEYS.characters);
    this.list.forEach((c) => {
      if (c.roster === 'investigation') return;
      if (!c.roster) c.roster = 'general';
    });
  },

  isInvestigation(c) {
    return c?.roster === 'investigation';
  },

  getForQuestFormat(questFormat) {
    const isInvestigation = questFormat === 'investigation';
    return this.list.filter((c) => (
      isInvestigation ? this.isInvestigation(c) : !this.isInvestigation(c)
    ));
  },

  save() {
    Storage.save(Storage.KEYS.characters, this.list);
  },

  generateId() {
    return 'char-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7);
  },

  renderList() {
    const container = document.getElementById('character-list');
    if (!container) return;

    if (this.list.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Aucun personnage pour l'instant.</p>
          <p>Clique sur « + Nouveau personnage » pour commencer !</p>
        </div>`;
      return;
    }

    const generalChars = this.list.filter((c) => !this.isInvestigation(c));
    if (generalChars.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Aucun héros d'aventure pour l'instant.</p>
          <p>Les enquêteurs se gèrent dans l'onglet <strong>🔍 Enquête</strong>.</p>
        </div>`;
      return;
    }

    container.innerHTML = generalChars.map((c) => `
      <div class="card" data-id="${c.id}">
        <h3>${this.escape(c.name)}</h3>
        <p class="card-meta">${this.escape(c.race || '?')} · ${this.escape(c.class || '?')}</p>
        <div class="card-stats">
          <span class="stat-badge">PV ${c.hp}</span>
          <span class="stat-badge">CA ${c.ac}</span>
          <span class="stat-badge">FOR ${c.stats.str}</span>
          <span class="stat-badge">DEX ${c.stats.dex}</span>
        </div>
        <div class="card-actions">
          <button class="btn btn-secondary btn-edit" data-id="${c.id}">Modifier</button>
          <button class="btn btn-danger btn-delete" data-id="${c.id}">Supprimer</button>
        </div>
      </div>
    `).join('');

    container.querySelectorAll('.btn-edit').forEach((btn) => {
      btn.addEventListener('click', () => this.showForm(btn.dataset.id));
    });

    container.querySelectorAll('.btn-delete').forEach((btn) => {
      btn.addEventListener('click', () => this.delete(btn.dataset.id));
    });
  },

  escape(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },

  showForm(id = null) {
    const form = document.getElementById('character-form');
    const title = document.getElementById('character-form-title');
    document.getElementById('bot-form')?.classList.add('hidden');
    form.classList.remove('hidden');

    if (id) {
      const char = this.list.find((c) => c.id === id);
      if (!char) return;

      title.textContent = 'Modifier le personnage';
      document.getElementById('char-id').value = char.id;
      document.getElementById('char-name').value = char.name;
      document.getElementById('char-race').value = char.race || '';
      document.getElementById('char-class').value = char.class || '';
      document.getElementById('char-str').value = char.stats.str;
      document.getElementById('char-dex').value = char.stats.dex;
      document.getElementById('char-con').value = char.stats.con;
      document.getElementById('char-int').value = char.stats.int;
      document.getElementById('char-wis').value = char.stats.wis;
      document.getElementById('char-cha').value = char.stats.cha;
      document.getElementById('char-hp').value = char.hp;
      document.getElementById('char-ac').value = char.ac;
      document.getElementById('char-backstory').value = char.backstory || '';
    } else {
      title.textContent = 'Nouveau personnage';
      document.getElementById('character-form-el').reset();
      document.getElementById('char-id').value = '';
      document.getElementById('char-str').value = 10;
      document.getElementById('char-dex').value = 10;
      document.getElementById('char-con').value = 10;
      document.getElementById('char-int').value = 10;
      document.getElementById('char-wis').value = 10;
      document.getElementById('char-cha').value = 10;
      document.getElementById('char-hp').value = 10;
      document.getElementById('char-ac').value = 10;
    }

    form.scrollIntoView({ behavior: 'smooth' });
  },

  hideForm() {
    document.getElementById('character-form').classList.add('hidden');
  },

  handleSubmit(e) {
    e.preventDefault();

    const id = document.getElementById('char-id').value;
    const existing = id ? this.list.find((c) => c.id === id) : null;
    const character = {
      id: id || this.generateId(),
      name: document.getElementById('char-name').value.trim(),
      race: document.getElementById('char-race').value.trim(),
      class: document.getElementById('char-class').value.trim(),
      roster: existing?.roster === 'investigation' ? 'investigation' : 'general',
      stats: {
        str: parseInt(document.getElementById('char-str').value, 10),
        dex: parseInt(document.getElementById('char-dex').value, 10),
        con: parseInt(document.getElementById('char-con').value, 10),
        int: parseInt(document.getElementById('char-int').value, 10),
        wis: parseInt(document.getElementById('char-wis').value, 10),
        cha: parseInt(document.getElementById('char-cha').value, 10),
      },
      hp: parseInt(document.getElementById('char-hp').value, 10),
      ac: parseInt(document.getElementById('char-ac').value, 10),
      backstory: document.getElementById('char-backstory').value.trim(),
    };

    if (id) {
      const index = this.list.findIndex((c) => c.id === id);
      if (index !== -1) this.list[index] = character;
    } else {
      this.list.push(character);
    }

    this.save();
    this.renderList();
    this.hideForm();
  },

  delete(id) {
    const char = this.list.find((c) => c.id === id);
    if (!char) return;

    if (confirm(`Supprimer le personnage « ${char.name} » ?`)) {
      this.list = this.list.filter((c) => c.id !== id);
      this.save();
      this.renderList();
    }
  },

  init() {
    this.load();
    this.renderList();

    document.getElementById('btn-new-character').addEventListener('click', () => this.showForm());
    document.getElementById('btn-cancel-character').addEventListener('click', () => this.hideForm());
    document.getElementById('character-form-el').addEventListener('submit', (e) => this.handleSubmit(e));
  },
};
