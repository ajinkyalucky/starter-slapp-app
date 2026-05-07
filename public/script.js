/* =============================================================
   AI Stylist — interactivity layer
   ============================================================= */
(() => {
  'use strict';

  /* ---------- DOM helpers ---------- */
  const $  = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  /* ---------- Static product thumbs ---------- */
  const THUMB_SVG = {
    blazer: '<svg viewBox="0 0 64 64"><path d="M16 14l16-6 16 6-2 12-6 4 4 28H22l4-28-6-4z" fill="#1f1a14" stroke="#d4af37" stroke-width="1.2"/><path d="M30 18v32" stroke="#d4af37" stroke-width="1" fill="none"/></svg>',
    shirt:  '<svg viewBox="0 0 64 64"><path d="M14 18l10-6 4 4h8l4-4 10 6-4 8-4-2v22H22V24l-4 2z" fill="#1d1d1d" stroke="#d4af37" stroke-width="1.2"/></svg>',
    pants:  '<svg viewBox="0 0 64 64"><path d="M20 10h24l-2 18-4 26h-6l-2-22-2 22h-6l-4-26z" fill="#251c12" stroke="#d4af37" stroke-width="1.2"/></svg>',
    shoes:  '<svg viewBox="0 0 64 64"><path d="M8 38c8-2 16-2 24 0 4 1 8 4 16 4 6 0 8 2 8 6H8z" fill="#f4f4f4" stroke="#d4af37" stroke-width="1.2"/><path d="M8 44h48" stroke="#d4af37" stroke-width="1" fill="none"/></svg>',
    watch:  '<svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="14" fill="#0a0a0a" stroke="#d4af37" stroke-width="1.5"/><path d="M32 24v8l5 3" stroke="#d4af37" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M26 18l2-8h8l2 8 M26 46l2 8h8l2-8" fill="#3b2f1d" stroke="#d4af37" stroke-width="1"/></svg>'
  };

  const BADGE_ICONS = {
    'Sharp jawline fit':         '<svg viewBox="0 0 24 24"><path d="M5 3h14v6c0 6-6 12-7 12s-7-6-7-12z" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
    'V-shape silhouette':        '<svg viewBox="0 0 24 24"><path d="M5 16c5-3 9-3 14 0 M8 8h8 M9 4h6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    'Broad shoulder enhancement':'<svg viewBox="0 0 24 24"><path d="M4 12c2-3 5-5 8-5s6 2 8 5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
    'Perfect for Date / Evening':'<svg viewBox="0 0 24 24"><path d="M19 4l-7 8-3-3-5 5v6h6l9-9z" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>',
    'Trending in Bangalore':     '<svg viewBox="0 0 24 24"><path d="M4 18l5-6 4 3 7-8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>'
  };
  const fallbackBadge = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M9 12l2 2 4-4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /* ---------- App state ---------- */
  const state = {
    category: 'date',
    look: null,
    lighting: { current: 0, styled: 0 },
    background: { current: 0, styled: 0 },
    swapped: false,
    reservation: null,
    timerInterval: null,
  };
  const LIGHTING_MODES = ['', 'light-bright', 'light-warm', 'light-cool'];
  const LIGHTING_NAMES = ['Studio', 'Bright daylight', 'Warm evening', 'Cool morning'];
  const BG_MODES = ['studio', 'rooftop', 'beach', 'loft'];
  const BG_NAMES = ['Studio', 'City rooftop', 'Beach sunset', 'Loft interior'];

  /* ---------- Toast & Modal ---------- */
  const toastEl = $('#toast');
  let toastTimer;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 2400);
  }

  const modalRoot = $('#modalRoot');
  const modalTitle = $('#modalTitle');
  const modalBody = $('#modalBody');
  function openModal(title, html) {
    modalTitle.textContent = title;
    modalBody.innerHTML = `<div class="modal-body">${html}</div>`;
    modalRoot.classList.add('open');
    modalRoot.setAttribute('aria-hidden', 'false');
  }
  function closeModal() {
    modalRoot.classList.remove('open');
    modalRoot.setAttribute('aria-hidden', 'true');
  }
  modalRoot.addEventListener('click', e => {
    if (e.target.dataset.close === 'true') closeModal();
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && modalRoot.classList.contains('open')) closeModal();
  });

  /* ---------- Data fetching ---------- */
  async function loadLook(category) {
    state.category = category;
    try {
      const res = await fetch(`/api/look/${category}`);
      if (!res.ok) throw new Error('not_found');
      const data = await res.json();
      state.look = data;
      renderLook(data);
    } catch (err) {
      toast('Could not load look. Showing cached.');
    }
  }

  function renderLook(look) {
    // tagline + score
    $('#stylistTagline').innerHTML = look.tagline.replace(/, /, ',<br>');
    animateNumber($('#fitScoreNum'), parseInt($('#fitScoreNum').textContent, 10) || 0, look.fitScore, 600);
    $('#fitScoreLabel').textContent =
      look.fitScore >= 92 ? 'Great fit' : look.fitScore >= 85 ? 'Solid fit' : 'Decent fit';

    // items
    const list = $('#lookList');
    list.innerHTML = look.items.map(item => `
      <li class="look-item" data-id="${item.id}">
        <div class="thumb">${THUMB_SVG[item.img] || THUMB_SVG.shirt}</div>
        <div class="meta">
          <b>${item.name}</b>
          <span class="price">₹${item.price.toLocaleString('en-IN')}</span>
          <span class="stock">
            <span class="stock-dot ${item.stock === 'Low Stock' ? 'low' : ''}"></span>
            ${item.stock} &nbsp;•&nbsp; ${item.left} left in your size
          </span>
        </div>
        <span class="arrow">›</span>
      </li>
    `).join('');

    // badges
    const badgesEl = $('#lookBadges');
    badgesEl.innerHTML = look.badges.map(b => `
      <div class="badge" title="${b}">
        <span class="b-icn">${BADGE_ICONS[b] || fallbackBadge}</span>
        <span>${b.replace(/ \/ /g, '<br>/ ').replace(/ for /, ' for<br>')}</span>
      </div>
    `).join('');

    // wire item clicks
    $$('.look-item', list).forEach(li => {
      li.addEventListener('click', () => openItem(li.dataset.id));
    });
  }

  function openItem(id) {
    const item = state.look.items.find(i => i.id === id);
    if (!item) return;
    openModal(item.name, `
      <div class="key-value">
        <b>Price</b><span>₹${item.price.toLocaleString('en-IN')}</span>
        <b>Stock</b><span>${item.stock}</span>
        <b>Your size</b><span>${item.left} left</span>
        <b>Match</b><span>Pairs with the rest of your "${state.category}" look</span>
        <b>Care</b><span>Dry clean / cold wash inside-out</span>
      </div>
      <p style="margin-top:14px;">An AI-curated piece chosen for your shoulder line, skin tone, and current trends in your city. Try it in motion to see how it drapes.</p>
    `);
  }

  /* ---------- Number animation ---------- */
  function animateNumber(el, from, to, dur) {
    const t0 = performance.now();
    const tick = (now) => {
      const p = Math.min(1, (now - t0) / dur);
      const eased = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.round(from + (to - from) * eased);
      if (p < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  /* ---------- Category chips ---------- */
  $$('#categoryChips .chip').forEach(chip => {
    chip.addEventListener('click', () => {
      $$('#categoryChips .chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      loadLook(chip.dataset.cat);
    });
  });

  /* ---------- Insight clicks ---------- */
  const INSIGHT_DETAIL = {
    shoulder: { title: 'Shoulder Fit',
      body: '<p>Your shoulder slope is <b>balanced</b> with even alignment across both sides. Garments naturally sit well — no padding adjustments needed.</p><p style="color:var(--gold)">Tip: Lean into structured shoulders for more presence.</p>' },
    chest: { title: 'Chest Fit',
      body: '<p>Your chest fit reads slightly relaxed in the current outfit. A more tailored cut would <b>sharpen the silhouette</b> and bring proportion to the shoulders.</p>' },
    waist: { title: 'Waist Fit',
      body: '<p>Waist fit is <b>OK</b> — there\'s room to taper for a stronger V-shape. Mid-rise tailored trousers will improve overall proportion.</p>' },
    legs: { title: 'Leg Length',
      body: '<p>Your inseam is well-balanced relative to torso. No alteration needed for standard cuts — you can rock cropped trousers too.</p>' },
    posture: { title: 'Posture',
      body: '<p>Posture detected as <b>good</b>. Shoulders open, neutral spine. Photo confidence stays high in front-facing shots.</p>' }
  };
  $$('#insightList li').forEach(li => {
    li.addEventListener('click', () => {
      const d = INSIGHT_DETAIL[li.dataset.insight];
      if (d) openModal(d.title, d.body);
    });
  });

  $('#whatIsThisBtn').addEventListener('click', () => {
    openModal('What is the Fit Score?', `
      <p>Your Fit Score is a <b>0–100</b> measure combining shoulder alignment, chest fit, waist taper, leg length, and posture against the curated look.</p>
      <p>It updates in real-time as you swap pieces, so you can see how each choice affects the whole look before you reserve.</p>
      <ul class="list">
        <li><b>90–100</b><span>Great fit</span></li>
        <li><b>80–89</b><span>Solid fit</span></li>
        <li><b>70–79</b><span>Workable</span></li>
        <li><b>< 70</b><span>Try a different cut</span></li>
      </ul>
    `);
  });

  $('#viewAnalysisBtn').addEventListener('click', () => {
    openModal('Body Analysis', `
      <p>A complete breakdown derived from your scan.</p>
      <div class="key-value">
        <b>Shoulder</b><span>Balanced · 0.4° slope</span>
        <b>Chest</b><span>Relaxed — could be sharper</span>
        <b>Waist</b><span>Ok — room to taper</span>
        <b>Leg length</b><span>Balanced inseam</span>
        <b>Posture</b><span>Good · neutral spine</span>
        <b>Skin tone</b><span>Warm undertone</span>
        <b>Frame</b><span>Mesomorph leaning</span>
      </div>
    `);
  });

  /* ---------- Lighting / background toggles per side ---------- */
  function applyLighting(target) {
    const wrap = $(`.silhouette[data-side="${target}"] .figure-wrap`);
    LIGHTING_MODES.forEach(c => c && wrap.classList.remove(c));
    const mode = LIGHTING_MODES[state.lighting[target]];
    if (mode) wrap.classList.add(mode);
  }
  function applyBackground(target) {
    const wrap = $(`.silhouette[data-side="${target}"] .figure-wrap`);
    wrap.dataset.bg = BG_MODES[state.background[target]];
  }

  $$('.tool-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.target;
      const action = btn.dataset.action;
      if (action === 'lighting') {
        state.lighting[target] = (state.lighting[target] + 1) % LIGHTING_MODES.length;
        applyLighting(target);
        toast(`${target === 'current' ? 'Current' : 'Styled'} · ${LIGHTING_NAMES[state.lighting[target]]}`);
      } else if (action === 'background') {
        state.background[target] = (state.background[target] + 1) % BG_MODES.length;
        applyBackground(target);
        toast(`${target === 'current' ? 'Current' : 'Styled'} · ${BG_NAMES[state.background[target]]}`);
      }
      btn.classList.toggle('active',
        (action === 'lighting' && state.lighting[target] !== 0) ||
        (action === 'background' && state.background[target] !== 0));
    });
  });

  /* ---------- Bottom action bar (applies to both) ---------- */
  $('#actionMotion').addEventListener('click', () => {
    const figs = $$('.figure-wrap');
    figs.forEach(f => {
      f.style.transition = 'transform .8s ease';
      f.style.transform = 'translateY(-6px) rotate(-1.2deg)';
      setTimeout(() => { f.style.transform = 'translateY(0) rotate(1.2deg)'; }, 400);
      setTimeout(() => { f.style.transform = ''; f.style.transition = ''; }, 1200);
    });
    toast('Animating walk cycle…');
  });
  $('#actionLighting').addEventListener('click', () => {
    state.lighting.current = state.lighting.styled = (state.lighting.styled + 1) % LIGHTING_MODES.length;
    applyLighting('current'); applyLighting('styled');
    toast(`Lighting · ${LIGHTING_NAMES[state.lighting.styled]}`);
  });
  $('#actionBackground').addEventListener('click', () => {
    state.background.current = state.background.styled = (state.background.styled + 1) % BG_MODES.length;
    applyBackground('current'); applyBackground('styled');
    toast(`Backdrop · ${BG_NAMES[state.background.styled]}`);
  });
  $('#actionReserve').addEventListener('click', reserveLook);

  /* ---------- Swap silhouettes ---------- */
  $('#swapBtn').addEventListener('click', (e) => {
    state.swapped = !state.swapped;
    const wrap = $('.silhouettes');
    const left = $('.silhouette[data-side="current"]', wrap);
    const right = $('.silhouette[data-side="styled"]', wrap);
    left.style.order  = state.swapped ? 1 : 0;
    right.style.order = state.swapped ? 0 : 1;
    e.currentTarget.classList.add('spinning');
    setTimeout(() => e.currentTarget.classList.remove('spinning'), 600);
    toast('Views swapped');
  });

  /* ---------- AI tip rotation ---------- */
  const TIPS = [
    'Try a darker tone—it sharpens your profile and complements your skin.',
    'A structured shoulder will add presence to your evening look.',
    'Cropped trousers would expose the sneaker — a sharper line for date night.',
    'Switch to a watch with a warm dial to echo the gold accents.',
    'Layer a linen overshirt for a dusk-to-dinner transition.'
  ];
  let tipIdx = 0;
  setInterval(() => {
    tipIdx = (tipIdx + 1) % TIPS.length;
    const txt = $('#aiTipText');
    txt.style.opacity = 0;
    setTimeout(() => { txt.textContent = TIPS[tipIdx]; txt.style.opacity = 1; }, 200);
  }, 6500);
  $('#aiTipText').style.transition = 'opacity .25s';

  /* ---------- Live stylist ---------- */
  $('#liveBtn').addEventListener('click', () => {
    openModal('AI Stylist · Live', `
      <p>Connecting you to a live stylist channel. While we route you, here are a few prompts:</p>
      <ul class="list">
        <li><b>"Make it sharper"</b><span>refine fit</span></li>
        <li><b>"Show me one in white"</b><span>swap color</span></li>
        <li><b>"Under ₹15,000 total"</b><span>budget</span></li>
        <li><b>"Closest store?"</b><span>availability</span></li>
      </ul>
    `);
  });

  /* ---------- Breakdown / Map ---------- */
  $('#breakdownBtn').addEventListener('click', () => {
    if (!state.look) return;
    const total = state.look.items.reduce((s, i) => s + i.price, 0);
    openModal('Look Breakdown', `
      <ul class="list">
        ${state.look.items.map(i => `<li><b>${i.name}</b><span>₹${i.price.toLocaleString('en-IN')}</span></li>`).join('')}
      </ul>
      <div class="total"><b>Total</b><span>₹${total.toLocaleString('en-IN')}</span></div>
      <p style="margin-top:14px;">Reserve the full look for 30 minutes — your size is held while you decide.</p>
    `);
  });
  $('#viewMapBtn').addEventListener('click', openMapModal);
  $('#mapMini').addEventListener('click', openMapModal);
  function openMapModal() {
    openModal('Phoenix Palladium Mall', `
      <p>Lower Ground Floor · 2 mins walk from your current location.</p>
      <div style="border-radius:12px;overflow:hidden;border:1px solid var(--line);">
        <svg viewBox="0 0 400 220" style="display:block;width:100%;height:auto;background:#0e0e0e">
          <g stroke="#262421" stroke-width="1" fill="none">
            <path d="M0 50h400 M0 130h400 M0 190h400 M80 0v220 M200 0v220 M320 0v220"/>
          </g>
          <g stroke="#3a3429" stroke-width="2.5" fill="none">
            <path d="M0 100h400 M250 0v220"/>
          </g>
          <circle cx="280" cy="120" r="9" fill="#d4af37"/>
          <circle cx="280" cy="120" r="18" fill="#d4af37" opacity=".18"/>
          <circle cx="120" cy="80" r="5" fill="#5cc28a"/>
          <text x="130" y="84" font-size="11" fill="#b9b3a6">You</text>
          <text x="290" y="124" font-size="11" fill="#d4af37">Store</text>
        </svg>
      </div>
      <p style="margin-top:12px;">Open in Google Maps or get walking directions from the store concierge.</p>
    `);
  }

  /* ---------- Reserve flow ---------- */
  async function reserveLook() {
    if (!state.look) return;
    const btn = $('#actionReserve');
    btn.disabled = true;
    try {
      const res = await fetch('/api/reserve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: state.look.items.map(i => i.id), category: state.category })
      });
      const data = await res.json();
      state.reservation = data;
      startReserveTimer(data.expiresAt);
      const total = state.look.items.reduce((s, i) => s + i.price, 0);
      openModal('Look Reserved', `
        <div class="reserve-success">
          <div class="check">✓</div>
          <p>Your look is held for <b>30 minutes</b>.</p>
          <div class="res-id">${data.reservationId}</div>
          <p style="margin-top:8px;color:var(--text-3);">Show this code at <b>Phoenix Palladium · LG</b>.</p>
        </div>
        <div class="total"><b>Reserved total</b><span>₹${total.toLocaleString('en-IN')}</span></div>
      `);
    } catch {
      toast('Reservation failed. Try again.');
    } finally {
      btn.disabled = false;
    }
  }
  function startReserveTimer(expiresAt) {
    clearInterval(state.timerInterval);
    const el = $('#reserveTimer');
    function tick() {
      const ms = expiresAt - Date.now();
      if (ms <= 0) {
        el.textContent = '(expired)';
        clearInterval(state.timerInterval);
        return;
      }
      const m = Math.floor(ms / 60000);
      const s = Math.floor((ms % 60000) / 1000);
      el.textContent = `(${m}:${s.toString().padStart(2, '0')})`;
    }
    tick();
    state.timerInterval = setInterval(tick, 1000);
  }

  /* ---------- Promise tiles ---------- */
  const PROMISE_DETAIL = {
    alterations: { title: 'Free Alterations',
      body: '<p>Every reserved look includes complimentary alterations at any of our partner tailors. Drop-off in-store, pick-up in 24 hours.</p>' },
    returns: { title: 'Easy Returns',
      body: '<p>30-day hassle-free returns. Pickup from your address, refund within 5 business days.</p>' },
    save: { title: 'Save Your Looks',
      body: '<p>All your tried-on looks sync across devices. Pick up where you left off on mobile or in-store.</p>' },
    help: { title: 'Need help?',
      body: '<p>Chat live with a human stylist 9 AM – 11 PM, or schedule a 15-min video consult.</p>' }
  };
  $$('.promise').forEach(p => {
    p.addEventListener('click', () => {
      const d = PROMISE_DETAIL[p.dataset.promise];
      if (d) openModal(d.title, d.body);
    });
  });

  $('#qrTile').addEventListener('click', () => {
    openModal('Continue on phone', `
      <p>Scan with your phone camera to keep this exact session — your fit, your look, and your reservation.</p>
      <p style="text-align:center;">
        <span style="display:inline-block;background:#fff;padding:14px;border-radius:10px;">
          <span style="display:block;width:160px;height:160px;background:radial-gradient(#000 1.5px,transparent 1.6px) 0 0/8px 8px;"></span>
        </span>
      </p>
    `);
  });

  /* ---------- Init ---------- */
  loadLook('date');
})();
