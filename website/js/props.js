// Procedural casino props in the game's palette: chips, roulette wheel, cards, the Big Wheel,
// the Peg Drop board, a marquee sign, podium blocks, columns and chandeliers.
import * as THREE from 'three';

export const PAL = {
  black: 0x151414, charcoal: 0x24211F, cream: 0xF2E6C9, red: 0xC83D3D, felt: 0x275E49,
  gold: 0xD6A84B, vipGold: 0xE3B95C, burgundy: 0x681F2C, money: 0x68C26F, loss: 0xE55353,
};
const css = (hex) => '#' + hex.toString(16).padStart(6, '0');

function canvasTex(w, h, draw, srgb = true) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

// ---------------------------------------------------------------- chips
const chipTexCache = {};
function chipTextures(color) {
  if (chipTexCache[color]) return chipTexCache[color];
  const base = css(color);
  const face = canvasTex(256, 256, (g, w) => {
    g.fillStyle = base; g.fillRect(0, 0, w, w);
    const c = w / 2;
    for (let i = 0; i < 8; i++) {
      g.save(); g.translate(c, c); g.rotate(i * Math.PI / 4);
      g.fillStyle = '#F2E6C9'; g.fillRect(-14, -c, 28, 36); g.restore();
    }
    g.strokeStyle = '#F2E6C9'; g.lineWidth = 6; g.setLineDash([10, 8]);
    g.beginPath(); g.arc(c, c, c * 0.62, 0, Math.PI * 2); g.stroke();
    g.setLineDash([]);
    g.fillStyle = 'rgba(0,0,0,0.14)'; g.beginPath(); g.arc(c, c, c * 0.55, 0, Math.PI * 2); g.fill();
    g.fillStyle = '#F2E6C9'; g.font = '900 92px "Barlow Condensed", sans-serif';
    g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText('$', c, c + 6);
  });
  const side = canvasTex(256, 16, (g, w, h) => {
    g.fillStyle = base; g.fillRect(0, 0, w, h);
    g.fillStyle = '#F2E6C9';
    for (let i = 0; i < 8; i++) g.fillRect(i * 32 + 8, 0, 14, h);
  });
  side.wrapS = THREE.RepeatWrapping;
  return (chipTexCache[color] = { face, side });
}

let chipGeo = null;
export function chipGeometry() {
  return chipGeo || (chipGeo = new THREE.CylinderGeometry(0.2, 0.2, 0.05, 40, 1, false));
}
export function chipMaterials(color = PAL.red) {
  const { face, side } = chipTextures(color);
  const s = new THREE.MeshStandardMaterial({ map: side, roughness: 0.45 });
  const f = new THREE.MeshStandardMaterial({ map: face, roughness: 0.4 });
  return [s, f, f];
}
export const CHIP_COLORS = [PAL.red, PAL.black, PAL.felt, PAL.red, 0x1F4E8C, PAL.burgundy, PAL.red, 0x2b2b2b];

/** A stack of chips as one InstancedMesh. */
export function chipStack(n, color, mats) {
  const mesh = new THREE.InstancedMesh(chipGeometry(), mats || chipMaterials(color), n);
  const m = new THREE.Matrix4();
  for (let i = 0; i < n; i++) {
    m.makeRotationY(Math.random() * 6);
    m.setPosition((Math.random() - 0.5) * 0.02, 0.025 + i * 0.052, (Math.random() - 0.5) * 0.02);
    mesh.setMatrixAt(i, m);
  }
  mesh.castShadow = true;
  return mesh;
}

