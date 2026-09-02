/**
 * app.js — Point d'entrée : accueil, modes de jeu, navigation entre les onglets.
 */

const App = {
  homeView: null,
  modesView: null,
  appView: null,
  tabs: null,
  panels: null,

  init() {
    this.homeView = document.getElementById('home-view');
    this.modesView = document.getElementById('modes-view');
    this.appView = document.getElementById('app-view');
    this.tabs = document.querySelectorAll('.tab');
    this.panels = document.querySelectorAll('.panel');

    this.bindHomeEvents();
    this.bindModesEvents();
    this.bindTabEvents();
    this.bindBackHome();

    Bots.load();
    Bots.initEditor();
    Characters.init();
    InvestigationRoster.init();
    Scenarios.init();
    AdventureRoster.init();
    Maps.init();
    Game.init();

    this.renderSavedGamesList();
    this.routeInitialView();
  },

  bindHomeEvents() {
    document.getElementById('btn-home-play')?.addEventListener('click', () => {
      this.showApp('play');
    });

    document.getElementById('btn-home-modes')?.addEventListener('click', () => {
      this.showModes();
    });

    document.getElementById('btn-home-enter')?.addEventListener('click', () => {
      this.showApp('adventures');
    });

    document.querySelectorAll('.home-card-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.showApp(btn.dataset.go || 'play');
      });
    });

    document.querySelectorAll('[data-go-investigation]').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.showApp('investigation');
      });
    });
  },

  bindModesEvents() {
    document.getElementById('btn-modes-back')?.addEventListener('click', () => {
      this.showHome();
    });

    document.querySelectorAll('.mode-play-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.showApp('play', {
          quest: btn.dataset.quest,
        });
      });
    });

    document.querySelectorAll('.mode-roster-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.showApp(btn.dataset.go || 'investigation');
      });
    });
  },

  bindBackHome() {
    document.getElementById('btn-back-home')?.addEventListener('click', () => {
      this.showHome();
    });
  },

  bindTabEvents() {
    this.tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        this.activateTab(tab.dataset.tab);
      });
    });
  },

  renderSavedGamesList() {
    const section = document.getElementById('home-saved-games');
    const list = document.getElementById('home-saved-games-list');
    if (!section || !list || typeof Game === 'undefined') return;

    const games = Game.getPlayingGames();
    section.classList.toggle('hidden', games.length === 0);
    list.innerHTML = '';

    games.forEach((game) => {
      list.appendChild(Game.buildSavedGameCard(game, {
        onResume: (id) => {
          Game.resumeGame(id);
          this.showApp('play');
        },
        onDelete: (id) => {
          if (!confirm('Effacer cette partie ? Toute la progression sera perdue.')) return;
          Game.deleteGame(id);
          this.renderSavedGamesList();
          Game.renderSavedGamesInSetup();
        },
      }));
    });
  },

  routeInitialView() {
    const playing = Game.getPlayingGames();
    const canAutoResume = Game.state?.status === 'playing'
      && Array.isArray(Game.state.party)
      && Game.state.party.length > 0
      && playing.length <= 1;

    if (canAutoResume) {
      this.showApp('play');
      Game.showSession();
      return;
    }

    this.showHome();
  },

  hideAllViews() {
    this.homeView?.classList.add('hidden');
    this.modesView?.classList.add('hidden');
    this.appView?.classList.add('hidden');
  },

  showHome() {
    this.hideAllViews();
    this.homeView?.classList.remove('hidden');
    this.renderSavedGamesList();
    document.title = 'OpenQuest JDR — Accueil';
  },

  showModes() {
    this.hideAllViews();
    this.modesView?.classList.remove('hidden');
    document.title = 'OpenQuest JDR — Modes de jeu';
    window.scrollTo(0, 0);
  },

  showApp(tabId = 'adventures', preset = null) {
    this.hideAllViews();
    this.appView?.classList.remove('hidden');
    this.activateTab(tabId, preset);
    document.title = 'OpenQuest JDR — Créateur de jeux de rôle';
  },

  activateTab(target, preset = null) {
    this.tabs.forEach((t) => t.classList.toggle('active', t.dataset.tab === target));
    this.panels.forEach((p) => p.classList.toggle('active', p.id === target));

    if (target === 'adventures' && typeof AdventureRoster !== 'undefined') {
      AdventureRoster.render();
    }

    if (target === 'investigation' && typeof InvestigationRoster !== 'undefined') {
      InvestigationRoster.render();
    }

    if (target === 'maps' && typeof Maps !== 'undefined') {
      Maps.renderList();
    }

    if (target === 'play' && typeof Game !== 'undefined') {
      Game.renderSetup();
      Game.renderSavedGamesInSetup();
      if (preset?.mode || preset?.gm || preset?.quest || preset?.scenario) {
        Game.applySetupPreset(preset.mode, preset.gm, preset.quest, preset.scenario);
      }
      if (Game.state?.status === 'playing' || Game.state?.status === 'completed') {
        Game.showSession();
      } else {
        Game.hideSession();
      }
      Game.renderSession();
    }
  },
};

document.addEventListener('DOMContentLoaded', () => {
  try {
    App.init();
  } catch (err) {
    console.error('OpenQuest — erreur au démarrage :', err);
    const home = document.getElementById('home-view');
    if (home) {
      home.classList.remove('hidden');
      const msg = document.createElement('p');
      msg.className = 'home-resume-detail';
      msg.textContent = 'Erreur au chargement — recharge la page (Ctrl+F5). Si le problème continue, vide le cache du navigateur.';
      home.querySelector('.home-main')?.prepend(msg);
    }
  }
});
