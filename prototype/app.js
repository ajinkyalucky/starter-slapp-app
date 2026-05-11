(function () {
  const screens = Array.from(document.querySelectorAll(".screen"));
  const order = screens.map((s) => s.dataset.screen);
  const map = document.getElementById("map");
  const label = document.getElementById("label");
  const prev = document.getElementById("prev");
  const next = document.getElementById("next");

  const labels = {
    splash: "1. Splash",
    welcome: "2. Welcome",
    verify: "3. Verify OTP",
    permissions: "4. Permissions",
    name: "5. Name",
    height: "6. Height",
    weight: "7. Weight",
    body: "8. Body type",
    brands: "9. Brands & sizes",
    gmail: "10. Connect Gmail",
    colour: "11. Colour store",
    upload: "12. Upload picture",
    source: "13. Source sheet",
    scan: "14. Face scan",
    palette: "15. Skin palette",
    boards: "16. Style boards",
    chat: "17. Chat",
  };

  order.forEach((id) => {
    const b = document.createElement("button");
    b.textContent = labels[id] || id;
    b.dataset.go = id;
    map.appendChild(b);
  });

  function show(id) {
    screens.forEach((s) => s.classList.toggle("is-active", s.dataset.screen === id));
    Array.from(map.children).forEach((b) => b.classList.toggle("is-active", b.dataset.go === id));
    label.textContent = labels[id] || id;
    window.history.replaceState(null, "", "#" + id);
    if (window._pickers && window._pickers[id]) window._pickers[id].refresh();
  }

  // Click handlers on anything with [data-go]
  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-go]");
    if (!t) return;
    e.preventDefault();
    show(t.dataset.go);
  });

  prev.addEventListener("click", () => {
    const cur = order.findIndex((id) => document.querySelector('.screen[data-screen="' + id + '"]').classList.contains("is-active"));
    show(order[Math.max(0, cur - 1)]);
  });
  next.addEventListener("click", () => {
    const cur = order.findIndex((id) => document.querySelector('.screen[data-screen="' + id + '"]').classList.contains("is-active"));
    show(order[Math.min(order.length - 1, cur + 1)]);
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") next.click();
    if (e.key === "ArrowLeft") prev.click();
  });

  // Auto-advance OTP fields
  const otp = document.getElementById("otp");
  if (otp) {
    const inputs = Array.from(otp.querySelectorAll("input"));
    inputs.forEach((inp, i) => {
      inp.addEventListener("input", () => {
        if (inp.value && i < inputs.length - 1) inputs[i + 1].focus();
      });
      inp.addEventListener("keydown", (e) => {
        if (e.key === "Backspace" && !inp.value && i > 0) inputs[i - 1].focus();
      });
    });
  }

  // Brand size selection
  document.querySelectorAll(".sizes").forEach((row) => {
    row.addEventListener("click", (e) => {
      const btn = e.target.closest("button");
      if (!btn) return;
      row.querySelectorAll("button").forEach((b) => b.classList.remove("on"));
      btn.classList.add("on");
    });
  });

  // Body type selection (no default, fade others, gate CTA)
  const bodiesGrid = document.getElementById("bodies-grid");
  const bodyCta = document.getElementById("body-cta");
  document.querySelectorAll(".body-card").forEach((c) => {
    c.addEventListener("click", () => {
      document.querySelectorAll(".body-card").forEach((b) => b.classList.remove("is-selected"));
      c.classList.add("is-selected");
      if (bodiesGrid) bodiesGrid.classList.add("has-selection");
      state.body = c.dataset.body;
      if (bodyCta) bodyCta.removeAttribute("disabled");
      haptic(12);
      renderSummary();
    });
  });

  // ----- Shared profile state + interactive picker -----
  const state = {
    height_cm: 175, height_ft: 69,   // 5'9"
    weight_kg: 67,  weight_lb: 148,
    body: null,
  };
  const ITEM_H = 56;

  function haptic(ms) {
    try {
      if (navigator.vibrate) navigator.vibrate(ms);
    } catch (_) {}
  }

  function buildPicker(el) {
    const minA = +el.dataset.min;
    const maxA = +el.dataset.max;
    const minB = +el.dataset.altMin;
    const maxB = +el.dataset.altMax;
    const units = (el.dataset.units || "").split(",");
    const key = el.dataset.picker;

    el.innerHTML = "";
    // tick rulers
    const ticksL = document.createElement("div"); ticksL.className = "picker-ticks left";
    const ticksR = document.createElement("div"); ticksR.className = "picker-ticks right";
    el.appendChild(ticksL); el.appendChild(ticksR);

    // red marks
    const markL = document.createElement("div"); markL.className = "picker-mark-left";
    const markR = document.createElement("div"); markR.className = "picker-mark-right";
    el.appendChild(markL); el.appendChild(markR);

    // track + items
    const track = document.createElement("div");
    track.className = "picker-track";
    el.appendChild(track);

    // fade overlays
    const fT = document.createElement("div"); fT.className = "picker-fade-top";
    const fB = document.createElement("div"); fB.className = "picker-fade-bot";
    el.appendChild(fT); el.appendChild(fB);

    let activeUnit = units[0]; // "cm" or "kg"
    function range() {
      return activeUnit === units[0] ? [minA, maxA] : [minB, maxB];
    }
    function rebuildItems() {
      track.innerHTML = "";
      const [min, max] = range();
      for (let v = min; v <= max; v++) {
        const item = document.createElement("div");
        item.className = "picker-item";
        item.textContent = v;
        item.dataset.value = v;
        track.appendChild(item);
      }
    }
    rebuildItems();

    const center = () => el.clientHeight / 2 - ITEM_H / 2;
    let offset = 0;
    let dragOffset = 0;
    let dragging = false;
    let startY = 0;

    function valueToOffset(v) { return center() - (v - range()[0]) * ITEM_H; }
    function offsetToValue(o) {
      const [min, max] = range();
      const v = Math.round((center() - o) / ITEM_H) + min;
      return Math.max(min, Math.min(max, v));
    }
    function getValue() { return state[key + "_" + activeUnit]; }
    function setValue(v) { state[key + "_" + activeUnit] = v; }

    function apply(animate) {
      track.style.transition = animate ? "transform .18s ease-out" : "none";
      const y = offset + dragOffset;
      track.style.transform = "translateY(" + y + "px)";
      ticksL.style.backgroundPosition = "0 " + (y % 8) + "px";
      ticksR.style.backgroundPosition = "0 " + (y % 8) + "px";
      const live = offsetToValue(y);
      Array.from(track.children).forEach((it) => {
        const v = +it.dataset.value;
        const d = Math.abs(v - live);
        it.classList.toggle("is-center", d === 0);
        it.classList.toggle("is-near", d === 1);
        it.style.opacity = d > 3 ? 0 : 1 - d * 0.22;
      });
    }
    function commit() {
      const v = offsetToValue(offset + dragOffset);
      const prev = getValue();
      offset = valueToOffset(v);
      dragOffset = 0;
      setValue(v);
      apply(true);
      renderSummary();
      if (v !== prev) {
        haptic(8);
        const center = track.querySelector(".picker-item.is-center");
        if (center) {
          center.classList.remove("is-pulse");
          // force reflow so the animation restarts every change
          void center.offsetWidth;
          center.classList.add("is-pulse");
        }
      }
    }

    function setUnit(u) {
      if (!units.includes(u) || u === activeUnit) return;
      activeUnit = u;
      rebuildItems();
      offset = valueToOffset(getValue());
      apply(false);
    }

    let lastTickedValue = null;
    el.addEventListener("pointerdown", (e) => {
      dragging = true; startY = e.clientY;
      lastTickedValue = offsetToValue(offset);
      try { el.setPointerCapture(e.pointerId); } catch (_) {}
    });
    el.addEventListener("pointermove", (e) => {
      if (!dragging) return;
      dragOffset = e.clientY - startY;
      apply(false);
      const live = offsetToValue(offset + dragOffset);
      if (live !== lastTickedValue) {
        lastTickedValue = live;
        haptic(5);
      }
    });
    function endDrag(e) {
      if (!dragging) return;
      dragging = false;
      try { el.releasePointerCapture(e.pointerId); } catch (_) {}
      commit();
    }
    el.addEventListener("pointerup", endDrag);
    el.addEventListener("pointercancel", endDrag);
    el.addEventListener("pointerleave", endDrag);

    el.addEventListener("wheel", (e) => {
      e.preventDefault();
      const [min, max] = range();
      // wheel up (deltaY<0) increases the value, matching the drag-up feel
      offset += Math.sign(e.deltaY) * ITEM_H;
      offset = Math.max(valueToOffset(max), Math.min(valueToOffset(min), offset));
      commit();
    }, { passive: false });

    el.tabIndex = 0;
    el.addEventListener("keydown", (e) => {
      if (e.key === "ArrowUp")   { offset += ITEM_H; commit(); e.preventDefault(); }
      if (e.key === "ArrowDown") { offset -= ITEM_H; commit(); e.preventDefault(); }
    });

    track.addEventListener("click", (e) => {
      const item = e.target.closest(".picker-item");
      if (!item) return;
      offset = valueToOffset(+item.dataset.value);
      commit();
    });

    return {
      refresh() { offset = valueToOffset(getValue()); apply(false); },
      setUnit,
      get activeUnit() { return activeUnit; },
    };
  }

  const pickers = {};
  document.querySelectorAll(".picker").forEach((el) => {
    pickers[el.dataset.picker] = buildPicker(el);
  });
  window._pickers = pickers;

  // Unit toggle wiring
  document.querySelectorAll(".unit-toggle").forEach((row) => {
    row.addEventListener("click", (e) => {
      const btn = e.target.closest("button");
      if (!btn) return;
      row.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === btn));
      const key = row.dataset.toggle;
      pickers[key].setUnit(btn.dataset.unit);
      renderSummary();
    });
  });

  function renderSummary() {
    const s = document.getElementById("summary");
    if (!s) return;
    const hU = pickers.height ? pickers.height.activeUnit : "cm";
    const wU = pickers.weight ? pickers.weight.activeUnit : "kg";
    const h = state["height_" + hU];
    const w = state["weight_" + wU];
    const body = state.body ? " · " + state.body : "";
    s.textContent = h + " " + hU + " · " + w + " " + wU + body;
  }
  renderSummary();

  // Initial screen
  const initial = (location.hash || "#splash").slice(1);
  show(order.includes(initial) ? initial : "splash");

  window.addEventListener("hashchange", () => {
    const id = location.hash.slice(1);
    if (order.includes(id)) show(id);
  });

  // Auto-advance splash after a beat
  if (initial === "splash" || !location.hash) {
    setTimeout(() => {
      if (document.querySelector('.screen[data-screen="splash"]').classList.contains("is-active")) {
        show("welcome");
      }
    }, 1400);
  }
})();
