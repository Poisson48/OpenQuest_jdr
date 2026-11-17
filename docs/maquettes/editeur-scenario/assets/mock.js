/* OpenQuest JDR — maquettes éditeur de scénario
   Données du scénario de démo + moteur de graphe partagé (SVG, liens AU-DESSUS
   des cartes, peignes, survol, zoom/pan). Aucune dépendance externe. */

(function () {
  "use strict";

  const SCENARIO = {
    id: "demo-valbois",
    title: "Retour à Valbois",
    format: "One-shot",
    roster: "Aventure",
    synopsis: "Trois compagnons reviennent à Valbois. Une dette ancienne les y attend.",
    setting: "Village de Valbois au crépuscule. Place du Marché, ruelles mouillées, lanterne.",
    mystery: "Un bijou volé, un maire qui nie, un homme encapuchonné qui change de table.",
    start: "retour-a-valbois",
    selected: "place-du-marche",
    health: { scenes: 9, branches: 27, crossroads: 8, warnings: 0 },
    acts: [
      { id: "acte-1", title: "Acte I — Le retour", scenes: ["retour-a-valbois", "forge-brume", "place-du-marche", "taverne-cerf"] },
      { id: "acte-2", title: "Acte II — La dette", scenes: ["manoir-maire", "piste-bijou", "ruelles-nuit"] },
      { id: "acte-3", title: "Acte III — Le prix", scenes: ["confrontation-dette", "denouement"] },
    ],
    npcs: [
      { name: "Marta l'étalière", role: "Marchande", scenes: "place-du-marche, piste-bijou" },
      { name: "Renard", role: "Tavernier", scenes: "taverne-cerf" },
      { name: "Gareth", role: "Forgeron", scenes: "forge-brume" },
      { name: "Dame Élise", role: "Épouse du maire", scenes: "manoir-maire" },
      { name: "Capitaine Ord", role: "Garde", scenes: "place-du-marche, ruelles-nuit" },
      { name: "L'Homme encapuchonné", role: "Informateur", scenes: "taverne-cerf, confrontation-dette" },
      { name: "Maire Corbin", role: "Maire", scenes: "manoir-maire, confrontation-dette" },
      { name: "Tom le gamin", role: "Villageois", scenes: "retour-a-valbois, place-du-marche" },
    ],
    maps: ["Valbois — Village de l'Ouest", "La Place du Marché", "Cité des Saules"],
    scenes: [
      {
        id: "retour-a-valbois", title: "Le chemin du village", act: "acte-1", start: true,
        tags: ["surface", "village"], x: 40, y: 340,
        content: "La route de Valbois apparaît entre les arbres. Trois silhouettes remontent le chemin, crottées et silencieuses.",
        transitions: [
          { to: "place-du-marche", label: "Descendre vers la Place du Marché", default: true },
          { to: "taverne-cerf", label: "Couper par la Taverne du Cerf" },
          { to: "forge-brume", label: "Monter à la forge de Brume" },
        ],
      },
      {
        id: "forge-brume", title: "La Forge de Brume", act: "acte-1",
        tags: ["atelier"], x: 340, y: 80,
        content: "Les étincelles dansent. Gareth le forgeron vous tend un marteau d'occasion, sans un mot de plus.",
        transitions: [
          { to: "manoir-maire", label: "Livrer le marteau au manoir", default: true },
          { to: "place-du-marche", label: "Remonter à la place" },
          { to: "retour-a-valbois", label: "Redescendre au village", gmOnly: true },
        ],
      },
      {
        id: "place-du-marche", title: "La Place du Marché", act: "acte-1",
        tags: ["marché", "indice", "carrefour"], x: 340, y: 330,
        content: "Étals de fruits, draps, ferraille. La fontaine crachote. Marta fixe trop longtemps. Sous un banc, un chiffon brodé.",
        transitions: [
          { to: "piste-bijou", label: "Suivre la piste du chiffon", default: true },
          { to: "taverne-cerf", label: "Chercher des rumeurs à la taverne" },
          { to: "manoir-maire", label: "Monter au manoir du maire" },
          { to: "retour-a-valbois", label: "Revenir sur le chemin", gmOnly: true },
        ],
      },
      {
        id: "taverne-cerf", title: "La Taverne du Cerf", act: "acte-1",
        tags: ["taverne", "rumeur"], x: 340, y: 590,
        content: "L'odeur de bière et de pain grillé. Renard essuie un verre en évitant vos yeux. L'homme encapuchonné a laissé une lettre.",
        transitions: [
          { to: "piste-bijou", label: "Suivre les traces vers la halle", default: true },
          { to: "place-du-marche", label: "Retourner à la place" },
          { to: "ruelles-nuit", label: "Filer par les ruelles", gmOnly: true },
        ],
      },
      {
        id: "manoir-maire", title: "Le Manoir du Maire", act: "acte-2",
        tags: ["manoir", "négociation"], x: 680, y: 80,
        content: "Le maire ne reçoit pas. Surtout pas un voleur. Dame Élise garde la porte et les apparences.",
        transitions: [
          { to: "piste-bijou", label: "Suivre la piste par la grille", default: true },
          { to: "confrontation-dette", label: "Convoquer la confrontation" },
          { to: "ruelles-nuit", label: "Sortir par les ruelles", gmOnly: true },
          { to: "place-du-marche", label: "Rendre le chiffon à la place" },
        ],
      },
      {
        id: "piste-bijou", title: "La Piste du Bijou", act: "acte-2",
        tags: ["enquête"], x: 680, y: 330,
        content: "Le chiffon sent la paille et l'encens. Des traces fraîches filent vers les ruelles de nuit.",
        transitions: [
          { to: "confrontation-dette", label: "Remonter la piste jusqu'au commanditaire", default: true },
          { to: "ruelles-nuit", label: "Suivre les traces vers les ruelles" },
          { to: "place-du-marche", label: "Rebrousser chemin vers la place", gmOnly: true },
        ],
      },
      {
        id: "ruelles-nuit", title: "Les Ruelles de Nuit", act: "acte-2",
        tags: ["nuit", "embuscade"], x: 680, y: 590,
        content: "Barrage au nord. Sud libre, pour l'instant. Les ombres se referment sur vos pas.",
        transitions: [
          { to: "confrontation-dette", label: "Rejoindre la confrontation", default: true },
          { to: "denouement", label: "Fui vers le dénouement", gmOnly: true },
          { to: "place-du-marche", label: "Rentrer par la place" },
        ],
      },
      {
        id: "confrontation-dette", title: "La Confrontation", act: "acte-3",
        tags: ["confrontation", "choix"], x: 1020, y: 80,
        content: "Rendez le nom… ou gardez le joyau. Choisissez. La dette n'était pas de l'or.",
        transitions: [
          { to: "denouement", label: "Rendre le bijou et clore la dette", default: true },
          { to: "ruelles-nuit", label: "Filer avec le joyau", gmOnly: true },
          { to: "place-du-marche", label: "Retourner annoncer la vérité" },
        ],
      },
      {
        id: "denouement", title: "Le Dénouement", act: "acte-3", terminal: true,
        tags: ["épilogue"], x: 1020, y: 390,
        content: "Valbois n'oubliera pas. Partez avant la nuit. L'aube se lève sur une dette morte.",
        transitions: [
          { to: "place-du-marche", label: "Dernier regard sur la place", gmOnly: true },
        ],
      },
    ],
  };

  const byId = {};
  SCENARIO.scenes.forEach((s) => { byId[s.id] = s; });
  SCENARIO.edges = [];
  SCENARIO.scenes.forEach((s) => {
    s.transitions.forEach((t) => SCENARIO.edges.push({ from: s.id, to: t.to, label: t.label, default: !!t.default, gmOnly: !!t.gmOnly }));
  });
  SCENARIO.sceneOrder = SCENARIO.scenes.map((s) => s.id);

  const NS = "http://www.w3.org/2000/svg";
  const XHTML = "http://www.w3.org/1999/xhtml";
  const listeners = [];

  function onSelect(fn) { listeners.push(fn); }
  function emitSelect(id) { SCENARIO.selected = id; listeners.forEach((fn) => fn(id)); }
  function scene(id) { return byId[id]; }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  }
  function trunc(s, n) { return s.length > n ? s.slice(0, n - 1) + "…" : s; }

  function edgeClass(e) { return e.default ? "is-default" : e.gmOnly ? "is-gm" : "is-branch"; }
  function edgeColor(e) { return e.default ? "#c9a44c" : e.gmOnly ? "#b9a0dc" : "#8fd2ea"; }

  /* ------------------------------------------------------------------ */
  /* Graphe                                                             */
  /* ------------------------------------------------------------------ */

  function mountMiniGraph(container) {
    const W = 262, H = 154;
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    svg.classList.add("mg", "mg--mini");
    const gLinks = document.createElementNS(NS, "g");
    const gNodes = document.createElementNS(NS, "g");
    svg.appendChild(gLinks);
    svg.appendChild(gNodes);

    const layout = {};
    SCENARIO.scenes.forEach((s) => {
      layout[s.id] = {
        x: 10 + (s.x / 1360) * 236,
        y: 8 + (s.y / 820) * 132,
        w: 22, h: 10,
      };
    });

    const paths = {};
    SCENARIO.edges.forEach((e) => {
      const a = layout[e.from], b = layout[e.to];
      const x1 = a.x + a.w, y1 = a.y + a.h / 2;
      const x2 = b.x, y2 = b.y + b.h / 2;
      const dx = Math.max(14, Math.abs(x2 - x1) * 0.5);
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`);
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", edgeColor(e));
      p.setAttribute("stroke-width", e.default ? "1.9" : "1.2");
      p.setAttribute("stroke-width", e.default ? "1.9" : "1.2");
      if (e.gmOnly) p.setAttribute("stroke-dasharray", "2.5 2");
      p.setAttribute("opacity", "0.85");
      gLinks.appendChild(p);
      paths[e.from + ">" + e.to] = p;
    });

    const rects = {};
    SCENARIO.scenes.forEach((s) => {
      const l = layout[s.id];
      const r = document.createElementNS(NS, "rect");
      r.setAttribute("x", l.x); r.setAttribute("y", l.y);
      r.setAttribute("width", l.w); r.setAttribute("height", l.h);
      r.setAttribute("rx", "2.5");
      r.setAttribute("fill", s.terminal ? "#2f5b52" : s.start ? "#6b5626" : "#2a2438");
      r.setAttribute("stroke", "#0b0912"); r.setAttribute("stroke-width", "1");
      r.style.cursor = "pointer";
      r.addEventListener("click", () => { emitSelect(s.id); refresh(); });
      gNodes.appendChild(r);
      rects[s.id] = r;
    });

    function refresh() {
      SCENARIO.scenes.forEach((s) => {
        const sel = s.id === SCENARIO.selected;
        rects[s.id].setAttribute("fill", sel ? "#f2d98a" : s.terminal ? "#2f5b52" : s.start ? "#6b5626" : "#2a2438");
        rects[s.id].setAttribute("stroke", sel ? "#fff3cf" : "#0b0912");
        rects[s.id].setAttribute("stroke-width", sel ? "2" : "1");
      });
      SCENARIO.edges.forEach((e) => {
        paths[e.from + ">" + e.to].setAttribute("opacity", (!SCENARIO.selected || e.from === SCENARIO.selected || e.to === SCENARIO.selected) ? "0.95" : "0.18");
      });
    }
    refresh();
    container.appendChild(svg);
    return { select() { refresh(); }, refreshSelection: refresh, fit() {}, zoomIn() {}, zoomOut() {}, svg };
  }

  function mountGraph(container, opts) {
    opts = opts || {};
    if (opts.mini) return mountMiniGraph(container);
    const W = opts.w || 1360;
    const H = opts.h || 820;
    const mini = !!opts.mini;
    const interactive = opts.interactive !== false;
    const dim = opts.dim !== false;

    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.classList.add("mg");
    if (mini) svg.classList.add("mg--mini");

    const defs = document.createElementNS(NS, "defs");
    [["default", "#c9a44c"], ["branch", "#8fd2ea"], ["gm", "#b9a0dc"]].forEach(([name, color]) => {
      const m = document.createElementNS(NS, "marker");
      m.setAttribute("id", "arw-" + name + "-" + (container.id || "g"));
      m.setAttribute("viewBox", "0 0 10 10");
      m.setAttribute("refX", "9"); m.setAttribute("refY", "5");
      m.setAttribute("markerWidth", "7"); m.setAttribute("markerHeight", "7");
      m.setAttribute("orient", "auto-start-reverse");
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", "M0,0 L10,5 L0,10 z");
      p.setAttribute("fill", color);
      m.appendChild(p); defs.appendChild(m);
    });
    svg.appendChild(defs);

    const world = document.createElementNS(NS, "g");
    world.classList.add("mg-world");
    svg.appendChild(world);

    const gNodes = document.createElementNS(NS, "g");
    gNodes.classList.add("mg-nodes");
    const gLinks = document.createElementNS(NS, "g");
    gLinks.classList.add("mg-links");
    const gPorts = document.createElementNS(NS, "g");
    gPorts.classList.add("mg-ports");
    const gHover = document.createElementNS(NS, "g");
    gHover.classList.add("mg-hover");
    gHover.style.display = "none";
    world.appendChild(gNodes);
    world.appendChild(gLinks);
    world.appendChild(gPorts);
    world.appendChild(gHover);

    // Cadres d'actes (optionnels, derrière les cartes).
    if (opts.frames && opts.frames.length) {
      opts.frames.forEach((f) => {
        const g = document.createElementNS(NS, "g");
        g.classList.add("mg-frame");
        const rect = document.createElementNS(NS, "rect");
        rect.setAttribute("x", f.x); rect.setAttribute("y", f.y);
        rect.setAttribute("width", f.w); rect.setAttribute("height", f.h);
        rect.setAttribute("rx", "16");
        const label = document.createElementNS(NS, "text");
        label.setAttribute("x", f.x + 16); label.setAttribute("y", f.y + 24);
        label.setAttribute("font-size", "12");
        label.setAttribute("letter-spacing", "0.14em");
        label.setAttribute("fill", "#6f7f96");
        label.textContent = f.label.toUpperCase();
        g.appendChild(rect); g.appendChild(label);
        world.insertBefore(g, world.firstChild);
      });
    }

    const hoverRect = document.createElementNS(NS, "rect");
    hoverRect.setAttribute("rx", "7"); hoverRect.setAttribute("height", "26");
    const hoverText = document.createElementNS(NS, "text");
    hoverText.setAttribute("x", "10"); hoverText.setAttribute("y", "17");
    hoverText.setAttribute("font-size", "12.5");
    hoverText.setAttribute("fill", "#f6eeda");
    gHover.appendChild(hoverRect);
    gHover.appendChild(hoverText);

    const layout = {};
    const cardW = mini ? 152 : 236;
    const gapY = mini ? 12 : 22;
    SCENARIO.scenes.forEach((s) => {
      const lines = 1 + Math.min(s.transitions.length, 3);
      layout[s.id] = {
        x: mini ? Math.round(s.x * 0.78) : s.x,
        y: mini ? Math.round(s.y * 0.78) : s.y,
        w: cardW,
        h: mini ? 46 : 122 + lines * 20,
        out: null, inn: null,
      };
    });

    // Peignes de ports : chaque branche part/arrive à un point distinct.
    const byFrom = {}, byTo = {};
    SCENARIO.edges.forEach((e) => {
      (byFrom[e.from] = byFrom[e.from] || []).push(e);
      (byTo[e.to] = byTo[e.to] || []).push(e);
    });
    Object.keys(byFrom).forEach((id) => {
      const list = byFrom[id];
      list.sort((a, b) => (layout[a.to].y + layout[a.to].h / 2) - (layout[b.to].y + layout[b.to].h / 2));
      list.forEach((e, i) => {
        const off = (i - (list.length - 1) / 2) * (mini ? 4 : 9);
        e._out = { x: layout[id].x + layout[id].w, y: layout[id].y + 38 + off };
      });
    });
    Object.keys(byTo).forEach((id) => {
      const list = byTo[id];
      list.sort((a, b) => (layout[a.from].y + layout[a.from].h / 2) - (layout[b.from].y + layout[b.from].h / 2));
      list.forEach((e, i) => {
        const off = (i - (list.length - 1) / 2) * (mini ? 4 : 9);
        e._in = { x: layout[id].x, y: layout[id].y + 38 + off };
      });
    });

    function route(e) {
      const a = e._out, b = e._in;
      const back = b.x < a.x + 40;
      const dx = Math.max(46, Math.abs(b.x - a.x) * 0.5);
      const bow = back ? Math.min(a.y, b.y) - 150 : 0;
      const c1 = { x: a.x + dx, y: a.y + bow * 0.6 };
      const c2 = { x: b.x - dx, y: b.y + bow * 0.6 };
      return `M ${a.x} ${a.y} C ${c1.x} ${c1.y}, ${c2.x} ${c2.y}, ${b.x} ${b.y}`;
    }

    // Liens AU-DESSUS des cartes.
    const paths = {};
    SCENARIO.edges.forEach((e) => {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", route(e));
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", edgeColor(e));
      p.setAttribute("stroke-width", e.default ? (mini ? 2.2 : 2.8) : mini ? 1.4 : 2);
      if (e.gmOnly) p.setAttribute("stroke-dasharray", mini ? "4 3" : "7 5");
      p.setAttribute("stroke-linecap", "round");
      p.setAttribute("marker-end", `url(#arw-${e.default ? "default" : e.gmOnly ? "gm" : "branch"}-${container.id || "g"})`);
      p.classList.add("mg-link", edgeClass(e));
      p.dataset.from = e.from; p.dataset.to = e.to;
      if (mini) p.setAttribute("opacity", "0.65");
      gLinks.appendChild(p);
      paths[e.from + ">" + e.to] = p;
    });

    // Cartes (foreignObject : mise en page HTML, comme le jeu).
    const cardEls = {};
    SCENARIO.scenes.forEach((s) => {
      const l = layout[s.id];
      const fo = document.createElementNS(NS, "foreignObject");
      fo.setAttribute("x", l.x); fo.setAttribute("y", l.y);
      fo.setAttribute("width", l.w); fo.setAttribute("height", l.h);
      fo.classList.add("mg-node");
      fo.dataset.id = s.id;

      const card = document.createElement("div");
      card.setAttribute("xmlns", XHTML);
      card.className = "mg-card";
      if (s.id === SCENARIO.selected) card.classList.add("is-selected");
      if (s.start) card.classList.add("is-start");
      if (s.terminal) card.classList.add("is-terminal");
      card.dataset.id = s.id;

      if (mini) {
        card.innerHTML = `<div class="mg-card-title">${s.start ? "★ " : s.terminal ? "⚑ " : ""}${esc(s.title)}</div>`;
      } else {
        const branches = s.transitions.slice(0, 3).map((t) => {
          const kind = t.default ? "is-default" : t.gmOnly ? "is-gm" : "is-branch";
          const mark = t.default ? "★" : t.gmOnly ? "👁" : "→";
          const target = byId[t.to] ? byId[t.to].title : t.to;
          return `<div class="mg-branch ${kind}"><span class="mg-mark">${mark}</span> ${esc(trunc(t.label || target, 30))}</div>`;
        }).join("");
        card.innerHTML =
          `<div class="mg-card-head"><span class="mg-card-title">${s.start ? "★ " : s.terminal ? "⚑ " : ""}${esc(s.title)}</span>` +
          `<span class="mg-card-act">${(s.act || "").replace("acte-", "A")}</span></div>` +
          `<div class="mg-tags">${s.tags.map((t) => `<span>#${esc(t)}</span>`).join("")}</div>` +
          `<div class="mg-card-body">${esc(trunc(s.content, 110))}</div>` +
          `<div class="mg-branches">${branches}</div>`;
      }
      if (interactive) {
        card.addEventListener("click", (ev) => { ev.stopPropagation(); select(s.id); });
      }
      fo.appendChild(card);
      gNodes.appendChild(fo);
      cardEls[s.id] = card;

      const r = mini ? 2.6 : 3.6;
      [l.x + l.w, l.x].forEach((cx, idx) => {
        const c = document.createElementNS(NS, "circle");
        c.setAttribute("cx", cx);
        c.setAttribute("cy", l.y + 38);
        c.setAttribute("r", r);
        c.setAttribute("fill", s.start ? "#c9a44c" : s.terminal ? "#4e9e8a" : idx === 0 ? "#f2d98a" : "#8fd2ea");
        c.setAttribute("stroke", "#0b0912"); c.setAttribute("stroke-width", "1.5");
        gPorts.appendChild(c);
      });
    });

    // Sélection + estompage des liens non connectés.
    function refreshSelection() {
      const sel = SCENARIO.selected;
      SCENARIO.scenes.forEach((s) => {
        const card = cardEls[s.id];
        if (!card) return;
        card.classList.toggle("is-selected", s.id === sel);
      });
      if (!dim) return;
      SCENARIO.edges.forEach((e) => {
        const p = paths[e.from + ">" + e.to];
        if (!p) return;
        const active = !sel || e.from === sel || e.to === sel;
        p.classList.toggle("is-dim", !active);
        p.classList.toggle("is-hot", !!sel && (e.from === sel || e.to === sel));
      });
    }
    function select(id) {
      if (SCENARIO.selected === id) return;
      emitSelect(id);
      refreshSelection();
    }

    // Survole de liens : distance au tracé, dans l'espace du graphe.
    let view = { k: 1, x: 0, y: 0 };
    function applyView() {
      world.setAttribute("transform", `translate(${view.x},${view.y}) scale(${view.k})`);
    }
    function fit() {
      const box = container.getBoundingClientRect();
      if (!box.width) return;
      const pad = opts.pad || [0, 0, 0, 0];
      const availW = Math.max(80, box.width - pad[0] - pad[2]);
      const availH = Math.max(80, box.height - pad[1] - pad[3]);
      view.k = Math.min(availW / W, availH / H) * 0.98;
      view.x = pad[0] + (availW - W * view.k) / 2;
      view.y = pad[1] + (availH - H * view.k) / 2;
      applyView();
    }

    const samples = {};
    function samplePoints(e) {
      const key = e.from + ">" + e.to;
      if (samples[key]) return samples[key];
      const p = paths[key];
      const len = p.getTotalLength ? p.getTotalLength() : 0;
      const arr = [];
      for (let d = 0; d <= len; d += 14) arr.push(p.getPointAtLength(d));
      samples[key] = arr;
      return arr;
    }

    function worldPoint(evt) {
      const box = svg.getBoundingClientRect();
      const x = (evt.clientX - box.left - view.x) / view.k;
      const y = (evt.clientY - box.top - view.y) / view.k;
      return { x, y };
    }
    function insideNode(p) {
      return SCENARIO.scenes.some((s) => {
        const l = layout[s.id];
        return p.x >= l.x && p.x <= l.x + l.w && p.y >= l.y && p.y <= l.y + l.h;
      });
    }
    function showHover(e, at) {
      const label = (e.default ? "★ " : e.gmOnly ? "MJ · " : "") + e.label;
      hoverText.textContent = trunc(label, 44);
      const w = Math.min(340, hoverText.textContent.length * 7.1 + 20);
      hoverRect.setAttribute("width", w);
      hoverRect.setAttribute("fill", "#15111f");
      hoverRect.setAttribute("stroke", edgeColor(e));
      hoverRect.setAttribute("stroke-width", "1");
      const x = Math.min(Math.max(at.x + 12, 6), W - w - 6);
      const y = Math.max(at.y - 34, 6);
      gHover.setAttribute("transform", `translate(${x},${y})`);
      gHover.style.display = "";
    }

    if (interactive) {
      svg.addEventListener("mousemove", (evt) => {
        const p = worldPoint(evt);
        if (insideNode(p)) { gHover.style.display = "none"; return; }
        let best = null, bestD = 13, bestAt = null;
        SCENARIO.edges.forEach((e) => {
          const pts = samplePoints(e);
          for (let i = 0; i < pts.length; i++) {
            const dx = pts[i].x - p.x, dy = pts[i].y - p.y;
            const d = Math.sqrt(dx * dx + dy * dy);
            if (d < bestD) { bestD = d; best = e; bestAt = pts[i]; }
          }
        });
        if (best) showHover(best, bestAt); else gHover.style.display = "none";
      });
      svg.addEventListener("mouseleave", () => { gHover.style.display = "none"; });
      if (opts.pan) {
        let dragging = false, last = null;
        svg.addEventListener("pointerdown", (evt) => {
          if (evt.button !== 1 && !(evt.button === 0 && evt.altKey)) return;
          dragging = true; last = { x: evt.clientX, y: evt.clientY };
          svg.setPointerCapture(evt.pointerId);
        });
        svg.addEventListener("pointermove", (evt) => {
          if (!dragging) return;
          view.x += evt.clientX - last.x; view.y += evt.clientY - last.y;
          last = { x: evt.clientX, y: evt.clientY };
          applyView();
        });
        svg.addEventListener("pointerup", () => { dragging = false; });
      }
      if (opts.zoom) {
        svg.addEventListener("wheel", (evt) => {
          evt.preventDefault();
          const box = svg.getBoundingClientRect();
          const mx = evt.clientX - box.left, my = evt.clientY - box.top;
          const k2 = Math.min(2.0, Math.max(0.45, view.k * (evt.deltaY < 0 ? 1.12 : 0.89)));
          view.x = mx - ((mx - view.x) / view.k) * k2;
          view.y = my - ((my - view.y) / view.k) * k2;
          view.k = k2;
          applyView();
        }, { passive: false });
      }
    }

    container.appendChild(svg);
    fit();
    refreshSelection();

    const api = {
      select,
      refreshSelection,
      getZoom() { return view.k; },
      zoomIn() { view.k = Math.min(2, view.k * 1.15); applyView(); },
      zoomOut() { view.k = Math.max(0.45, view.k / 1.15); applyView(); },
      fit,
      svg,
    };
    return api;
  }

  /* ------------------------------------------------------------------ */
  /* Inspecteur générique                                               */
  /* ------------------------------------------------------------------ */

  function inspectorHTML(id, style) {
    const s = byId[id];
    if (!s) return "";
    const styleAttr = style ? ` class="inspector inspector--${style}"` : ' class="inspector"';
    const transitions = s.transitions.map((t) => {
      const kind = t.default ? "is-default" : t.gmOnly ? "is-gm" : "is-branch";
      const mark = t.default ? "★" : t.gmOnly ? "👁" : "→";
      const target = byId[t.to] ? byId[t.to].title : t.to;
      return `<div class="tr-row ${kind}">
        <span class="tr-mark">${mark}</span>
        <div class="tr-main"><div class="tr-label">${esc(t.label || target)}</div>
        <div class="tr-target">${esc(target)}</div></div>
        <span class="tr-badge">${t.default ? "défaut" : t.gmOnly ? "MJ" : "branche"}</span>
      </div>`;
    }).join("");
    return `<div${styleAttr} data-scene="${s.id}">
      <div class="ins-head">
        <div>
          <div class="ins-kicker">Scène ${SCENARIO.sceneOrder.indexOf(id) + 1} / ${SCENARIO.sceneOrder.length} · ${esc(s.act.replace("acte-", "Acte "))}</div>
          <h2 class="ins-title">${esc(s.title)}</h2>
        </div>
        <div class="ins-badges">
          ${s.start ? '<span class="badge badge--gold">★ départ</span>' : ""}
          ${s.terminal ? '<span class="badge badge--green">⚑ fin</span>' : ""}
          <span class="badge">${esc(s.id)}</span>
        </div>
      </div>
      <div class="ins-tags">${s.tags.map((t) => `<span class="tag">#${esc(t)}</span>`).join("")}</div>
      <label class="field"><span class="field-label">Titre</span>
        <input class="input" value="${esc(s.title)}"></label>
      <label class="field"><span class="field-label">Tags</span>
        <input class="input" value="${esc(s.tags.join(", "))}"></label>
      <label class="field"><span class="field-label">Contenu lu / montré aux joueurs</span>
        <textarea class="textarea" rows="4">${esc(s.content)}</textarea></label>
      <div class="field">
        <span class="field-label">Branches sortantes <span class="field-count">${s.transitions.length}</span></span>
        <div class="tr-list">${transitions}</div>
        <button class="btn btn--ghost btn--sm">+ Ajouter une branche</button>
      </div>
      <div class="ins-two">
        <label class="field"><span class="field-label">Cartes liées</span>
          <div class="chips">${SCENARIO.maps.slice(0, 2).map((m) => `<span class="chip chip--map">${esc(m)}</span>`).join("")}</div>
        </label>
        <label class="field"><span class="field-label">PNJ présents</span>
          <div class="chips">${SCENARIO.npcs.filter((n) => n.scenes.includes(s.id)).slice(0, 3).map((n) => `<span class="chip">${esc(n.name)}</span>`).join("")}</div>
        </label>
      </div>
      <div class="ins-foot">
        <button class="btn btn--ghost">Dupliquer</button>
        <button class="btn btn--danger">Supprimer</button>
        <span class="spacer"></span>
        <button class="btn btn--ghost">Scène de départ</button>
      </div>
    </div>`;
  }

  function sceneListItem(s, cls) {
    const warnings = s.transitions.length === 0 && !s.terminal;
    return `<button class="scene-row ${cls || ""}" data-id="${s.id}">
      <span class="scene-num">${String(SCENARIO.sceneOrder.indexOf(s.id) + 1).padStart(2, "0")}</span>
      <span class="scene-main">
        <span class="scene-title">${s.start ? "★ " : s.terminal ? "⚑ " : ""}${esc(s.title)}</span>
        <span class="scene-meta">${s.transitions.length} branche${s.transitions.length > 1 ? "s" : ""}${warnings ? " · ⚠" : ""}</span>
      </span>
      <span class="scene-dot ${s.terminal ? "is-green" : s.start ? "is-gold" : ""}"></span>
    </button>`;
  }

  function actsHTML(activeId) {
    return SCENARIO.acts.map((a) => `
      <div class="act-group">
        <div class="act-head">${esc(a.title)}</div>
        ${a.scenes.map((sid) => sceneListItem(byId[sid], sid === activeId ? "is-active" : "")).join("")}
      </div>`).join("");
  }

  function healthHTML() {
    const h = SCENARIO.health;
    return `<span class="health"><span class="health-dot"></span>${h.scenes} scènes · ${h.branches} branches · ${h.crossroads} carrefours</span>`;
  }

  /* Expose */
  window.MOCK = {
    scenario: SCENARIO,
    scene, byId, esc, trunc, mountGraph, inspectorHTML, sceneListItem, actsHTML, healthHTML,
    onSelect, emitSelect, edgeColor, edgeClass,
  };
})();
