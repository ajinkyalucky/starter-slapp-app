# Rewards film — photoreal shot prompts

Five shots, 13 s, 1920×1080, 24 fps. The order is the reference film reversed: the door opens first, the room last.
Use image-to-video where possible: feed the matching frame from `rewards-film.mp4` as the start image so layout and camera match, and attach the reward photo named in each shot as a reference.

**Shared style (append to every prompt)**
Photoreal architectural interior film. Private gallery room at dusk: oak-veneer wall bays, dark bronze metal frames, taupe carpet, thin warm LED lines along the top and bottom of the walls, cool blue evening light from a full-height window. Low-key lighting, deep soft shadows, warm 2700K practicals against cool daylight. Slow, steady camera on a slider. Shallow grain, no people, no text, no logos added, no lens flare.

| # | Time | Shot | Prompt |
|---|------|------|--------|
| 1 | 0.0–3.5 s | Door opens | Black screen. A tall matte taupe sliding door, dark bronze pull handle, fills the frame in near darkness. It glides open to the left, a strip of warm light widening, revealing the gallery behind it: a glass display case in the centre and red framed product photographs on the oak wall beyond. Camera pushes in slowly, straight on. |
| 2 | 3.5–5.7 s | From above | High overhead view of the same room, camera rolled about 20° like an architectural plan. Glass display case in the middle, low linen bench and rug, three warm paper globe pendants, red framed photographs along two walls, blue dusk window on the right. Very slow drift. |
| 3 | 5.7–7.9 s | The case | Close shot into the glass display case. One small framed photograph stands on a bronze stand under a warm spotlight (reference: `08-airpods-pro.jpg`). Reflections of the red wall frames slide across the glass. Slow push in, shallow depth of field. |
| 4 | 7.9–10.3 s | The wall | Straight-on lateral dolly, left to right, along the oak wall. Large framed portrait photographs on red backdrops, one per bay (references in order: `03-coach-tabby.jpg`, `04-mokobara-luggage.jpg`, `05-ck-one.jpg`). Warm wash from above, LED line at the base. |
| 5 | 10.3–13.0 s | The room | Wide shot from the corner by the door. Lights rise from dim to full over one second, then hold: the whole wall of rewards, the case, the lounge chair, the pendants, the dusk window. Slow push in. Fade out over the last half second. |

**Keep the rewards accurate.** Video models redraw small text and logos. Generate the room with plain red panels in the frames, then composite the real photos from `rewards/` onto them (corner-pin track), rather than asking the model to render the products.