// ---------------------------------------------------------------- roulette
export function makeRoulette() {
  const g = new THREE.Group();
  const N = 37;
  const order = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26];
  const reds = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]);
  const tex = canvasTex(1024, 1024, (ctx, w) => {
    const c = w / 2;
    ctx.fillStyle = '#3b2216'; ctx.fillRect(0, 0, w, w);
    for (let i = 0; i < N; i++) {
      const a0 = (i / N) * Math.PI * 2 - Math.PI / 2, a1 = ((i + 1) / N) * Math.PI * 2 - Math.PI / 2;
      const n = order[i];
      ctx.fillStyle = n === 0 ? css(PAL.felt) : reds.has(n) ? css(PAL.red) : '#1a1817';
      ctx.beginPath(); ctx.moveTo(c, c); ctx.arc(c, c, c * 0.98, a0, a1); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#D6A84B'; ctx.lineWidth = 3; ctx.stroke();
      ctx.save(); ctx.translate(c, c); ctx.rotate((a0 + a1) / 2 + Math.PI / 2);
      ctx.fillStyle = '#F2E6C9'; ctx.font = '800 40px "Barlow Condensed", sans-serif'; ctx.textAlign = 'center';
      ctx.fillText(String(n), 0, -c * 0.83); ctx.restore();
    }
    // pocket ring + inner cone
    ctx.strokeStyle = '#D6A84B'; ctx.lineWidth = 6;
    ctx.beginPath(); ctx.arc(c, c, c * 0.74, 0, Math.PI * 2); ctx.stroke();
    const grd = ctx.createRadialGradient(c, c, 10, c, c, c * 0.72);
    grd.addColorStop(0, '#6b3b22'); grd.addColorStop(1, '#3b2216');
    ctx.fillStyle = grd; ctx.beginPath(); ctx.arc(c, c, c * 0.72, 0, Math.PI * 2); ctx.fill();
    for (let i = 0; i < 4; i++) {
      ctx.save(); ctx.translate(c, c); ctx.rotate(i * Math.PI / 2);
      ctx.fillStyle = 'rgba(214,168,75,.5)'; ctx.fillRect(-6, -c * 0.7, 12, c * 0.7); ctx.restore();
    }
  });
  const wheel = new THREE.Mesh(new THREE.CylinderGeometry(1.2, 1.15, 0.12, 64), [
    new THREE.MeshStandardMaterial({ color: 0x4a2a1a, roughness: 0.5 }),
    new THREE.MeshStandardMaterial({ map: tex, roughness: 0.35, metalness: 0.1 }),
    new THREE.MeshStandardMaterial({ color: 0x2b1a12 }),
  ]);
  wheel.receiveShadow = true;
  g.add(wheel);
  // bowl rim (wood + gold)
  const rimPts = [];
  for (let i = 0; i <= 12; i++) { const t = i / 12; rimPts.push(new THREE.Vector2(1.2 + Math.sin(t * Math.PI) * 0.12 + t * 0.18, -0.08 + t * 0.32)); }
  const rim = new THREE.Mesh(new THREE.LatheGeometry(rimPts, 72), new THREE.MeshStandardMaterial({ color: 0x5a2f1c, roughness: 0.45, side: THREE.DoubleSide }));
  g.add(rim);
  const goldRing = new THREE.Mesh(new THREE.TorusGeometry(1.39, 0.035, 10, 96), new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.9, roughness: 0.25 }));
  goldRing.rotation.x = Math.PI / 2; goldRing.position.y = 0.24;
  g.add(goldRing);
  // turret
  const gold = new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.95, roughness: 0.22 });
  const turret = new THREE.Group();
  const stem = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.12, 0.35, 16), gold);
  stem.position.y = 0.2; turret.add(stem);
  for (let i = 0; i < 4; i++) {
    const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.025, 0.42, 4, 8), gold);
    arm.rotation.z = Math.PI / 2; arm.position.y = 0.33;
    const piv = new THREE.Group(); piv.rotation.y = i * Math.PI / 2; piv.add(arm); arm.position.x = 0.22;
    const knob = new THREE.Mesh(new THREE.SphereGeometry(0.045, 12, 8), gold); knob.position.set(0.45, 0.33, 0); piv.add(knob);
    turret.add(piv);
  }
  const top = new THREE.Mesh(new THREE.SphereGeometry(0.07, 16, 12), gold); top.position.y = 0.42; turret.add(top);
  wheel.add(turret);
  const ball = new THREE.Mesh(new THREE.SphereGeometry(0.05, 16, 12), new THREE.MeshStandardMaterial({ color: 0xfffdf7, roughness: 0.15 }));
  ball.castShadow = true;
  g.add(ball);
  let ballA = 0, ballR = 1.28, ballV = 7, phase = 0, clock = 0;
  g.userData.update = (dt) => {
    clock += dt;
    wheel.rotation.y += dt * 0.9;
    // ball: spins fast on the rim, slows, drops into the pockets, rides along, then relaunches
    const cycle = clock % 9;
    if (cycle < 5.5) { ballV = THREE.MathUtils.lerp(9, 2.2, cycle / 5.5); ballR = 1.27; phase = 0; ballA -= ballV * dt; ball.position.y = 0.16; }
    else if (cycle < 6.3) { ballR = THREE.MathUtils.lerp(1.27, 0.92, (cycle - 5.5) / 0.8); ballA -= 2 * dt; ball.position.y = 0.16 - (cycle - 5.5) * 0.12 + Math.abs(Math.sin(cycle * 18)) * 0.06; }
    else { ballR = 0.92; ballA += dt * 0.9; ball.position.y = 0.1; }
    ball.position.x = Math.cos(ballA) * ballR; ball.position.z = Math.sin(ballA) * ballR;
  };
  return g;
}

