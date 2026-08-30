/**
 * dice.js — Lanceur de dés.
 * Comprend les formules comme "2d6+3" ou "1d20".
 */

const Dice = {
  history: [],

  /**
   * Parse une formule de dés (ex: "2d6+3") et retourne le résultat.
   */
  roll(formula) {
    const cleaned = formula.trim().toLowerCase().replace(/\s/g, '');

    // Format: XdY+Z ou XdY-Z ou XdY
    const match = cleaned.match(/^(\d+)d(\d+)([+-]\d+)?$/);
    if (!match) {
      return { error: 'Formule invalide. Exemples : 1d20, 2d6+3, 1d8-1' };
    }

    const count = parseInt(match[1], 10);
    const sides = parseInt(match[2], 10);
    const modifier = match[3] ? parseInt(match[3], 10) : 0;

    if (count < 1 || count > 100 || sides < 2 || sides > 1000) {
      return { error: 'Valeurs hors limites (max 100d1000).' };
    }

    const rolls = [];
    for (let i = 0; i < count; i++) {
      rolls.push(Math.floor(Math.random() * sides) + 1);
    }

    const sum = rolls.reduce((a, b) => a + b, 0);
    const total = sum + modifier;

    return {
      formula: `${count}d${sides}${modifier >= 0 ? (modifier ? '+' + modifier : '') : modifier}`,
      rolls,
      modifier,
      total,
    };
  },

  addToHistory(result) {
    if (result.error) return;

    this.history.unshift({
      ...result,
      time: new Date().toLocaleTimeString('fr-FR'),
    });

    if (this.history.length > 20) {
      this.history = this.history.slice(0, 20);
    }

    Storage.save(Storage.KEYS.rollHistory, this.history);
  },

  loadHistory() {
    this.history = Storage.load(Storage.KEYS.rollHistory) || [];
  },

  renderHistory() {
    const list = document.getElementById('roll-history-list');
    if (!list) return;

    if (this.history.length === 0) {
      list.innerHTML = '<li>Aucun lancer pour l\'instant.</li>';
      return;
    }

    list.innerHTML = this.history.map((r) => {
      const detail = r.rolls.length > 1
        ? `[${r.rolls.join(', ')}]${r.modifier ? (r.modifier > 0 ? '+' + r.modifier : r.modifier) : ''}`
        : '';
      return `<li><strong>${r.total}</strong> — ${r.formula} ${detail} <span style="float:right">${r.time}</span></li>`;
    }).join('');
  },

  showResult(result) {
    const panel = document.getElementById('dice-result');
    if (!panel) return;

    if (result.error) {
      panel.classList.remove('hidden');
      panel.querySelector('.result-label').textContent = 'Erreur';
      panel.querySelector('.result-value').textContent = '!';
      panel.querySelector('.result-detail').textContent = result.error;
      return;
    }

    panel.classList.remove('hidden');
    panel.querySelector('.result-label').textContent = result.formula;
    panel.querySelector('.result-value').textContent = result.total;

    let detail = '';
    if (result.rolls.length > 1) {
      detail = `Dés : ${result.rolls.join(', ')}`;
      if (result.modifier) detail += ` ${result.modifier > 0 ? '+' : ''}${result.modifier}`;
    } else if (result.modifier) {
      detail = `${result.rolls[0]} ${result.modifier > 0 ? '+' : ''}${result.modifier}`;
    }

    panel.querySelector('.result-detail').textContent = detail;

    this.addToHistory(result);
    this.renderHistory();
  },

  init() {
    this.loadHistory();
    this.renderHistory();

    // Boutons rapides
    document.querySelectorAll('.dice-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        const formula = btn.dataset.roll;
        this.showResult(this.roll(formula));
      });
    });

    // Formule personnalisée
    const input = document.getElementById('custom-roll-input');
    const btnRoll = document.getElementById('btn-custom-roll');

    const doCustomRoll = () => {
      const formula = input.value.trim() || '1d20';
      this.showResult(this.roll(formula));
    };

    btnRoll.addEventListener('click', doCustomRoll);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') doCustomRoll();
    });
  },
};
