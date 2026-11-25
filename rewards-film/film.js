import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const W = 1920, H = 1080;
export const DURATION = 13, FPS = 24;

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x030303);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.12;

const camera = new THREE.PerspectiveCamera(40, W / H, 0.05, 60);

// ---------- helpers ----------
const std = (color, rough = 0.8, metal = 0, extra = {}) =>
  new THREE.MeshStandardMaterial({ color, roughness: rough, metalness: metal, ...extra });
function box(w, h, d, mat, x, y, z, parent = scene) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true;
  parent.add(m); return m;
}
function canvasTex(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}
// deterministic noise
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;

// ---------- materials ----------
const woodTex = canvasTex(1024, 1024, (g, w, h) => {
  g.fillStyle = '#7a6049'; g.fillRect(0, 0, w, h);
  for (let i = 0; i < 900; i++) {
    const x = rnd() * w; g.globalAlpha = 0.04 + rnd() * 0.07;
    g.fillStyle = rnd() > 0.5 ? '#3d2c1f' : '#a88a6c';
    g.fillRect(x, 0, 1 + rnd() * 2.5, h);
  }
  g.globalAlpha = 1;
});
woodTex.wrapS = woodTex.wrapT = THREE.RepeatWrapping;
const wood = std(0xffffff, 0.62, 0, { map: woodTex });
const woodDark = std(0x8a7a6c, 0.6, 0, { map: woodTex });
const wall = std(0x4b4640, 0.92);
const carpetTex = canvasTex(512, 512, (g, w, h) => {
  g.fillStyle = '#56524d'; g.fillRect(0, 0, w, h);
  for (let i = 0; i < 26000; i++) {
    g.globalAlpha = 0.05 + rnd() * 0.08; g.fillStyle = rnd() > 0.5 ? '#2c2a27' : '#7b766f';
    g.fillRect(rnd() * w, rnd() * h, 1.5, 1.5);
  }
});
carpetTex.wrapS = carpetTex.wrapT = THREE.RepeatWrapping; carpetTex.repeat.set(6, 6);
const floorMat = std(0xffffff, 0.97, 0, { map: carpetTex });
const metal = std(0x2a2826, 0.35, 0.9);
const led = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.0, 0.72, 0.42).multiplyScalar(2.4) });
const glass = new THREE.MeshPhysicalMaterial({
  color: 0xcfd8dc, roughness: 0.02, metalness: 0, transparent: true, opacity: 0.1,
  envMapIntensity: 6, depthWrite: false, side: THREE.DoubleSide,
});
const leather = std(0x8a4f2e, 0.55);
const linen = std(0xb9b0a3, 0.95);

// ---------- room: x -4..4, y 0..3, z -6..0 ----------
const room = new THREE.Group(); scene.add(room);
const floor = box(8, 0.1, 6.4, floorMat, 0, -0.05, -3, room); floor.castShadow = false;
const ceiling = box(8, 0.1, 6.4, std(0x2e2b28, 0.9), 0, 3.05, -3, room);
box(8, 3, 0.1, wall, 0, 1.5, -6.05, room);            // back
box(0.1, 3, 6.4, wall, -4.05, 1.5, -3, room);          // left
// right wall: night window
box(0.1, 3, 1.2, wall, 4.05, 1.5, -0.6, room);
box(0.1, 3, 1.0, wall, 4.05, 1.5, -5.5, room);
const nightTex = canvasTex(1024, 512, (g, w, h) => {
  const gr = g.createLinearGradient(0, 0, 0, h);
  gr.addColorStop(0, '#93a7bd'); gr.addColorStop(0.55, '#5d7186'); gr.addColorStop(1, '#27323d');
  g.fillStyle = gr; g.fillRect(0, 0, w, h);
  // soft tree line
  for (let i = 0; i < 70; i++) {
    const x = rnd() * w, r = 40 + rnd() * 90, y = h * (0.62 + rnd() * 0.3);
    const rg = g.createRadialGradient(x, y, 0, x, y, r);
    rg.addColorStop(0, 'rgba(18,26,32,0.85)'); rg.addColorStop(1, 'rgba(18,26,32,0)');
    g.fillStyle = rg; g.fillRect(x - r, y - r, r * 2, r * 2);
  }
});
const night = new THREE.Mesh(new THREE.PlaneGeometry(5.2, 3.4),
  new THREE.MeshBasicMaterial({ map: nightTex, color: new THREE.Color(0.55, 0.6, 0.68) }));
