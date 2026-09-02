/**
 * storage.js — Sauvegarde et chargement des données dans le navigateur.
 * Les données restent sur ton ordinateur (localStorage).
 */

const Storage = {
  KEYS: {
    characters: 'forge-rpg-characters',
    bots: 'forge-rpg-bots',
    scenarios: 'forge-rpg-scenarios',
    rollHistory: 'forge-rpg-roll-history',
    activeGame: 'forge-rpg-active-game',
    savedGames: 'forge-rpg-saved-games',
    lastActiveGameId: 'forge-rpg-last-active-game-id',
    maps: 'forge-rpg-maps',
    removedDemos: 'forge-rpg-removed-demos',
  },

  load(key) {
    try {
      const data = localStorage.getItem(key);
      return data ? JSON.parse(data) : null;
    } catch {
      return null;
    }
  },

  loadArray(key) {
    const data = this.load(key);
    return Array.isArray(data) ? data : [];
  },

  save(key, data) {
    localStorage.setItem(key, JSON.stringify(data));
  },
};
