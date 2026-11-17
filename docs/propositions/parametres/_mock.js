/* ==========================================================================
   OpenQuest — comportements partagés des maquettes de Paramètres.
   Aucune dépendance. Auto-init sur DOMContentLoaded.
   ========================================================================== */
(function () {
  "use strict";

  /* ---------- Curseurs : remplissage + valeur affichée ---------- */
  function initRanges(root) {
    root.querySelectorAll('input[type="range"]').forEach(function (r) {
      var out = r.parentElement.querySelector(".value");
      var fmt = r.dataset.fmt || "raw";
      var unit = r.dataset.unit || "";
      function paint() {
        var min = parseFloat(r.min || "0");
        var max = parseFloat(r.max || "100");
        var pct = ((parseFloat(r.value) - min) / (max - min)) * 100;
        r.style.setProperty("--fill", pct.toFixed(1) + "%");
        if (!out) return;
        var v = parseFloat(r.value);
        if (fmt === "pct") out.textContent = Math.round(v) + " %";
        else if (fmt === "x") out.textContent = v.toFixed(1) + "×";
        else if (fmt === "int") out.textContent = Math.round(v) + (unit ? " " + unit : "");
        else if (Number.isInteger(v)) out.textContent = v + (unit ? " " + unit : "");
        else out.textContent = v.toFixed(1) + (unit ? " " + unit : "");
      }
      r.addEventListener("input", paint);
      paint();
    });
  }

  /* ---------- Contrôles segmentés ---------- */
  function initSegments(root) {
    root.querySelectorAll(".seg").forEach(function (seg) {
      seg.addEventListener("click", function (ev) {
        var btn = ev.target.closest("button");
        if (!btn || !seg.contains(btn)) return;
        seg.querySelectorAll("button").forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        var group = seg.dataset.seg;
        if (group) {
          document.dispatchEvent(new CustomEvent("mock:seg", {
            detail: { group: group, value: btn.dataset.value || btn.textContent.trim() }
          }));
        }
      });
    });
  }

  /* ---------- Onglets (boutons [data-tab] → panneaux [data-panel]) ---------- */
  function initTabs(root) {
    root.querySelectorAll("[data-tabs]").forEach(function (host) {
      var buttons = host.querySelectorAll("[data-tab]");
      var panels = host.querySelectorAll("[data-panel]");
      if (!buttons.length || !panels.length) return;
      buttons.forEach(function (btn) {
        btn.addEventListener("click", function () {
          buttons.forEach(function (b) { b.classList.remove("active"); });
          btn.classList.add("active");
          panels.forEach(function (p) {
            p.classList.toggle("hidden", p.dataset.panel !== btn.dataset.tab);
          });
          var scroller = host.querySelector(".content-scroll:not(.hidden), .s-main-scroll");
          if (scroller) scroller.scrollTop = 0;
        });
      });
    });
  }

  /* ---------- FPS : nombre + graphe de frametime ---------- */
  function initFps(root) {
    var num = root.querySelector(".fps-num");
    var spark = root.querySelector(".spark");
    var ms = root.querySelector("[data-fps-ms]");
    var dc = root.querySelector("[data-fps-dc]");
    if (!num && !spark) return;

    if (spark && !spark.childElementCount) {
      for (var i = 0; i < 36; i++) spark.appendChild(document.createElement("i"));
    }
    var values = [];

    function tick() {
      var base = window.__fpsBase || 118;
      var jitter = (Math.random() - 0.5) * 16;
      var fps = Math.max(24, Math.round(base + jitter));
      values.push(fps);
      if (values.length > 36) values.shift();

      if (num) {
        num.textContent = String(fps);
        num.classList.remove("good", "warn", "bad");
        num.classList.add(fps >= 100 ? "good" : fps >= 55 ? "warn" : "bad");
      }
      if (ms) ms.textContent = (1000 / fps).toFixed(1) + " ms";
      if (dc) dc.textContent = String(Math.round(420 + (120 - fps) * 9 + Math.random() * 30));
      if (spark) {
        var bars = spark.children;
        for (var k = 0; k < bars.length; k++) {
          var v = values[values.length - bars.length + k] || 60;
          bars[k].style.height = Math.max(3, Math.min(26, (v / 144) * 26)).toFixed(1) + "px";
          bars[k].style.opacity = String(0.35 + (v / 144) * 0.65);
        }
      }
    }
    tick();
    setInterval(tick, 620);
  }

  /* ---------- Captation de touche sur un keycap ---------- */
  var USED_KEYS = {
    "Ctrl+Z": "Édition · Annuler",
    "Ctrl+S": "Fichier · Enregistrer",
    "Ctrl+D": "Édition · Dupliquer",
    "V": "Outil · Sélection",
    "P": "Outil · Chemin",
    "W": "Outil · Mur",
    "F": "Affichage · Cadrer",
    "Tab": "Affichage · Masquer l'UI"
  };

  function keyLabel(ev) {
    var parts = [];
    if (ev.ctrlKey) parts.push("Ctrl");
    if (ev.altKey) parts.push("Alt");
    if (ev.shiftKey) parts.push("Maj");
    var k = ev.key;
    if (k === " ") k = "Espace";
    if (k.length === 1) k = k.toUpperCase();
    if (k === "Escape") k = "Échap";
    if (k === "ArrowUp") k = "↑";
    if (k === "ArrowDown") k = "↓";
    if (k === "ArrowLeft") k = "←";
    if (k === "ArrowRight") k = "→";
    parts.push(k);
    return parts.join("+");
  }

  function initKeycaps(root) {
    var current = null;
    var initial = "";

    root.querySelectorAll(".keycap[data-key]").forEach(function (cap) {
      cap.addEventListener("click", function (ev) {
        ev.preventDefault();
        if (current) stop();
        current = cap;
        initial = cap.textContent;
        cap.dataset.initial = initial;
        cap.textContent = "Appuyez…";
        cap.classList.add("capturing");
        cap.classList.remove("conflict");
      });
    });

    function stop() {
      if (!current) return;
      current.textContent = current.dataset.initial || current.textContent;
      current.classList.remove("capturing");
      current = null;
    }

    document.addEventListener("keydown", function (ev) {
      if (!current) return;
      ev.preventDefault();
      if (ev.key === "Escape") { stop(); return; }
      if (ev.key === "Tab") { /* laisser Tab capturable, sans changer de focus */ }
      var label = keyLabel(ev);
      current.textContent = label;
      current.classList.remove("capturing");
      var conflict = USED_KEYS[label];
      if (conflict) {
        current.classList.add("conflict");
        toast("⚠ " + label + " est déjà utilisé par « " + conflict + " ».");
      } else {
        USED_KEYS[label] = "cette action";
        toast("Raccourci remplacé par " + label + " — appliqué immédiatement.");
      }
      current = null;
    }, true);
  }

  /* ---------- Toast discret ---------- */
  var toastEl = null, toastTimer = null;
  function toast(msg) {
    if (!toastEl) {
      toastEl = document.createElement("div");
      toastEl.style.cssText =
        "position:fixed;right:18px;bottom:16px;z-index:90;max-width:330px;" +
        "padding:9px 13px;border-radius:6px;font-size:12px;line-height:1.4;" +
        "background:rgba(28,23,15,.96);color:#f1e3cc;border:1px solid #6b573a;" +
        "box-shadow:0 8px 24px rgba(0,0,0,.5);opacity:0;transform:translateY(6px);" +
        "transition:opacity .18s ease,transform .18s ease;pointer-events:none";
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = msg;
    requestAnimationFrame(function () {
      toastEl.style.opacity = "1";
      toastEl.style.transform = "translateY(0)";
    });
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toastEl.style.opacity = "0";
      toastEl.style.transform = "translateY(6px)";
    }, 2600);
  }

  /* ---------- Preset graphique : influence le FPS simulé ---------- */
  var PRESET_FPS = { performance: 172, equilibre: 118, cinema: 74 };

  function initPresetFeedback() {
    document.addEventListener("mock:seg", function (ev) {
      var g = ev.detail.group;
      var v = String(ev.detail.value).toLowerCase();
      if (g === "preset") {
        var key = v.indexOf("perf") >= 0 ? "performance" : v.indexOf("cin") >= 0 ? "cinema" : "equilibre";
        window.__fpsBase = PRESET_FPS[key];
        var note = document.getElementById("preset-note");
        if (note) {
          note.textContent = {
            performance: "Performance — ombres off, AA off, végétation réduite, échelle 85 %.",
            equilibre: "Équilibré — ombres moyennes, MSAA 2×, végétation normale, échelle 100 %.",
            cinema: "Cinéma — ombres hautes + AO/SSIL, tonemap filmique, végétation dense."
          }[key];
        }
        toast("Preset « " + ev.detail.value + " » appliqué à la scène.");
      }
      if (g === "theme") {
        document.documentElement.style.setProperty("--accent", v === "jade" ? "#55d6be" : "#f2c46c");
        document.documentElement.style.setProperty("--accent-soft", v === "jade" ? "#3fae99" : "#daaf56");
        document.documentElement.style.setProperty("--accent-dim", v === "jade" ? "rgba(85,214,190,.16)" : "rgba(242,196,108,.16)");
        toast("Thème « " + (v === "jade" ? "Cartographe Jade" : "Cartographe Or") + " » appliqué.");
      }
    });
  }

  /* ---------- Init ---------- */
  function init() {
    initRanges(document);
    initSegments(document);
    initTabs(document);
    initKeycaps(document);
    initPresetFeedback();
    if (!document.body.classList.contains("no-fps")) initFps(document);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();

  window.Mock = { toast: toast };
})();