// ---------------------------------------------------------------- cards
const loader = new THREE.TextureLoader();
const cardCache = {};
export function makeCard(face, manager) {
  const l = manager ? new THREE.TextureLoader(manager) : loader;
  const get = (n) => cardCache[n] || (cardCache[n] = (() => { const t = l.load(`assets/cards/card_${n}.png`); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t; })());
  const geo = new THREE.PlaneGeometry(0.42, 0.6);
  const front = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: get(face), roughness: 0.5, transparent: true, alphaTest: 0.1 }));
  const back = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: get('back'), roughness: 0.5, transparent: true, alphaTest: 0.1 }));
  back.rotation.y = Math.PI;
  const g = new THREE.Group(); g.add(front, back);
  front.castShadow = true;
  return g;
}

// ---------------------------------------------------------------- felt table
export function makeFeltTable(radius = 2.2) {
  const g = new THREE.Group();
  const felt = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, 0.12, 64, 1, false, 0, Math.PI),
    [new THREE.MeshStandardMaterial({ color: 0x3a2014, roughness: 0.5 }), new THREE.MeshStandardMaterial({ color: PAL.felt, roughness: 0.92 }), new THREE.MeshStandardMaterial({ color: 0x3a2014 })]);
  felt.rotation.y = -Math.PI / 2;
  felt.receiveShadow = true;
  g.add(felt);
  const rail = new THREE.Mesh(new THREE.TorusGeometry(radius, 0.12, 12, 64, Math.PI), new THREE.MeshStandardMaterial({ color: 0x4a2414, roughness: 0.35 }));
  rail.rotation.x = Math.PI / 2; rail.rotation.z = Math.PI; rail.position.y = 0.06;
  g.add(rail);
  const ped = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.6, 0.9, 24), new THREE.MeshStandardMaterial({ color: 0x2b1a12, roughness: 0.5 }));
  ped.position.y = -0.5; g.add(ped);
  return g;
}

