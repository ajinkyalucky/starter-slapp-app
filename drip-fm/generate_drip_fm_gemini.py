import os
import sys
import time
import wave
import base64
import json
import urllib.request
import urllib.error

API_KEY = os.environ.get("GEMINI_API_KEY")
VOICE_NAME = "Sulafat"  # Options: Sulafat, Despina, Aoede, Gacrux
MODEL_ID = os.environ.get("MODEL_ID", "gemini-3.8-flash-tts")
OUT_DIR = os.environ.get("OUT_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio"))

STYLE_DIRECTION = (
    "Speak as a female host on a late-night city radio station. "
    "Warm, smooth, confident, slightly playful, unhurried. "
    "Premium editorial tone, never like an ad read. "
    "Pause briefly at ellipses and take a full one-second beat at [beat]:\n\n"
)

SEGMENTS = {
    "01-arrival": "Good evening… and welcome to Drip. [beat] You're listening to Drip FM, live from the club. Drip is an invite-only shopping app for men. Men's shopping… upgraded. [beat] The doors are open. Come on in.",
    "02-lounge": "Take a seat in the lounge. [beat] Most shopping apps hand you a million products… and wish you luck. Drip does the opposite. Every label, every piece, even your size… is picked for you. You just walk in. [beat] The DJ's in the booth at the back. Move on when you're ready… and I'll show you round.",
    "03-labels": "On your right… the labels wall. Over a hundred brands. One address. [beat] Drip isn't a brand. It's a platform for the labels worth wearing. Rare Rabbit, Code Brown, Motherland, Mint and Oak… and plenty more up there. Every piece picked, and checked, before it ever reaches you.",
    "04-stair": "Now… across the hall, and up the stairs. [beat] Somebody up here never blinks. At the top, on your left… the surveillance room.",
    "05-ccroom": "Every piece is watched. [beat] On camera three, the curation floor: a sneaker passes three checks in an inspector's hands… then the pair is matched. On camera seven, final inspection. Cleared pieces go to packing. [beat] Fabric. Stitching. Fit. Durability. Only qualities making the cut. Tap Watch the feeds… and see for yourself.",
    "05a-cam03": "Camera three. The curation floor. [beat] One sneaker, three checks, in an inspector's hands. Pass all three… and the pair is matched.",
    "05b-cam07": "Camera seven. Final inspection. [beat] A jacket, a shirt… each one checked before it's cleared. Cleared pieces go to packing. [beat] Over a hundred thousand styles never made it this far.",
    "06-stylist": "Through here… the stylist's room. Drip is handpicked by more than two hundred stylists. [beat] First, your stylist reads your colours. In daylight, one drape at a time. Then… your collection. Twelve pieces, from over a hundred labels. [beat] Fit first. Then colour.",
    "07-lift": "This is the glass lift. [beat] Best view in the house. One more move… and we ride it down to the hall. Together.",
    "08-ride": "Going down. [beat] While we ride… this is the club. Every spend on Drip unlocks your next upgrade. Seven levels… of exclusive rewards. [beat] Mind the doors.",
    "09-car": "And here she is… under the pool light. Easy on the eyes, isn't she? [beat] Drip is members only. We let in a few members at a time… and your invite code arrives when the doors open for you. [beat] One more move takes you back to the lounge.",
    "10-loop-back": "Back across the hall, then. [beat] Same lounge, same DJ… and me, right here on Drip FM. Go round again. I'm not going anywhere.",
    "id-01": "You're listening to Drip FM.",
    "id-02": "Drip FM. [beat] Men's shopping, upgraded.",
    "id-03": "This is Drip FM… live from the club.",
    "id-04": "Drip FM. Members only.",
    "id-05": "Stay close. This is Drip FM.",
    "id-06": "Drip FM. [beat] Picked for you.",
    "fill-01": "If you're just joining us… Drip is an invite-only shopping app for men. Every label, every piece, picked for you.",
    "fill-02": "Over a hundred thousand styles didn't make the cut. [beat] The ones that did… you'll find on Drip.",
    "fill-03": "Over a hundred brands. More than two hundred stylists. Seven levels of rewards. [beat] Not bad for one address.",
    "fill-04": "The DJ's still spinning at the back of the hall. Tap a record on her ledge… and she'll put it on.",
    "fill-05": "Even your size is picked for you. [beat] No more guessing between a medium… and a large.",
    "fill-06": "Fabric. Stitching. Fit. Durability. [beat] Four checks, on every piece.",
    "fill-07": "Built by Audacity. Made in India. [beat] And playing wherever you are in the club.",
    "fill-08": "Still with me? Good. [beat] Drip FM never closes. It's only the doors that are picky.",
    "fill-09": "Coming up, at the top of the stairs… the surveillance room. Where every piece is watched.",
    "fill-10": "Upstairs, a stylist is reading someone's colours right now. [beat] Deep Autumn… if I had to guess.",
}

def synth(text: str) -> bytes:
    """Call the Gemini REST API directly; returns a complete WAV file as bytes."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL_ID}:generateContent"
    body = {
        "contents": [{"parts": [{"text": STYLE_DIRECTION + text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": VOICE_NAME}}},
        },
    }
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": API_KEY},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                data = json.load(r)
            break
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 503) and attempt < 3:
                time.sleep(5 * (attempt + 1))
                continue
            raise SystemExit(f"API error {e.code}: {e.read().decode()[:500]}")
    part = data["candidates"][0]["content"]["parts"][0]["inlineData"]
    audio = base64.b64decode(part["data"])
    if audio[:4] == b"RIFF":  # already a WAV file
        return audio
    import io
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(24000)
        wf.writeframes(audio)
    return buf.getvalue()

def main():
    if not API_KEY:
        raise SystemExit("Set GEMINI_API_KEY first: export GEMINI_API_KEY='your_key'")

    only = sys.argv[1:]  # optional: segment ids to run, e.g. 01-arrival
    os.makedirs(OUT_DIR, exist_ok=True)

    for seg_id, text in SEGMENTS.items():
        if only and seg_id not in only:
            continue
        out_path = os.path.join(OUT_DIR, f"{seg_id}.wav")
        if os.path.exists(out_path) and not only:
            print(f"Skipping {seg_id}.wav (already exists)")
            continue
        print(f"Generating {seg_id}.wav ...", flush=True)
        with open(out_path, "wb") as f:
            f.write(synth(text))
        time.sleep(2)

    print(f"\nDone! Files saved in {OUT_DIR}/")

if __name__ == "__main__":
    main()
