/**
 * scenarios.js — Gestion des scénarios et aventures.
 */

const Scenarios = {
  list: [],
  removedDemos: [],

  load() {
    this.list = Storage.loadArray(Storage.KEYS.scenarios);
    this.removedDemos = Storage.loadArray(Storage.KEYS.removedDemos);
    this.list.forEach((s) => {
      if (s.roster === 'investigation') {
        if (!s.questFormat) {
          s.questFormat = s.id === 'inv-demo-serpent-noir' ? 'long' : 'oneshot';
        }
        return;
      }
      if (!s.questFormat) {
        s.questFormat = (s.id === 'demo-kharak' || s.id === 'demo-couronne-fracturee')
          ? 'long'
          : 'oneshot';
      }
    });
  },

  save() {
    Storage.save(Storage.KEYS.scenarios, this.list);
  },

  saveRemovedDemos() {
    Storage.save(Storage.KEYS.removedDemos, this.removedDemos);
  },

  isBuiltInDemo(id) {
    return this.DEMO_SCENARIOS.some((d) => d.id === id)
      || this.INVESTIGATION_SCENARIOS.some((d) => d.id === id);
  },

  generateId() {
    return 'scn-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7);
  },

  escape(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },

  renderList() {
    if (typeof AdventureRoster !== 'undefined') {
      AdventureRoster.renderScenarios();
    }
  },

  updateScenarioFormMode(isInvestigation, questFormatOption = null) {
    const formatRow = document.getElementById('scenario-format-row');
    const formatSelect = document.getElementById('scenario-quest-format');
    const mysteryRow = document.getElementById('scenario-mystery-row');
    mysteryRow?.classList.toggle('hidden', !isInvestigation);

    if (isInvestigation && formatSelect) {
      formatRow?.classList.remove('hidden');
      formatSelect.innerHTML = `
        <option value="oneshot">Affaire one-shot (1–2 sessions)</option>
        <option value="long">Enquête longue durée (plusieurs semaines)</option>`;
      formatSelect.value = questFormatOption === 'long' ? 'long' : 'oneshot';
      return;
    }

    if (formatSelect) {
      formatSelect.innerHTML = `
        <option value="oneshot">One-shot (3–4 h)</option>
        <option value="long">Campagne longue durée</option>`;
    }
    formatRow?.classList.toggle('hidden', isInvestigation);
  },

  renderSceneItem(scene = { title: '', content: '' }) {
    const div = document.createElement('div');
    div.className = 'sub-item';
    div.innerHTML = `
      <button type="button" class="btn-danger remove-btn btn-remove-scene">✕</button>
      <div class="form-row">
        <label>Titre de la scène</label>
        <input type="text" class="scene-title" value="${this.escape(scene.title)}" placeholder="Arrivée au village...">
      </div>
      <div class="form-row">
        <label>Description</label>
        <textarea class="scene-content" rows="3" placeholder="Ce que voient les joueurs, indices, événements...">${this.escape(scene.content)}</textarea>
      </div>
    `;
    div.querySelector('.btn-remove-scene').addEventListener('click', () => div.remove());
    return div;
  },

  renderNpcItem(npc = { name: '', description: '' }) {
    const div = document.createElement('div');
    div.className = 'sub-item';
    div.innerHTML = `
      <button type="button" class="btn-danger remove-btn btn-remove-npc">✕</button>
      <div class="form-row two-cols">
        <div>
          <label>Nom du PNJ</label>
          <input type="text" class="npc-name" value="${this.escape(npc.name)}" placeholder="Gérard le tavernier">
        </div>
        <div>
          <label>Rôle</label>
          <input type="text" class="npc-role" value="${this.escape(npc.role || '')}" placeholder="Informateur, ennemi...">
        </div>
      </div>
      <div class="form-row">
        <label>Description</label>
        <textarea class="npc-description" rows="2" placeholder="Apparence, personnalité, secrets...">${this.escape(npc.description)}</textarea>
      </div>
    `;
    div.querySelector('.btn-remove-npc').addEventListener('click', () => div.remove());
    return div;
  },

  showForm(id = null, options = {}) {
    const form = document.getElementById('scenario-form');
    const title = document.getElementById('scenario-form-title');
    const scenesList = document.getElementById('scenes-list');
    const npcsList = document.getElementById('npcs-list');
    const rosterInput = document.getElementById('scenario-roster');
    const formatSelect = document.getElementById('scenario-quest-format');

    form.classList.remove('hidden');
    scenesList.innerHTML = '';
    npcsList.innerHTML = '';

    if (id) {
      const scenario = this.list.find((s) => s.id === id);
      if (!scenario) return;

      const isInvestigation = scenario.roster === 'investigation';
      this.updateScenarioFormMode(isInvestigation, scenario.questFormat);

      title.textContent = isInvestigation
        ? 'Modifier le scénario d\'enquête'
        : 'Modifier le scénario';
      document.getElementById('scenario-id').value = scenario.id;
      document.getElementById('scenario-title').value = scenario.title;
      document.getElementById('scenario-synopsis').value = scenario.synopsis || '';
      document.getElementById('scenario-setting').value = scenario.setting || '';
      document.getElementById('scenario-mystery').value = scenario.mystery || '';
      if (rosterInput) rosterInput.value = scenario.roster || '';
      if (formatSelect) {
        formatSelect.value = scenario.questFormat === 'long' ? 'long' : 'oneshot';
      }

      scenario.scenes.forEach((scene) => scenesList.appendChild(this.renderSceneItem(scene)));
      scenario.npcs.forEach((npc) => npcsList.appendChild(this.renderNpcItem(npc)));
    } else {
      const isInvestigation = options.roster === 'investigation';
      this.updateScenarioFormMode(isInvestigation, options.questFormat);

      title.textContent = isInvestigation ? 'Nouveau scénario d\'enquête' : 'Nouveau scénario';
      document.getElementById('scenario-form-el').reset();
      document.getElementById('scenario-id').value = '';
      if (rosterInput) rosterInput.value = isInvestigation ? 'investigation' : '';
      if (formatSelect) {
        formatSelect.value = options.questFormat === 'long' ? 'long' : 'oneshot';
      }
      if (isInvestigation) {
        document.getElementById('scenario-setting').value = 'Ville brumeuse, nuit, tension et secrets…';
      }
      scenesList.appendChild(this.renderSceneItem());
    }

    App.showApp('adventures');
    form.scrollIntoView({ behavior: 'smooth' });
  },

  hideForm() {
    document.getElementById('scenario-form').classList.add('hidden');
  },

  collectScenes() {
    return [...document.querySelectorAll('#scenes-list .sub-item')].map((item) => ({
      title: item.querySelector('.scene-title').value.trim(),
      content: item.querySelector('.scene-content').value.trim(),
    })).filter((s) => s.title || s.content);
  },

  collectNpcs() {
    return [...document.querySelectorAll('#npcs-list .sub-item')].map((item) => ({
      name: item.querySelector('.npc-name').value.trim(),
      role: item.querySelector('.npc-role').value.trim(),
      description: item.querySelector('.npc-description').value.trim(),
    })).filter((n) => n.name || n.description);
  },

  handleSubmit(e) {
    e.preventDefault();

    const id = document.getElementById('scenario-id').value;
    const roster = document.getElementById('scenario-roster')?.value.trim() || undefined;
    const mystery = document.getElementById('scenario-mystery')?.value.trim() || '';
    const scenario = {
      id: id || this.generateId(),
      title: document.getElementById('scenario-title').value.trim(),
      synopsis: document.getElementById('scenario-synopsis').value.trim(),
      setting: document.getElementById('scenario-setting').value.trim(),
      scenes: this.collectScenes(),
      npcs: this.collectNpcs(),
    };
    if (roster) scenario.roster = roster;
    if (mystery) scenario.mystery = mystery;
    if (!scenario.roster || scenario.roster !== 'investigation') {
      const format = document.getElementById('scenario-quest-format')?.value;
      scenario.questFormat = format === 'long' ? 'long' : 'oneshot';
    } else {
      const format = document.getElementById('scenario-quest-format')?.value;
      scenario.questFormat = format === 'long' ? 'long' : 'oneshot';
    }

    if (id) {
      const index = this.list.findIndex((s) => s.id === id);
      const existing = index !== -1 ? this.list[index] : null;
      if (existing?.roster && !scenario.roster) scenario.roster = existing.roster;
      if (index !== -1) this.list[index] = scenario;
    } else {
      this.list.push(scenario);
    }

    this.save();
    this.renderList();
    if (typeof InvestigationRoster !== 'undefined') {
      InvestigationRoster.renderScenarios();
    }
    this.hideForm();
  },

  delete(id) {
    const scenario = this.list.find((s) => s.id === id);
    if (!scenario) return;

    const label = scenario.roster === 'investigation' ? 'affaire' : 'scénario';
    if (!confirm(`Supprimer ${label === 'affaire' ? 'l\'' : 'le '}${label} « ${scenario.title} » ?`)) return;

    this.list = this.list.filter((s) => s.id !== id);
    if (this.isBuiltInDemo(id) && !this.removedDemos.includes(id)) {
      this.removedDemos.push(id);
      this.saveRemovedDemos();
    }
    this.save();
    this.renderList();
    if (typeof InvestigationRoster !== 'undefined') {
      InvestigationRoster.renderScenarios();
    }
    if (typeof Game !== 'undefined') {
      Game.refreshSetupCharacters();
      Game.refreshSetupMaps();
    }
  },

  /** Scénarios d'exemple inclus avec l'application */
  DEMO_SCENARIOS: [
    {
      id: 'demo-crypte',
      questFormat: 'oneshot',
      title: 'La Crypte Oubliée',
      synopsis: 'Une crypte ancienne a été découverte sous le village de Brumeval. Des disparitions mystérieuses poussent les aventuriers à descendre dans les ténèbres.',
      setting: 'Village de Brumeval, sous une pluie fine. Torches, pierre humide, odeur de moisi.',
      scenes: [
        {
          title: 'Le cimetière de Brumeval',
          content: 'Sous la pluie, Eldric le fossoyeur montre une dalle descellée près d\'un mausolée effondré. Des traces de griffes marquent la terre. Des murmures montent du trou — ou est-ce le vent ?',
        },
        {
          title: 'L\'entrée de la crypte',
          content: 'Un escalier de pierre descend dans l\'obscurité. Des runes effacées ornent les murs. Au fond, une porte de fer entrouverte laisse échapper un courant d\'air froid. Des ossements humains gisent sur les marches.',
        },
        {
          title: 'Le couloir des veilleurs',
          content: 'Des niches abritent des statues de chevaliers pétrifiés. L\'une d\'elles a bougé depuis la dernière visite — impossible. Des mécanismes de flèches sont visibles dans le plafond. Un journal d\'explorateur mort gît au sol.',
        },
        {
          title: 'La salle des offrandes',
          content: 'Une salle circulaire avec un autel fissuré. Des offrandes pourries sont éparpillées. Trois passages mènent vers l\'ouest, le nord et le bas. L\'eau suinte des murs et forme des flaques d\'un noir huileux.',
        },
        {
          title: 'La fosse aux morts-vivants',
          content: 'Le passage du bas mène à une fosse où des cadavres se tordent péniblement. Une cloche rouillée peut les apaiser — ou les provoquer. Au fond, une échelle de corde mène plus bas.',
        },
        {
          title: 'Le sanctuaire interdit',
          content: 'Une lueur verdâtre pulse au centre de la pièce. Le Gardien des Ombres veille devant un autel noir. Les disparus du village sont là, vivants mais transfigurés. Le secret de Brumeval se révèle enfin.',
        },
      ],
      npcs: [
        {
          name: 'Eldric le fossoyeur',
          role: 'Informateur',
          description: 'Un vieil homme nerveux qui a vu des lumières sous le cimetière. Il offre une clé rouillée.',
        },
        {
          name: 'Le Gardien des Ombres',
          role: 'Antagoniste',
          description: 'Une entité liée à la crypte. Il teste la bravoure ou la ruse des intrus.',
        },
      ],
    },
    {
      id: 'demo-manoir',
      questFormat: 'oneshot',
      title: 'Le Manoir de Valenwood',
      synopsis: 'Le comte Valenwood a disparu. Son manoir isolé dans la forêt regorge de secrets, de pièges et de créatures qui rôdent la nuit.',
      setting: 'Manoir gothique en lisière de forêt, nuit pluvieuse, chandelles qui vacillent.',
      scenes: [
        {
          title: 'L\'approche du manoir',
          content: 'Allée de chênes tordus, portail rouillé, fenêtres éteintes. Une lettre du comte invite les aventuriers à « enquêter sur des troubles nocturnes ». Martha la servante les accueille, pâle et terrorisée.',
        },
        {
          title: 'Le hall d\'entrée',
          content: 'Un grand hall poussiéreux, un portrait du comte fixe les visiteurs. Une tapisserie dissimule peut-être un passage. Des pas résonnent à l\'étage. Un chandelier tombe soudain — accident ou piège ?',
        },
        {
          title: 'La salle à manger',
          content: 'Vaisselle encore dressée, nourriture moisie. Six couverts, mais une chaise renversée. Des griffures sur la table forment un mot : « SORTEZ ». Une porte mène aux cuisines, une autre à l\'étage.',
        },
        {
          title: 'La bibliothèque maudite',
          content: 'Des livres jonchent le sol. Un grimoire ouvert pulse d\'une lumière violette. Une fenêtre brisée laisse entrer le vent et la pluie. Derrière une étagère basculante se cache le passage secret.',
        },
        {
          title: 'La chambre secrète du comte',
          content: 'Une chambre circulaire avec un cercle de sel brisé au sol. Le comte Aldric est enchaîné — ou possédé. Une entité murmure à travers lui. La fenêtre donne sur un jardin où des ombres dansent.',
        },
        {
          title: 'Le jardin des ombres',
          content: 'Nuit noire, rosée glacée. Les ombres prennent forme humaine — d\'anciens Valenwood piégés ici. Le comte peut être sauvé ou sacrifié. Le manoir tremble tandis que l\'aube approche.',
        },
      ],
      npcs: [
        {
          name: 'Martha la servante',
          role: 'Témoin',
          description: 'Elle tremble et murmure que « les murs écoutent ». Elle connaît un passage derrière la tapisserie.',
        },
        {
          name: 'Comte Aldric Valenwood',
          role: 'Victime / allié ambigu',
          description: 'Noble érudit, peut-être possédé. Il alterne entre lucidité et rage surnaturelle.',
        },
      ],
    },
    {
      id: 'demo-kharak',
      questFormat: 'long',
      title: 'Les Sables de Kharak',
      synopsis: 'Une caravane a disparu dans le désert de Kharak. Les aventuriers doivent traverser dunes, tempêtes et ruines oubliées pour retrouver les marchands — et ce qu\'ils transportaient.',
      setting: 'Désert brûlant, ruines antiques à demi enfouies dans le sable, ciel orange au coucher du soleil.',
      scenes: [
        {
          title: 'L\'oasis de Selim',
          content: 'La dernière étape avant le désert profond. Des nomades parlent d\'une « cité engloutie » et de mirages vivants. Une carte partielle est vendue au marché. Le vent porte une odeur de soufre.',
        },
        {
          title: 'La tempête de sable',
          content: 'Visibilité nulle. Le groupe doit se lier avec des cordes pour ne pas se perdre. Des voix les appellent par leur nom — mirages du Seigneur des Sables. Un repaire de bandits offre un abri douteux.',
        },
        {
          title: 'Les ruines de Zhar-Rim',
          content: 'Des colonnes de pierre émergent des sables. Des inscriptions préviennent les intrus. Au centre, un puits mène vers des catacombes fraîches. Des scarabées de pierre s\'animent au passage du groupe.',
        },
        {
          title: 'Les catacombes fraîches',
          content: 'Contraste saisissant : fraîcheur et silence sous le désert brûlant. Fresques racontent la chute de Zhar-Rim. Des urnes contiennent des cendres et des gemmes. Un passage s\'effondre derrière le groupe.',
        },
        {
          title: 'Le trésor de la caravane',
          content: 'Les marchands sont retrouvés, assiégés par des scarabées géants. Yasmina la caravanière protège un coffre scellé. Leur cargaison contient un artefact qui attire les créatures du désert.',
        },
        {
          title: 'Le tribunal du Seigneur des Sables',
          content: 'L\'esprit ancien émerge des dunes en tempête. Il exige un tribut, une épreuve de sagesse ou un combat. Le sort de la caravane et de l\'artefact se joue ici, sous un ciel de feu.',
        },
      ],
      npcs: [
        {
          name: 'Yasmina la caravanière',
          role: 'Survivante',
          description: 'Marchande épuisée qui cache la véritable nature de la cargaison.',
        },
        {
          name: 'Le Seigneur des Sables',
          role: 'Antagoniste',
          description: 'Esprit ancien lié aux ruines. Il exige un tribut ou une épreuve de sagesse.',
        },
      ],
    },
    {
      id: 'demo-couronne-fracturee',
      questFormat: 'long',
      title: 'La Couronne Fracturée',
      synopsis: 'Campagne épique sur 10 à 15 sessions (plusieurs semaines) : le roi d\'Aldermar est mort sans héritier clair, cinq ducs se disputent le trône, et au nord un sceau millénaire se fissure. Les héros doivent naviguer intrigues, guerres et horreurs anciennes pour décider du sort du royaume.',
      setting: 'Royaume médiéval-fantastique d\'Aldermar — capitale Valdris, forteresses de montagne, marches du nord gelées, cours nobles et champs de bataille.',
      scenes: [
        {
          title: 'Acte I — La nouvelle de Valdris',
          content: 'Les cloches sonnent le deuil. Le roi Aldric III est mort dans son lit, couronne encore vissée sur le crâne. À Valdris, la Garde royale verrouille les portes du palais ; les ducs convoquent leurs bannerets. Une servante murmure que la marque noire sur le poignet du roi n\'était pas là la veille. Le groupe arrive comme émissaires, mercenaires ou héros convoqués — le conseil doit se tenir dans trois jours.',
        },
        {
          title: 'Acte I — Le conseil des cinq ducs',
          content: 'Hall du trône surchargé de bannières rivales. Duc Harald (guerre), duchesse Mira (commerce), duc Corvin (foi), duc Lyonel (intrigues), duchess Sylka (marché du nord) — chacun réclame la couronne. Un messager épuisé annonce des pillards aux frontières et des lumières vertes au-dessus du fort de Brume-noire. Le régent provisoire demande aux aventuriers d\'enquêter avant que le royaume ne se déchire.',
        },
        {
          title: 'Acte I — La route des réfugiés',
          content: 'Sur la grand-route sud, des colonnes de paysans fuient vers Valdris. Ils parlent de « soldats sans visage » la nuit et de récoltes brûlées. Un convoi de la duchesse Mira est attaqué ; survivants implorent protection. Choix difficile : escorter les réfugiés (perte de temps) ou foncer vers le nord. Indices : une bannière arrachée porte le sigil du duc Lyonel — ou un faux.',
        },
        {
          title: 'Acte I — Première nuit aux murailles',
          content: 'Le fortin de Garde-Haute abrite le groupe pour la nuit. Le capitaine Elwen montre des flèches noircies trouvées sur les cadavres. À minuit, une attaque de créatures en lambeaux teste les remparts. Au matin, un éclaireur rapporte que les runes du pont de Brume-noire brillent faiblement — signe que le Sceau du Nord s\'affaiblit.',
        },
        {
          title: 'Acte II — Le fort de Brume-noire',
          content: 'Forteresse en ruine sur un éperon rocheux. La garnison est réduite de moitié ; le commandant Torval affirme avoir vu le Roi Corbeau dans ses rêves — entité légendaire scellée sous la montagne. Sous la chapelle, une porte de fer gravée de chaînes fissurées pulse. Il faudra plusieurs explorations pour comprendre l\'étendue du danger.',
        },
        {
          title: 'Acte II — Les runes fissurées',
          content: 'Crypte sous le fort : runes naines et elfiques entremêlées, datant de l\'Alliance des Trois Couronnes. Un grimoire poussiéreux explique que le sceau demande un « serment renouvelé » du titulaire légitime d\'Aldermar — ou se brisera en sept lunes. Quelqu\'un a gratté trois runes récemment. Piste vers la bibliothèque royale de Valdris.',
        },
        {
          title: 'Acte II — Le village des Sans-Nom',
          content: 'Hameau oublié dans la vallée, habitants terrifiés, enfants qui dessinent le même corbeau à trois yeux. La chamane Oldra connaît la légende : le premier roi scella son frère jumeau corrompu par une entité du Gouffre. Elle peut guider le groupe vers Keldorm, cité naine où reposent les archives du serment.',
        },
        {
          title: 'Acte II — L\'ambassade naine de Keldorm',
          content: 'Tunnels lumineux, forge éternelle, négociations tendues. L\'archiviste Thrain montre le Traité de Cendres : seul un roi couronné à Valdris avec les trois reliques peut renouveler le sceau. Problème : les reliques (épée, anneau, calice) ont été dispersées après la guerre civile d\'il y a cent ans. Thrain soupçonne le duc Corvin d\'en cacher une.',
        },
        {
          title: 'Acte II — Trahison aux ponts de Sel',
          content: 'Retour vers le sud : le pont stratégique de Sel est occupé par les hommes du duc Lyonel, qui exige la capture du groupe « pour le bon ordre du royaume ». Combat, négociation ou détour dangereux par les marécages. Un prisonnier révèle que Lyonel négocie en secret avec des cultistes du Gouffre — il croit pouvoir contrôler le Roi Corbeau.',
        },
        {
          title: 'Acte III — Siège de la citadelle d\'Or',
          content: 'Valdris bascule en guerre ouverte : Harald assiège la citadelle d\'Or où Mira a barricadé les entrepôts royaux. Le groupe doit traverser les lignes, négocier un cessez-le-feu ou voler les provisions. Dans les caves, première relique : l\'Anneau du Serment, gardé par un golem de cire mélée.',
        },
        {
          title: 'Acte III — La bibliothèque des rois maudits',
          content: 'Retour au palais — section interdite. Manuscrits racontent la chute du jumeau corrompu, Corvus. Sylka y est déjà, cherchant la vérité pour le nord. Ensemble ou en rivalité, vous découvrez que le roi mort a été empoisonné par le culte — la marque noire est une malédiction qui accélère la rupture du sceau. Deuxième relique : le Calice des Larmes, dissimulé dans un tombeau familial.',
        },
        {
          title: 'Acte III — Le pacte oublié',
          content: 'Corvin convoque le groupe en cathedrale : il possède l\'Épée de l\'Aube, troisième relique, mais refuse de la remettre sans garanties pour l\'Église. Révélation : le grand prêtre cache un cultiste parmi ses novices. Purifier la cathédrale ou forcer la main au duc — conséquences durables sur la confiance du peuple.',
        },
        {
          title: 'Acte III — Marche des ombres',
          content: 'Le Gouffre exhale des brumes ; des villages entiers somnolent d\'un sommeil sans fin. Le groupe mène une expédition nocturne pour sauver Oldra et récupérer un artefact de liaison. Première confrontation avec un avatar mineur du Roi Corbeau — il parle avec la voix du roi défunt. « Mon frère m\'a trahi une fois. Renouvelez le serment… ou rejoignez-moi. »',
        },
        {
          title: 'Acte IV — Bataille des champs de cendre',
          content: 'Armées des ducs s\'affrontent près de Brume-noire pendant que le ciel se déchire. Lyonel lance ses cultistes dans la mêlée. Objectif : tenir le pont jusqu\'à ce que le rituel de renouvellement soit possible, empêcher Lyonel d\'atteindre le fort, rallier au moins deux ducs à la cause du sceau. Session épique — plusieurs vagues, choix tactiques, pertes possibles.',
        },
        {
          title: 'Acte IV — Le trône vide',
          content: 'Valdris en chaos. Le régent est mort ; le trône est vacant. Le groupe doit convoquer un parlement d\'urgence : qui sera roi ou reine ? Un candidat doit accepter le fardeau du serment. Intrigue finale : Sylka propose un royaume partagé ; Harald veut la couronne par le sang ; Mira offre de financer la reconstruction. Les choix ici façonnent la fin.',
        },
        {
          title: 'Acte IV — Descente dans le Gouffre Scellé',
          content: 'Le sceau cède malgré tout — fissure centrale sous Brume-noire. Descente en plusieurs niveaux : vestiges de l\'ancien empire, pièges, échos du passé (visions du jumeau et du premier roi). Lyonel attend au seuil, fusionné partiellement avec l\'ombre. Boss intermédiaire avant le cœur du gouffre.',
        },
        {
          title: 'Acte V — Le cœur du sceau',
          content: 'Chambre primordiale : le Roi Corbeau enchaîné, colossal, lucide et fou. Combat final ou négociation selon les reliques et le serment. Trois issues majeures : renouveler le sceau (sacrifice du souverain), détruire Corvus au prix d\'une cicatrice sur le royaume, ou sceller à nouveau en exilant le nouveau roi dans la pierre. Conséquences narrées pour les générations futures.',
        },
        {
          title: 'Acte V — Couronnement ou cendres',
          content: 'Épilogue ouvert : couronnement à Valdris, funérailles nationales, reconstruction du nord, ou royaume fragmenté si l\'échec est total. Le MJ IA prolonge les quêtes annexes (déserteurs, cultes résiduels, reconstruction de Keldorm). Campagne conçue pour se terminer ici ou continuer en épilogue libre sur plusieurs sessions supplémentaires.',
        },
      ],
      npcs: [
        {
          name: 'Commandant Torval',
          role: 'Garde du nord',
          description: 'Vétéran du fort de Brume-noire, hanté par des visions. Loyal au royaume, pas à un duc en particulier.',
        },
        {
          name: 'Duc Lyonel de Sel',
          role: 'Antagoniste politique',
          description: 'Maître des intrigues, pactise avec le culte du Gouffre. Croit dompter le Roi Corbeau pour s\'emparer du trône.',
        },
        {
          name: 'Duchesse Sylka du Nord',
          role: 'Alliée potentielle',
          description: 'Pragmatique, protège son peuple contre les brumes. Veut un royaume où le nord ne soit plus oublié.',
        },
        {
          name: 'Duc Harald le Martel',
          role: 'Factions / guerre',
          description: 'Général brutal, veut la couronne par conquest. Respecte la force ; peut être rallié si on le bat ou lui sauve la face.',
        },
        {
          name: 'Archiviste Thrain de Keldorm',
          role: 'Informateur',
          description: 'Nain érudit, garde les secrets du Traité de Cendres. Exige des preuves avant de révéler chaque parcelle du rituel.',
        },
        {
          name: 'Oldra la chamane',
          role: 'Guide spirituelle',
          description: 'Ancienne du village des Sans-Nom, connaît la vraie histoire des jumeaux rois. Peut être possédée si le groupe tarde.',
        },
        {
          name: 'Grand prêtre Alaric',
          role: 'Autorité religieuse',
          description: 'Chef de la foi d\'Aldermar, possède des indices sur le Calice. Son ordre cache un traître cultiste.',
        },
        {
          name: 'Le Roi Corbeau (Corvus)',
          role: 'Antagoniste final',
          description: 'Jumeau scellé du premier roi, fusionné avec une entité du Gouffre. Offre pouvoir, vérité ou destruction selon les choix du groupe.',
        },
        {
          name: 'Capitaine Elwen',
          role: 'Alliée militaire',
          description: 'Officier de Garde-Haute, compétente et directe. Peut commander des renforts si le groupe gagne sa confiance.',
        },
      ],
    },
    {
      id: 'demo-tour-mage',
      title: 'La Tour du Mage Fou',
      synopsis: 'L\'archimage Theron s\'est enfermé dans sa tour depuis des mois. Des éclairs colorent le ciel chaque nuit. La guilde des mages envoie une équipe enquêter.',
      setting: 'Tour de magie flottante au-dessus d\'une falaise, salles impossibles, gravité capricieuse.',
      scenes: [
        {
          title: 'Le portail d\'entrée',
          content: 'Une porte flottante pose une énigme en runes : « Je parle sans bouche, j\'entends sans oreilles. Qui suis-je ? » Répondre correctement ouvre le passage.',
        },
        {
          title: 'Le laboratoire renversé',
          content: 'Le plafond est le sol. Des fioles flottent. Un golem de cire patrouille. Des notes de Theron mentionnent une « fusion interdite ».',
        },
        {
          title: 'Le sommet de la tour',
          content: 'Theron flotte en lotus, entouré de sphères d\'énergie. Il n\'est pas fou — il retient quelque chose qui veut entrer dans notre monde.',
        },
      ],
      npcs: [
        {
          name: 'Archimage Theron',
          role: 'Mage / garde',
          description: 'Excentrique mais lucide. Il teste les visiteurs avant de leur confier la vérité.',
        },
        {
          name: 'Pip le familier',
          role: 'Guide comique',
          description: 'Chat parlant qui connaît les pièges de la tour — pour un prix (fromage ou flatterie).',
        },
      ],
    },
    {
      id: 'demo-pirates',
      title: 'Piraterie sur la Mer d\'Argent',
      synopsis: 'Le capitaine Morgane recherche l\'île du Crâne d\'Or, où le légendaire corsaire Noirval aurait caché son butin. Rivalité entre équipages, tempête et créatures marines au programme.',
      setting: 'Océan déchaîné, galion pirate, île tropicale avec grottes et récifs.',
      scenes: [
        {
          title: 'Le port de Brinecove',
          content: 'Taverne bruyante, rumeurs de trésor, recrutement d\'équipage. Un vieux loup de mer vend une carte moitié brûlée. Un rival pirate est déjà en mer.',
        },
        {
          title: 'Tempête et mutinerie',
          content: 'La mer se déchaîne. Une partie de l\'équipage veut rebrousser chemin. Un kraken juvénile attaque la coque pendant l\'ouragan.',
        },
        {
          title: 'L\'île du Crâne d\'Or',
          content: 'Une plage de sable noir, une grotte marquée d\'un crâne doré. Le trésor est là — mais Noirval l\'a laissé piégé, et le rival n\'est pas loin.',
        },
      ],
      npcs: [
        {
          name: 'Capitaine Morgane',
          role: 'Alliée / leader',
          description: 'Pirate charismatique, cherche le trésor pour sauver son équipage de la ruine.',
        },
        {
          name: 'Barbe-Rousse Kael',
          role: 'Rival',
          description: 'Capitaine rival impitoyable. Il préfère couler ses ennemis que partager le butin.',
        },
      ],
    },
    {
      id: 'demo-forgefer',
      title: 'La Révolte de Forgefer',
      synopsis: 'Dans la cité naine de Forgefer, les forgerons se rebellent contre le thane corrompu. Les aventuriers arrivent au pire moment — choisir un camp ou tenter de rétablir la paix.',
      setting: 'Citadelle souterraine, forges incandescentes, couloirs de pierre et halls de marbre nain.',
      scenes: [
        {
          title: 'Les basses-forges',
          content: 'Ouvriers en grève, gardes nerveux. Des affiches appellent à renverser le thane. Un explosif a été volé dans l\'arsenal.',
        },
        {
          title: 'Le trône de pierre',
          content: 'Audience tendue avec le thane Durin. Il accuse les rebelles de sabotage. Une preuve de corruption pourrait basculer la situation.',
        },
        {
          title: 'Le grand creuset',
          content: 'La révolte éclate. Feu, fumée, combats dans les ruelles de la cité. Le destin de Forgefer se joue autour du creuset ancestral.',
        },
      ],
      npcs: [
        {
          name: 'Thane Durin Ferpoing',
          role: 'Antagoniste / autorité',
          description: 'Chef corrompu qui taxe les forgerons. Il cache des contrats avec des marchands surface.',
        },
        {
          name: 'Helga Brise-enclume',
          role: 'Cheffe rebelle',
          description: 'Forgère respectée qui veut justice, pas anarchie. Elle peut devenir alliée si on lui apporte des preuves.',
        },
      ],
    },
  ],

  /** Scénarios dédiés au mode enquête */
  INVESTIGATION_SCENARIOS: [
    {
      id: 'inv-demo-bal-masque',
      roster: 'investigation',
      title: 'Le Meurtre au Bal Masqué',
      synopsis: 'Lors d\'un bal masqué au manoir de Lavière, le baron est retrouvé poisonné dans la bibliothèque. Cinq invités ont un mobile — et personne n\'a quitté la salle avant le drame.',
      setting: 'Manoir de Lavière, nuit d\'hiver, bougies, masques vénitiens, orchestre étouffé par la panique.',
      mystery: 'Qui a empoisonné le baron ? Quel masque cachait le coupable ?',
      scenes: [
        {
          title: 'La découverte du corps',
          content: 'Le baron Lavière gît près du bureau, une coupe renversée à la main. L\'odeur d\'amandes amères flotte dans la bibliothèque. Le majordome Henri a verrouillé les portes sur ordre de la comtesse. Six masques sont posés sur le piano — chacun correspond à un invité encore présent.',
        },
        {
          title: 'Interrogatoires au salon',
          content: 'Les invités sont rassemblés sous la tapisserie des Valenwood. La comtesse Eliane pleure ; le docteur Morvan examine les symptômes ; le capitaine Rourke clame son innocence. Une plume d\'écriture appartenant au baron porte une note partielle : « Ce soir je révèle… »',
        },
        {
          title: 'La bibliothèque — fouille',
          content: 'Derrière une étagère basculante, un coffre contient des lettres compromettantes. Une fenêtre entrouverte laisse une empreinte de boue sur le rebord — impossible sans échelle. Un journal intime du baron mentionne un chantage et un rendez-vous à minuit.',
        },
        {
          title: 'Les cuisines et le poison',
          content: 'La cuisinière Marthe jure n\'avoir servi que du vin de la cave. Une fiole vide se cache dans le garde-manger, étiquetée en latin. Le docteur identifie de l\'aconit — rare, réservé à son cabinet. Qui y a eu accès cette semaine ?',
        },
        {
          title: 'Le jardin gelé',
          content: 'Des traces mènent jusqu\'à la serre abandonnée. Un masque brisé gît dans la neige — pas celui du baron. Une échelle portative manque au hangar. Un témoin affirme avoir vu une silhouette en domino noir traverser le couloir est.',
        },
        {
          title: 'Confrontation finale',
          content: 'Les indices convergent : alibi contradictoires, mobile financier, jalousie, secret de famille. Il est temps de réunir les suspects, présenter les preuves et désigner le coupable — ou révéler une vérité plus sombre que prévu.',
        },
      ],
      npcs: [
        {
          name: 'Comtesse Eliane de Lavière',
          role: 'Suspecte / veuve',
          description: 'Élégante, froide sous le choc. Elle hérite du manoir. Son alibi : elle dansait au salon — mais personne ne l\'a vue pendant dix minutes.',
        },
        {
          name: 'Docteur Morvan',
          role: 'Suspect / expert',
          description: 'Médecin de campagne, connaît les poisons. Il a quitté le bal « pour prendre l\'air ». Il détenait de l\'aconit dans son cabinet.',
        },
        {
          name: 'Capitaine Rourke',
          role: 'Suspect / créancier',
          description: 'Officier en retraite, endetté envers le baron. Il menace souvent de « régler ses comptes ». Porte un masque de renard.',
        },
        {
          name: 'Henri le majordome',
          role: 'Témoin clé',
          description: 'Serviteur loyal de vingt ans. Il a servi le vin et verrouillé les portes. Il sait qui est monté à la bibliothèque — mais hésite à parler.',
        },
        {
          name: 'Marthe la cuisinière',
          role: 'Témoin',
          description: 'Nerveuse, protège son neveu apprenti. Elle a vu quelqu\'un entrer dans la cave aux vins avant le bal.',
        },
      ],
    },
    {
      id: 'inv-demo-brumeval',
      roster: 'investigation',
      title: 'Disparition à Brumeval',
      synopsis: 'La fille du boulanger a disparu sans laisser de trace. Le village murmure malédiction, rançon ou fugue. L\'enquête mène des ruelles brumeuses à la lisière de la forêt.',
      setting: 'Village de Brumeval, brume matinale, cloches lointaines, rumeurs et secrets de voisinage.',
      mystery: 'Où est Léna ? Kidnapping, accident ou départ volontaire ?',
      scenes: [
        {
          title: 'La boulangerie',
          content: 'La mère Simone pleure devant un lit intact. La fenêtre est entrouverte, une écharpe arrachée au clou. Sur la table, un mot cryptique : trois chiffres grattés à la hâte. Le père accuse le garde du poste de négligence.',
        },
        {
          title: 'La place du village',
          content: 'Les commerçants se disputent. Le tavernier Gérard prétend avoir vu Léna partir vers la forêt à l\'aube avec un manteau gris. La vieille Thérèse parle d\'une lumière près du cimetière. Un jouet en bois gît près du puits — est-ce le sien ?',
        },
        {
          title: 'Le cimetière et la dalle',
          content: 'Une dalle récemment bougée près du mausolée des Aubry. Des traces de petits pas mènent vers une crypte entrouverte. Eldric le fossoyeur avoue avoir entendu des voix la nuit dernière — il n\'a rien dit par peur.',
        },
        {
          title: 'La maison du garde',
          content: 'Le garde Tomas nie toute faute. Son registre de ronde comporte une page arrachée. Une clef rouillée manque à son trousseau. Sa fille admet que Tomas connaissait Léna « en secret » — relation interdite par les parents.',
        },
        {
          title: 'La lisière de la forêt',
          content: 'Un campement abandonné : cendres encore tièdes, empreintes de bottes adultes et d\'enfant. Une bouteille porte une marque de marchands itinérants. Un passage vers une grotte est dissimulé sous des branchages.',
        },
        {
          title: 'La vérité dans la brume',
          content: 'Les témoignages se contredisent : rançon, enlèvement rituel, ou fuite avec un amoureux. Les indices matériels tranchent — si l\'équipe sait les recouper. Léna est vivante… pour l\'instant.',
        },
      ],
      npcs: [
        {
          name: 'Simone la boulangère',
          role: 'Mère / plaignante',
          description: 'Épuisée, méfiante envers les étrangers. Elle cache que Léna recevait des lettres qu\'elle brûlait.',
        },
        {
          name: 'Gérard le tavernier',
          role: 'Témoin / rumeur',
          description: 'Aime le sensationnalisme. Il exagère peut-être ce qu\'il a vu pour attirer l\'attention.',
        },
        {
          name: 'Tomas le garde',
          role: 'Suspect',
          description: 'Amoureux secret de Léna. Il a des trous dans son alibi et des pages manquantes dans son registre.',
        },
        {
          name: 'Eldric le fossoyeur',
          role: 'Témoin',
          description: 'Vieil homme superstitieux. Il connaît les passages sous le cimetière — personne ne l\'écoute.',
        },
        {
          name: 'Thérèse la sage-femme',
          role: 'Informateur',
          description: 'Connaît tous les secrets du village. Elle insinue qu\'une « société » se réunit près de la crypte.',
        },
      ],
    },
    {
      id: 'inv-demo-alchimiste',
      roster: 'investigation',
      title: 'Le Poison du Grand Alchimiste',
      synopsis: 'Maître Aldric, alchimiste réputé, est mort dans son laboratoire verrouillé de l\'intérieur. Suicide, accident ou meurtre par procuration ? Ses trois apprentis et son rival ont tout à y gagner.',
      setting: 'Tour-laboratoire d\'Aldric, fumées acides, grimoires, fioles étiquetées, ville universitaire en contrebas.',
      mystery: 'Comment le poison est-il entré dans une pièce verrouillée ?',
      scenes: [
        {
          title: 'Le laboratoire scellé',
          content: 'Aldric est affalé sur son bureau, lèvres bleuies. La porte était verrouillée de l\'intérieur, la clef dans la serrure. Une fiole de cyanure brisée sur le sol. Les fenêtres sont scellées depuis des années — sauf une trappe d\'aération au plafond.',
        },
        {
          title: 'Les apprentis',
          content: 'Lysa, Bram et Petronille sont interrogés séparément. Lysa veut reprendre le laboratoire ; Bram a volé des formules ; Petronille était amoureuse d\'Aldric. Chacun a un motif, chacun a un alibi partiel pour la nuit du décès.',
        },
        {
          title: 'Le grimoire des formules',
          content: 'Une page arrachée concernait un « élixir de silence » — poison retardé. Des taches chimiques sur le rebord de la fenêtre intérieure. Un parchemin signé par le rival Zephon menace Aldric de ruine publique.',
        },
        {
          title: 'La trappe d\'aération',
          content: 'La gaine mène au toit puis à la cheminée voisine — appartement de Zephon. Des traces de suie fraîche. Un mécanisme de corde permettrait de descendre un objet sans entrer. Un bout de gants brûlé gît sur le toit.',
        },
        {
          title: 'L\'apothicaire du quartier',
          content: 'Le marchand de produits rares confirme une vente de cyanure — signature illisible. Un témoin a vu un apprenti en cape noire la veille. Les registres de la guilde des mages mentionnent une dette d\'Aldric envers Zephon.',
        },
        {
          title: 'Reconstitution du crime',
          content: 'Locked room : suicide simulé, empoisonnement différé, ou complice dans la tour voisine ? Les preuves physiques et les témoignages permettent de reconstruire la méthode — et de nommer le coupable.',
        },
      ],
      npcs: [
        {
          name: 'Lysa l\'apprentie',
          role: 'Suspecte',
          description: 'Ambitieuse, froide. Elle hériterait du laboratoire si Aldric n\'avait pas changé son testament la veille.',
        },
        {
          name: 'Bram l\'apprenti',
          role: 'Suspect',
          description: 'Maladroit, endetté. Il a copié des formules pour un acheteur inconnu.',
        },
        {
          name: 'Petronille',
          role: 'Suspecte / témoin',
          description: 'Sensible, jalouse de Lysa. Elle affirme avoir entendu des pas sur le toit à minuit.',
        },
        {
          name: 'Zephon le rival',
          role: 'Suspect principal',
          description: 'Alchimiste vaniteux, voisin de tour. Son alibi est faible ; il avait accès au toit commun.',
        },
        {
          name: 'Maître Corbin',
          role: 'Autorité / témoin',
          description: 'Représentant de la guilde. Il possède une copie du testament et connaît les rivalités.',
        },
      ],
    },
    {
      id: 'inv-demo-oracle',
      roster: 'investigation',
      title: 'L\'Oracle Silencieux',
      synopsis: 'Dans le quartier des temples, un prêtre oracle a été retrouvé muet et marqué de symboles. Culte, rivalité religieuse ou machination politique ? Les fidèles exigent des réponses.',
      setting: 'Temple d\'Ilyra, encens, mosaïques, sous-sols interdits, cité portuaire agitée.',
      mystery: 'Qui a réduit l\'oracle au silence — et pourquoi ces symboles sur sa peau ?',
      scenes: [
        {
          title: 'Le sanctuaire profané',
          content: 'Le prêtre Orin est assis devant l\'autel, vivant mais incapable de parler. Des symboles arcanaïques sont gravés sur ses avant-bras — encre ou brûlure ? L\'offrande du matin a été renversée. Une porte du sanctuaire menant aux cryptes est entrouverte.',
        },
        {
          title: 'Les prêtresses et le schisme',
          content: 'Sœur Maelis dirige la faction orthodoxe ; le frère Kael prêche une réforme. Chacun accuse l\'autre de profanation. Un registre des visiteurs liste un sénateur, une marchande et un inconnu masqué hier soir.',
        },
        {
          title: 'Les cryptes sous le temple',
          content: 'Couloirs humides, fresques effacées. Un cercle de sel brisé au sol. Des bougies récentes. Un grimoire interdit manque à la niche scellée. Des traces de pas légères remontent vers une trappe de service.',
        },
        {
          title: 'Le marché des reliques',
          content: 'La marchande Yara vend des amulettes « bénies ». Elle a vu Orin argumenter avec un client la veille. Une fausse relique porte le même symbole que sur le bras du prêtre — vendue par un colporteur au domino bleu.',
        },
        {
          title: 'Le sénateur Vorn',
          content: 'Le politicien nie être venu au temple — pourtant il est inscrit au registre. Son chasseur admet l\'avoir accompagné « pour des conseils privés ». Vorn profitait des prophéties d\'Orin pour manipuler les élections.',
        },
        {
          title: 'Révélation au clair de lune',
          content: 'Rituel interrompu, culte clandestin ou vengeance personnelle ? Les symboles mènent à un artisan tatoueur ou à un sort de silence. Orin peut peut-être encore communiquer par écrit — s\'il ose.',
        },
      ],
      npcs: [
        {
          name: 'Prêtre Orin',
          role: 'Victime / témoin muet',
          description: 'Oracle respecté, terrifié. Il peut écrire des mots simples si on lui fait confiance.',
        },
        {
          name: 'Sœur Maelis',
          role: 'Suspecte',
          description: 'Conservatrice rigide. Elle voulait exiler Orin pour ses prophéties trop libres.',
        },
        {
          name: 'Frère Kael',
          role: 'Suspect',
          description: 'Réformateur charismatique. Des fidèles jurent l\'avoir vu dans les cryptes après la cloche du soir.',
        },
        {
          name: 'Yara la marchande',
          role: 'Témoin',
          description: 'Pragmatique, informée. Elle traque le colporteur au domino bleu pour d\'autres raisons.',
        },
        {
          name: 'Sénateur Vorn',
          role: 'Suspect',
          description: 'Politicien lisse, menteur habile. Les prophéties d\'Orin menaçaient sa campagne.',
        },
      ],
    },
    {
      id: 'inv-demo-train',
      roster: 'investigation',
      title: 'Le Crime du Train de Minuit',
      synopsis: 'Le train de luxe « Étoile du Nord » est immobilisé par une tempête de neige. Un passager est retrouvé mort dans son compartiment verrouillé — et chaque voyageur de la voiture-restaurant a un secret.',
      setting: 'Train art déco, nuit d\'hiver, neige, lumière tamisée, tension claustrophobique entre passagers.',
      mystery: 'Qui a tué le banquier Hoffmann — et comment le meurtrier a-t-il quitté un compartiment verrouillé ?',
      scenes: [
        {
          title: 'Arrêt forcé en pleine neige',
          content: 'Le convoi est bloqué entre deux gares. Le contrôleur Voss annonce qu\'un passager de la première classe est mort. La police la plus proche n\'arrivera qu\'à l\'aube. Les sept passagers de la voiture-restaurant sont invités à rester dans le salon — personne ne descend.',
        },
        {
          title: 'Le compartiment 7',
          content: 'Hoffmann gît sur son lit, une plaie nette. La porte était verrouillée de l\'intérieur, la fenêtre entrouverte sur le vide. Une mallette contient des dossiers compromettants sur chaque passager du train. Une carte à jouer — le valet de pique — est posée sur le corps.',
        },
        {
          title: 'Interrogatoire au salon',
          content: 'La comtesse, l\'inventeur, la veuve, le prêtre, la journaliste et le marchand d\'art se contredisient sur les horaires. Voss le contrôleur possède une clef passe-partout. Chacun a quitté le salon « une minute » pendant le dîner.',
        },
        {
          title: 'La voiture-bagages',
          content: 'Une valise ouverte contient un manteau taché et un couteau de chasse propre. Des empreintes sur la trappe du toit mènent à la voiture suivante. Un billet falsifié porte un nom différent de celui d\'un passager présent.',
        },
        {
          title: 'La cabine du conducteur',
          content: 'Le mécanicien admet avoir ralenti volontairement avant l\'arrêt — on lui a payé. Un télégramme non envoyé mentionne une rançon. Le journal de bord du train comporte une page arrachée.',
        },
        {
          title: 'Révélation avant l\'aube',
          content: 'La tempête faiblit. Il faut accuser ou laisser filer le coupable au prochain départ. Les alibis, la mallette de Hoffmann et la carte à jouer convergent vers une vérité que personne n\'avouera facilement.',
        },
      ],
      npcs: [
        {
          name: 'Contrôleur Voss',
          role: 'Suspect / témoin',
          description: 'Sévère, connaît chaque compartiment. Il possède des passe et cache une dette envers Hoffmann.',
        },
        {
          name: 'Comtesse Adèle',
          role: 'Suspecte',
          description: 'Voyage en secret. Hoffmann menaçait de révéler une fausse identité qui lui permet d\'hériter.',
        },
        {
          name: 'Inventeur Karl Bren',
          role: 'Suspect',
          description: 'Nerveux, brevet volé par Hoffmann. Il a quitté le salon pendant le dessert.',
        },
        {
          name: 'Père Anselme',
          role: 'Témoin / suspect',
          description: 'Prêtre discret. Il a entendu une dispute dans le couloir — mais refuse de dire entre qui.',
        },
        {
          name: 'Journaliste Nora Pike',
          role: 'Suspecte / alliée',
          description: 'Enquête sur Hoffmann depuis des mois. Elle possède des copies des dossiers de la mallette.',
        },
      ],
    },
    {
      id: 'inv-demo-serpent-noir',
      roster: 'investigation',
      questFormat: 'long',
      title: 'L\'Affaire du Serpent Noir',
      synopsis: 'Enquête longue sur 10 à 15 sessions (plusieurs semaines) : à Marée-Haute, des meurtres rituels marqués d\'un serpent noir secouent la ville. Corruption policière, société secrète et secrets de famille — l\'équipe doit démêler une conspiration avant la prochaine victime.',
      setting: 'Port de Marée-Haute — brumes salées, entrepôts, université, quartier noble, égouts et phare abandonné. Époque fin de siècle / fantasy urbaine.',
      mystery: 'Qui dirige le culte du Serpent Noir ? Quel est le lien entre les victimes — et qui protège le tueur au sein de la ville ?',
      scenes: [
        {
          title: 'Acte I — Cadavre sur le quai 7',
          content: 'À l\'aube, un pêcheur trouve le corps du notaire Fontaine, marque de serpent gravée dans le dos. Le commissaire Varenne veut classer l\'affaire « bandits du port ». La presse s\'enflamme. Le groupe est mandaté par le préfet ou contacté en secret par la journaliste Nora Pike — première liste de témoins et accès limité à la scène de crime.',
        },
        {
          title: 'Acte I — Autopsie et première trace',
          content: 'Le légiste Dr. Selim révèle : victime droguée avant la mise en scène rituelle, poison rare d\'origine orientale. Dans la poche du notaire, un billet pour le bal de la Fondation Hale. Une écaille de métal noir, pas biologique, est retrouvée sous l\'ongle de la victime — artefact ou bijou de culte ?',
        },
        {
          title: 'Acte I — Le bal masqué de la Fondation',
          content: 'Soirée charitable des élites : tous les suspects se croisent en masques. Le banquier Hale, la veuve Fontaine, le professeur Orin, le capitaine des docks Mercier. Une serveuse glisse un pli : « Ne faites pas confiance à Varenne. » Un domino noir quitte la salle par la terrasse — poursuite possible ou perte de piste.',
        },
        {
          title: 'Acte I — Archives du port',
          content: 'Registres des navires : trois cargaisons « textiles » sans manifeste complet, capitaine Mercier signataire. Correspondance chiffrée dans un coffre administratif. Un clerk est retrouvé battu — il murmure « le Serpent paie en or et en silence » avant de perdre connaissance.',
        },
        {
          title: 'Acte II — Deuxième victime : le professeur',
          content: 'Orin est retrouvé dans son bureau universitaire, même marque. Ses notes portent sur les cultes maritimes oubliés. Un étudiant discret, Lio, admet qu\'Orin recevait des menaces depuis qu\'il enquêtait sur la Fondation Hale. Vol de carnets — piste vers la bibliothèque interdite.',
        },
        {
          title: 'Acte II — Bibliothèque des marées',
          content: 'Manuscrits sur le « Serpent des profondeurs », secte liée aux marées et aux sacrifices de notables corrompus. Symboles identiques à la marque des victimes. Une page arrachée mentionne un « nid » sous le phare. Garde archiviste corrompu — pot-de-vin ou intimidation à découvrir.',
        },
        {
          title: 'Acte II — Interrogatoire du commissaire Varenne',
          content: 'Varenne bloque l\'accès aux dossiers. Témoignages de flics honnêtes : plaintes classées sans suite, témoins menacés. Surveillance du commissariat : rendez-vous nocturne avec un homme encapuchonné. Mandat ou infiltration pour obtenir preuves de complicité.',
        },
        {
          title: 'Acte II — Les docks la nuit',
          content: 'Filature de Mercier : entrepôt 14, chants étouffés, cadavres d\'animaux disposés en cercle. Combat ou infiltration. Documents liant la Fondation Hale à des « cotisations occultes ». Mercier s\'échappe ou est capturé — il parle d\'un « Messager » plus haut placé.',
        },
        {
          title: 'Acte III — La veuve et l\'héritage',
          content: 'Madame Fontaine hérite d\'une fortune si l\'enquête s\'arrête. Contradictions dans son alibi. Testament du notaire léguant des terres au phare — terrains inexploitables selon la ville, mais registre cadastral secret dit autre chose. Jalousie, argent, ou complicité forcée ?',
        },
        {
          title: 'Acte III — Le témoignage du prêtre',
          content: 'Père Aldric confesse avoir béni des « pèlerins nocturnes » sans comprendre. Il mène le groupe à une chapelle oubliée dans les égouts — fresques du serpent, autel récent. Quelqu\'un a laissé une lanterne encore chaude. Embuscade de cultistes ou fuite organisée.',
        },
        {
          title: 'Acte III — Nora Pike en danger',
          content: 'La journaliste publie un article partiel — son appartement est saccagé. Elle possède une liste de noms raturés retrouvée chez Orin. Protection, planque, ou appât pour attraper le Messager. Choix moral : exposer la vérité tout de suite ou creuser encore.',
        },
        {
          title: 'Acte III — Fausse piste : le syndicat des dockers',
          content: 'Syndicat accusé publiquement par Hale de terrorisme. En creusant, alibi solide mais haine légitime contre Fontaine qui les ruina. Le vrai coupable pourrait utiliser la colère populaire. Grève imminente — fenêtre pour une nouvelle victime pendant le chaos.',
        },
        {
          title: 'Acte IV — Descente dans les égouts',
          content: 'Réseau sous la ville : passages vers le phare, ossements anciens, chambre d\'initiation. Journaux du culte listant les « offrandes » sur vingt ans — noms de victimes futures dont un membre du conseil municipal. Course contre la montre.',
        },
        {
          title: 'Acte IV — Le phare abandonné',
          content: 'Île rocheuse à marée basse. Le phare abrite le nid du culte : salle circulaire, carte de Marée-Haute avec des croix sur des maisons nobles. Le Messager se révèle — identité selon indices (Hale, Varenne, ou figure surprise). Confrontation partielle, fuite vers le sanctuaire final.',
        },
        {
          title: 'Acte IV — Le conseil municipal',
          content: 'Session d\'urgence : le groupe présente preuves ou échoue à convaincre. Hale accuse le groupe de diffamation. Alliés politiques à mobiliser (préfet, Nora, flics loyaux). Arrestation ratée si le culte a des hommes dans la garde — émeute ou siège de l\'hôtel de ville.',
        },
        {
          title: 'Acte V — Sanctuaire sous la cathédrale',
          content: 'Dernière piste : crypte sous la cathédrale, jamais cartographiée. Cérémonie en cours — victime vivante sur l\'autel. Le Serpent Noir n\'est pas qu\'un symbole : relique ou entité invoquée. Infiltration silencieuse ou assaut — conséquences sur la réputation du groupe.',
        },
        {
          title: 'Acte V — Révélation du Serpent',
          content: 'Vérité finale : le culte protège un trafic d\'artefacts marins et élimine quiconque approche du secret des Hale. Mobile : pouvoir, immortalité rituelle, ou peur d\'une malédiction familiale. Le Messager avoue, se bat, ou se sacrifie. Plusieurs coupables possibles selon les preuves accumulées.',
        },
        {
          title: 'Acte V — Verdict de Marée-Haute',
          content: 'Épilogue : procès public, réforme de la police, chute de la Fondation, ou cover-up partiel si le groupe a échoué. Nora rédige la chronique ; Dr. Selim enterre les derniers secrets. Affaire classée ou cicatrice ouverte — le MJ IA peut prolonger en enquêtes annexes (survivants du culte, artefacts restants).',
        },
      ],
      npcs: [
        {
          name: 'Commissaire Varenne',
          role: 'Suspect / obstacle',
          description: 'Chef de police corrompu ou lâche, classe les meurtres. Protège quelqu\'un — ou tremble devant le culte.',
        },
        {
          name: 'Nora Pike',
          role: 'Alliée / journaliste',
          description: 'Enquête depuis des mois, possède des sources. Risque sa vie pour la vérité — mobile personnel à découvrir.',
        },
        {
          name: 'Dr. Selim',
          role: 'Expert légiste',
          description: 'Méticuleux, connaît les poisons rares. Cache peut-être un lien avec les victimes ou les Hale.',
        },
        {
          name: 'Banquier Hale',
          role: 'Suspect principal',
          description: 'Philanthrope en surface, patron de la Fondation. Chaque victime menaçait ses intérêts ou connaissait un secret.',
        },
        {
          name: 'Capitaine Mercier',
          role: 'Suspect / trafic',
          description: 'Contrôle les docks, signe des manifestes falsifiés. Peut être un pion ou un initié du culte.',
        },
        {
          name: 'Madame Fontaine',
          role: 'Suspecte / veuve',
          description: 'Héritière, calme trop parfaite. Aimait-elle son mari ? Savait-elle pour ses dettes envers le culte ?',
        },
        {
          name: 'Père Aldric',
          role: 'Témoin / guide',
          description: 'Prêtre troublé, a béni les cultistes sans le vouloir. Accès aux cryptes et à la conscience des pauvres.',
        },
        {
          name: 'Lio l\'étudiant',
          role: 'Témoin clé',
          description: 'Assistant d\'Orin, terrorisé. A vu qui entrait la nuit du meurtre du professeur — s\'il ose parler.',
        },
        {
          name: 'Le Messager',
          role: 'Antagoniste',
          description: 'Exécutant du culte, identité masquée jusqu\'à l\'acte IV. Obéit au « Serpent » — ou est la tête du serpent.',
        },
      ],
    },
  ],

  getInvestigationScenarios() {
    return this.list.filter((s) => s.roster === 'investigation');
  },

  getInvestigationOneshotScenarios() {
    return this.getInvestigationScenarios().filter((s) => s.questFormat !== 'long');
  },

  getInvestigationLongScenarios() {
    return this.getInvestigationScenarios().filter((s) => s.questFormat === 'long');
  },

  getGeneralScenarios() {
    return this.list.filter((s) => s.roster !== 'investigation');
  },

  getOneshotScenarios() {
    return this.getGeneralScenarios().filter((s) => (s.questFormat || 'oneshot') !== 'long');
  },

  getLongScenarios() {
    return this.getGeneralScenarios().filter((s) => s.questFormat === 'long');
  },

  isInvestigationScenario(scenarioOrId) {
    const id = typeof scenarioOrId === 'string' ? scenarioOrId : scenarioOrId?.id;
    const scenario = this.list.find((s) => s.id === id);
    return scenario?.roster === 'investigation';
  },

  /** Ajoute ou met à jour les scénarios d'exemple */
  ensureDemoScenario() {
    const UPDATED_DEMOS = ['demo-crypte', 'demo-manoir', 'demo-kharak', 'demo-couronne-fracturee'];
    const UPDATED_INVESTIGATION = [
      'inv-demo-bal-masque', 'inv-demo-brumeval', 'inv-demo-alchimiste',
      'inv-demo-oracle', 'inv-demo-train', 'inv-demo-serpent-noir',
    ];
    let changed = false;

    this.DEMO_SCENARIOS.forEach((demo) => {
      if (this.removedDemos.includes(demo.id)) return;
      const index = this.list.findIndex((s) => s.id === demo.id);
      if (index === -1) {
        this.list.push(JSON.parse(JSON.stringify(demo)));
        changed = true;
      } else if (UPDATED_DEMOS.includes(demo.id)) {
        this.list[index] = JSON.parse(JSON.stringify(demo));
        changed = true;
      }
    });

    this.INVESTIGATION_SCENARIOS.forEach((demo) => {
      if (this.removedDemos.includes(demo.id)) return;
      const index = this.list.findIndex((s) => s.id === demo.id);
      if (index === -1) {
        this.list.push(JSON.parse(JSON.stringify(demo)));
        changed = true;
      } else if (UPDATED_INVESTIGATION.includes(demo.id)) {
        this.list[index] = JSON.parse(JSON.stringify(demo));
        changed = true;
      }
    });

    if (changed) this.save();
  },

  init() {
    this.load();
    this.ensureDemoScenario();

    document.getElementById('btn-cancel-scenario')?.addEventListener('click', () => this.hideForm());
    document.getElementById('scenario-form-el')?.addEventListener('submit', (e) => this.handleSubmit(e));

    document.getElementById('btn-add-scene')?.addEventListener('click', () => {
      document.getElementById('scenes-list').appendChild(this.renderSceneItem());
    });

    document.getElementById('btn-add-npc')?.addEventListener('click', () => {
      document.getElementById('npcs-list').appendChild(this.renderNpcItem());
    });
  },
};
