/**
 * bots.ts — Compagnons bots : archétypes, sélection d'action ancrée dans la scène.
 * Port TypeScript de js/bots.js.
 *
 * Simplification par rapport à la version navigateur : pas de personnalisation
 * persistée via localStorage (customBots/customizations gérés par l'onglet UI) —
 * seuls les archétypes par défaut sont exposés. Le format d'aventure/enquête
 * continue de piloter le choix des compagnons et de leurs actions.
 */

import type {
  ActionType,
  BotArchetype,
  Npc,
  PartyMember,
  QuestFormat,
  Scenario,
  Scene,
  WorldFact,
} from "./game_types.js";

export interface QuestFormatProfile {
  label: string;
  actionBoosts: Record<ActionType, number>;
  companionPersonalities: string[];
  companionIds: string[];
}

export const PERSONALITIES: { id: string; label: string }[] = [
  { id: "cautious", label: "Prudent·e" },
  { id: "curious", label: "Curieux·se" },
  { id: "bold", label: "Audacieux·se" },
  { id: "diplomatic", label: "Diplomate" },
  { id: "fierce", label: "Féroce" },
  { id: "cheerful", label: "Enjoué·e" },
  { id: "mystic", label: "Mystique" },
];

export const ACTION_TYPES: { id: ActionType; label: string }[] = [
  { id: "explore", label: "Explorer / fouiller" },
  { id: "talk", label: "Parler / négocier" },
  { id: "combat", label: "Combattre" },
  { id: "stealth", label: "Discrétion" },
  { id: "support", label: "Soutien / soins" },
];

export const QUEST_FORMAT_PROFILES: Record<QuestFormat, QuestFormatProfile> = {
  investigation: {
    label: "Mode enquête",
    actionBoosts: { talk: 4, explore: 3, stealth: 2, support: 1, combat: 0, creative: 0 },
    companionPersonalities: ["diplomatic", "curious", "cheerful", "mystic"],
    companionIds: ["bot-inv-elise", "bot-inv-noah", "bot-inv-jade", "bot-inv-oscar", "bot-inv-luna"],
  },
  oneshot: {
    label: "One-shot",
    actionBoosts: { combat: 3, explore: 2, stealth: 2, talk: 1, support: 1, creative: 0 },
    companionPersonalities: ["bold", "fierce", "cautious"],
    companionIds: ["bot-rook", "bot-thorn", "bot-kael"],
  },
  long: {
    label: "Campagne longue",
    actionBoosts: { explore: 2, talk: 2, support: 2, stealth: 1, combat: 1, creative: 0 },
    companionPersonalities: ["cautious", "diplomatic", "curious", "mystic"],
    companionIds: ["bot-kael", "bot-sera", "bot-lyra", "bot-zara"],
  },
};

export const DEFAULT_ARCHETYPES: BotArchetype[] = [
  {
    id: "bot-kael",
    name: "Kael",
    race: "Nain",
    class: "Guerrier",
    personality: "cautious",
    preferredActions: ["explore", "stealth", "support"],
    stats: { str: 16, dex: 10, con: 14, int: 8, wis: 12, cha: 10 },
    hp: 14,
    ac: 16,
    traits: ["protecteur", "méfiant"],
  },
  {
    id: "bot-lyra",
    name: "Lyra",
    race: "Elfe",
    class: "Mage",
    personality: "curious",
    preferredActions: ["explore", "talk"],
    stats: { str: 8, dex: 14, con: 10, int: 16, wis: 12, cha: 10 },
    hp: 8,
    ac: 12,
    traits: ["curieuse", "analytique"],
  },
  {
    id: "bot-rook",
    name: "Rook",
    race: "Humain",
    class: "Rôdeur",
    personality: "bold",
    preferredActions: ["explore", "stealth", "combat"],
    stats: { str: 10, dex: 16, con: 12, int: 10, wis: 12, cha: 14 },
    hp: 10,
    ac: 14,
    traits: ["impulsif", "courageux"],
  },
  {
    id: "bot-sera",
    name: "Sera",
    race: "Demi-elfe",
    class: "Clerc",
    personality: "diplomatic",
    preferredActions: ["talk", "support"],
    stats: { str: 10, dex: 10, con: 12, int: 12, wis: 16, cha: 14 },
    hp: 11,
    ac: 15,
    traits: ["bienveillante", "persuasive"],
  },
  {
    id: "bot-thorn",
    name: "Thorn",
    race: "Orc",
    class: "Barbare",
    personality: "fierce",
    preferredActions: ["combat", "explore"],
    stats: { str: 18, dex: 12, con: 16, int: 8, wis: 10, cha: 8 },
    hp: 16,
    ac: 14,
    traits: ["brutal", "têtu"],
  },
  {
    id: "bot-mira",
    name: "Mira",
    race: "Halfelin",
    class: "Barde",
    personality: "cheerful",
    preferredActions: ["talk", "explore"],
    stats: { str: 8, dex: 14, con: 10, int: 12, wis: 10, cha: 16 },
    hp: 9,
    ac: 13,
    traits: ["drôle", "observatrice"],
  },
  {
    id: "bot-zara",
    name: "Zara",
    race: "Tieffelin",
    class: "Occultiste",
    personality: "mystic",
    preferredActions: ["explore", "talk"],
    stats: { str: 8, dex: 12, con: 12, int: 14, wis: 14, cha: 16 },
    hp: 10,
    ac: 13,
    traits: ["énigmatique", "secrète"],
  },
];

