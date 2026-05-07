# AI Stylist — Web App

A virtual try-on and AI-curated styling experience. Compare your "current you"
against a "styled you" silhouette, swap looks for Work / Date / Casual / Travel,
and reserve the full look at your nearest store.

## Features

- **Fit Score** with breakdown of shoulder, chest, waist, leg, and posture
- **Side-by-side silhouettes** — Current You vs Styled You with annotations
- **AI Stylist categories** — Work, Date, Casual, Travel (live API-driven)
- **Per-side controls** — lighting and background scene toggles
- **Bottom action bar** — view in motion, lighting, background, reserve look
- **Reserve flow** — 30-minute hold with live countdown timer
- **Store locator** with mini-map and full-map modal
- **Promise tiles** — alterations, returns, save, help

## Run locally

```bash
npm install
npm start
# open http://localhost:3000
```

For development with auto-reload:

```bash
npm run watch
```

## API

| Method | Path                     | Description                           |
|--------|--------------------------|---------------------------------------|
| GET    | `/api/look/:category`    | Returns the curated look + items      |
| POST   | `/api/reserve`           | Holds the look for 30 minutes         |
| GET    | `/healthz`               | Health check                          |

Categories: `work`, `date`, `casual`, `travel`.

## Tech

- Node.js + Express (server)
- Vanilla HTML / CSS / JS (frontend) — no build step
- SVG-only graphics — no external image assets
