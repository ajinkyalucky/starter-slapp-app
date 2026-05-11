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
    });
  });

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
