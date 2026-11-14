// The bean, rebuilt for the web after player/avatar_visuals.gd: a chubby jelly bean with glossy
// shine, googly eyes, stubby arms with oversized cream gloves and little dark feet.
import * as THREE from 'three';

const BODY_RADIUS = 0.46;
const BODY_HEIGHT = 1.4;
const BODY_BOTTOM = 0.1;
const BODY_DEPTH = 0.9;
const EYE_Y = 1.08;
const EYE_RADIUS = 0.13;
const EYE_SPREAD = 0.128;
const HAND_RADIUS = 0.135;
const ARM_LENGTH = 0.36;

function radiusAt(t) {
  const u = Math.min(Math.max(t, 0), 1) * 2 - 1;
  const roundness = Math.pow(Math.max(0, 1 - Math.pow(Math.abs(u), 2.4)), 1 / 2.4);
  return THREE.MathUtils.lerp(BODY_RADIUS, BODY_RADIUS * 0.86, t) * roundness;
}
function bendAt(t) { const u = t * 2 - 1; return -0.045 * (1 - u * u); }

let bodyGeo = null;
function bodyGeometry() {
  if (bodyGeo) return bodyGeo;
  const pts = [];
  const N = 40;
  for (let i = 0; i <= N; i++) {
    const t = i / N;
    pts.push(new THREE.Vector2(Math.max(radiusAt(t), 0.0001), t * BODY_HEIGHT));
  }
  const g = new THREE.LatheGeometry(pts, 48);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i);
    const t = y / BODY_HEIGHT;
    p.setZ(i, p.getZ(i) * BODY_DEPTH - bendAt(t)); // belly forward (+Z is the face)
    p.setY(i, y + BODY_BOTTOM);
  }
  g.computeVertexNormals();
  bodyGeo = g;
  return g;
}

const shared = {};
function mats() {
  if (shared.white) return shared;
  shared.white = new THREE.MeshStandardMaterial({ color: 0xFFFDF7, roughness: 0.25 });
  shared.pupil = new THREE.MeshStandardMaterial({ color: 0x151414, roughness: 0.2 });
  shared.glove = new THREE.MeshStandardMaterial({ color: 0xFBF4E4, roughness: 0.55 });
  shared.shoe = new THREE.MeshStandardMaterial({ color: 0x2B2421, roughness: 0.6 });
  shared.mouth = new THREE.MeshStandardMaterial({ color: 0x3a1717, roughness: 0.6 });
  shared.blush = new THREE.MeshBasicMaterial({ color: 0xF08080, transparent: true, opacity: 0.45 });
  shared.gold = new THREE.MeshStandardMaterial({ color: 0xE3B95C, metalness: 0.9, roughness: 0.25 });
  return shared;
}

/** Front surface z of the body at height y (bean-local, feet at 0) and sideways x. */
function frontZ(y, x) {
  const t = (y - BODY_BOTTOM) / BODY_HEIGHT;
  const r = radiusAt(t);
  return -bendAt(t) + Math.sqrt(Math.max(r * r - x * x, 0)) * BODY_DEPTH;
}

