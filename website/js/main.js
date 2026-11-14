// Better at Gambling website: one fixed WebGL stage, a camera that travels down a casino hall as
// the page scrolls (stations: logo, tables, shove, minigames, Last Call, podium), plus the page UI.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import Lenis from 'lenis';
import { makeBean, BEAN_COLORS } from './bean.js';
import {
  PAL, chipGeometry, chipMaterials, chipStack, makeRoulette, makeCard, makeFeltTable, makeBigWheel,
  makePegDrop, makeMarquee, makePodium, makeColumn, makeChandelier, makeRope,
} from './props.js';

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const isTouch = matchMedia('(pointer: coarse)').matches;
const body = document.body;
const loaderPct = document.getElementById('loaderPct');

// ------------------------------------------------------------------ page UI (works without WebGL)
const lenis = reduceMotion ? null : new Lenis({ lerp: 0.09, smoothWheel: true });
document.querySelectorAll('a[href^="#"]').forEach((a) => a.addEventListener('click', (e) => {
  const id = a.getAttribute('href');
  const el = id === '#top' ? document.body : document.querySelector(id);
  if (!el) return;
  e.preventDefault();
  if (lenis) lenis.scrollTo(id === '#top' ? 0 : el, { offset: 0, duration: 1.8 });
  else el.scrollIntoView({ behavior: 'smooth' });
}));

const io = new IntersectionObserver((entries) => entries.forEach((en) => {
  if (en.isIntersecting) { en.target.classList.add('is-in'); io.unobserve(en.target); }
}), { threshold: 0.15 });
document.querySelectorAll('.reveal').forEach((el) => io.observe(el));

const vio = new IntersectionObserver((entries) => entries.forEach((en) => {
  const v = en.target;
  if (en.isIntersecting) {
    if (v.dataset.lazy !== 'done') { v.preload = 'auto'; v.load(); v.dataset.lazy = 'done'; }
    v.play().catch(() => {});
  } else v.pause();
}), { threshold: 0.25 });
document.querySelectorAll('video[data-lazy]').forEach((v) => vio.observe(v));

const trailer = document.getElementById('trailerVideo');
document.getElementById('trailerPlay').addEventListener('click', () => {
  trailer.closest('.trailer__frame').classList.add('is-playing');
  trailer.play();
});

const nav = document.getElementById('nav');
let lastY = 0;
const floatCta = document.getElementById('floatCta');
const bigCtas = [...document.querySelectorAll('.cta-steam')];
function navOnScroll(y) {
  const ctaVisible = bigCtas.some((el) => { const r = el.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; });
  floatCta.classList.toggle('is-on', y > innerHeight * 0.8 && !ctaVisible);
  nav.classList.toggle('is-scrolled', y > 40);
  nav.classList.toggle('is-hidden', y > lastY + 4 && y > 400);
  if (y < lastY - 4 || y < 400) nav.classList.remove('is-hidden');
  lastY = y;
}

// cursor + card tilt (desktop)
const cursor = document.getElementById('cursor');
const mouse = { x: 0, y: 0, nx: 0, ny: 0, sx: 0, sy: 0 };
window.addEventListener('pointermove', (e) => {
  mouse.x = e.clientX; mouse.y = e.clientY;
  mouse.nx = (e.clientX / innerWidth) * 2 - 1; mouse.ny = -((e.clientY / innerHeight) * 2 - 1);
  if (!isTouch) { cursor.classList.add('is-on'); cursor.style.transform = `translate(${e.clientX}px, ${e.clientY}px)`; }
}, { passive: true });
document.querySelectorAll('a, button, .tilt, .item-card').forEach((el) => {
  el.addEventListener('pointerenter', () => cursor.classList.add('is-hover'));
  el.addEventListener('pointerleave', () => cursor.classList.remove('is-hover'));
});
if (!isTouch && !reduceMotion) document.querySelectorAll('.tilt').forEach((el) => {
  el.addEventListener('pointermove', (e) => {
    const r = el.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
    el.style.transform = `perspective(900px) rotateY(${x * 10}deg) rotateX(${-y * 10}deg) translateY(-6px)`;
  });
  el.addEventListener('pointerleave', () => { el.style.transform = ''; });
});

// items rail moves sideways while its section scrolls past; Last Call timer counts down
const itemsSec = document.getElementById('items');
const rail = document.getElementById('itemsRail');
const lcSec = document.getElementById('lastcall');
const lcTimer = document.getElementById('lcTimer');
function sectionProgress(el) {
  const r = el.getBoundingClientRect();
  return THREE.MathUtils.clamp((innerHeight - r.top) / (r.height + innerHeight), 0, 1);
}
function uiOnScroll() {
  const p = sectionProgress(itemsSec);
  const max = Math.max(0, rail.scrollWidth - innerWidth);
  rail.style.transform = `translate3d(${-max * THREE.MathUtils.smoothstep(p, 0.15, 0.85)}px,0,0)`;
  const lp = THREE.MathUtils.clamp((sectionProgress(lcSec) - 0.25) / 0.5, 0, 1);
  const secs = Math.round(60 - lp * 59);
  lcTimer.textContent = `00:${String(secs).padStart(2, '0')}`;
}

// ------------------------------------------------------------------ WebGL stage
const canvas = document.getElementById('stage');
let renderer;
try {
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
} catch (e) {
  body.classList.add('no-webgl');
}

