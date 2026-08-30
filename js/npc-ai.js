/**
 * npc-ai.js — IA PNJ : génération improvisée et gestion pendant les parties.
 */

const NpcAI = {
  FIRST_NAMES: [
    'Gareth', 'Elira', 'Bram', 'Sylva', 'Orrin', 'Nessa', 'Corbin', 'Liora',
    'Dain', 'Maelis', 'Torven', 'Ysolde', 'Perrin', 'Kaela', 'Hugo', 'Isara',
    'Roland', 'Vera', 'Edwin', 'Fiora',
  ],

  SCENE_TYPES: {
    crypt: /crypte|tombe|sépul|catacombe|ossuaire/i,
    manor: /manoir|château|demeure|salon|bibliothèque/i,
    forest: /forêt|bois|clairière|sentier|arbre/i,
    ruins: /ruines|temple|ancien|effondr/i,
    tavern: /taverne|auberge|foyer|brass/i,
    dungeon: /donjon|cachot|prison|geôle/i,
    desert: /désert|dune|oasis|sable/i,
    mountain: /mont|caverne|mine|grotte/i,
  },

  TEMPLATES: {
    crypt: [
      { role: 'Fossoyeur', personality: 'wary', desc: 'Yeux cernés, pelle usée, connaît chaque pierre du lieu.' },
      { role: 'Ermitage des cryptes', personality: 'mystic', desc: 'Murmure des prières aux morts, sent la cendre et l\'encens.' },
      { role: 'Pilleur de tombes', personality: 'bold', desc: 'Regard fuyant, sac lourd — clairement ici pour voler, pas prier.' },
    ],
    manor: [
      { role: 'Servante', personality: 'cautious', desc: 'Uniforme froissé, parle bas, semble terrifiée par quelque chose à l\'étage.' },
      { role: 'Majordome', personality: 'diplomatic', desc: 'Maintien rigide, connaît les secrets de la maisonnée.' },
      { role: 'Invité surprise', personality: 'curious', desc: 'Arrivé sans invitation — affaire ou malédiction ?' },
    ],
    forest: [
      { role: 'Rôdeur', personality: 'cautious', desc: 'Capuche basse, connaît les traces et les pièges naturels.' },
      { role: 'Herboriste', personality: 'cheerful', desc: 'Panier de plantes, odeur de mousse et de thé.' },
      { role: 'Refugié', personality: 'fierce', desc: 'Blessé, méfiant, cache quelque chose dans son manteau.' },
    ],
    ruins: [
      { role: 'Archéologue', personality: 'curious', desc: 'Pinceau, carnet griffonné — obsédé par une inscription.' },
      { role: 'Cultiste errant', personality: 'mystic', desc: 'Chuchote des noms oubliés, fixe les symboles muraux.' },
      { role: 'Garde des ruines', personality: 'fierce', desc: 'Vétéran usé qui protège ce qu\'il ne comprend pas.' },
    ],
    tavern: [
      { role: 'Tavernier', personality: 'diplomatic', desc: 'Essuie un verre, entend tout ce qui se dit dans la salle.' },
      { role: 'Barde de passage', personality: 'cheerful', desc: 'Luth sous le bras, rumeurs et chansons en stock.' },
      { role: 'Mercenaire', personality: 'bold', desc: 'Armure voyante, cherche une paye ou une rixe.' },
    ],
    dungeon: [
      { role: 'Prisonnier', personality: 'fierce', desc: 'Chaînes récentes, supplie ou menace — connaît les couloirs.' },
      { role: 'Geôlier', personality: 'cautious', desc: 'Trousseau de clés, regard calculateur.' },
    ],
    desert: [
      { role: 'Caravanier', personality: 'cautious', desc: 'Voile poussiéreux, eau précieuse, cartes mentales du désert.' },
      { role: 'Nomade', personality: 'mystic', desc: 'Lit le vent et les étoiles, parle par énigmes.' },
    ],
    mountain: [
      { role: 'Guide de montagne', personality: 'bold', desc: 'Corde et pics, connaît chaque passage dangereux.' },
      { role: 'Prospecteur', personality: 'curious', desc: 'Cherche un filon ou une légende enterrée.' },
    ],
    generic: [
      { role: 'Voyageur', personality: 'curious', desc: 'Route longue, yeux fatigués, histoire à vendre ou à cacher.' },
      { role: 'Marchand', personality: 'diplomatic', desc: 'Sac à provisions, prix et rumeurs au même tarif.' },
      { role: 'Blessé', personality: 'cautious', desc: 'Demande de l\'aide — ou tend peut-être un piège.' },
      { role: 'Informateur', personality: 'mystic', desc: 'Sourit trop peu, sait quelque chose sur {title}.' },
      { role: 'Sentinelle', personality: 'fierce', desc: 'Surveille {title} — ami, ennemi ou simple obstacle ?' },
    ],
  },

  PERSONALITY_LABELS: {
    cautious: 'méfiant·e',
    curious: 'curieux·se',
    bold: 'audacieux·se',
    diplomatic: 'diplomate',
    fierce: 'féroce',
    cheerful: 'enjoué·e',
    mystic: 'mystérieux·se',
    wary: 'sur ses gardes',
  },

  detectSceneType(scene, scenario) {
    const text = `${scene?.content || ''} ${scene?.title || ''} ${scenario?.setting || ''}`;
    for (const [type, re] of Object.entries(this.SCENE_TYPES)) {
      if (re.test(text)) return type;
    }
    return 'generic';
  },

  ensureRegistry(world) {
    if (!world.dynamicNpcs) world.dynamicNpcs = [];
    return world.dynamicNpcs;
  },

  getUsedNames(game, scenario) {
    const names = new Set();
    (scenario?.npcs || []).forEach((n) => names.add(n.name.toLowerCase()));
    (game?.aiState?.world?.dynamicNpcs || []).forEach((n) => names.add(n.name.toLowerCase()));
    (game?.party || []).forEach((m) => names.add(m.name.toLowerCase()));
    return names;
  },

  pickName(usedNames) {
    const available = this.FIRST_NAMES.filter((n) => !usedNames.has(n.toLowerCase()));
    const pool = available.length ? available : this.FIRST_NAMES.map((n) => `${n} ${Math.floor(Math.random() * 90) + 10}`);
    return pool[Math.floor(Math.random() * pool.length)];
  },

  generateId() {
    return `npc-dyn-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
  },

  buildNpc(game, scenario, scene, hooks, trigger) {
    const world = game.aiState.world;
    const usedNames = this.getUsedNames(game, scenario);
    const sceneType = this.detectSceneType(scene, scenario);
    const templates = this.TEMPLATES[sceneType] || this.TEMPLATES.generic;
    const tpl = templates[Math.floor(Math.random() * templates.length)];
    const name = this.pickName(usedNames);
    const title = hooks?.title || scene?.title || 'les lieux';
    const obj = hooks?.objects?.[0] || title;

    let description = tpl.desc
      .replace(/\{title\}/g, title)
      .replace(/\{obj\}/g, obj);

    const motivePool = [
      `Cherche quelque chose près de ${obj}.`,
      `A une dette envers quelqu'un qui habite ${title}.`,
      `N'a pas l'intention de quitter ${title} de sitôt.`,
      `Observe le groupe avec intérêt — opportunité ou menace ?`,
    ];
    const motive = motivePool[Math.floor(Math.random() * motivePool.length)];

    const npc = {
      id: this.generateId(),
      name,
      role: tpl.role,
      description,
      personality: tpl.personality,
      motive,
      generated: true,
      sceneIndex: game.currentSceneIndex,
      status: 'present',
      introduced: false,
      spawnTrigger: trigger,
    };

    this.ensureRegistry(world).push(npc);

    if (!world.npcRelations[npc.name]) {
      world.npcRelations[npc.name] = {
        trust: 1,
        met: false,
        mood: 'neutral',
        history: [],
        label: 'inconnu',
        dynamic: true,
      };
    }

    world.plotThreads.push({
      id: npc.id,
      title: `PNJ : ${npc.name}`,
      status: 'pending',
      note: `${npc.role} — ${motive}`,
    });

    if (world.dynamicNpcs.length > 12) {
      world.dynamicNpcs = world.dynamicNpcs.slice(-12);
    }

    return npc;
  },

  getDynamicNpcs(game, sceneIndex = null) {
    const world = game?.aiState?.world;
    if (!world) return [];
    const idx = sceneIndex ?? game.currentSceneIndex;
    return (world.dynamicNpcs || []).filter(
      (n) => n.status === 'present' && (n.sceneIndex === idx || n.followsParty),
    );
  },

  getAllNpcs(game, scenario, scene) {
    const scenarioNpcs = (scenario?.npcs || []).map((n) => ({ ...n, generated: false }));
    const dynamic = game ? this.getDynamicNpcs(game) : [];
    return [...scenarioNpcs, ...dynamic];
  },

  getPrimaryNpc(game, scenario, scene) {
    const all = this.getAllNpcs(game, scenario, scene);
    return all[0] || null;
  },

  findNpcByName(game, scenario, name) {
    if (!name) return null;
    const lower = name.toLowerCase();
    const all = this.getAllNpcs(game, scenario);
    return all.find((n) => n.name.toLowerCase() === lower || lower.includes(n.name.toLowerCase())) || null;
  },

  findNpcInAction(game, scenario, actionText, hooks) {
    const all = this.getAllNpcs(game, scenario);
    const t = (actionText || '').toLowerCase();
    return all.find((n) => t.includes(n.name.toLowerCase()))
      || hooks?.allNpcs?.find((n) => t.includes(n.name.toLowerCase()))
      || null;
  },

  formatIntro(npc, sceneTitle) {
    const perso = this.PERSONALITY_LABELS[npc.personality] || npc.personality;
    return `👤 **${npc.name}** (${npc.role}) — ${npc.description} *Personnalité : ${perso}.*\n\n*${npc.motive}*`;
  },

  onSceneEnter(game, scenario, sceneIndex) {
    if (!game?.aiState || game.gmType !== 'ai') return '';

    const world = game.aiState.world;
    const scene = scenario?.scenes?.[sceneIndex];
    if (!scene) return '';

    if (sceneIndex === 0 && (scenario?.npcs?.length || 0) >= 2) return '';
    if (sceneIndex === 0 && (scenario?.npcs?.length || 0) >= 1 && Math.random() > 0.4) return '';

    this.departSceneNpcs(game, sceneIndex - 1);

    const hooks = AiGM.getSceneHooks(scenario, scene, game);
    const present = this.getDynamicNpcs(game, sceneIndex);

    if (present.length >= 2) return '';

    const spawnChance = present.length === 0 ? 0.55 : 0.25;
    if (Math.random() > spawnChance) return '';

    const npc = this.buildNpc(game, scenario, scene, hooks, 'scene-enter');
    npc.introduced = true;
    return `${this.formatIntro(npc, scene.title)}\n\n*Un nouveau visage rejoint la scène — le MJ PNJ l'a improvisé pour ${scene.title}.*`;
  },

  departSceneNpcs(game, oldSceneIndex) {
    if (oldSceneIndex == null || oldSceneIndex < 0) return;
    const world = game?.aiState?.world;
    if (!world?.dynamicNpcs) return;

    world.dynamicNpcs.forEach((npc) => {
      if (npc.sceneIndex !== oldSceneIndex || npc.status !== 'present') return;
      const rel = world.npcRelations[npc.name];
      if (rel?.trust >= 4) {
        npc.followsParty = true;
        return;
      }
      npc.status = 'departed';
    });
  },

  maybeSpawnOnAction(game, scenario, scene, hooks, actionType, success) {
    if (!success || !game?.aiState) return '';
    if (!['explore', 'talk'].includes(actionType)) return '';

    const present = this.getDynamicNpcs(game);
    if (present.length >= 3) return '';
    if (Math.random() > 0.18) return '';

    const npc = this.buildNpc(game, scenario, scene, hooks, `action-${actionType}`);
    npc.introduced = true;

    const lines = [
      `Alors que vous agissez, **${npc.name}** (${npc.role}) se révèle : ${npc.description}`,
      `Un mouvement dans ${hooks.title} — **${npc.name}**, ${npc.role}, vous observe : « ${npc.motive} »`,
    ];
    return `👤 **IA PNJ :** ${lines[Math.floor(Math.random() * lines.length)]}`;
  },

  updateNpcAfterInteraction(world, npc, success, actorName) {
    const rel = world.npcRelations[npc.name];
    if (!rel) return;
    rel.met = true;
    if (success && !npc.introduced) npc.introduced = true;
  },

  getNpcStatusLabel(npc, world) {
    const rel = world?.npcRelations?.[npc.name];
    if (!rel) return 'inconnu';
    return rel.label || AiGM.getNpcRelationLabel(rel.trust);
  },

  renderPanelList(game, scenario) {
    const world = game?.aiState?.world;
    const all = this.getAllNpcs(game, scenario);
    if (!all.length) {
      return '<p class="npc-empty">Aucun PNJ pour l\'instant — l\'IA en génère en jeu.</p>';
    }

    return all.map((npc) => {
      const rel = world?.npcRelations?.[npc.name];
      const badge = npc.generated ? '✨ IA' : '📜';
      const status = rel?.met ? this.getNpcStatusLabel(npc, world) : 'pas encore rencontré';
      const trust = rel?.met ? `${rel.trust}/5` : '—';
      const mood = rel?.mood || '—';
      return `
        <li class="npc-entry ${npc.generated ? 'is-generated' : ''}">
          <span class="npc-entry-name">${badge} ${this.escape(npc.name)}</span>
          <span class="npc-entry-role">${this.escape(npc.role || 'PNJ')}</span>
          <span class="npc-entry-meta">${status} · confiance ${trust} · ${mood}</span>
          ${npc.generated && npc.motive ? `<span class="npc-entry-motive">${this.escape(npc.motive)}</span>` : ''}
        </li>`;
    }).join('');
  },

  escape(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },

  getSummaryNpcs(game, scenario) {
    return this.getAllNpcs(game, scenario).map((npc) => {
      const rel = game?.aiState?.world?.npcRelations?.[npc.name];
      return {
        ...npc,
        relation: rel,
      };
    });
  },
};
