/**
 * dice.js — Moteur de lancer de dés (formules type 2d6+3, 1d20).
 */

const Dice = {
  /**
   * Parse une formule de dés (ex: "2d6+3") et retourne le résultat.
   */
  roll(formula) {
    const cleaned = formula.trim().toLowerCase().replace(/\s/g, '');

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
    for (let i = 0; i < count; i += 1) {
      rolls.push(Math.floor(Math.random() * sides) + 1);
    }

    const sum = rolls.reduce((a, b) => a + b, 0);
    const total = sum + modifier;

    return {
      formula: `${count}d${sides}${modifier >= 0 ? (modifier ? `+${modifier}` : '') : modifier}`,
      rolls,
      modifier,
      total,
    };
  },

  formatResult(result) {
    if (result.error) return result.error;

    let text = `🎲 **${result.total}** (${result.formula})`;
    if (result.rolls.length > 1) {
      text += ` — dés : ${result.rolls.join(', ')}`;
      if (result.modifier) {
        text += ` ${result.modifier > 0 ? '+' : ''}${result.modifier}`;
      }
    } else if (result.modifier) {
      text += ` — ${result.rolls[0]} ${result.modifier > 0 ? '+' : ''}${result.modifier}`;
    } else if (result.rolls.length === 1) {
      text += ` — dé : ${result.rolls[0]}`;
    }
    return text;
  },
};