night.rotation.y = -Math.PI / 2; night.position.set(4.6, 1.5, -3.1); room.add(night);
for (const z of [-1.2, -3.1, -5.0]) box(0.06, 3, 0.05, metal, 4.0, 1.5, z, room); // mullions
const winGlass = new THREE.Mesh(new THREE.PlaneGeometry(3.8, 3), glass);
winGlass.rotation.y = -Math.PI / 2; winGlass.position.set(4.0, 1.5, -3.1); room.add(winGlass);

// ---------- reward cards ----------
const REWARD_COUNT = 8;
function placeholderTex(i) {
  return canvasTex(768, 960, (g, w, h) => {
    const tones = ['#efe9df', '#e6ddd0', '#dcd3c6', '#ece4d6'];
    g.fillStyle = tones[i % tones.length]; g.fillRect(0, 0, w, h);
    const rg = g.createRadialGradient(w * 0.5, h * 0.42, 20, w * 0.5, h * 0.42, w * 0.8);
    rg.addColorStop(0, 'rgba(255,255,255,0.55)'); rg.addColorStop(1, 'rgba(120,100,80,0.18)');
    g.fillStyle = rg; g.fillRect(0, 0, w, h);
    g.strokeStyle = 'rgba(60,48,38,0.55)'; g.lineWidth = 3;
    g.beginPath(); g.arc(w / 2, h * 0.42, 150, 0, Math.PI * 2); g.stroke();
    g.fillStyle = 'rgba(50,40,32,0.8)'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.font = '200 150px Inter, "Helvetica Neue", sans-serif';
    g.fillText(String(i + 1).padStart(2, '0'), w / 2, h * 0.43);
  });
}
const rewardTex = [];
async function loadRewards() {
  const loader = new THREE.TextureLoader();
  let files = [];
  try { files = await (await fetch('./rewards/manifest.json')).json(); } catch (e) {}
  for (let i = 0; i < REWARD_COUNT; i++) {
    if (files.length) {
      const t = await loader.loadAsync('./rewards/' + files[i % files.length]);
      t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; rewardTex.push(t);
    } else rewardTex.push(placeholderTex(i));
  }
}
// A framed reward: image keeps its aspect inside a w×h mat (cover-fit via UV crop).
function rewardCard(i, w, h, parent, x, y, z, ry = 0, glow = 0.42) {
  const g = new THREE.Group(); g.position.set(x, y, z); g.rotation.y = ry; parent.add(g);
  box(w + 0.03, h + 0.03, 0.02, metal, 0, 0, 0, g);
  const t = rewardTex[i % rewardTex.length].clone(); t.needsUpdate = true;
  const ia = t.image.width / t.image.height, ca = w / h;
  if (ia > ca) { t.repeat.set(ca / ia, 1); t.offset.set((1 - ca / ia) / 2, 0); }
  else { t.repeat.set(1, ia / ca); t.offset.set(0, (1 - ia / ca) / 2); }
  const face = new THREE.Mesh(new THREE.PlaneGeometry(w, h),
    new THREE.MeshStandardMaterial({ map: t, roughness: 0.6, emissive: 0xffffff, emissiveMap: t, emissiveIntensity: glow }));
  face.position.z = 0.0105; face.receiveShadow = true; g.add(face);
  return g;
}