if (!renderer) {
  finishLoading();
  const loop = (t) => { lenis?.raf(t); const y = scrollY; navOnScroll(y); uiOnScroll(); requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
} else {
  start();
}

function finishLoading() {
  if (!body.classList.contains('is-loading')) return;
  loaderPct.textContent = '100%';
  setTimeout(() => {
    body.classList.remove('is-loading');
    setTimeout(() => body.classList.add('is-ready'), 250);
    document.querySelectorAll('.hero .reveal').forEach((el, i) => setTimeout(() => el.classList.add('is-in'), 500 + i * 140));
  }, 250);
}

async function start() {
  const small = innerWidth < 760;
  const dpr = Math.min(devicePixelRatio || 1, small ? 1.5 : 1.75);
  renderer.setPixelRatio(dpr);
  renderer.setSize(innerWidth, innerHeight, false);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.95;
  renderer.shadowMap.enabled = !small;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  try { await Promise.race([document.fonts.load('900 40px "Barlow Condensed"'), new Promise((r) => setTimeout(r, 2500))]); } catch (e) { /* draw with fallback */ }

  const manager = new THREE.LoadingManager();
  manager.onProgress = (_u, done, total) => { loaderPct.textContent = Math.round((done / Math.max(total, 1)) * 100) + '%'; };
  manager.onLoad = finishLoading;
  setTimeout(finishLoading, 9000);

  const scene = new THREE.Scene();
  const FOG = new THREE.Color(0x171312);
  scene.background = FOG.clone();
  scene.fog = new THREE.FogExp2(FOG.clone(), 0.034);

  const camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.1, 160);

  // warm reflection environment (no cold studio light: gold has to look like casino gold)
  const pmrem = new THREE.PMREMGenerator(renderer);
  const envScene = new THREE.Scene();
  envScene.background = new THREE.Color(0x120d0b);
  const addPanel = (color, intensity, pos, size) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(size[0], size[1]), new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity), side: THREE.DoubleSide }));
    m.position.set(...pos); m.lookAt(0, 0, 0); envScene.add(m);
  };
  addPanel(0xffc277, 4, [0, 8, 2], [8, 4]);
  addPanel(0xff9a4a, 2.2, [-8, 2, 4], [4, 6]);
  addPanel(0xffe0a8, 2.5, [7, 3, 6], [5, 4]);
  addPanel(0x8a2a2a, 1.4, [0, 1, -8], [14, 4]);
  addPanel(0xfff1d6, 1.2, [0, -6, 0], [10, 10]);
  scene.environment = pmrem.fromScene(envScene, 0.03).texture;
  scene.environmentIntensity = 0.75;

  // lights
  const hemi = new THREE.HemisphereLight(0xffe2b8, 0x2a1410, 0.55);
  scene.add(hemi);
  const key = new THREE.DirectionalLight(0xffd29a, 1.7);
  key.position.set(6, 14, 10);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  key.shadow.camera.left = -10; key.shadow.camera.right = 10; key.shadow.camera.top = 10; key.shadow.camera.bottom = -10;
  key.shadow.camera.far = 40; key.shadow.bias = -0.0004; key.shadow.normalBias = 0.02;
  scene.add(key, key.target);
  const rim = new THREE.DirectionalLight(0xff8a5a, 1.1);
  rim.position.set(-8, 6, -10);
  scene.add(rim);
  const spot = new THREE.PointLight(0xffb866, 14, 16, 1.6);
  scene.add(spot);

  // ---------------------------------------------------------------- hall: floor, carpet, wall, columns
  const HALL_LEN = 120, HALL_X0 = -20;
  const floorTex = (() => {
    const c = document.createElement('canvas'); c.width = c.height = 512;
    const g = c.getContext('2d');
    g.fillStyle = '#b8a789'; g.fillRect(0, 0, 512, 512);
    g.fillStyle = '#2a2420';
    g.fillRect(0, 0, 256, 256); g.fillRect(256, 256, 256, 256);
    g.strokeStyle = 'rgba(214,168,75,.7)'; g.lineWidth = 4;
    g.strokeRect(0, 0, 512, 512); g.beginPath(); g.moveTo(256, 0); g.lineTo(256, 512); g.moveTo(0, 256); g.lineTo(512, 256); g.stroke();
    for (let i = 0; i < 900; i++) { g.fillStyle = `rgba(255,255,255,${Math.random() * 0.04})`; g.fillRect(Math.random() * 512, Math.random() * 512, 2 + Math.random() * 30, 1); }
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(HALL_LEN / 3, 30 / 3); t.anisotropy = 8; return t;
  })();
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(HALL_LEN, 30), new THREE.MeshStandardMaterial({ map: floorTex, roughness: 0.32, metalness: 0.05 }));
  floor.rotation.x = -Math.PI / 2; floor.position.set(HALL_X0 + HALL_LEN / 2, 0, -2);
  floor.receiveShadow = true;
  scene.add(floor);

  const carpetTex = (() => {
    const c = document.createElement('canvas'); c.width = 64; c.height = 256;
    const g = c.getContext('2d');
    g.fillStyle = '#9b2a33'; g.fillRect(0, 0, 64, 256);
    g.fillStyle = '#D6A84B'; g.fillRect(0, 10, 64, 6); g.fillRect(0, 240, 64, 6);
    g.fillStyle = '#681F2C'; g.fillRect(0, 0, 64, 10); g.fillRect(0, 246, 64, 10);
    g.fillStyle = 'rgba(214,168,75,.25)';
    for (let y = 40; y < 220; y += 36) { g.beginPath(); g.moveTo(32, y); g.lineTo(46, y + 14); g.lineTo(32, y + 28); g.lineTo(18, y + 14); g.closePath(); g.fill(); }
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = THREE.RepeatWrapping; t.repeat.set(HALL_LEN / 1.6, 1); t.anisotropy = 8; return t;
  })();
  const carpet = new THREE.Mesh(new THREE.PlaneGeometry(HALL_LEN, 3.2), new THREE.MeshStandardMaterial({ map: carpetTex, roughness: 0.95 }));
  carpet.rotation.x = -Math.PI / 2; carpet.position.set(HALL_X0 + HALL_LEN / 2, 0.006, 3.6);
  carpet.receiveShadow = true;
  scene.add(carpet);

  const wallTex = (() => {
    const c = document.createElement('canvas'); c.width = 512; c.height = 512;
    const g = c.getContext('2d');
    g.fillStyle = '#4a1720'; g.fillRect(0, 0, 512, 512);
    g.fillStyle = '#3a2014'; g.fillRect(0, 330, 512, 182);
    g.strokeStyle = '#D6A84B'; g.lineWidth = 5;
    g.strokeRect(40, 360, 432, 120); g.beginPath(); g.moveTo(0, 330); g.lineTo(512, 330); g.stroke();
    g.lineWidth = 3; g.strokeRect(60, 40, 392, 250);
    g.fillStyle = 'rgba(214,168,75,.14)';
    for (let x = 80; x < 440; x += 40) for (let y = 60; y < 280; y += 40) { g.beginPath(); g.arc(x + 10, y + 10, 6, 0, Math.PI * 2); g.fill(); }
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = THREE.RepeatWrapping; t.repeat.set(HALL_LEN / 6, 1); return t;
  })();
  const wall = new THREE.Mesh(new THREE.PlaneGeometry(HALL_LEN, 8), new THREE.MeshStandardMaterial({ map: wallTex, roughness: 0.8 }));
  wall.position.set(HALL_X0 + HALL_LEN / 2, 4, -9);
  wall.receiveShadow = true;
  scene.add(wall);

  const columnProto = makeColumn(8);
  for (let x = -12; x < HALL_X0 + HALL_LEN; x += 8) {
    const c = columnProto.clone(); c.position.set(x, 0, -6.5); scene.add(c);
  }
  const chandelierProto = makeChandelier();
  for (let x = -8; x < HALL_X0 + HALL_LEN; x += 16) {
    const ch = chandelierProto.clone(); ch.position.set(x, 6.4, -2.5); scene.add(ch);
  }
  for (let x = 4; x < 92; x += 16) {
    const r = makeRope(2.6); r.position.set(x, 0, 5.6); scene.add(r);
  }

  const updaters = [];
  const t0 = performance.now();

  // ---------------------------------------------------------------- station 0: the logo coin sign
  const STATIONS = [0, 16, 32, 48, 66, 84];
  const logoPivot = new THREE.Group();
  logoPivot.position.set(0, 3.5, -1);
  scene.add(logoPivot);
  const heroBeans = [];
  new GLTFLoader(manager).load('assets/models/logo_3d.glb', (gltf) => {
    const model = gltf.scene;
    model.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = true;
      const col = o.geometry.getAttribute('color');
      if (col && !o.geometry.userData.srgbFixed) {
        // the generator writes sRGB vertex colours (Godot reads them with vertex_color_is_srgb)
        const c = new THREE.Color();
        for (let i = 0; i < col.count; i++) { c.setRGB(col.getX(i), col.getY(i), col.getZ(i), THREE.SRGBColorSpace); col.setXYZ(i, c.r, c.g, c.b); }
        col.needsUpdate = true; o.geometry.userData.srgbFixed = true;
      }
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      for (const m of mats) { m.vertexColors = !!col; m.envMapIntensity = 1.2; }
    });
    model.scale.setScalar(0.36);
    logoPivot.add(model);
  });
  // spotlight on the sign
  const logoLight = new THREE.SpotLight(0xffd8a0, 90, 30, 0.45, 0.6, 1.4);
  logoLight.position.set(0, 9, 7); logoLight.target = logoPivot;
  scene.add(logoLight);

  {
    const b1 = makeBean(BEAN_COLORS[1]); b1.root.position.set(0.9, 0, 2.7); b1.root.rotation.y = -0.1; scene.add(b1.root);
    const b2 = makeBean(BEAN_COLORS[0]); b2.root.position.set(3.6, 0, 1.2); b2.root.rotation.y = -0.45; scene.add(b2.root);
    const stack = new THREE.Group();
    [PAL.red, PAL.black, PAL.felt].forEach((c, i) => { const s = chipStack(6 + i * 4, c, chipMaterials(c)); s.position.set(i * 0.45, 0, (i % 2) * 0.3); stack.add(s); });
    stack.position.set(2.0, 0, 2.6); scene.add(stack);
    heroBeans.push(b1, b2);
    updaters.push((dt, t) => {
      b1.idle(t); b1.wave(t);
      b2.idle(t); if ((t % 6) > 4) b2.cheer(t);
    });
  }

  // ---------------------------------------------------------------- station 1: the tables
  {
    const X = STATIONS[1];
    const table = makeFeltTable(2.6); table.position.set(X + 1.8, 0.95, -0.4); scene.add(table);
    const wheel = makeRoulette(); wheel.position.set(X + 1.8, 1.07, -0.9); wheel.scale.setScalar(0.85); scene.add(wheel);
    updaters.push((dt) => wheel.userData.update(dt));
    const chipsA = chipStack(9, PAL.red, chipMaterials(PAL.red)); chipsA.position.set(X + 0.3, 1.01, 0.9); scene.add(chipsA);
    const chipsB = chipStack(5, PAL.black, chipMaterials(PAL.black)); chipsB.position.set(X + 0.75, 1.01, 1.2); scene.add(chipsB);
    const chipsC = chipStack(7, PAL.felt, chipMaterials(PAL.felt)); chipsC.position.set(X + 3.2, 1.01, 1.0); scene.add(chipsC);
    const dealer = makeBean(PAL.cream); dealer.root.position.set(X + 1.8, 0, -3.75); scene.add(dealer.root);
    const bowTie = new THREE.Mesh(new THREE.TorusKnotGeometry(0.06, 0.03, 30, 6, 2, 3), new THREE.MeshStandardMaterial({ color: PAL.red }));
    bowTie.position.set(0, 1.18 - 0.5, 0.42); bowTie.scale.set(1.6, 0.8, 0.6); dealer.pivot.add(bowTie);
    const player = makeBean(BEAN_COLORS[5]); player.root.position.set(X - 1.0, 0, 0.9); player.root.rotation.y = 1.0; scene.add(player.root);
    // a blackjack hand dealt on the felt; the top card flips over now and then
    const deal = [['spades_A', -0.55, 1.35, 0.15], ['hearts_K', -0.3, 1.38, -0.12], ['diamonds_Q', 0.75, 1.5, 0.1], ['clubs_J', 1.0, 1.48, -0.18]];
    const cards = deal.map(([f, dx, dz, rz]) => { const c = makeCard(f, manager); c.rotation.set(-Math.PI / 2, 0, rz); c.position.set(X + 1.8 + dx, 1.025, -0.4 + dz); scene.add(c); return c; });
    const flip = makeCard('spades_10', manager); flip.position.set(X + 1.8 + 0.2, 1.03, -0.4 + 1.55); scene.add(flip);
    updaters.push((dt, t) => {
      dealer.idle(t); player.idle(t); player.setMouth((Math.sin(t * 5) + 1) * 0.3);
      dealer.look(camera.position); player.look(wheel.getWorldPosition(new THREE.Vector3()));
      const fc = (t % 5) / 5, k = THREE.MathUtils.smoothstep(fc, 0.55, 0.75) - THREE.MathUtils.smoothstep(fc, 0.9, 1.0);
      flip.rotation.set(-Math.PI / 2 + k * Math.PI, 0, 0.05);
      flip.position.y = 1.03 + Math.sin(k * Math.PI) * 0.35;
    });
  }

  // ---------------------------------------------------------------- station 2: shove gag
  const burst = []; // chips knocked out of pockets
  {
    const X = STATIONS[2];
    const shover = makeBean(BEAN_COLORS[2]); scene.add(shover.root);
    const victim = makeBean(BEAN_COLORS[6], { crown: true }); scene.add(victim.root);
    const guard = makeBean(0x3d4a66, { cap: true }); guard.root.position.set(X - 4.2, 0, -2.5); scene.add(guard.root);
    const stars = new THREE.Group();
    for (let i = 0; i < 4; i++) { const s = new THREE.Mesh(new THREE.OctahedronGeometry(0.09), new THREE.MeshBasicMaterial({ color: 0xffe08a })); s.position.set(Math.cos(i * Math.PI / 2) * 0.45, 0, Math.sin(i * Math.PI / 2) * 0.45); stars.add(s); }
    scene.add(stars);
    const startS = new THREE.Vector3(X - 2.6, 0, 0.6), startV = new THREE.Vector3(X - 1.4, 0, 0.4);
    const land = new THREE.Vector3(X + 1.6, 0, -0.6);
    let fired = false;
    updaters.push((dt, t) => {
      const T = 4.6, c = t % T;
      guard.idle(t); guard.look(victim.root.position.clone().add(new THREE.Vector3(0, 1, 0)));
      guard.root.rotation.y = Math.atan2(victim.root.position.x - guard.root.position.x, victim.root.position.z - guard.root.position.z) * 0.6;
      stars.visible = false;
      if (c < 0.9) { // sneak up
        fired = false;
        const k = c / 0.9;
        shover.root.position.lerpVectors(startS, startV.clone().add(new THREE.Vector3(-0.9, 0, 0.1)), THREE.MathUtils.smoothstep(k, 0, 1));
        shover.root.position.y = Math.abs(Math.sin(k * Math.PI * 4)) * 0.08;
        shover.idle(t, 2); shover.root.rotation.y = Math.PI / 2;
        shover.arms[0].rotation.x = shover.arms[1].rotation.x = -0.4 * k;
        victim.root.position.copy(startV); victim.root.rotation.set(0, -0.3, 0); victim.pivot.rotation.set(0, 0, 0); victim.idle(t); victim.setMouth(0);
        victim.look(camera.position);
      } else if (c < 1.15) { // shove
        const k = (c - 0.9) / 0.25;
        shover.arms[0].rotation.x = shover.arms[1].rotation.x = THREE.MathUtils.lerp(-0.4, -1.25, k);
        shover.arms[0].rotation.z = -0.35; shover.arms[1].rotation.z = 0.35;
        shover.root.position.x += dt * 2.5; shover.setMouth(1);
        victim.setMouth(1);
      } else if (c < 2.1) { // fly
        if (!fired) { fired = true; for (let i = 0; i < 10; i++) burst.push({ p: victim.root.position.clone().add(new THREE.Vector3(0, 1, 0)), v: new THREE.Vector3(1.5 + Math.random() * 2.5, 3 + Math.random() * 3, (Math.random() - 0.5) * 3), life: 0 }); }
        const k = (c - 1.15) / 0.95;
        victim.root.position.lerpVectors(startV, land, k);
        victim.root.position.y = Math.sin(k * Math.PI) * 1.6;
        victim.pivot.rotation.z = -k * Math.PI * 1.5;
        victim.arms[0].rotation.z = -2.5 + Math.sin(t * 30) * 0.4; victim.arms[1].rotation.z = 2.5 - Math.sin(t * 30) * 0.4;
        shover.cheer(t);
      } else if (c < 3.9) { // knocked out
        victim.root.position.copy(land); victim.root.position.y = 0.45;
        victim.pivot.rotation.set(0, 0, -Math.PI / 2);
        victim.mouth.scale.set(2.2, 0.7, 1);
        stars.visible = true; stars.position.copy(land).add(new THREE.Vector3(-0.9, 0.85, 0)); stars.rotation.y = t * 4;
        shover.idle(t); shover.cheer(t);
      } else { // wobbly get-up
        const k = (c - 3.9) / (T - 3.9);
        victim.root.position.copy(land); victim.root.position.y = 0.45 * (1 - k);
        victim.pivot.rotation.set(0, 0, -Math.PI / 2 * (1 - THREE.MathUtils.smoothstep(k, 0, 1)) + Math.sin(k * 20) * 0.08);
        shover.idle(t);
      }
    });
  }

  // ---------------------------------------------------------------- station 3: minigames
  {
    const X = STATIONS[3];
    const wheel = makeBigWheel(); wheel.position.set(X + 1.4, 3.5, -2.0); wheel.scale.setScalar(0.9); scene.add(wheel);
    const peg = makePegDrop(); peg.position.set(X + 6.2, 2.5, -2.4); peg.rotation.y = -0.35; scene.add(peg);
    updaters.push((dt, t) => { wheel.userData.update(dt, t); peg.userData.update(dt); });
    const fans = [BEAN_COLORS[3], BEAN_COLORS[4], BEAN_COLORS[9]].map((c, i) => {
      const b = makeBean(c); b.root.position.set(X + 0.2 + i * 1.3, 0, 1.6 - (i % 2) * 0.6); b.root.rotation.y = Math.PI + 0.3 - i * 0.3; scene.add(b.root); return b;
    });
    updaters.push((dt, t) => fans.forEach((b, i) => { b.idle(t); b.root.position.y = Math.max(0, Math.sin(t * 6 + i * 2)) * 0.25; if (i !== 1) b.cheer(t); }));
    // Lucky's stage spot
    const pl = new THREE.PointLight(0xffc77a, 22, 14, 1.6); pl.position.set(X + 3, 6, 2); scene.add(pl);
  }

  // ---------------------------------------------------------------- station 4: Last Call
  let lastCallSign;
  {
    const X = STATIONS[4];
    lastCallSign = makeMarquee('×1.5', 'PAYOUTS', 3.4, 1.7);
    lastCallSign.position.set(X, 8.6, -6.5); lastCallSign.rotation.x = 0.2;
    const jack = makeMarquee('JACKPOT', null, 5, 1.4);
    jack.position.set(X - 6.4, 4.6, -4.6); jack.rotation.y = 0.45; scene.add(jack);
    const jack2 = makeMarquee('HOT TABLE', null, 4.6, 1.3);
    jack2.position.set(X + 6.4, 4.4, -4.6); jack2.rotation.y = -0.45; scene.add(jack2);
    updaters.push((dt, t) => { jack.userData.update(dt, t * 0.7); jack2.userData.update(dt, t * 1.2); });
    const runners = [BEAN_COLORS[7], BEAN_COLORS[8], BEAN_COLORS[10], BEAN_COLORS[11]].map((c) => { const b = makeBean(c); scene.add(b.root); return b; });
    updaters.push((dt, t) => runners.forEach((b, i) => {
      const a = t * 0.9 + i * Math.PI / 2;
      b.root.position.set(X + Math.cos(a) * 3.2, Math.abs(Math.sin(t * 9 + i)) * 0.18, -0.8 + Math.sin(a) * 1.6);
      b.root.rotation.y = -a; b.idle(t, 2); b.cheer(t * 1.5);
      b.pivot.rotation.x = 0.25;
    }));
  }

  // ---------------------------------------------------------------- station 5: podium
  {
    const X = STATIONS[5];
    const podium = makePodium(); podium.position.set(X, 0, -1.2); scene.add(podium);
    const tops = podium.userData.tops;
    const winners = [
      makeBean(BEAN_COLORS[11], { crown: true }), makeBean(BEAN_COLORS[1]), makeBean(BEAN_COLORS[5]),
    ];
    winners.forEach((b, i) => { b.root.position.copy(tops[i]).add(podium.position); scene.add(b.root); });
    const loser = makeBean(BEAN_COLORS[2]); loser.root.position.set(X + 3.6, 0.45, 1.6); loser.root.rotation.y = -0.5; loser.pivot.rotation.z = Math.PI / 2; scene.add(loser.root);
    const coinPile = new THREE.Group();
    for (let i = 0; i < 18; i++) { const s = chipStack(1 + Math.floor(Math.random() * 5), [PAL.red, PAL.black, PAL.felt][i % 3]); s.position.set((Math.random() - 0.5) * 2.4, 0, (Math.random() - 0.5) * 1.2); coinPile.add(s); }
    coinPile.position.set(X - 2.6, 0, 1.2); scene.add(coinPile);
    updaters.push((dt, t) => {
      const [w, s2, s3] = winners;
      w.idle(t); w.cheer(t); w.root.position.y = tops[0].y + Math.max(0, Math.sin(t * 5)) * 0.35;
      s2.idle(t); s2.wave(t);
      s3.idle(t); s3.arms[0].rotation.z = -0.1; s3.arms[1].rotation.z = 0.1; s3.setMouth(0.2); s3.pivot.rotation.x = 0.12;
      winners.forEach((b) => b.look(camera.position));
      loser.mouth.scale.set(2.2, 0.7, 1);
    });
    const pl = new THREE.PointLight(0xffd9a0, 26, 14, 1.5); pl.position.set(X, 6, 3); scene.add(pl);
  }

  // decor: Poly Haven statue + bust (CC0), scaled to a real size from their bounding boxes
  const fitHeight = (obj, h) => {
    const box = new THREE.Box3().setFromObject(obj); const size = box.getSize(new THREE.Vector3());
    obj.scale.multiplyScalar(h / size.y);
    const b2 = new THREE.Box3().setFromObject(obj); obj.position.y -= b2.min.y;
    const c = b2.getCenter(new THREE.Vector3()); obj.position.x -= c.x; obj.position.z -= c.z;
    const g = new THREE.Group(); g.add(obj); return g;
  };
  const marble = new THREE.MeshStandardMaterial({ color: 0xE8DCC4, roughness: 0.35 });
  const goldTrim = new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.9, roughness: 0.3 });
  const pedestal = (w, h, d) => {
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), marble); body.position.y = h / 2; body.castShadow = body.receiveShadow = true;
    const cap = new THREE.Mesh(new THREE.BoxGeometry(w + 0.12, 0.08, d + 0.12), goldTrim); cap.position.y = h + 0.04;
    const foot = new THREE.Mesh(new THREE.BoxGeometry(w + 0.16, 0.1, d + 0.16), goldTrim); foot.position.y = 0.05;
    g.add(body, cap, foot); return g;
  };
  const gl = new GLTFLoader(manager);
  gl.load('assets/models/horse_statue_01/horse_statue_01_1k.gltf', (g) => {
    g.scene.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    const horse = fitHeight(g.scene, 1.7);
    for (const [x, ry] of [[8.2, 0.6], [STATIONS[5] - 6.5, -0.5]]) {
      const ped = pedestal(1.3, 0.9, 0.8); ped.position.set(x, 0, -4.2); scene.add(ped);
      const h = horse.clone(); h.position.set(x, 0.98, -4.2); h.rotation.y = ry; scene.add(h);
    }
  });
  gl.load('assets/models/marble_bust_01/marble_bust_01_1k.gltf', (g) => {
    g.scene.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    const bust = fitHeight(g.scene, 0.95);
    for (const [x, ry] of [[STATIONS[2] + 4.4, -0.5], [STATIONS[3] - 4.5, 0.5]]) {
      const ped = pedestal(0.6, 1.25, 0.6); ped.position.set(x, 0, -3.8); scene.add(ped);
      const b = bust.clone(); b.position.set(x, 1.33, -3.8); b.rotation.y = ry; scene.add(b);
    }
  });

  // ---------------------------------------------------------------- chip rain (instanced, 4 colours)
  const RAIN_COLORS = [PAL.red, PAL.black, PAL.felt, PAL.vipGold];
  const PER = small ? 18 : 34;
  const rainMeshes = RAIN_COLORS.map((c) => {
    const mesh = new THREE.InstancedMesh(chipGeometry(), chipMaterials(c), PER);
    mesh.castShadow = !small; mesh.frustumCulled = false; scene.add(mesh); return mesh;
  });
  const rain = [];
  const focus = new THREE.Vector3();
  const spawnChip = (d, initial) => {
    d.p.set(focus.x + (Math.random() - 0.5) * 16, initial ? Math.random() * 12 : 9 + Math.random() * 5, focus.z + (Math.random() - 0.5) * 9 - 1);
    d.v.set((Math.random() - 0.5) * 0.4, -1.2 - Math.random() * 1.6, 0);
    d.axis.set(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
    d.spin = 2 + Math.random() * 5; d.rest = 0; d.q.setFromAxisAngle(d.axis, Math.random() * 6);
  };
  RAIN_COLORS.forEach((_, mi) => { for (let i = 0; i < PER; i++) { const d = { mi, i, p: new THREE.Vector3(), v: new THREE.Vector3(), axis: new THREE.Vector3(), q: new THREE.Quaternion(), spin: 0, rest: 0 }; spawnChip(d, true); rain.push(d); } });
  const tmpM = new THREE.Matrix4(), tmpQ = new THREE.Quaternion(), ONE = new THREE.Vector3(1, 1, 1), ZERO = new THREE.Vector3(0, 0, 0);
  const flatQ = new THREE.Quaternion();
  let rainDensity = 1;

  // burst chips (from the shove gag) reuse the gold mesh's last slots via a separate mesh
  const burstMesh = new THREE.InstancedMesh(chipGeometry(), chipMaterials(PAL.red), 30);
  burstMesh.frustumCulled = false; scene.add(burstMesh);

  // ---------------------------------------------------------------- confetti + dust
  const CONF = small ? 120 : 260;
  const confetti = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.08, 0.14), new THREE.MeshStandardMaterial({ side: THREE.DoubleSide, roughness: 0.5, metalness: 0.3 }), CONF);
  confetti.frustumCulled = false;
  const confCols = [PAL.vipGold, PAL.red, PAL.cream, PAL.money, PAL.gold];
  const conf = [];
  const ccol = new THREE.Color();
  for (let i = 0; i < CONF; i++) {
    conf.push({ p: new THREE.Vector3(STATIONS[5] + (Math.random() - 0.5) * 12, Math.random() * 9, -1 + (Math.random() - 0.5) * 7), r: new THREE.Euler(Math.random() * 6, Math.random() * 6, 0), s: 0.6 + Math.random() * 1.5, ph: Math.random() * 6 });
    confetti.setColorAt(i, ccol.set(confCols[i % confCols.length]));
  }
  scene.add(confetti);

  const dustGeo = new THREE.BufferGeometry();
  const DUST = small ? 250 : 600;
  const dpos = new Float32Array(DUST * 3);
  for (let i = 0; i < DUST; i++) { dpos[i * 3] = HALL_X0 + Math.random() * HALL_LEN; dpos[i * 3 + 1] = Math.random() * 8; dpos[i * 3 + 2] = -8 + Math.random() * 16; }
  dustGeo.setAttribute('position', new THREE.BufferAttribute(dpos, 3));
  const dustTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d'); const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32); gr.addColorStop(0, 'rgba(255,220,160,1)'); gr.addColorStop(1, 'rgba(255,200,120,0)'); g.fillStyle = gr; g.fillRect(0, 0, 64, 64); return new THREE.CanvasTexture(c); })();
  const dust = new THREE.Points(dustGeo, new THREE.PointsMaterial({ size: 0.06, map: dustTex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.7 }));
  scene.add(dust);

  // ---------------------------------------------------------------- post
  const composer = new EffectComposer(renderer);
  composer.setPixelRatio(dpr);
  composer.setSize(innerWidth, innerHeight);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.42, 0.55, 0.9);
  if (!small) composer.addPass(bloom);
  composer.addPass(new OutputPass());

  // ---------------------------------------------------------------- camera keyframes
  // Each [data-cam] section has a shot; between them the camera swoops down the hall.
  const shot = (px, py, pz, tx, ty, tz) => ({ p: new THREE.Vector3(px, py, pz), t: new THREE.Vector3(tx, ty, tz) });
  function shotsFor(aspect) {
    const narrow = aspect < 0.9;
    const S = STATIONS;
    return [
      narrow ? shot(0, 2.4, 16, 0, 0.8, 0) : shot(-1.9, 3.2, 10.2, -2.0, 2.9, 0),
      narrow ? shot(S[1] + 1.8, 4.6, 7.8, S[1] + 1.8, 0.9, -0.5) : shot(S[1] - 1.2, 4.6, 6.6, S[1] + 0.1, 1.0, -0.6),
      narrow ? shot(S[2], 3.0, 8.8, S[2], 1.6, 0) : shot(S[2] + 2.0, 2.6, 7.0, S[2] - 0.6, 1.25, 0),
      narrow ? shot(S[3] + 3.2, 4.2, 14.5, S[3] + 3.2, 3.6, -2) : shot(S[3] - 1.4, 3.4, 8.6, S[3] + 2.0, 3.0, -1.6),
      narrow ? shot(S[4], 3.0, 11, S[4], 4.6, -3) : shot(S[4], 2.0, 9.2, S[4], 4.2, -3),
      narrow ? shot(S[5], 2.3, 11, S[5], 2.9, -1) : shot(S[5], 2.1, 8.4, S[5], 2.45, -1),
    ];
  }
  let shots = shotsFor(innerWidth / innerHeight);
  const anchors = [...document.querySelectorAll('[data-cam]')];
  let anchorY = [];
  function measure() {
    anchorY = anchors.map((el, i) => (i === 0 ? 0 : el.offsetTop + el.offsetHeight / 2 - innerHeight / 2));
  }
  measure();
  function camParam(y) {
    if (y <= anchorY[0]) return 0;
    for (let i = 0; i < anchorY.length - 1; i++) {
      if (y < anchorY[i + 1]) {
        const k = (y - anchorY[i]) / (anchorY[i + 1] - anchorY[i]);
        const held = THREE.MathUtils.clamp((k - 0.18) / 0.64, 0, 1);
        return i + held * held * (3 - 2 * held);
      }
    }
    return anchorY.length - 1;
  }

  const camPos = new THREE.Vector3(), camTgt = new THREE.Vector3();
  const curPos = shots[0].p.clone().add(new THREE.Vector3(0, 2, 6)), curTgt = shots[0].t.clone();
  const fogCalm = new THREE.Color(0x171312), fogRed = new THREE.Color(0x3a0c10);
  const keyCalm = new THREE.Color(0xffd29a), keyRed = new THREE.Color(0xff4a3a);

  // pause the 3D while a full-bleed section covers the viewport
  const covers = [...document.querySelectorAll('.trailer, .reel, .rules')];
  function covered() {
    for (const el of covers) { const r = el.getBoundingClientRect(); if (r.top <= 0 && r.bottom >= innerHeight) return true; }
    // the trailer, reel and rules run back to back: also covered while their joint spans the screen
    const a = covers[0].getBoundingClientRect(), b = covers[covers.length - 1].getBoundingClientRect();
    return a.top <= 0 && b.bottom >= innerHeight;
  }

  // dev aid: #cam=px,py,pz,tx,ty,tz pins the camera (used for close-up checks)
  const camHash = location.hash.match(/^#cam=([-\d.,]+)$/);
  const debugCam = camHash ? (() => { const v = camHash[1].split(',').map(Number); return [new THREE.Vector3(v[0], v[1], v[2]), new THREE.Vector3(v[3], v[4], v[5])]; })() : null;
  let last = performance.now();
  let s = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    lenis?.raf(now);
    const y = lenis ? lenis.animatedScroll : scrollY;
    navOnScroll(y); uiOnScroll();
    const dt = Math.min((now - last) / 1000, 0.05); last = now;
    const t = (now - t0) / 1000;
    if (covered()) return;

    s = camParam(y);
    const i = Math.min(Math.floor(s), shots.length - 2), k = s - i;
    camPos.lerpVectors(shots[i].p, shots[i + 1].p, k);
    camTgt.lerpVectors(shots[i].t, shots[i + 1].t, k);
    const swoop = Math.sin(k * Math.PI);
    camPos.y += swoop * 1.6; camPos.z += swoop * 2.2;
    // parallax
    mouse.sx += (mouse.nx - mouse.sx) * 0.05; mouse.sy += (mouse.ny - mouse.sy) * 0.05;
    camPos.x += mouse.sx * 0.45; camPos.y += mouse.sy * 0.25;
    const ease = reduceMotion ? 1 : 1 - Math.pow(0.0015, dt);
    curPos.lerp(camPos, ease); curTgt.lerp(camTgt, ease);
    if (debugCam) { curPos.copy(debugCam[0]); curTgt.copy(debugCam[1]); }
    camera.position.copy(curPos); camera.lookAt(curTgt);

    // lighting follows the camera; Last Call turns the room red
    focus.copy(curTgt);
    key.position.set(curTgt.x + 6, 14, 10); key.target.position.copy(curTgt);
    spot.position.set(curTgt.x, 5.5, 3);
    const red = Math.max(0, 1 - Math.abs(s - 4) * 1.4);
    const pulse = red * (0.75 + 0.25 * Math.sin(t * 6));
    scene.fog.color.lerpColors(fogCalm, fogRed, pulse); scene.background.copy(scene.fog.color);
    key.color.lerpColors(keyCalm, keyRed, red * 0.85);
    spot.color.setHex(red > 0.2 ? 0xff5040 : 0xffb866); spot.intensity = 14 + pulse * 40;
    hemi.intensity = 0.55 - red * 0.2;
    rainDensity = THREE.MathUtils.lerp(0.45, 1.6, red) + Math.max(0, 1 - s) * 0.8;

    // logo sway + mouse tilt
    logoPivot.rotation.y = Math.sin(t * 0.6) * 0.09 + mouse.sx * 0.35;
    logoPivot.rotation.x = Math.sin(t * 0.45 + 1.3) * 0.03 - mouse.sy * 0.12;
    const narrowNow = camera.aspect < 0.9;
    logoPivot.position.y = (narrowNow ? 4.5 : 3.5) + Math.sin(t * 0.9) * 0.08;
    logoPivot.scale.setScalar(narrowNow ? 0.8 : 1);
    const lookPt = camera.position.clone().add(new THREE.Vector3(mouse.sx * 3, mouse.sy * 2, 0));
    heroBeans.forEach((b) => b.look(lookPt));

    for (const u of updaters) u(dt, t);

    // chip rain
    const active = Math.round(PER * Math.min(1, rainDensity));
    for (const d of rain) {
      const mesh = rainMeshes[d.mi];
      if (d.i >= active && d.rest === 0 && d.p.y > 8) { tmpM.compose(d.p, d.q, ZERO); mesh.setMatrixAt(d.i, tmpM); continue; }
      if (d.rest > 0) {
        d.rest -= dt;
        if (d.rest <= 0 || Math.abs(d.p.x - focus.x) > 14) spawnChip(d, false);
      } else {
        d.v.y -= 3.5 * dt * (reduceMotion ? 0.3 : 1);
        d.p.addScaledVector(d.v, dt * (reduceMotion ? 0.3 : 1));
        tmpQ.setFromAxisAngle(d.axis, d.spin * dt); d.q.multiply(tmpQ);
        if (d.p.y <= 0.03) { d.p.y = 0.03; flatQ.setFromAxisAngle(THREE.Object3D.DEFAULT_UP, Math.random() * 6); d.q.copy(flatQ); d.rest = 2 + Math.random() * 3; }
        if (Math.abs(d.p.x - focus.x) > 14) spawnChip(d, false);
      }
      tmpM.compose(d.p, d.q, ONE); mesh.setMatrixAt(d.i, tmpM);
    }
    rainMeshes.forEach((m) => { m.instanceMatrix.needsUpdate = true; });

    for (let j = 0; j < 30; j++) {
      const b = burst[j];
      if (b) {
        b.life += dt; b.v.y -= 9.8 * dt; b.p.addScaledVector(b.v, dt);
        if (b.p.y < 0.03) { b.p.y = 0.03; b.v.set(0, 0, 0); }
        tmpQ.setFromEuler(new THREE.Euler(b.life * 9, b.life * 4, 0));
        tmpM.compose(b.p, b.v.lengthSq() > 0 ? tmpQ : flatQ, ONE);
      } else tmpM.compose(ZERO, flatQ, ZERO);
      burstMesh.setMatrixAt(j, tmpM);
    }
    for (let j = burst.length - 1; j >= 0; j--) if (burst[j].life > 3.2) burst.splice(j, 1);
    while (burst.length > 30) burst.shift();
    burstMesh.instanceMatrix.needsUpdate = true;

    // confetti over the podium
    if (s > 3.5) {
      for (let j = 0; j < CONF; j++) {
        const c = conf[j];
        c.p.y -= dt * c.s * 0.9; c.p.x += Math.sin(t * 2 + c.ph) * dt * 0.4;
        c.r.x += dt * 3 * c.s; c.r.y += dt * 2;
        if (c.p.y < 0.02) { c.p.y = 8 + Math.random() * 2; }
        tmpQ.setFromEuler(c.r); tmpM.compose(c.p, tmpQ, ONE); confetti.setMatrixAt(j, tmpM);
      }
      confetti.instanceMatrix.needsUpdate = true;
      confetti.visible = true;
    } else confetti.visible = false;

    dust.rotation.y = 0; dust.position.y = Math.sin(t * 0.2) * 0.3;

    composer.render();
  }
  requestAnimationFrame(frame);

  let rt;
  window.addEventListener('resize', () => {
    clearTimeout(rt);
    rt = setTimeout(() => {
      camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
      renderer.setSize(innerWidth, innerHeight, false); composer.setSize(innerWidth, innerHeight);
      shots = shotsFor(camera.aspect); measure();
    }, 120);
  });
  window.addEventListener('load', measure);
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
  // first frame early so the loader fades onto a finished picture
  renderer.compile(scene, camera);
}