export const INVESTIGATION_ARCHETYPES: BotArchetype[] = [
  {
    id: "bot-inv-elise",
    name: "Élise",
    race: "Humaine",
    class: "Inspectrice",
    personality: "diplomatic",
    preferredActions: ["talk", "explore"],
    stats: { str: 10, dex: 12, con: 11, int: 14, wis: 15, cha: 16 },
    hp: 10,
    ac: 13,
    traits: ["méthodique", "à l'écoute"],
    role: "Mène les interrogatoires et recoupe les témoignages.",
  },
  {
    id: "bot-inv-noah",
    name: "Noah",
    race: "Nain",
    class: "Expert légiste",
    personality: "curious",
    preferredActions: ["explore", "support"],
    stats: { str: 12, dex: 10, con: 14, int: 16, wis: 14, cha: 9 },
    hp: 12,
    ac: 14,
    traits: ["rigoureux", "obsessionnel"],
    role: "Analyse les traces, objets et scènes de crime.",
  },
  {
    id: "bot-inv-jade",
    name: "Jade",
    race: "Tieffeline",
    class: "Interrogatrice",
    personality: "bold",
    preferredActions: ["talk", "stealth"],
    stats: { str: 9, dex: 14, con: 11, int: 13, wis: 12, cha: 17 },
    hp: 9,
    ac: 12,
    traits: ["perspicace", "implacable"],
    role: "Déstabilise les suspects et fait parler les témoins réticents.",
  },
  {
    id: "bot-inv-oscar",
    name: "Oscar",
    race: "Humain",
    class: "Profiler",
    personality: "mystic",
    preferredActions: ["talk", "explore"],
    stats: { str: 9, dex: 11, con: 10, int: 16, wis: 15, cha: 12 },
    hp: 9,
    ac: 11,
    traits: ["intuitif", "froid"],
    role: "Reconstitue les motivations et les incohérences du dossier.",
  },
  {
    id: "bot-inv-luna",
    name: "Luna",
    race: "Elfe",
    class: "Photographe de scène",
    personality: "cheerful",
    preferredActions: ["explore", "talk"],
    stats: { str: 8, dex: 16, con: 10, int: 13, wis: 14, cha: 13 },
    hp: 8,
    ac: 12,
    traits: ["minutieuse", "discrete"],
    role: "Documente les lieux et repère les détails que les autres manquent.",
  },
];

function getArchetype(id: string): BotArchetype | null {
  return DEFAULT_ARCHETYPES.find((b) => b.id === id) || null;
}

function getArchetypes(): BotArchetype[] {
  return [...DEFAULT_ARCHETYPES];
}

function getInvestigationArchetype(id: string): BotArchetype | null {
  return INVESTIGATION_ARCHETYPES.find((b) => b.id === id) || null;
}

function getInvestigationArchetypes(): BotArchetype[] {
  return [...INVESTIGATION_ARCHETYPES];
}

function getBotsForQuestFormat(questFormat: QuestFormat): BotArchetype[] {
  return questFormat === "investigation" ? getInvestigationArchetypes() : getArchetypes();
}

function personalityLabel(id: string): string {
  return PERSONALITIES.find((p) => p.id === id)?.label || id;
}

function normalizeId(id: string): string {
  if (!id) return "";
  return id.startsWith("bot:") ? id.replace("bot:", "") : id;
}