// ---------- furnishings (built after textures load) ----------
const lights = {}; const globes = [];
function build() {
  // Back wall: wood panelling in bays with LED lines and hung rewards
  const back = new THREE.Group(); back.position.set(0, 0, -5.98); room.add(back);
  for (let i = 0; i < 5; i++) {
    const p = box(1.36, 2.5, 0.06, wood, -2.8 + i * 1.4, 1.35, 0.03, back); p.castShadow = false;
  }
  for (let i = 0; i <= 5; i++) box(0.04, 2.5, 0.12, metal, -3.5 + i * 1.4, 1.35, 0.06, back);
  box(7.0, 0.02, 0.03, led, 0, 2.63, 0.1, back);
  box(7.0, 0.02, 0.03, led, 0, 0.08, 0.1, back);
  box(7.04, 0.05, 0.3, woodDark, 0, 2.66, 0.15, back);
  box(7.04, 0.08, 0.34, woodDark, 0, 0.04, 0.17, back);
  for (let i = 0; i < 5; i++) rewardCard(i, 0.84, 1.26, back, -2.8 + i * 1.4, 1.42, 0.1);

  // Left wall: shelving with two more rewards
  const left = new THREE.Group(); left.position.set(-3.98, 0, -3); left.rotation.y = Math.PI / 2; room.add(left);
  for (let i = 0; i < 4; i++) { const p = box(1.36, 2.5, 0.06, wood, -2.1 + i * 1.4, 1.35, 0.03, left); p.castShadow = false; }
  for (let i = 0; i <= 4; i++) box(0.04, 2.5, 0.12, metal, -2.8 + i * 1.4, 1.35, 0.06, left);
  box(5.6, 0.02, 0.03, led, 0, 2.63, 0.1, left);
  box(5.6, 0.02, 0.03, led, 0, 0.08, 0.1, left);
  for (const i of [0, 3]) for (const y of [0.7, 1.35, 2.0]) box(1.3, 0.03, 0.3, woodDark, -2.1 + i * 1.4, y, 0.2, left);
  rewardCard(5, 0.84, 1.26, left, -0.7, 1.42, 0.1);
  rewardCard(6, 0.84, 1.26, left, 0.7, 1.42, 0.1);

  // Vitrine island with the hero reward
  const vit = new THREE.Group(); vit.position.set(0, 0, -2.6); room.add(vit);
  box(2.2, 0.72, 0.9, wood, 0, 0.36, 0, vit);
  box(2.24, 0.03, 0.94, metal, 0, 0.735, 0, vit);
  const inner = box(2.1, 0.012, 0.8, std(0xc9b79f, 0.9), 0, 0.756, 0, vit); inner.castShadow = false;
  const gh = 0.5, gy = 0.75 + gh / 2;
  const gmesh = (w, h, d, x, y, z) => { const m = box(w, h, d, glass, x, y, z, vit); m.castShadow = false; m.receiveShadow = false; m.renderOrder = 5; };
  gmesh(2.2, gh, 0.006, 0, gy, 0.45); gmesh(2.2, gh, 0.006, 0, gy, -0.45);
  gmesh(0.006, gh, 0.9, 1.1, gy, 0); gmesh(0.006, gh, 0.9, -1.1, gy, 0);
  gmesh(2.2, 0.006, 0.9, 0, 0.75 + gh, 0);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) box(0.016, gh, 0.016, metal, sx * 1.1, gy, sz * 0.45, vit);
  for (const sz of [-1, 1]) box(2.2, 0.016, 0.016, metal, 0, 0.75 + gh, sz * 0.45, vit);
  for (const sx of [-1, 1]) box(0.016, 0.016, 0.9, metal, sx * 1.1, 0.75 + gh, 0, vit);
  box(2.1, 0.008, 0.012, led, 0, 0.77, 0.43, vit);
  // hero card on a small stand, leaning back
  const stand = new THREE.Group(); stand.position.set(0, 0.762, -0.02); vit.add(stand);
  box(0.36, 0.02, 0.16, metal, 0, 0.01, 0, stand);
  const hero = rewardCard(7, 0.28, 0.42, stand, 0, 0.235, -0.01, 0, 0.22); hero.rotation.x = -0.12;

  // Rug, bench, lounge chair, pendant globes
  const rug = box(3.4, 0.015, 2.2, std(0x7d766c, 1), 0.6, 0.008, -4.3, room); rug.castShadow = false;
  box(1.7, 0.1, 0.8, linen, 0.9, 0.36, -4.45, room);
  box(1.6, 0.04, 0.72, metal, 0.9, 0.29, -4.45, room);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) box(0.03, 0.28, 0.03, metal, 0.9 + sx * 0.78, 0.14, -4.45 + sz * 0.33, room);
  const chair = new THREE.Group(); chair.position.set(-1.25, 0, -4.55); chair.rotation.y = 0.5; room.add(chair);
  box(0.72, 0.3, 0.7, leather, 0, 0.3, 0, chair);
  const bk = box(0.72, 0.62, 0.14, leather, 0, 0.62, -0.3, chair); bk.rotation.x = -0.2;
  box(0.64, 0.14, 0.6, std(0x3a3835, 0.8), 0, 0.08, 0, chair);
  const globe = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.0, 0.8, 0.55).multiplyScalar(1.35) });
  [[0.55, 2.2, -4.3, 0.2], [0.95, 2.05, -4.5, 0.24], [1.3, 2.28, -4.25, 0.17]].forEach(([x, y, z, r]) => {
    const s = new THREE.Mesh(new THREE.SphereGeometry(r, 48, 32), globe); s.position.set(x, y, z); s.scale.y = 0.78; room.add(s); globes.push(s);
    box(0.006, 3 - y - r * 0.7, 0.006, metal, x, (3 + y + r * 0.7) / 2, z, room).castShadow = false;
  });

  // ---------- lighting ----------
  const spot = (x, y, z, tx, ty, tz, i, ang = 0.5, shadow = true) => {
    const s = new THREE.SpotLight(0xffd2a0, i, 14, ang, 0.75, 1.6);
    s.position.set(x, y, z); s.target.position.set(tx, ty, tz); room.add(s, s.target);
    if (shadow) { s.castShadow = true; s.shadow.mapSize.set(2048, 2048); s.shadow.bias = -0.0004; s.shadow.radius = 6; }
    return s;
  };
  lights.wallA = spot(-1.6, 2.9, -3.6, -1.6, 1.3, -6, 12, 0.8);
  lights.wallB = spot(1.6, 2.9, -3.6, 1.6, 1.3, -6, 12, 0.8);
  lights.vit = spot(0, 2.95, -2.1, 0, 0.8, -2.6, 2.6, 0.42);
  lights.left = spot(-2.2, 2.9, -3, -4, 1.3, -3, 8, 0.85, false);
  const p1 = new THREE.PointLight(0xffc890, 5, 5, 1.8); p1.position.set(0.95, 1.95, -4.4); room.add(p1); lights.globe = p1;
  const p2 = new THREE.PointLight(0xffb070, 0.5, 2.5, 2); p2.position.set(0, 0.95, -2.3); room.add(p2); lights.case = p2;
  const moon = new THREE.DirectionalLight(0x8fa8c8, 0.5); moon.position.set(6, 2.5, -3); room.add(moon); lights.moon = moon;
  room.add(new THREE.HemisphereLight(0x8a8478, 0x3a2e24, 0.75));
}

