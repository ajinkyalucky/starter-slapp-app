# Quirk Cam

A silly camera game: the browser reads your facial expression (face-api.js, runs 100% locally, nothing uploaded)
and announces your mood as a dramatic persona, e.g. "Goose With a Grudge" or "Cat Meeting a Cucumber".

- **Just read me** – free mode, live quirky verdicts + invented "science" stats.
- **Mood Missions** – 5 rounds, act out the prompt (hold the emotion ~1s) before the 8s timer ends.
- **Snap** – saves a photo with the AI's caption baked in.

Run it (camera needs https or localhost):

    cd quirk-cam && python3 -m http.server 8000   # then open http://localhost:8000

`vendor/` holds @vladmandic/face-api 1.7.13 plus the tiny face detector and expression models, so no CDN is needed.