function createPartyMember(archetypeOrId: BotArchetype | string, index = 0): PartyMember {
  const archetype = typeof archetypeOrId === "string" ? getArchetype(archetypeOrId) || getInvestigationArchetype(archetypeOrId) : archetypeOrId;
  if (!archetype) {
    throw new Error(`Archétype de bot introuvable : ${String(archetypeOrId)}`);
  }
  const a: BotArchetype = { ...archetype, stats: { ...archetype.stats } };
  return {
    id: `party-${a.id}-${Date.now()}-${index}`,
    characterId: a.id,
    name: a.name,
    race: a.race,
    class: a.class,
    stats: a.stats,
    hp: a.hp,
    maxHp: a.hp,
    ac: a.ac,
    isBot: true,
    isHuman: false,
    playerName: null,
    personality: a.personality,
    preferredActions: a.preferredActions || ["explore"],
    traits: a.traits || [],
  };
}

function shuffle<T>(array: T[]): T[] {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function generateCompanions(count = 2, excludeIds: string[] = [], questFormat: QuestFormat | null = null): PartyMember[] {
  const excludeSet = new Set(excludeIds.map((id) => normalizeId(id)).filter(Boolean));
  const useInvestigation = questFormat === "investigation";
  let available = (useInvestigation ? getInvestigationArchetypes() : getArchetypes()).filter(
    (a) => !excludeSet.has(a.id),
  );

  const profile = questFormat ? QUEST_FORMAT_PROFILES[questFormat] : null;
  if (profile?.companionIds?.length && available.length > count) {
    const prioritized: BotArchetype[] = [];
    const rest: BotArchetype[] = [];
    available.forEach((bot) => {
      if (profile.companionIds.includes(bot.id)) prioritized.push(bot);
      else rest.push(bot);
    });
    available = [...shuffle(prioritized), ...shuffle(rest)];
  } else {
    available = shuffle(available);
  }

  return available.slice(0, Math.min(count, available.length)).map((a, i) => createPartyMember(a, i));
}

function usedIdsFromParty(party: PartyMember[]): string[] {
  return party.map((m) => m.characterId).filter((id): id is string => Boolean(id));
}

function pickUniqueAction(pool: string[], recentActions: string[] = []): string {
  const recent = new Set(recentActions);
  let available = pool.filter((a) => !recent.has(a));
  if (available.length === 0) available = pool;
  return available[Math.floor(Math.random() * available.length)];
}

const PREFERENCE_MATCHERS: Record<ActionType, RegExp> = {
  explore: /fouill|examin|inspect|cherch|décrypt|traduit|analyse|runes|symboles|compartiment/,
  talk: /parl|question|interroge|confiance|chanson|légende|demande|pnj/,
  combat: /attaq|frapp|défie|arme|combat|force|menace|protège le groupe/,
  stealth: /discr|cache|silenc|sans alerter|repli|cachette/,
  support: /soin|prie|bénis|bande|aide|moral|remonte/,
  creative: /.^/,
};

function actionMatchesPreference(action: string, pref: ActionType): boolean {
  const t = action.toLowerCase();
  return PREFERENCE_MATCHERS[pref]?.test(t) || false;
}

function pickPreferredAction(pool: string[], bot: { preferredActions?: ActionType[] }, recentActions: string[] = []): string {
  const recent = new Set(recentActions);
  let available = pool.filter((a) => !recent.has(a));
  if (available.length === 0) available = pool;

  const prefs = bot.preferredActions || [];
  if (!prefs.length) return pickUniqueAction(pool, recentActions);

  const weighted: string[] = [];
  available.forEach((action) => {
    const weight = prefs.some((p) => actionMatchesPreference(action, p)) ? 3 : 1;
    for (let i = 0; i < weight; i += 1) weighted.push(action);
  });

  return weighted[Math.floor(Math.random() * weighted.length)];
}

export interface SceneDetails {
  title: string;
  clauses: string[];
  objects: string[];
  npc: Npc | null;
  allNpcs: Npc[];
  hasThreat?: boolean;
}

const SCENE_OBJECT_PATTERNS: { re: RegExp }[] = [
  { re: /porte[^.,;]{0,30}/i },
  { re: /escalier[^.,;]{0,25}/i },
  { re: /runes?[^.,;]{0,25}/i },
  { re: /symboles?[^.,;]{0,25}/i },
  { re: /autel[^.,;]{0,25}/i },
  { re: /passage[^.,;]{0,25}/i },
  { re: /couloir[^.,;]{0,25}/i },
  { re: /puits[^.,;]{0,25}/i },
  { re: /coffre[^.,;]{0,25}/i },
  { re: /grimoire[^.,;]{0,25}/i },
  { re: /journal[^.,;]{0,25}/i },
  { re: /torches?[^.,;]{0,20}/i },
  { re: /murs?[^.,;]{0,20}/i },
  { re: /silhouette[^.,;]{0,25}/i },
  { re: /créature[^.,;]{0,25}/i },
  { re: /gardien[^.,;]{0,25}/i },
  { re: /offrandes?[^.,;]{0,25}/i },
  { re: /tapisserie[^.,;]{0,25}/i },
  { re: /bibliothèque[^.,;]{0,25}/i },
  { re: /fenêtre[^.,;]{0,25}/i },
  { re: /dunes?[^.,;]{0,20}/i },
  { re: /ruines?[^.,;]{0,25}/i },
];

export interface BotActionContext {
  scene?: Scene;
  scenario?: Scenario;
  humanFailed?: boolean;
  humanActionType?: ActionType;
  questFormat?: QuestFormat | null;
  recentActions?: string[];
  storyBeat?: string[];
  worldFacts?: WorldFact[];
  worldFlags?: Record<string, unknown>;
  sceneChanges?: string[];
  allNpcs?: Npc[];
}

function extractSceneDetails(scene: Scene | undefined, scenario: Scenario | undefined, context: BotActionContext = {}): SceneDetails {
  const content = scene?.content || "";
  const title = scene?.title || "la zone";
  const full = `${title}. ${content}`.toLowerCase();

  const allNpcs = context.allNpcs || scenario?.npcs || [];
  const details: SceneDetails = {
    title,
    clauses: content
      .split(/[,;.] /)
      .map((s) => s.trim())
      .filter((s) => s.length > 12),
    objects: [],
    npc: allNpcs[0] || null,
    allNpcs,
  };

  SCENE_OBJECT_PATTERNS.forEach(({ re }) => {
    const m = content.match(re);
    if (m) {
      const item = m[0].trim();
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
}

/** Actions précises selon la classe du bot et le format de quête. */
function classActions(bot: { class: string }, details: SceneDetails, questFormat: QuestFormat = "oneshot"): string[] {
  const obj = details.objects[0] || `les lieux de ${details.title}`;
  const obj2 = details.objects[1] || obj;
  const npc = details.npc;
  const clause = details.clauses[0] || details.title;

  const investigationExtras: Record<string, string[]> = {
    Guerrier: [
      `Je vérifie si ${obj} a été forcé récemment — preuve d'effraction ou fausse piste ?`,
      `Je protège ${npc ? npc.name : "le témoin"} pendant l'interrogatoire pour qu'il parle sans crainte.`,
    ],
    Mage: [
      `Je cherche une trace magique sur ${obj} — sortilège, illusion ou simple supercherie ?`,
      `Je dresse une chronologie des événements en recoupant ${clause} avec nos notes.`,
    ],
    Rôdeur: [
      `Je repère les traces dissimulées près de ${obj} : sang, cendres, empreintes.`,
      `Je surveille ${npc ? npc.name : "le suspect"} discrètement pendant qu'il répond aux questions.`,
    ],
    Clerc: [
      `Je demande à ${npc ? npc.name : "le témoin"} de jurer sur sa version des faits.`,
      `Je cherche des signes de mensonge ou de peur chez ${npc ? npc.name : "l'interlocuteur"}.`,
    ],
    Barbare: [
      `Je intimide ${npc ? npc.name : "le suspect"} pour qu'il lâche une contradiction dans son récit.`,
      `Je force l'accès à ${obj} si c'est là que se cache la preuve.`,
    ],
    Barde: [
      `J'écoute le ton de ${npc ? npc.name : "l'interlocuteur"} — hésitation, colère, trop de détails ?`,
      `Je compare les témoignages : qui contredit qui sur ${obj} ?`,
    ],
    Occultiste: [
      `Je sonde ${obj} pour détecter un enchantement de dissimulation.`,
      `Je relève une empreinte occulte qui pourrait trahir le coupable.`,
    ],
  };

  const oneshotExtras: Record<string, string[]> = {
    Guerrier: [`Je fonce vers ${obj} — on règle ça maintenant, pas demain.`],
    Mage: [`Je lance le sort le plus direct pour débloquer ${obj} immédiatement.`],
    Rôdeur: [`Je contourne par ${obj2} pour surprendre l'adversaire avant qu'il réagisse.`],
    Clerc: [`Je galvanise le groupe : « Plus de temps à perdre, on avance ! »`],
    Barbare: [`Je charge ${obj} sans hésiter — la scène doit tourner, vite.`],
    Barde: [`Je pousse ${npc ? npc.name : "le PNJ"} à parler tout de suite, sans détour.`],
    Occultiste: [`J'invoque une aide rapide pour percer ${obj} sans longues incantations.`],
  };

  const longExtras: Record<string, string[]> = {
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
      `Je prends le temps d'écouter ${npc ? npc.name : "les habitants"} — les relations comptent sur le long terme.`,
      `Je bénis le campement près de ${obj} : on reviendra peut-être.`,
    ],
    Barbare: [
      `Je teste ${obj} sans précipitation — une campagne, ça se joue sur plusieurs jours.`,
      `Je laisse une marque au groupe sur ${obj2} pour ne pas oublier ce lieu.`,
    ],
    Barde: [
      `Je transforme ce qu'on apprend sur ${obj} en une ballade pour la chronique du groupe.`,
      `Je retourne voir ${npc ? npc.name : "le PNJ"} — la confiance se construit avec le temps.`,
    ],
    Occultiste: [
      `J'archive mes observations sur ${obj} — le fil occulte se dévoile lentement.`,
      `Je laisse une rune discrète sur ${obj2} pour la retrouver à notre prochain passage.`,
    ],
  };

  const templates: Record<string, string[]> = {
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
      `Je questionne ${npc ? npc.name : "les gens du coin"} sur l'histoire de ${obj}.`,
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
      `J'interroge ${npc ? npc.name : "le témoin"} sur son alibi et je compare avec nos notes.`,
      `Je demande à ${npc ? npc.name : "l'interlocuteur"} de répéter sa version — je cherche les incohérences.`,
      `Je recoupe ce qu'on sait de ${obj} avec les témoignages déjà recueillis.`,
    ],
    "Expert légiste": [
      `Je prélève des traces sur ${obj} : poussière, fibre, résidu — tout est une preuve.`,
      `J'analyse ${obj2} avec mes outils pour dater ou identifier l'origine du geste.`,
      `Je documente ${obj} photographiquement avant qu'on ne perturbe la scène.`,
      `Je compare ${clause} avec les rapports d'autopsie ou d'archives disponibles.`,
    ],
    Interrogatrice: [
      `Je pousse ${npc ? npc.name : "le suspect"} dans ses contradictions sur ${obj}.`,
      `Je change soudain de sujet pour surprendre ${npc ? npc.name : "le témoin"} sur son alibi.`,
      `Je laisse un silence pesant après la question sur ${obj} — qui craque le premier ?`,
      `Je feins de connaître la vérité sur ${obj2} pour provoquer une réaction.`,
    ],
    Profiler: [
      `Je reconstitue le profil psychologique de celui qui a manipulé ${obj}.`,
      `Je cherche le mobile derrière ${clause} — passion, argent ou vengeance ?`,
      `J'identifie qui bénéficie le plus de ce qui s'est passé près de ${obj}.`,
      `Je dresse une chronologie des actes probables autour de ${details.title}.`,
    ],
    "Photographe de scène": [
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

  let actions = [...(templates[bot.class] || templates["Rôdeur"])];

  if (questFormat === "investigation") {
    actions = [...(investigationExtras[bot.class] || []), ...actions];
  } else if (questFormat === "oneshot") {
    actions = [...(oneshotExtras[bot.class] || []), ...actions];
  } else if (questFormat === "long") {
    actions = [...(longExtras[bot.class] || []), ...actions];
  }

  return actions;
}

/** Actions liées à chaque objet détecté dans la scène. */
function objectActions(_bot: unknown, details: SceneDetails): string[] {
  const actions: string[] = [];
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
}

/** Actions de dialogue avec PNJ nommés. */
function npcActions(details: SceneDetails): string[] {
  if (!details.allNpcs.length) return [];
  const actions: string[] = [];
  details.allNpcs.forEach((npc) => {
    actions.push(
      `Je m'approche de ${npc.name} (${npc.role || "PNJ"}) et je lui demande : « Que savez-vous sur ${details.title} ? »`,
      `Je questionne ${npc.name} sur son rôle ici : « ${(npc.description || "").split(".")[0]} » — est-ce vrai ?`,
      `Je tente de gagner la confiance de ${npc.name} pour qu'il nous guide vers la suite.`,
    );
  });
  return actions;
}

/** Réagit aux faits du monde et aux changements de scène mémorisés par le MJ IA. */
function worldAwareActions(bot: { preferredActions?: ActionType[] }, context: BotActionContext, details: SceneDetails): string[] {
  const actions: string[] = [];
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
}

function complementActions(_bot: unknown, details: SceneDetails, humanActionType: ActionType | undefined): string[] {
  const obj = details.objects[0] || details.title;
  const npc = details.npc;
  const obj2Fallback = details.objects[1] || details.clauses[0] || details.title;
  const map: Record<string, string[]> = {
    explore: [
      `Puisque la fouille a échoué, j'interroge ${npc ? npc.name : "un témoin"} sur ${obj}.`,
      `J'essaie une autre zone : ${obj2Fallback}.`,
    ],
    talk: [
      `La conversation n'a rien donné — j'inspecte plutôt ${obj} physiquement.`,
      `Je fouille ${obj} pendant que le PNJ est distrait.`,
    ],
    combat: [`Le combat tourne mal — je bande les blessures du groupe et je cherche une retraite vers ${obj}.`],
    stealth: [`On nous a repérés — j'attaque de front ${obj} pour créer une diversion.`],
  };
  return (humanActionType && map[humanActionType]) || [];
}

function buildActionPool(bot: BotArchetype | PartyMember, context: BotActionContext): string[] {
  const { scene, scenario, humanFailed, humanActionType, questFormat } = context;
  const details = extractSceneDetails(scene, scenario, context);

  let pool = [
    ...classActions(bot, details, questFormat || "oneshot"),
    ...objectActions(bot, details),
    ...npcActions(details),
    ...worldAwareActions(bot, context, details),
  ];

  if (questFormat === "investigation") {
    const npcName = details.npc?.name || details.allNpcs?.[0]?.name || "le témoin";
    const obj = details.objects[0] || details.title;
    pool.unshift(
      `J'interroge ${npcName} sur son alibi et ce qu'il a vu cette nuit-là.`,
      `Je recoupe les indices trouvés jusqu'ici avec ce qu'on sait de ${obj}.`,
      `J'examine ${obj} en cherchant une preuve ou une trace laissée par le suspect.`,
      `Je demande à ${npcName} de confirmer ou infirmer la version des faits du groupe.`,
    );
  }

  if (questFormat === "oneshot") {
    pool.unshift(`J'agis vite et directement sur ${details.objects[0] || details.title} — pas de temps à perdre.`);
  }

  if (questFormat === "long") {
    pool.push(`Je prends des notes détaillées sur ${details.title} pour ne rien oublier d'ici la prochaine session.`);
  }

  if (humanFailed && humanActionType) {
    pool = complementActions(bot, details, humanActionType).concat(pool);
  }

  if (details.hasThreat && (bot.preferredActions || []).includes("combat")) {
    const threat = details.objects.find((o) => /silhouette|créature|gardien/i.test(o)) || "la menace";
    pool.unshift(`J'attaque ${threat} pour protéger le groupe !`);
  }

  pool = pool.filter((a) => a.length > 25 && !/quelque chose|inattendu|imprévu|d'une façon/i.test(a));
  return [...new Set(pool)];
}

function chooseAction(bot: BotArchetype | PartyMember, context: BotActionContext): string {
  const pool = buildActionPool(bot, context);

  if (pool.length === 0) {
    const details = extractSceneDetails(context.scene, context.scenario, context);
    const fallback = `J'examine minutieusement ${details.objects[0] || context.scene?.title || "la scène"} pour trouver un indice.`;
    return pickPreferredAction([fallback], bot, context.recentActions);
  }

  return pickPreferredAction(pool, bot, context.recentActions);
}

function getCompanions(party: PartyMember[]): PartyMember[] {
  return party.filter((m) => m.isBot);
}

export const Bots = {
  PERSONALITIES,
  ACTION_TYPES,
  QUEST_FORMAT_PROFILES,
  DEFAULT_ARCHETYPES,
  INVESTIGATION_ARCHETYPES,
  getArchetype,
  getArchetypes,
  getInvestigationArchetype,
  getInvestigationArchetypes,
  getBotsForQuestFormat,
  personalityLabel,
  normalizeId,
  createPartyMember,
  shuffle,
  generateCompanions,
  usedIdsFromParty,
  pickUniqueAction,
  actionMatchesPreference,
  pickPreferredAction,
  extractSceneDetails,
  classActions,
  objectActions,
  npcActions,
  worldAwareActions,
  complementActions,
  buildActionPool,
  chooseAction,
  getCompanions,
};