// ---------- entrance: wall at z=0 with a sliding door ----------
const entry = new THREE.Group(); scene.add(entry);
const doorMat = std(0x5a544c, 0.6);
const jamb = std(0x4f4a43, 0.75);
box(4.2, 3.2, 0.14, jamb, -3.0, 1.6, 0.02, entry);   // wall left of opening (door pockets in front of it)
box(4.2, 3.2, 0.14, jamb, 3.0, 1.6, 0.02, entry);    // wall right of opening
box(1.8, 0.4, 0.14, jamb, 0, 3.0, 0.02, entry);       // header
const door = new THREE.Group(); entry.add(door);
box(1.9, 2.9, 0.05, doorMat, 0, 1.45, 0.14, door);
box(0.018, 0.34, 0.03, metal, 0.84, 1.1, 0.185, door); // pull
const hallFill = new THREE.PointLight(0xd8c8b0, 0, 9, 1.4); hallFill.position.set(0.6, 2.2, 3.2); scene.add(hallFill);
const hallFloor = box(10, 0.1, 5, std(0x2a2826, 0.9), 0, -0.05, 2.6, entry); hallFloor.castShadow = false;

// ---------- post ----------
const rt = new THREE.WebGLRenderTarget(W, H, { samples: 4, type: THREE.HalfFloatType });
const composer = new EffectComposer(renderer, rt);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), 0.4, 0.6, 1.0);
composer.addPass(bloom);
composer.addPass(new OutputPass());
const grade = new ShaderPass({
  uniforms: { tDiffuse: { value: null }, fade: { value: 1 }, time: { value: 0 } },
  vertexShader: 'varying vec2 vUv; void main(){vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
  fragmentShader: `uniform sampler2D tDiffuse; uniform float fade; uniform float time; varying vec2 vUv;
    float h(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233))+time*37.)*43758.5453);}
    void main(){ vec3 c=texture2D(tDiffuse,vUv).rgb;
      vec2 q=vUv-.5; c*=1.-dot(q,q)*0.55;           // vignette
      c=mix(c,c*vec3(1.03,1.0,0.95),0.6);            // warm grade
      c+= (h(vUv*vec2(1920.,1080.))-.5)*0.018;       // fine grain, kills banding
      gl_FragColor=vec4(c*fade,1.); }`,
});
composer.addPass(grade);

