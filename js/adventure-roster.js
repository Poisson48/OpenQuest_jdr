/**
 * adventure-roster.js — Espace unifié personnages, bots & scénarios (one-shot / longue durée).
 */

const AdventureRoster = {
  init() {
    this.bindEvents();
    this.render();
  },

  bindEvents() {
    document.getElementById('btn-adv-launch-oneshot')?.addEventListener('click', () => {
      App.showApp('play', { quest: 'oneshot', gm: 'ai' });
    });
    document.getElementById('btn-adv-launch-long')?.addEventListener('click', () => {
      App.showApp('play', { quest: 'long', gm: 'ai' });
    });
    document.getElementById('btn-adv-new-scenario-oneshot')?.addEventListener('click', () => {
      Scenarios.showForm(null, { questFormat: 'oneshot' });
    });
    document.getElementById('btn-adv-new-scenario-long')?.addEventListener('click', () => {
      Scenarios.showForm(null, { questFormat: 'long' });
    });
  },

  render() {
    Characters.load();
    Bots.load();
    Scenarios.load();
    Scenarios.ensureDemoScenario();
    Characters.renderList();
    Bots.renderList();
    this.renderScenarios();
  },

  renderScenarioCards(scenarios, emptyMessage) {
    if (scenarios.length === 0) {
      return `
        <div class="empty-state">
          <p>${emptyMessage}</p>
        </div>`;
    }

    return scenarios.map((s) => {
      const format = s.questFormat === 'long' ? 'long' : 'oneshot';
      const formatLabel = format === 'long' ? 'Campagne longue' : 'One-shot';
      const badgeClass = format === 'long' ? 'adv-badge-long' : 'adv-badge-oneshot';
      return `
      <div class="card card-adventure" data-id="${s.id}">
        <span class="bot-badge ${badgeClass}">⚔️ ${formatLabel}</span>
        <h3>${Scenarios.escape(s.title)}</h3>
        <p class="card-meta">${s.scenes.length} scène(s) · ${s.npcs.length} PNJ</p>
        <p class="adv-scenario-desc">${Scenarios.escape((s.synopsis || '').slice(0, 120))}${(s.synopsis || '').length > 120 ? '…' : ''}</p>
        <div class="card-actions">
          <button type="button" class="btn btn-primary btn-small btn-adv-play-scenario" data-id="${s.id}" data-format="${format}">Jouer</button>
          <button type="button" class="btn btn-secondary btn-small btn-adv-edit-scenario" data-id="${s.id}">Modifier</button>
          <button type="button" class="btn btn-danger btn-small btn-adv-delete-scenario" data-id="${s.id}">Supprimer</button>
        </div>
      </div>`;
    }).join('');
  },

  bindScenarioCardEvents(container) {
    if (!container) return;

    container.querySelectorAll('.btn-adv-play-scenario').forEach((btn) => {
      btn.addEventListener('click', () => {
        App.showApp('play', {
          quest: btn.dataset.format || 'oneshot',
          gm: 'ai',
          scenario: btn.dataset.id,
        });
      });
    });
    container.querySelectorAll('.btn-adv-edit-scenario').forEach((btn) => {
      btn.addEventListener('click', () => {
        Scenarios.showForm(btn.dataset.id);
      });
    });
    container.querySelectorAll('.btn-adv-delete-scenario').forEach((btn) => {
      btn.addEventListener('click', () => {
        Scenarios.delete(btn.dataset.id);
      });
    });
  },

  renderScenarios() {
    const oneshotContainer = document.getElementById('adv-scenario-list-oneshot');
    const longContainer = document.getElementById('adv-scenario-list-long');
    if (!oneshotContainer || !longContainer) return;

    const oneshot = Scenarios.getOneshotScenarios();
    const long = Scenarios.getLongScenarios();

    oneshotContainer.innerHTML = this.renderScenarioCards(
      oneshot,
      'Aucun scénario one-shot. Les aventures courtes (3–4 h) apparaîtront ici.',
    );
    longContainer.innerHTML = this.renderScenarioCards(
      long,
      'Aucune campagne longue. Crée une aventure multi-sessions pour ce format.',
    );

    this.bindScenarioCardEvents(oneshotContainer);
    this.bindScenarioCardEvents(longContainer);
  },
};
