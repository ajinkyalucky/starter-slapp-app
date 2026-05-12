(function () {
  "use strict";

  // ---- Data --------------------------------------------------------------
  // Each shirt drives both the thumbnail and the main model rendering.
  // Colors and trim are passed into SVG factories so the prototype runs
  // fully offline without any external image hosting.
  const SHIRTS = [
    {
      id: "ringer-white-red",
      brand: "H&M",
      title: "Ringer Tee — White / Red",
      price: "₹1290",
      was: "₹1900",
      body: "#ffffff",
      trim: "#e84a5f",
      message:
        "Akshay, the classic ringer tee is a clean everyday pick — pairs with anything in your closet.",
    },
    {
      id: "ringer-white-pink",
      brand: "ZARA",
      title: "Soft Ringer Tee — Pink Trim",
      price: "₹1490",
      was: "₹2100",
      body: "#fafafa",
      trim: "#f29db0",
      message:
        "Akshay, this softer ringer trim gives a more relaxed weekend vibe.",
    },
    {
      id: "louis-philippe-maroon",
      brand: "LOUIS PHILIPPE",
      title: "Slim Fit White Shirt...",
      price: "₹3400",
      was: "₹4900",
      body: "#6b2c2c",
      trim: "#6b2c2c",
      isFeatured: true,
      message:
        "Akshay, this tshirt will fall best on you.\nAlso, this is one of our best sellers.",
    },
    {
      id: "ringer-white-coral",
      brand: "UNIQLO",
      title: "Cotton Ringer Tee — Coral",
      price: "₹1690",
      was: "₹2200",
      body: "#ffffff",
      trim: "#ff7a6b",
      message:
        "Akshay, a coral-trim tee adds just enough pop without going loud.",
    },
    {
      id: "ringer-white-blush",
      brand: "M&S",
      title: "Premium Ringer Tee — Blush",
      price: "₹1990",
      was: "₹2600",
      body: "#fdfdfd",
      trim: "#f0a8b1",
      message:
        "Akshay, the blush trim works well with neutral bottoms and brown shoes.",
    },
  ];

  // ---- SVG factories -----------------------------------------------------
  function thumbnailSvg(shirt) {
    // A flat-lay style t-shirt thumbnail; body + trim colors are driven by data.
    const { body, trim } = shirt;
    return `
      <svg viewBox="0 0 120 110" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <defs>
          <filter id="s-${shirt.id}" x="-10%" y="-10%" width="120%" height="120%">
            <feDropShadow dx="0" dy="2" stdDeviation="1.2" flood-opacity="0.08" />
          </filter>
        </defs>
        <g filter="url(#s-${shirt.id})">
          <path
            d="M30 18 L46 10 Q60 22 74 10 L90 18 L108 28 L96 44 L86 38 L86 96 Q60 102 34 96 L34 38 L24 44 L12 28 Z"
            fill="${body}"
            stroke="#e2e2e2"
            stroke-width="1"
          />
          <!-- Ringer collar -->
          <path
            d="M46 10 Q60 22 74 10 Q72 16 60 18 Q48 16 46 10 Z"
            fill="${trim}"
          />
          <!-- Ringer sleeve trim -->
          <path d="M12 28 L24 44 L20 46 L8 30 Z" fill="${trim}" />
          <path d="M108 28 L96 44 L100 46 L112 30 Z" fill="${trim}" />
        </g>
      </svg>
    `;
  }

  function modelSvg(shirt) {
    // A stylized standing figure where the t-shirt fill is driven by the
    // currently selected shirt. Keeps everything self-contained.
    const { body, trim } = shirt;
    return `
      <svg viewBox="0 0 240 540" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <defs>
          <linearGradient id="pants" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stop-color="#5a3a22" />
            <stop offset="100%" stop-color="#3d2615" />
          </linearGradient>
          <linearGradient id="skin" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stop-color="#e6c4a6" />
            <stop offset="100%" stop-color="#c89d7d" />
          </linearGradient>
        </defs>

        <!-- Head -->
        <ellipse cx="120" cy="60" rx="34" ry="40" fill="url(#skin)" />
        <!-- Hair -->
        <path
          d="M86 50 Q100 18 138 22 Q160 30 156 56 Q150 44 130 42 Q108 44 92 60 Z"
          fill="#2b1a10"
        />
        <!-- Neck -->
        <rect x="108" y="92" width="24" height="22" fill="url(#skin)" />

        <!-- T-shirt body -->
        <path
          d="M70 120 L100 108 Q120 122 140 108 L170 120 L196 150 L178 178 L164 168 L164 290 Q120 304 76 290 L76 168 L62 178 L44 150 Z"
          fill="${body}"
          stroke="#dcdcdc"
          stroke-width="1.5"
        />
        <!-- Ringer collar -->
        <path
          d="M100 108 Q120 122 140 108 Q138 118 120 120 Q102 118 100 108 Z"
          fill="${trim}"
        />
        <!-- Sleeve trim -->
        <path d="M44 150 L62 178 L56 184 L38 156 Z" fill="${trim}" />
        <path d="M196 150 L178 178 L184 184 L202 156 Z" fill="${trim}" />

        <!-- Arms (skin) -->
        <path d="M58 178 Q44 220 50 270 L66 268 Q62 224 72 184 Z" fill="url(#skin)" />
        <path d="M182 178 Q196 220 190 270 L174 268 Q178 224 168 184 Z" fill="url(#skin)" />

        <!-- Belt -->
        <rect x="80" y="290" width="80" height="10" fill="#1a1208" />
        <rect x="116" y="290" width="10" height="10" fill="#8a6a3a" />

        <!-- Pants -->
        <path
          d="M76 300 L164 300 L168 500 L130 500 L122 340 L118 340 L110 500 L72 500 Z"
          fill="url(#pants)"
        />

        <!-- Shoes -->
        <ellipse cx="92" cy="510" rx="26" ry="12" fill="#0e0e0e" />
        <ellipse cx="148" cy="510" rx="26" ry="12" fill="#0e0e0e" />
      </svg>
    `;
  }

  // ---- Render ------------------------------------------------------------
  const thumbsEl = document.querySelector(".thumbs");
  const modelEl = document.querySelector(".model");
  const modelImg = document.getElementById("model-image");
  const card = document.getElementById("product-card");
  const cardImg = document.getElementById("product-image");
  const brandEl = document.getElementById("product-brand");
  const titleEl = document.getElementById("product-title");
  const priceEl = document.getElementById("product-price");
  const wasEl = document.getElementById("product-was");
  const assistantText = document.getElementById("assistant-text");

  function svgToDataUrl(svg) {
    // Trim leading whitespace; encodeURIComponent handles special chars.
    return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg.trim());
  }

  function renderThumbs() {
    thumbsEl.innerHTML = "";
    SHIRTS.forEach((shirt, idx) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `thumb thumb--${idx + 1}`;
      btn.dataset.shirtId = shirt.id;
      btn.setAttribute("role", "option");
      btn.setAttribute("aria-label", `${shirt.brand} ${shirt.title}`);

      const img = document.createElement("img");
      img.src = svgToDataUrl(thumbnailSvg(shirt));
      img.alt = "";
      btn.appendChild(img);

      btn.addEventListener("click", () => select(shirt.id));
      thumbsEl.appendChild(btn);
    });
  }

  function select(id) {
    const shirt = SHIRTS.find((s) => s.id === id);
    if (!shirt) return;

    // Fade the model while we swap the SVG so the change feels intentional.
    modelEl.classList.add("is-loading");
    window.requestAnimationFrame(() => {
      modelImg.src = svgToDataUrl(modelSvg(shirt));
      modelImg.onload = () => modelEl.classList.remove("is-loading");
    });

    // Mark selected thumb and place the product card in its slot.
    document.querySelectorAll(".thumb").forEach((t) => {
      t.classList.toggle("is-selected", t.dataset.shirtId === id);
    });

    // Product card
    cardImg.src = svgToDataUrl(thumbnailSvg(shirt));
    cardImg.alt = `${shirt.brand} ${shirt.title}`;
    brandEl.textContent = shirt.brand;
    titleEl.textContent = shirt.title;
    priceEl.textContent = shirt.price;
    wasEl.textContent = shirt.was;
    card.hidden = false;
    positionCardOverSelectedThumb();

    // Assistant message swaps per selection so it feels conversational.
    assistantText.innerHTML = shirt.message.replace(/\n/g, "<br />");
  }

  function positionCardOverSelectedThumb() {
    const selected = document.querySelector(".thumb.is-selected");
    if (!selected) return;
    const stage = document.querySelector(".stage");
    const sRect = stage.getBoundingClientRect();
    const tRect = selected.getBoundingClientRect();
    // Align card's left edge with the selected thumb's left edge, vertically centered on it.
    const top = tRect.top - sRect.top - 22;
    card.style.top = `${Math.max(20, top)}px`;
  }

  window.addEventListener("resize", positionCardOverSelectedThumb);

  // ---- Boot --------------------------------------------------------------
  renderThumbs();
  // Default to the "featured" shirt from the reference design.
  const initial = SHIRTS.find((s) => s.isFeatured) || SHIRTS[0];
  select(initial.id);
})();