// ---------- timeline ----------
const ease = t => t * t * (3 - 2 * t);
const io = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const clamp01 = x => Math.min(1, Math.max(0, x));
const seg = (t, a, b) => clamp01((t - a) / (b - a));
const v = (x, y, z) => new THREE.Vector3(x, y, z);
const tgt = new THREE.Vector3();
function cam(p0, p1, l0, l1, k, fov, roll = 0) {
  camera.position.lerpVectors(p0, p1, k); tgt.lerpVectors(l0, l1, k);
  camera.up.set(0, 1, 0); camera.fov = fov; camera.updateProjectionMatrix();
  camera.lookAt(tgt); if (roll) camera.rotateZ(roll);
}
// Shots: reference film reversed — door opens, then the room.
export const CUTS = [0, 3.5, 5.7, 7.9, 10.3, 13];
function frame(t) {
  let fade = 1;
  ceiling.visible = true; entry.visible = true; globes.forEach(g => (g.visible = true));
  bloom.strength = 0.4;
  const lightsUp = k => {
    lights.wallA.intensity = lights.wallB.intensity = 12 * k; lights.vit.intensity = 2.6 * k;
    lights.left.intensity = 8 * k; lights.globe.intensity = 4 * k; lights.case.intensity = 0.5 * k;
  };
  lightsUp(1);
  if (t < CUTS[1]) {                       // 1 — door slides open
    const k = seg(t, 0, CUTS[1]);
    const open = io(seg(t, 0.9, 3.3));
    door.position.x = -1.86 * open;
    hallFill.intensity = 1.7 * ease(seg(t, 0.1, 1.2));
    cam(v(0.12, 1.5, 4.4), v(0.05, 1.5, 3.7), v(0.1, 1.45, 0), v(0.05, 1.4, -1), ease(k), 34);
    fade = ease(seg(t, 0, 0.9));
  } else if (t < CUTS[2]) {                // 2 — from above
    const k = seg(t, CUTS[1], CUTS[2]);
    ceiling.visible = false; entry.visible = false;
    cam(v(2.1, 8.4, 0.9), v(1.8, 8.0, 0.6), v(0.2, 0, -3.4), v(0.2, 0, -3.4), k, 38, -0.32);
  } else if (t < CUTS[3]) {                // 3 — the case
    const k = seg(t, CUTS[2], CUTS[3]);
    entry.visible = false;
    cam(v(-0.5, 1.42, -1.25), v(-0.3, 1.4, -1.33), v(0.02, 0.98, -2.6), v(0.02, 0.98, -2.6), k, 30);
  } else if (t < CUTS[4]) {                // 4 — the wall
    const k = seg(t, CUTS[3], CUTS[4]);
    entry.visible = false;
    globes.forEach(g => (g.visible = false));
    cam(v(0.5, 1.36, -3.35), v(1.3, 1.36, -3.35), v(0.7, 1.36, -6), v(1.5, 1.36, -6), k, 50);
  } else {                                 // 5 — the room, lights settle up
    const k = seg(t, CUTS[4], CUTS[5]);
    entry.visible = false;
    cam(v(-2.9, 1.75, -0.35), v(-2.6, 1.7, -0.6), v(1.2, 1.1, -4.6), v(1.2, 1.1, -4.6), ease(k), 50);
    lightsUp(0.35 + 0.65 * ease(seg(k, 0, 0.5)));
    fade = 1 - ease(seg(t, 12.4, 13));
  }
  grade.uniforms.fade.value = fade; grade.uniforms.time.value = Math.floor(t * FPS);
  composer.render();
}

await document.fonts.load('200 150px Inter').catch(() => {});
await loadRewards();
build();
window.renderFrame = i => { frame(i / FPS); return true; };
window.ready = true;
const q = new URLSearchParams(location.search);
if (q.has('t')) frame(parseFloat(q.get('t')));
else if (q.has('play')) { const t0 = performance.now(); (function loop() { frame(((performance.now() - t0) / 1000) % DURATION); requestAnimationFrame(loop); })(); }
else frame(4);
