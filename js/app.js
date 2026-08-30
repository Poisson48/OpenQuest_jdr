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
    Dice.init();
    Scenarios.init();
    Game.init();

    this.updateHomeResume();
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
      this.showApp('characters');
    });

    document.getElementById('btn-home-resume')?.addEventListener('click', () => {
      this.showApp('play');
      if (Game.state?.status === 'playing' || Game.state?.status === 'completed') {
        Game.showSession();
        Game.renderSession();
      }
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

  updateHomeResume() {
    const banner = document.getElementById('home-resume');
    const label = document.getElementById('home-resume-label');
    const detail = document.getElementById('home-resume-detail');
    if (!banner || !Game.state) return;

    const active = Game.state.status === 'playing' || Game.state.status === 'completed';
    banner.classList.toggle('hidden', !active);

    if (!active) return;

    const scenario = Scenarios.list.find((s) => s.id === Game.state.scenarioId);
    if (Game.state.status === 'completed') {
      label.textContent = 'Aventure terminée';
      detail.textContent = scenario?.title
        ? `« ${scenario.title} » — consulte ou télécharge ton résumé.`
        : 'Consulte ou télécharge ton résumé.';
    } else {
      label.textContent = 'Partie en cours';
      detail.textContent = scenario?.title
        ? `« ${scenario.title} » — reprends là où tu t'étais arrêté.`
        : 'Reprends là où tu t\'étais arrêté.';
    }
  },

  routeInitialView() {
    if (Game.state?.status === 'playing') {
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
    this.updateHomeResume();
    document.title = 'OpenQuest JDR — Accueil';
  },

  showModes() {
    this.hideAllViews();
    this.modesView?.classList.remove('hidden');
    document.title = 'OpenQuest JDR — Modes de jeu';
    window.scrollTo(0, 0);
  },

  showApp(tabId = 'characters', preset = null) {
    this.hideAllViews();
    this.appView?.classList.remove('hidden');
    this.activateTab(tabId, preset);
    document.title = 'OpenQuest JDR — Créateur de jeux de rôle';
  },

  activateTab(target, preset = null) {
    this.tabs.forEach((t) => t.classList.toggle('active', t.dataset.tab === target));
    this.panels.forEach((p) => p.classList.toggle('active', p.id === target));

    if (target === 'characters' && typeof Bots !== 'undefined') {
      Bots.load();
      Bots.renderList();
    }

    if (target === 'investigation' && typeof InvestigationRoster !== 'undefined') {
      InvestigationRoster.render();
    }

    if (target === 'play' && typeof Game !== 'undefined') {
      Game.renderSetup();
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
  App.init();
});