// ---------------------------------------------------------------- Big Wheel
export function makeBigWheel() {
  const g = new THREE.Group();
  const labels = ['$100', '×2', '$250', 'JACKPOT', '$100', '$500', '$50', '×2', '$250', 'BUST', '$100', '$1000'];
  const cols = [PAL.red, PAL.cream, PAL.felt, PAL.vipGold, PAL.red, PAL.charcoal, PAL.felt, PAL.cream, PAL.red, PAL.black, PAL.felt, PAL.burgundy];
  const N = labels.length;
  const tex = canvasTex(1024, 1024, (ctx, w) => {
    const c = w / 2;
    for (let i = 0; i < N; i++) {
      const a0 = (i / N) * Math.PI * 2, a1 = ((i + 1) / N) * Math.PI * 2;
      ctx.fillStyle = css(cols[i]);
      ctx.beginPath(); ctx.moveTo(c, c); ctx.arc(c, c, c, a0, a1); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#E3B95C'; ctx.lineWidth = 8; ctx.stroke();
      ctx.save(); ctx.translate(c, c); ctx.rotate((a0 + a1) / 2);
      const dark = cols[i] === PAL.cream || cols[i] === PAL.vipGold;
      ctx.fillStyle = dark ? '#151414' : '#F2E6C9';
      ctx.font = `900 ${labels[i].length > 5 ? 60 : 78}px "Barlow Condensed", sans-serif`;
      ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
      ctx.fillText(labels[i], c * 0.9, 0); ctx.restore();
    }
    ctx.fillStyle = '#151414'; ctx.beginPath(); ctx.arc(c, c, c * 0.2, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#E3B95C'; ctx.font = '900 70px "Barlow Condensed", sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('★', c, c + 4);
  });
  const R = 2.2;
  const disc = new THREE.Mesh(new THREE.CylinderGeometry(R, R, 0.14, 72), [
    new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.85, roughness: 0.3 }),
    new THREE.MeshStandardMaterial({ map: tex, roughness: 0.5 }),
    new THREE.MeshStandardMaterial({ color: PAL.charcoal }),
  ]);
  disc.rotation.x = Math.PI / 2;
  const spin = new THREE.Group(); spin.add(disc);
  // pegs
  const pegMat = new THREE.MeshStandardMaterial({ color: PAL.cream, metalness: 0.3, roughness: 0.3 });
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2;
    const peg = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.2, 8), pegMat);
    peg.rotation.x = Math.PI / 2; peg.position.set(Math.cos(a) * (R - 0.08), Math.sin(a) * (R - 0.08), 0.12);
    spin.add(peg);
  }
  g.add(spin);
  // bulb ring (static)
  const bulbs = new THREE.InstancedMesh(new THREE.SphereGeometry(0.07, 10, 8), new THREE.MeshBasicMaterial({ color: 0xffffff }), 36);
  const m = new THREE.Matrix4(); const col = new THREE.Color();
  for (let i = 0; i < 36; i++) { const a = (i / 36) * Math.PI * 2; m.makeTranslation(Math.cos(a) * (R + 0.22), Math.sin(a) * (R + 0.22), 0.05); bulbs.setMatrixAt(i, m); bulbs.setColorAt(i, col.set(0xffd27a)); }
  g.add(bulbs);
  const frame = new THREE.Mesh(new THREE.TorusGeometry(R + 0.22, 0.09, 12, 96), new THREE.MeshStandardMaterial({ color: PAL.burgundy, roughness: 0.5 }));
  g.add(frame);
  // pointer
  const ptr = new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.5, 3), new THREE.MeshStandardMaterial({ color: PAL.red, roughness: 0.4 }));
  ptr.rotation.z = Math.PI; ptr.position.set(0, R + 0.4, 0.2);
  g.add(ptr);
  // stand
  const stand = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.25, R + 1.2, 16), new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.9, roughness: 0.3 }));
  stand.position.set(0, -(R + 1.2) / 2, -0.25); g.add(stand);
  let v = 0, clock = 0;
  g.userData.update = (dt, t) => {
    clock += dt;
    const cyc = clock % 7;
    v = cyc < 0.3 ? 6 : Math.max(0, v - dt * 1.2);
    spin.rotation.z -= v * dt;
    for (let i = 0; i < 36; i++) bulbs.setColorAt(i, col.set(((i + Math.floor(t * 6)) % 3 === 0) ? 0xfff1c8 : 0x8a5a1a));
    bulbs.instanceColor.needsUpdate = true;
  };
  return g;
}

