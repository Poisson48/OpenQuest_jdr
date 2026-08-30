/**
 * scenarios.js — Gestion des scénarios et aventures.
 */

const Scenarios = {
  list: [],

  load() {
    this.list = Storage.load(Storage.KEYS.scenarios) || [];
  },

  save() {
    Storage.save(Storage.KEYS.scenarios, this.list);
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
    const container = document.getElementById('scenario-list');
    if (!container) return;

    if (this.list.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Aucun scénario pour l'instant.</p>
          <p>Clique sur « + Nouveau scénario » pour écrire ton aventure !</p>
        </div>`;
      return;
    }

    container.innerHTML = this.list.map((s) => {
      const inv = s.roster === 'investigation';
      return `
      <div class="card ${inv ? 'card-investigation' : ''}" data-id="${s.id}">
        ${inv ? '<span class="bot-badge inv-badge">🔍 Enquête</span>' : ''}
        <h3>${this.escape(s.title)}</h3>
        <p class="card-meta">${s.scenes.length} scène(s) · ${s.npcs.length} PNJ</p>
        ${s.mystery ? `<p class="inv-scenario-mystery">${this.escape(s.mystery)}</p>` : ''}
        <p style="font-size:0.9rem;color:var(--text-muted)">${this.escape(s.synopsis || 'Pas de synopsis').slice(0, 100)}${(s.synopsis || '').length > 100 ? '...' : ''}</p>
        <div class="card-actions">
          <button class="btn btn-secondary btn-edit" data-id="${s.id}">Modifier</button>
          <button class="btn btn-danger btn-delete" data-id="${s.id}">Supprimer</button>
        </div>
      </div>`;
    }).join('');

    container.querySelectorAll('.btn-edit').forEach((btn) => {
      btn.addEventListener('click', () => this.showForm(btn.dataset.id));
    });

    container.querySelectorAll('.btn-delete').forEach((btn) => {
      btn.addEventListener('click', () => this.delete(btn.dataset.id));
    });
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

    form.classList.remove('hidden');
    scenesList.innerHTML = '';
    npcsList.innerHTML = '';

    if (id) {
      const scenario = this.list.find((s) => s.id === id);
      if (!scenario) return;

      title.textContent = scenario.roster === 'investigation'
        ? 'Modifier le scénario d\'enquête'
        : 'Modifier le scénario';
      document.getElementById('scenario-id').value = scenario.id;
      document.getElementById('scenario-title').value = scenario.title;
      document.getElementById('scenario-synopsis').value = scenario.synopsis || '';
      document.getElementById('scenario-setting').value = scenario.setting || '';
      document.getElementById('scenario-mystery').value = scenario.mystery || '';
      if (rosterInput) rosterInput.value = scenario.roster || '';

      scenario.scenes.forEach((scene) => scenesList.appendChild(this.renderSceneItem(scene)));
      scenario.npcs.forEach((npc) => npcsList.appendChild(this.renderNpcItem(npc)));
    } else {
      const isInvestigation = options.roster === 'investigation';
      title.textContent = isInvestigation ? 'Nouveau scénario d\'enquête' : 'Nouveau scénario';
      document.getElementById('scenario-form-el').reset();
      document.getElementById('scenario-id').value = '';
      if (rosterInput) rosterInput.value = isInvestigation ? 'investigation' : '';
      if (isInvestigation) {
        document.getElementById('scenario-setting').value = 'Ville brumeuse, nuit, tension et secrets…';
      }
      scenesList.appendChild(this.renderSceneItem());
    }

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

    if (confirm(`Supprimer le scénario « ${scenario.title} » ?`)) {
      this.list = this.list.filter((s) => s.id !== id);
      this.save();
      this.renderList();
      if (typeof InvestigationRoster !== 'undefined') {
        InvestigationRoster.renderScenarios();
      }
    }
  },

  /** Scénarios d'exemple inclus avec l'application */
  DEMO_SCENARIOS: [
    {
      id: 'demo-crypte',
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
  ],

  getInvestigationScenarios() {
    return this.list.filter((s) => s.roster === 'investigation');
  },

  getGeneralScenarios() {
    return this.list.filter((s) => s.roster !== 'investigation');
  },

  isInvestigationScenario(scenarioOrId) {
    const id = typeof scenarioOrId === 'string' ? scenarioOrId : scenarioOrId?.id;
    const scenario = this.list.find((s) => s.id === id);
    return scenario?.roster === 'investigation';
  },

  /** Ajoute ou met à jour les scénarios d'exemple */
  ensureDemoScenario() {
    const UPDATED_DEMOS = ['demo-crypte', 'demo-manoir', 'demo-kharak'];
    const UPDATED_INVESTIGATION = [
      'inv-demo-bal-masque', 'inv-demo-brumeval', 'inv-demo-alchimiste',
      'inv-demo-oracle', 'inv-demo-train',
    ];
    let changed = false;

    this.DEMO_SCENARIOS.forEach((demo) => {
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
    this.renderList();

    document.getElementById('btn-new-scenario').addEventListener('click', () => this.showForm());
    document.getElementById('btn-cancel-scenario').addEventListener('click', () => this.hideForm());
    document.getElementById('scenario-form-el').addEventListener('submit', (e) => this.handleSubmit(e));

    document.getElementById('btn-add-scene').addEventListener('click', () => {
      document.getElementById('scenes-list').appendChild(this.renderSceneItem());
    });

    document.getElementById('btn-add-npc').addEventListener('click', () => {
      document.getElementById('npcs-list').appendChild(this.renderNpcItem());
    });
  },
};
