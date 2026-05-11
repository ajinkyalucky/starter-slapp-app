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

  // Body type selection
  document.querySelectorAll(".body-card").forEach((c) => {
    c.addEventListener("click", () => {
      document.querySelectorAll(".body-card").forEach((b) => b.classList.remove("is-selected"));
      c.classList.add("is-selected");
      state.body = c.dataset.body;
      renderSummary();
    });
  });

  // ----- Shared profile state + interactive picker -----
  const state = { height: 175, weight: 67, body: "male" };
  const ITEM_H = 56;

  function buildPicker(el) {
    const min = +el.dataset.min;
    const max = +el.dataset.max;
    const unit = el.dataset.unit;
    const key = el.dataset.picker;

    el.innerHTML = "";
    const track = document.createElement("div");
    track.className = "picker-track";
    for (let v = min; v <= max; v++) {
      const item = document.createElement("div");
      item.className = "picker-item";
      item.textContent = v;
      item.dataset.value = v;
      track.appendChild(item);
    }
    el.appendChild(track);

    const mark = document.createElement("div");
    mark.className = "picker-mark";
    mark.innerHTML = '<span class="arrow">‹</span><span class="bar"></span><span class="unit">' + unit + "</span>";
    el.appendChild(mark);

    const center = () => el.clientHeight / 2 - ITEM_H / 2;
    let value = state[key];
    let offset = 0;
    let dragOffset = 0;
    let dragging = false;
    let startY = 0;

    function valueToOffset(v) { return center() - (v - min) * ITEM_H; }
    function offsetToValue(o) {
      const v = Math.round((center() - o) / ITEM_H) + min;
      return Math.max(min, Math.min(max, v));
    }
    function apply(animate) {
      track.style.transition = animate ? "transform .18s ease-out" : "none";
      track.style.transform = "translateY(" + (offset + dragOffset) + "px)";
      const live = offsetToValue(offset + dragOffset);
      Array.from(track.children).forEach((it) => {
        const v = +it.dataset.value;
        const d = Math.abs(v - live);
        it.classList.toggle("is-center", d === 0);
        it.classList.toggle("is-near", d === 1);
        it.style.opacity = d > 3 ? 0 : 1 - d * 0.18;
      });
    }
    function commit() {
      value = offsetToValue(offset + dragOffset);
      offset = valueToOffset(value);
      dragOffset = 0;
      state[key] = value;
      apply(true);
      renderSummary();
    }

    offset = valueToOffset(value);
    apply(false);

    // Pointer drag
    el.addEventListener("pointerdown", (e) => {
      dragging = true;
      startY = e.clientY;
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener("pointermove", (e) => {
      if (!dragging) return;
      dragOffset = e.clientY - startY;
      apply(false);
    });
    function endDrag(e) {
      if (!dragging) return;
      dragging = false;
      try { el.releasePointerCapture(e.pointerId); } catch (_) {}
      commit();
    }
    el.addEventListener("pointerup", endDrag);
    el.addEventListener("pointercancel", endDrag);

    // Wheel
    el.addEventListener("wheel", (e) => {
      e.preventDefault();
      offset -= Math.sign(e.deltaY) * ITEM_H;
      offset = Math.max(valueToOffset(max), Math.min(valueToOffset(min), offset));
      commit();
    }, { passive: false });

    // Keyboard when focused
    el.tabIndex = 0;
    el.addEventListener("keydown", (e) => {
      if (e.key === "ArrowUp")   { offset += ITEM_H; commit(); e.preventDefault(); }
      if (e.key === "ArrowDown") { offset -= ITEM_H; commit(); e.preventDefault(); }
    });

    // Tap an item to jump
    track.addEventListener("click", (e) => {
      const item = e.target.closest(".picker-item");
      if (!item) return;
      offset = valueToOffset(+item.dataset.value);
      commit();
    });

    return { refresh: () => { offset = valueToOffset(state[key]); apply(true); } };
  }

  const pickers = {};
  document.querySelectorAll(".picker").forEach((el) => {
    pickers[el.dataset.picker] = buildPicker(el);
  });
  window._pickers = pickers;

  function renderSummary() {
    const s = document.getElementById("summary");
    if (s) s.textContent = state.height + " cm · " + state.weight + " kg · " + state.body;
  }
  renderSummary();

  // Initial screen
  const initial = (location.hash || "#splash").slice(1);
  show(order.includes(initial) ? initial : "splash");

  // Auto-advance splash after a beat
  if (initial === "splash" || !location.hash) {
    setTimeout(() => {
      if (document.querySelector('.screen[data-screen="splash"]').classList.contains("is-active")) {
        show("welcome");
      }
    }, 1400);
  }
})();