// ---------------------------------------------------------------- Peg Drop (2D physics in the board plane)
export function makePegDrop() {
  const g = new THREE.Group();
  const W = 3.2, H = 4.2;
  const board = new THREE.Mesh(new THREE.BoxGeometry(W + 0.3, H + 0.3, 0.12), new THREE.MeshStandardMaterial({ color: 0x1d2a24, roughness: 0.8 }));
  board.position.z = -0.12; g.add(board);
  const frameMat = new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.85, roughness: 0.3 });
  for (const [x, y, w, h] of [[0, H / 2 + 0.15, W + 0.5, 0.12], [0, -H / 2 - 0.15, W + 0.5, 0.12], [-W / 2 - 0.2, 0, 0.12, H + 0.4], [W / 2 + 0.2, 0, 0.12, H + 0.4]]) {
    const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.3), frameMat); b.position.set(x, y, 0); g.add(b);
  }
  const pegs = [];
  const rows = 9;
  for (let r = 0; r < rows; r++) {
    const n = r % 2 ? 7 : 8;
    for (let i = 0; i < n; i++) {
      const x = (i - (n - 1) / 2) * 0.38;
      const y = H / 2 - 0.7 - r * 0.36;
      pegs.push({ x, y });
    }
  }
  const pegMesh = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.035, 0.035, 0.22, 10), new THREE.MeshStandardMaterial({ color: PAL.cream, metalness: 0.4, roughness: 0.3 }), pegs.length);
  const m = new THREE.Matrix4(); const rx = new THREE.Matrix4().makeRotationX(Math.PI / 2);
  pegs.forEach((p, i) => { m.makeTranslation(p.x, p.y, 0.05).multiply(rx); pegMesh.setMatrixAt(i, m); });
  g.add(pegMesh);
  // bins
  const binCols = [PAL.red, PAL.felt, PAL.vipGold, PAL.felt, PAL.red, PAL.felt, PAL.vipGold, PAL.red];
  const binTex = canvasTex(1024, 128, (ctx, w, h) => {
    const labels = ['×0', '×1', '×5', '×2', '×2', '×5', '×1', '×0'];
    for (let i = 0; i < 8; i++) {
      ctx.fillStyle = css(binCols[i]); ctx.fillRect(i * w / 8 + 3, 0, w / 8 - 6, h);
      ctx.fillStyle = binCols[i] === PAL.vipGold ? '#151414' : '#F2E6C9';
      ctx.font = '900 72px "Barlow Condensed", sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(labels[i], i * w / 8 + w / 16, h / 2 + 4);
    }
  });
  const bins = new THREE.Mesh(new THREE.PlaneGeometry(W, 0.4), new THREE.MeshStandardMaterial({ map: binTex, roughness: 0.6, emissive: 0x222222, emissiveMap: binTex }));
  bins.position.set(0, -H / 2 + 0.2, -0.05); g.add(bins);
  // header
  const head = canvasTex(1024, 220, (ctx, w, h) => {
    ctx.fillStyle = css(PAL.burgundy); ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = '#E3B95C'; ctx.lineWidth = 10; ctx.strokeRect(8, 8, w - 16, h - 16);
    ctx.fillStyle = '#F2E6C9'; ctx.font = '900 150px "Barlow Condensed", sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('PEG DROP', w / 2, h / 2 + 8);
  });
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(W + 0.4, (W + 0.4) * 220 / 1024), new THREE.MeshStandardMaterial({ map: head, roughness: 0.5, emissive: 0xffffff, emissiveMap: head, emissiveIntensity: 0.25 }));
  sign.position.set(0, H / 2 + 0.6, 0.05); g.add(sign);

  const MAXB = 14, BR = 0.09;
  const ballMat = new THREE.MeshStandardMaterial({ color: 0xffffff, metalness: 0.7, roughness: 0.2 });
  const balls = [];
  const ballMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(BR, 16, 12), ballMat, MAXB);
  ballMesh.castShadow = true;
  const bc = new THREE.Color();
  const ballColors = [PAL.vipGold, PAL.red, PAL.cream, PAL.money];
  g.add(ballMesh);
  let spawn = 0;
  g.userData.update = (dt) => {
    dt = Math.min(dt, 1 / 30);
    spawn -= dt;
    if (spawn <= 0 && balls.length < MAXB) {
      spawn = 0.55;
      balls.push({ x: (Math.random() - 0.5) * 0.5, y: H / 2 - 0.25, vx: (Math.random() - 0.5) * 0.4, vy: 0, c: ballColors[balls.length % 4], life: 0 });
    }
    const sub = 3, h = dt / sub;
    for (let s = 0; s < sub; s++) {
      for (const b of balls) {
        b.vy -= 7.5 * h; b.x += b.vx * h; b.y += b.vy * h; b.life += h;
        for (const p of pegs) {
          const dx = b.x - p.x, dy = b.y - p.y, d2 = dx * dx + dy * dy, R = BR + 0.035;
          if (d2 < R * R) {
            const d = Math.sqrt(d2) || 0.001, nx = dx / d, ny = dy / d;
            b.x = p.x + nx * R; b.y = p.y + ny * R;
            const vn = b.vx * nx + b.vy * ny;
            if (vn < 0) { b.vx -= 1.55 * vn * nx; b.vy -= 1.55 * vn * ny; b.vx += (Math.random() - 0.5) * 0.15; }
          }
        }
        if (b.x < -W / 2 + BR) { b.x = -W / 2 + BR; b.vx = Math.abs(b.vx) * 0.6; }
        if (b.x > W / 2 - BR) { b.x = W / 2 - BR; b.vx = -Math.abs(b.vx) * 0.6; }
        if (b.y < -H / 2 + 0.45) { b.y = -H / 2 + 0.45; b.vy = 0; b.vx *= 0.8; }
      }
    }
    for (let i = balls.length - 1; i >= 0; i--) if (balls[i].life > 4.6) balls.splice(i, 1);
    for (let i = 0; i < MAXB; i++) {
      const b = balls[i];
      if (b) { m.makeTranslation(b.x, b.y, 0.08); ballMesh.setColorAt(i, bc.set(b.c)); }
      else m.makeScale(0, 0, 0);
      ballMesh.setMatrixAt(i, m);
    }
    ballMesh.instanceMatrix.needsUpdate = true;
    if (ballMesh.instanceColor) ballMesh.instanceColor.needsUpdate = true;
  };
  return g;
}