export function makeBean(color = 0xE69F00, opts = {}) {
  const m = mats();
  const root = new THREE.Group();
  root.name = 'Bean';
  const pivot = new THREE.Group(); // tilts the whole bean around its base
  root.add(pivot);
  const bodyMat = new THREE.MeshPhysicalMaterial({ color, roughness: 0.32, clearcoat: 0.8, clearcoatRoughness: 0.25 });
  const body = new THREE.Mesh(bodyGeometry(), bodyMat);
  body.castShadow = true;
  pivot.add(body);

  // Eyes
  const eyeGeo = new THREE.SphereGeometry(EYE_RADIUS, 24, 16);
  const pupilGeo = new THREE.SphereGeometry(EYE_RADIUS * 0.48, 16, 12);
  const eyes = [];
  for (const side of [-1, 1]) {
    const x = side * EYE_SPREAD;
    const eye = new THREE.Mesh(eyeGeo, m.white);
    eye.position.set(x, EYE_Y, frontZ(EYE_Y, x) - EYE_RADIUS * 0.45);
    eye.scale.set(1, 1.12, 0.8);
    const pupil = new THREE.Mesh(pupilGeo, m.pupil);
    pupil.position.set(0, -0.01, EYE_RADIUS * 0.82);
    pupil.scale.set(1, 1, 0.5);
    eye.add(pupil);
    pivot.add(eye);
    eyes.push({ eye, pupil });
  }
  // Mouth: a little dark capsule; scaled for "o" / "O"
  const mouth = new THREE.Mesh(new THREE.CapsuleGeometry(0.03, 0.09, 4, 12), m.mouth);
  mouth.rotation.z = Math.PI / 2;
  mouth.position.set(0, 0.82, frontZ(0.82, 0) - 0.005);
  pivot.add(mouth);
  // Blush
  for (const side of [-1, 1]) {
    const b = new THREE.Mesh(new THREE.CircleGeometry(0.06, 16), m.blush);
    const x = side * 0.26;
    b.position.set(x, 0.9, frontZ(0.9, x) + 0.004);
    b.lookAt(b.position.clone().add(new THREE.Vector3(side * 0.6, 0, 1)));
    pivot.add(b);
  }

  // Arms
  const armGeo = new THREE.CapsuleGeometry(0.075, ARM_LENGTH, 4, 10);
  armGeo.translate(0, -ARM_LENGTH / 2, 0);
  const handGeo = new THREE.SphereGeometry(HAND_RADIUS, 18, 14);
  const arms = [];
  for (const side of [-1, 1]) {
    const shoulder = new THREE.Group();
    const sy = BODY_BOTTOM + BODY_HEIGHT * 0.5 - 0.02;
    shoulder.position.set(side * (radiusAt(0.5) - 0.03), sy, 0.02);
    const arm = new THREE.Mesh(armGeo, bodyMat);
    arm.castShadow = true;
    shoulder.add(arm);
    const hand = new THREE.Mesh(handGeo, m.glove);
    hand.position.y = -ARM_LENGTH - 0.05;
    hand.scale.set(1, 1.05, 0.85);
    hand.castShadow = true;
    shoulder.add(hand);
    shoulder.rotation.z = side * 0.25;
    pivot.add(shoulder);
    arms.push(shoulder);
  }
  // Feet
  const footGeo = new THREE.SphereGeometry(0.13, 16, 10);
  const feet = [];
  for (const side of [-1, 1]) {
    const f = new THREE.Mesh(footGeo, m.shoe);
    f.scale.set(0.85, 0.55, 1.25);
    f.position.set(side * 0.17, 0.06, 0.05);
    f.castShadow = true;
    root.add(f);
    feet.push(f);
  }

  if (opts.crown) {
    const crown = makeCrown();
    crown.position.set(0, BODY_BOTTOM + BODY_HEIGHT - 0.06, 0);
    pivot.add(crown);
  }
  if (opts.cap) {
    const cap = new THREE.Group();
    const top = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.32, 0.16, 24), new THREE.MeshStandardMaterial({ color: 0x1b1d26, roughness: 0.6 }));
    const brim = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.03, 24, 1, false, -Math.PI / 2, Math.PI), top.material);
    brim.position.set(0, -0.06, 0.24);
    const badge = new THREE.Mesh(new THREE.CircleGeometry(0.05, 12), mats().gold);
    badge.position.set(0, 0.0, 0.305);
    cap.add(top, brim, badge);
    cap.position.set(0, BODY_BOTTOM + BODY_HEIGHT - 0.04, 0);
    pivot.add(cap);
  }

  const bean = {
    root, pivot, body, eyes, mouth, arms, feet,
    phase: Math.random() * 10,
    /** Look at a world point with the pupils. */
    look(target) {
      for (const { eye, pupil } of eyes) {
        const local = eye.worldToLocal(target.clone());
        local.normalize();
        pupil.position.set(local.x * EYE_RADIUS * 0.45, local.y * EYE_RADIUS * 0.4 - 0.01, EYE_RADIUS * 0.82);
      }
    },
    /** Idle: bob, breathe, blink, dangle arms. */
    idle(t, amount = 1) {
      const p = t + bean.phase;
      const s = Math.sin(p * 3.1);
      pivot.scale.set(1 - s * 0.02 * amount, 1 + s * 0.03 * amount, 1 - s * 0.02 * amount);
      pivot.rotation.z = Math.sin(p * 1.3) * 0.04 * amount;
      arms[0].rotation.x = Math.sin(p * 2.2) * 0.15 * amount;
      arms[1].rotation.x = Math.sin(p * 2.2 + 1.5) * 0.15 * amount;
      arms[0].rotation.z = -0.25 - Math.sin(p * 1.7) * 0.06;
      arms[1].rotation.z = 0.25 + Math.sin(p * 1.9) * 0.06;
      const blink = (p % 3.7) < 0.12 ? 0.1 : 1.12;
      for (const { eye } of eyes) eye.scale.y = blink;
      mouth.scale.set(1, 1, 1);
    },
    /** Waving right arm. */
    wave(t) {
      const p = t + bean.phase;
      arms[1].rotation.z = 2.6 + Math.sin(p * 9) * 0.35;
      arms[1].rotation.x = -0.2;
      mouth.scale.set(2.2, 0.7, 1);
    },
    cheer(t) {
      const p = t + bean.phase;
      arms[0].rotation.z = -2.7 - Math.sin(p * 10) * 0.2;
      arms[1].rotation.z = 2.7 + Math.sin(p * 10 + 1) * 0.2;
      mouth.scale.set(3.0, 0.9, 1);
    },
    setMouth(open) { mouth.scale.set(1 + open * 2.4, 1 - open * 0.3, 1); },
  };
  return bean;
}

export function makeCrown() {
  const g = new THREE.Group();
  const gold = mats().gold;
  const band = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.26, 0.14, 24, 1, true), gold);
  band.material.side = THREE.DoubleSide;
  g.add(band);
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    const spike = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.16, 8), gold);
    spike.position.set(Math.sin(a) * 0.24, 0.14, Math.cos(a) * 0.24);
    g.add(spike);
    const gem = new THREE.Mesh(new THREE.SphereGeometry(0.03, 8, 6), new THREE.MeshStandardMaterial({ color: i % 2 ? 0xC83D3D : 0x275E49, roughness: 0.15, metalness: 0.2 }));
    gem.position.set(Math.sin(a) * 0.255, 0, Math.cos(a) * 0.255);
    g.add(gem);
  }
  return g;
}

export const BEAN_COLORS = [0xE69F00, 0x56B4E9, 0x009E73, 0xF0E442, 0x0072B2, 0xD55E00, 0xCC79A7, 0xF2E6C9, 0xB3263E, 0x8FE3C3, 0xB7A3E8, 0xF2C14E];