// ---------------------------------------------------------------- marquee sign with bulbs
export function makeMarquee(text, sub, w = 6, h = 2.2) {
  const g = new THREE.Group();
  const tex = canvasTex(1536, Math.round(1536 * h / w), (ctx, cw, ch) => {
    const grd = ctx.createLinearGradient(0, 0, 0, ch);
    grd.addColorStop(0, '#7a2433'); grd.addColorStop(1, '#4a1420');
    ctx.fillStyle = grd; ctx.fillRect(0, 0, cw, ch);
    ctx.strokeStyle = '#E3B95C'; ctx.lineWidth = 14; ctx.strokeRect(70, 70, cw - 140, ch - 140);
    ctx.fillStyle = '#F2E6C9'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = `900 ${Math.round(ch * 0.42)}px "Barlow Condensed", sans-serif`;
    ctx.fillText(text, cw / 2, ch * (sub ? 0.43 : 0.52));
    if (sub) { ctx.fillStyle = '#E3B95C'; ctx.font = `800 ${Math.round(ch * 0.16)}px "Barlow Condensed", sans-serif`; ctx.fillText(sub, cw / 2, ch * 0.74); }
  });
  const board = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.25), [
    new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.8, roughness: 0.3 }),
    new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.8, roughness: 0.3 }),
    new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.8, roughness: 0.3 }),
    new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.8, roughness: 0.3 }),
    new THREE.MeshStandardMaterial({ map: tex, roughness: 0.55, emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: 0.35 }),
    new THREE.MeshStandardMaterial({ color: PAL.charcoal }),
  ]);
  g.add(board);
  const pts = [];
  const step = 0.3;
  for (let x = -w / 2 + 0.18; x <= w / 2 - 0.17; x += step) { pts.push([x, h / 2 - 0.15]); pts.push([x, -h / 2 + 0.15]); }
  for (let y = -h / 2 + 0.45; y <= h / 2 - 0.44; y += step) { pts.push([-w / 2 + 0.18, y]); pts.push([w / 2 - 0.18, y]); }
  const bulbs = new THREE.InstancedMesh(new THREE.SphereGeometry(0.065, 10, 8), new THREE.MeshBasicMaterial({ color: 0xffffff }), pts.length);
  const m = new THREE.Matrix4(), c = new THREE.Color();
  pts.forEach(([x, y], i) => { m.makeTranslation(x, y, 0.14); bulbs.setMatrixAt(i, m); bulbs.setColorAt(i, c.set(0xffe2a0)); });
  g.add(bulbs);
  g.userData.update = (dt, t) => {
    const k = Math.floor(t * 8);
    for (let i = 0; i < pts.length; i++) bulbs.setColorAt(i, c.set(((i + k) % 4 < 2) ? 0xfff0c8 : 0x6a4214));
    bulbs.instanceColor.needsUpdate = true;
  };
  return g;
}

// ---------------------------------------------------------------- podium
export function makePodium() {
  const g = new THREE.Group();
  const heights = [1.1, 0.75, 0.5];
  const xs = [0, -1.45, 1.45];
  const tops = [];
  heights.forEach((h, i) => {
    const tex = canvasTex(256, 256, (ctx, w) => {
      ctx.fillStyle = i === 0 ? '#681F2C' : '#24211F'; ctx.fillRect(0, 0, w, w);
      ctx.strokeStyle = '#E3B95C'; ctx.lineWidth = 10; ctx.strokeRect(14, 14, w - 28, w - 28);
      ctx.fillStyle = '#E3B95C'; ctx.font = '900 150px "Barlow Condensed", sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(String(i + 1), w / 2, w / 2 + 10);
    });
    const side = new THREE.MeshStandardMaterial({ color: i === 0 ? PAL.burgundy : PAL.charcoal, roughness: 0.6 });
    const topM = new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.8, roughness: 0.3 });
    const box = new THREE.Mesh(new THREE.BoxGeometry(1.35, h, 1.2), [side, side, topM, side, new THREE.MeshStandardMaterial({ map: tex, roughness: 0.5 }), side]);
    box.position.set(xs[i], h / 2, 0);
    box.castShadow = box.receiveShadow = true;
    g.add(box);
    tops.push(new THREE.Vector3(xs[i], h, 0));
  });
  g.userData.tops = tops;
  return g;
}

// ---------------------------------------------------------------- architecture
export function makeColumn(height = 7) {
  const g = new THREE.Group();
  const marble = new THREE.MeshStandardMaterial({ color: 0xE8DCC4, roughness: 0.35 });
  const gold = new THREE.MeshStandardMaterial({ color: PAL.gold, metalness: 0.9, roughness: 0.3 });
  const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.36, height, 20), marble);
  shaft.position.y = height / 2; shaft.castShadow = true; shaft.receiveShadow = true; g.add(shaft);
  for (const y of [0.15, height - 0.15]) {
    const cap = new THREE.Mesh(new THREE.BoxGeometry(0.95, 0.3, 0.95), marble); cap.position.y = y; g.add(cap);
  }
  for (const y of [0.45, 1.6, height - 0.45]) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.37, 0.04, 8, 32), gold); ring.rotation.x = Math.PI / 2; ring.position.y = y; g.add(ring);
  }
  return g;
}

export function makeChandelier() {
  const g = new THREE.Group();
  const gold = new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.95, roughness: 0.25 });
  const chain = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 2.5, 6), gold); chain.position.y = 1.25; g.add(chain);
  const hub = new THREE.Mesh(new THREE.SphereGeometry(0.22, 16, 12), gold); g.add(hub);
  for (const [r, y, n] of [[0.9, -0.1, 8], [0.55, 0.35, 6]]) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(r, 0.03, 8, 48), gold); ring.rotation.x = Math.PI / 2; ring.position.y = y; g.add(ring);
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      const candle = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.18, 8), new THREE.MeshStandardMaterial({ color: PAL.cream })); candle.position.set(Math.cos(a) * r, y + 0.1, Math.sin(a) * r); g.add(candle);
      const flame = new THREE.Mesh(new THREE.SphereGeometry(0.055, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd28a })); flame.position.set(Math.cos(a) * r, y + 0.24, Math.sin(a) * r); g.add(flame);
    }
  }
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2;
    const drop = new THREE.Mesh(new THREE.OctahedronGeometry(0.06), new THREE.MeshStandardMaterial({ color: 0xfff6e0, metalness: 0.3, roughness: 0.05, emissive: 0x3a2a10 }));
    drop.position.set(Math.cos(a) * 0.9, -0.32, Math.sin(a) * 0.9); drop.scale.y = 1.8; g.add(drop);
  }
  return g;
}

/** Velvet rope post pair with a sagging rope. */
export function makeRope(len = 2.4) {
  const g = new THREE.Group();
  const gold = new THREE.MeshStandardMaterial({ color: PAL.vipGold, metalness: 0.9, roughness: 0.28 });
  for (const x of [-len / 2, len / 2]) {
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.06, 1, 12), gold); post.position.set(x, 0.5, 0); g.add(post);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.22, 0.06, 20), gold); base.position.set(x, 0.03, 0); g.add(base);
    const knob = new THREE.Mesh(new THREE.SphereGeometry(0.08, 12, 10), gold); knob.position.set(x, 1.04, 0); g.add(knob);
  }
  const curve = new THREE.QuadraticBezierCurve3(new THREE.Vector3(-len / 2, 0.95, 0), new THREE.Vector3(0, 0.45, 0), new THREE.Vector3(len / 2, 0.95, 0));
  const rope = new THREE.Mesh(new THREE.TubeGeometry(curve, 24, 0.035, 8), new THREE.MeshStandardMaterial({ color: 0x8e1f2e, roughness: 0.8 }));
  g.add(rope);
  return g;
}
