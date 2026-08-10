import * as THREE from "three";

(() => {
  "use strict";

  const MODES = {
    sixshot: { name: "六目标", count: 6, color: 0xff6b5e, scorePerKill: 10, respawnDelay: 400 },
    tracking: { name: "跟踪", count: 1, color: 0x4fc3ff, scorePerKill: 25, respawnDelay: 350 },
    gridshot: { name: "极速切换", count: 1, color: 0xffc24d, scorePerKill: 15, respawnDelay: 200 }
  };
  // 无畏契约的灵敏度换算：1 个鼠标计数 = 0.07 度
  // 视角平滑预设：[单帧角度上限, 最大角速度(弧度/秒)]
  const SMOOTH_PRESETS = {
    responsive: { step: 0.25, vel: 16 },
    balanced: { step: 0.1, vel: 8 },
    stable: { step: 0.05, vel: 4 }
  };
  const VALORANT_DEG_PER_COUNT = 0.07;
  const RAD_PER_PIXEL = VALORANT_DEG_PER_COUNT * Math.PI / 180;
  const PITCH_LIMIT = 1.4; // 约 80 度，防止镜头翻转
  const ADMIN_PASS_HASH = "3bacef24";

  const $ = (id) => document.getElementById(id);
  const ui = {
    hud: $("hud"),
    menu: $("menu"),
    pause: $("pause"),
    results: $("results"),
    timer: $("timer"),
    score: $("score"),
    statAcc: $("stat-acc"),
    statKills: $("stat-kills"),
    statShots: $("stat-shots"),
    modeLabel: $("mode-label"),
    hitmarker: $("hitmarker"),
    resScore: $("res-score"),
    resKills: $("res-kills"),
    resAcc: $("res-acc"),
    resAvg: $("res-avg"),
    resBest: $("res-best"),
    resNewBest: $("res-newbest"),
    sensInput: $("set-sens-input"),
    adminBtn: $("admin-btn"),
    adminLogin: $("admin-login"),
    adminPass: $("admin-pass"),
    adminOk: $("admin-ok"),
    adminMsg: $("admin-msg"),
    adminPanel: $("admin-panel"),
    adminExit: $("admin-exit"),
    setTriggerbot: $("set-triggerbot"),
    setAssist: $("set-assist"),
    setAssistFov: $("set-assist-fov"),
    setAssistStrength: $("set-assist-strength"),
    fovValue: $("fov-value"),
    strengthValue: $("strength-value"),
    accName: $("acc-name"),
    accPass: $("acc-pass"),
    accMsg: $("account-msg"),
    lbBtn: $("lb-btn"),
    lbList: $("lb-list"),
    lbClose: $("lb-close"),
    leaderboard: $("leaderboard")
  };

  // ---------- 渲染环境 ----------
  const canvas = $("game");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0d1117);
  scene.fog = new THREE.Fog(0x0d1117, 28, 60);

  const camera = new THREE.PerspectiveCamera(90, window.innerWidth / window.innerHeight, 0.1, 200);
  camera.position.set(0, 1.6, 0);
  camera.rotation.order = "YXZ";

  scene.add(new THREE.HemisphereLight(0xbfd9ff, 0x14161d, 1.1));
  const sun = new THREE.DirectionalLight(0xffffff, 1.4);
  sun.position.set(12, 22, 8);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  sun.shadow.camera.left = -35;
  sun.shadow.camera.right = 35;
  sun.shadow.camera.top = 35;
  sun.shadow.camera.bottom = -35;
  sun.shadow.camera.near = 1;
  sun.shadow.camera.far = 70;
  sun.shadow.bias = -0.0005;
  scene.add(sun);

  // ---------- 训练场 ----------
  function makeGridTexture() {
    const c = document.createElement("canvas");
    c.width = 256;
    c.height = 256;
    const ctx = c.getContext("2d");
    ctx.fillStyle = "#141922";
    ctx.fillRect(0, 0, 256, 256);
    ctx.strokeStyle = "rgba(120, 160, 220, 0.14)";
    ctx.lineWidth = 2;
    for (let i = 0; i <= 8; i++) {
      ctx.beginPath();
      ctx.moveTo(i * 32, 0);
      ctx.lineTo(i * 32, 256);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * 32);
      ctx.lineTo(256, i * 32);
      ctx.stroke();
    }
    return new THREE.CanvasTexture(c);
  }

  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(64, 64),
    new THREE.MeshStandardMaterial({ map: makeGridTexture(), roughness: 0.9 })
  );
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);

  const blockers = [];
  blockers.push(floor);
  function addBox(w, h, d, x, y, z, material) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), material);
    mesh.position.set(x, y, z);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    scene.add(mesh);
    blockers.push(mesh);
    return mesh;
  }

  const wallMat = new THREE.MeshStandardMaterial({ color: 0x1b2230, roughness: 0.85 });
  const pillarMat = new THREE.MeshStandardMaterial({ color: 0x242e40, roughness: 0.75 });
  addBox(64, 14, 1, 0, 7, -32, wallMat);
  addBox(64, 14, 1, 0, 7, 32, wallMat);
  addBox(1, 14, 64, -32, 7, 0, wallMat);
  addBox(1, 14, 64, 32, 7, 0, wallMat);
  addBox(64, 1, 64, 0, 14.5, 0, wallMat);
  for (const [x, z] of [[-11, -11], [11, -11], [-11, 11], [11, 11]]) {
    addBox(2, 9, 2, x, 4.5, z, pillarMat);
  }

  const glowTex = makeGlowTexture();
  function makeGlowTexture() {
    const c = document.createElement("canvas");
    c.width = c.height = 128;
    const ctx = c.getContext("2d");
    const grad = ctx.createRadialGradient(64, 64, 4, 64, 64, 62);
    grad.addColorStop(0, "rgba(255,255,255,0.9)");
    grad.addColorStop(0.35, "rgba(255,255,255,0.35)");
    grad.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 128, 128);
    return new THREE.CanvasTexture(c);
  }

  // ---------- 游戏状态 ----------
let mode = "sixshot";
let account = null;
let sizeMult = 1;
  let speedMult = 1;
  let running = false;
  let paused = false;
  let finished = false;
  let timeLeft = 60;
  let kills = 0;
  let shots = 0;
  let hits = 0;
  let score = 0;
  let mouseDown = false;
  let dragging = false;
  let locked = false;
  let controlMode = "lock";
  let smoothingMode = "balanced";
  let adminUnlocked = false;
  let triggerbot = false;
  let assist = false;
  let assistFov = 12 * Math.PI / 180;
  let assistStrength = 0.4;
  let lastAutoFire = 0;
  let yaw = 0;
  let pitch = 0;
  let targetYaw = 0;
  let targetPitch = 0;
  let sens = 1;
  let spawnSide = "front";
  let skipMoveUntil = 0;
  let firstMoveAfterLock = true;
  let lastNow = performance.now();
  let startReal = 0;
  let hitmarkerAt = 0;
  let duration = 60;

  let targets = [];
  let targetMeshes = [];
  const raycaster = new THREE.Raycaster();

  function createTarget(color) {
    const r = 0.34 * sizeMult;
    const group = new THREE.Group();
    const sphere = new THREE.Mesh(
      new THREE.SphereGeometry(r, 24, 18),
      new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 0.5, roughness: 0.3 })
    );
    sphere.castShadow = true;
    const glow = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: glowTex, color, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false })
    );
    glow.scale.set(r * 7, r * 7, 1);
    group.add(sphere, glow);
    group.visible = false;
    scene.add(group);
    return {
      group,
      sphere,
      radius: r,
      alive: false,
      respawnAt: 0,
      hp: 100,
      angY: 0,
      angP: 0,
      vy: 0.4,
      vp: 0.3,
      angYMin: -1.35,
      angYMax: 1.35,
      pulsePhase: Math.random() * Math.PI * 2
    };
  }

  function randomTargetPos() {
    for (let i = 0; i < 24; i++) {
      // 以场地固定方向为基准生成（前方=初始视角方向），球不会出现在背后、脚下或相机内部
      const worldYaw = spawnSide === "front"
        ? (Math.random() * 2 - 1) * 0.7
        : (Math.random() * 2 - 1) * Math.PI;
      const worldPitch = Math.max(-0.1, Math.min(0.8, pitch + (Math.random() * 2 - 1) * 0.35));
      const dir = new THREE.Vector3(
        -Math.sin(worldYaw) * Math.cos(worldPitch),
        Math.sin(worldPitch),
        -Math.cos(worldYaw) * Math.cos(worldPitch)
      );
      // 生成距离 3~10 米；如果前方有墙或柱子，就把球放到障碍物前面
      const dist = 6.5 + Math.random() * 3.5;
      const ray = new THREE.Raycaster(camera.position, dir);
      const hits = ray.intersectObjects(blockers, false);
      let targetDist = dist;
      if (hits.length && hits[0].distance < dist - 0.6) {
        targetDist = Math.max(3, hits[0].distance - 0.6);
      }
      const pos = camera.position.clone().addScaledVector(dir, targetDist);
      pos.y = Math.max(pos.y, 0.7);
      let ok = true;
      for (const t of targets) {
        if (t.alive && t.group.position.distanceTo(pos) < 3) {
          ok = false;
          break;
        }
      }
      if (ok) return pos;
    }
    return null;
  }

  function spawnTarget(t) {
    if (mode === "tracking") {
      t.angY = spawnSide === "front"
        ? (Math.random() * 2 - 1) * 0.6
        : (Math.random() * 2 - 1) * Math.PI;
      t.angYMin = spawnSide === "front" ? -0.8 : -Math.PI;
      t.angYMax = spawnSide === "front" ? 0.8 : Math.PI;
      t.angP = Math.max(-0.1, Math.min(0.7, pitch + (Math.random() * 2 - 1) * 0.4));
      t.vy = (0.35 + Math.random() * 0.5) * speedMult * (Math.random() < 0.5 ? -1 : 1);
      t.vp = (0.25 + Math.random() * 0.35) * speedMult * (Math.random() < 0.5 ? -1 : 1);
      t.hp = 100;
      placeTrackingTarget(t);
    } else {
      const pos = randomTargetPos();
      if (!pos) {
        t.respawnAt = performance.now() + 300;
        return;
      }
      t.group.position.copy(pos);
    }
    t.alive = true;
    t.group.visible = true;
  }

  function placeTrackingTarget(t) {
    const dir = new THREE.Vector3(
      -Math.sin(t.angY) * Math.cos(t.angP),
      Math.sin(t.angP),
      -Math.cos(t.angY) * Math.cos(t.angP)
    );
    const ray = new THREE.Raycaster(camera.position, dir);
    const hits = ray.intersectObjects(blockers, false);
    let dist = 10;
    if (hits.length && hits[0].distance < dist - 0.6) {
      dist = Math.max(3, hits[0].distance - 0.6);
    }
    const pos = camera.position.clone().addScaledVector(dir, dist);
    pos.y = Math.max(pos.y, 0.7);
    t.group.position.copy(pos);
  }

  function startRound() {
    const cards = document.querySelectorAll(".mode-card");
    for (const card of cards) {
      if (card.classList.contains("active")) mode = card.dataset.mode;
    }
    duration = Number($("set-duration").value);
    sizeMult = Number($("set-size").value);
    speedMult = Number($("set-speed").value);
    spawnSide = $("set-side").value;
    controlMode = $("set-control").value;
    smoothingMode = $("set-smooth").value;

    for (const t of targets) scene.remove(t.group);
    targets = [];
    const cfg = MODES[mode];
    for (let i = 0; i < cfg.count; i++) targets.push(createTarget(cfg.color));
    targetMeshes = targets.map((t) => t.sphere);
    for (const t of targets) spawnTarget(t);

    kills = 0;
    shots = 0;
    hits = 0;
    score = 0;
    timeLeft = duration;
    running = true;
    paused = false;
    finished = false;
    startReal = performance.now();

    ui.menu.classList.add("hidden");
    ui.results.classList.add("hidden");
    ui.hud.classList.remove("hidden");
    ui.modeLabel.textContent = cfg.name;
    updateHud();
    if (controlMode === "lock") canvas.requestPointerLock();
    ui.pause.classList.add("hidden");
    playStart();
  }

  function endRound() {
    running = false;
    finished = true;
    if (document.pointerLockElement === canvas) document.exitPointerLock();
    const elapsed = (performance.now() - startReal) / 1000;
    const acc = shots ? Math.round((hits / shots) * 100) : 0;
    const avg = kills ? elapsed / kills : null;
    const key = bestKey();
    const prevBest = Number(localStorage.getItem(key) || 0);
    const isBest = score > prevBest;
    if (isBest) localStorage.setItem(key, String(score));
    if (account) {
      apiPost("/api/score", {
        name: account.name,
        password: account.password,
        mode,
        score,
        kills,
        acc,
        avg: avg ? Math.round(avg * 100) / 100 : 0
      });
    }

    ui.resScore.textContent = score;
    ui.resKills.textContent = kills;
    ui.resAcc.textContent = acc + "%";
    ui.resAvg.textContent = avg ? avg.toFixed(2) + " 秒" : "—";
    ui.resBest.textContent = Math.max(prevBest, score);
    ui.resNewBest.classList.toggle("hidden", !isBest);
    ui.hud.classList.add("hidden");
    ui.results.classList.remove("hidden");
    playEnd();
  }

  function bestKey() {
    return `aimtrainer-${mode}-${duration}-${sizeMult}-${speedMult}`;
  }

  // ---------- 射击 ----------
  function castRay() {
    raycaster.setFromCamera(new THREE.Vector2(0, 0), camera);
    const found = raycaster.intersectObjects(targetMeshes, false);
    return found.length ? found[0] : null;
  }

  function hitTargetOf(obj) {
    for (const t of targets) {
      if (t.alive && t.sphere === obj) return t;
    }
    return null;
  }

  // 瞄准辅助：把目标角度向视野范围内的最近靶子轻微吸附
  function updateAssist(dt) {
    if (!assist) return;
    let best = null;
    for (const t of targets) {
      if (!t.alive) continue;
      const dir = new THREE.Vector3().subVectors(t.group.position, camera.position).normalize();
      const targetYawAngle = Math.atan2(-dir.x, -dir.z);
      const targetPitchAngle = Math.asin(Math.max(-1, Math.min(1, dir.y)));
      let dy = targetYawAngle - yaw;
      dy = Math.atan2(Math.sin(dy), Math.cos(dy));
      const dp = targetPitchAngle - pitch;
      const d = Math.hypot(dy, dp);
      if (d <= assistFov && (!best || d < best.d)) best = { d, dy, dp };
    }
    if (!best) return;
    const pull = assistStrength * Math.min(1, 10 * dt);
    targetYaw += best.dy * pull;
    targetPitch += best.dp * pull;
    targetPitch = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, targetPitch));
  }

  function fire() {
    if (!running || paused) return;
    shots++;
    playShot();
    const hit = castRay();
    if (hit) {
      const t = hitTargetOf(hit.object);
      if (t) {
        hits++;
        showHitmarker();
        playHit();
        burst(hit.point, t.sphere.material.color.getHex());
        onKill(t);
      }
    } else {
      playMiss();
    }
    updateHud();
  }

  function onKill(t) {
    const cfg = MODES[mode];
    kills++;
    score += cfg.scorePerKill;
    t.alive = false;
    t.group.visible = false;
    t.respawnAt = performance.now() + cfg.respawnDelay;
    playKill();
  }

  function updateTracking(dt) {
    const t = targets[0];
    if (!t || !t.alive) return;
    t.angY += t.vy * dt;
    t.angP += t.vp * dt;
    if (t.angY > t.angYMax || t.angY < t.angYMin) t.vy *= -1;
    if (t.angP > 0.65 || t.angP < -0.1) t.vp *= -1;
    t.angY = Math.max(t.angYMin, Math.min(t.angYMax, t.angY));
    t.angP = Math.max(-0.1, Math.min(0.65, t.angP));
    placeTrackingTarget(t);

    const hit = castRay();
    const onTarget = !!hit && hitTargetOf(hit.object) === t;
    const holding = mouseDown || (triggerbot && onTarget);
    if (holding) {
      shots += dt;
      if (onTarget) {
        hits += dt;
        t.hp -= 120 * dt;
        if (performance.now() - hitmarkerAt > 140) {
          showHitmarker();
          hitmarkerAt = performance.now();
        }
        if (t.hp <= 0) onKill(t);
      }
    }
    updateHud();
  }

  // ---------- 粒子 ----------
  const PARTICLE_COUNT = 60;
  const particlePool = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(0.07, 0.07, 0.07),
      new THREE.MeshBasicMaterial({ color: 0xffb347, transparent: true })
    );
    mesh.visible = false;
    scene.add(mesh);
    particlePool.push({ mesh, vel: new THREE.Vector3(), life: 0, max: 0.3 });
  }
  let pIdx = 0;

  function burst(pos, color) {
    for (let i = 0; i < 10; i++) {
      const p = particlePool[pIdx++ % PARTICLE_COUNT];
      p.mesh.position.copy(pos);
      p.vel.set((Math.random() - 0.5) * 5, (Math.random() - 0.5) * 5, (Math.random() - 0.5) * 5);
      p.life = p.max = 0.28 + Math.random() * 0.15;
      p.mesh.material.color.setHex(color);
      p.mesh.material.opacity = 1;
      p.mesh.visible = true;
    }
  }

  function updateParticles(dt) {
    for (const p of particlePool) {
      if (!p.mesh.visible) continue;
      p.life -= dt;
      if (p.life <= 0) {
        p.mesh.visible = false;
        continue;
      }
      p.mesh.position.addScaledVector(p.vel, dt);
      p.vel.multiplyScalar(0.92);
      p.mesh.material.opacity = Math.max(0, p.life / p.max);
    }
  }

  // ---------- HUD ----------
  function updateHud() {
    ui.timer.textContent = Math.max(0, timeLeft).toFixed(1);
    ui.score.textContent = score;
    const acc = shots ? Math.round((hits / shots) * 100) : 0;
    ui.statAcc.textContent = acc + "%";
    ui.statKills.textContent = kills;
    ui.statShots.textContent = mode === "tracking" ? shots.toFixed(1) + "s" : shots;
  }

  function showHitmarker() {
    ui.hitmarker.classList.remove("pop");
    void ui.hitmarker.offsetWidth;
    ui.hitmarker.classList.add("pop");
  }

  // ---------- 输入 ----------
  canvas.addEventListener("click", () => {
    if (controlMode === "lock" && running && !finished && document.pointerLockElement !== canvas) {
      canvas.requestPointerLock();
    }
    ensureAudio();
  });

  document.addEventListener("pointerlockchange", () => {
    if (controlMode !== "lock") return;
    locked = document.pointerLockElement === canvas;
    if (locked) {
      skipMoveUntil = performance.now() + 120;
      firstMoveAfterLock = true;
      targetYaw = yaw;
      targetPitch = pitch;
    }
    if (running && !finished && !locked) {
      paused = true;
      ui.pause.classList.remove("hidden");
    } else if (locked && paused) {
      paused = false;
      ui.pause.classList.add("hidden");
      lastNow = performance.now();
    }
  });

  document.addEventListener("mousemove", (e) => {
    if (!running || paused) return;
    const dx = e.movementX;
    const dy = e.movementY;
    if (controlMode === "lock") {
      if (!locked) return;
      if (performance.now() < skipMoveUntil) return;
      if (firstMoveAfterLock) {
        firstMoveAfterLock = false;
        if (Math.abs(dx) > 120 || Math.abs(dy) > 120) return;
      }
    } else if (!dragging) {
      return;
    }
    // 位移只累计到目标角度，由主循环插值平滑追过去，不直接改当前角度
    targetYaw -= dx * RAD_PER_PIXEL * sens;
    targetPitch -= dy * RAD_PER_PIXEL * sens;
    targetPitch = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, targetPitch));
  });

  canvas.addEventListener("mousedown", (e) => {
    if (e.button === 2 && controlMode === "drag") {
      dragging = true;
      return;
    }
    if (e.button === 0) {
      mouseDown = true;
      if ((locked || controlMode === "drag") && running && !paused && mode !== "tracking") fire();
    }
  });

  window.addEventListener("mouseup", (e) => {
    if (e.button === 0) mouseDown = false;
    if (e.button === 2) dragging = false;
  });

  document.addEventListener("contextmenu", (e) => e.preventDefault());

  ui.pause.addEventListener("click", () => {
    if (running) canvas.requestPointerLock();
  });

  // ---------- 菜单 ----------
  document.querySelectorAll(".mode-card").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".mode-card").forEach((b) => b.classList.toggle("active", b === btn));
    });
  });

  $("start-btn").addEventListener("click", startRound);
  $("again-btn").addEventListener("click", startRound);
  $("menu-btn").addEventListener("click", () => {
    ui.results.classList.add("hidden");
    ui.menu.classList.remove("hidden");
  });

  // ---------- 云端账号 ----------
  async function apiPost(path, payload) {
    try {
      const res = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      return await res.json();
    } catch {
      return { ok: false, error: "无法连接服务器" };
    }
  }

  function setAccMsg(text, ok) {
    ui.accMsg.textContent = text;
    ui.accMsg.style.color = ok ? "#6ee7a5" : "#ff7b6e";
  }

  async function doLogin() {
    const name = ui.accName.value.trim();
    const password = ui.accPass.value;
    if (!name || !password) return setAccMsg("请输入用户名和密码");
    const data = await apiPost("/api/login", { name, password });
    if (data.ok) {
      account = { name, password };
      localStorage.setItem("aimtrainer-acc-name", name);
      setAccMsg("已登录：" + name, true);
    } else {
      setAccMsg(data.error || "登录失败");
    }
  }

  async function doRegister() {
    const name = ui.accName.value.trim();
    const password = ui.accPass.value;
    if (!name || !password) return setAccMsg("请输入用户名和密码");
    if (name.length > 12) return setAccMsg("用户名最多 12 字");
    const data = await apiPost("/api/register", { name, password });
    if (data.ok) {
      account = { name, password };
      localStorage.setItem("aimtrainer-acc-name", name);
      setAccMsg("注册成功，已自动登录：" + name, true);
    } else {
      setAccMsg(data.error || "注册失败");
    }
  }

  const savedAccName = localStorage.getItem("aimtrainer-acc-name");
  if (savedAccName) ui.accName.value = savedAccName;
  $("acc-login").addEventListener("click", doLogin);
  $("acc-register").addEventListener("click", doRegister);
  ui.accPass.addEventListener("keydown", (e) => {
    if (e.key === "Enter") doLogin();
  });

  // ---------- 排行榜 ----------
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  async function loadLeaderboard(m) {
    ui.lbList.innerHTML = '<div class="lb-row"><span>加载中…</span></div>';
    try {
      const res = await fetch("/api/leaderboard?mode=" + encodeURIComponent(m));
      const data = await res.json();
      if (!data.ok || !data.entries || !data.entries.length) {
        ui.lbList.innerHTML = '<div class="lb-row"><span>暂无成绩</span></div>';
        return;
      }
      ui.lbList.innerHTML = "";
      data.entries.forEach((e, i) => {
        const row = document.createElement("div");
        row.className = "lb-row";
        row.innerHTML = `<span class="lb-rank">${i + 1}</span><span>${escapeHtml(e.name)}</span><span>${e.score} 分</span>`;
        ui.lbList.appendChild(row);
      });
    } catch {
      ui.lbList.innerHTML = '<div class="lb-row"><span>无法连接服务器</span></div>';
    }
  }

  ui.lbBtn.addEventListener("click", () => {
    ui.leaderboard.classList.remove("hidden");
    const active = document.querySelector(".lb-mode.active");
    loadLeaderboard(active ? active.dataset.mode : "sixshot");
  });
  ui.lbClose.addEventListener("click", () => ui.leaderboard.classList.add("hidden"));
  document.querySelectorAll(".lb-mode").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".lb-mode").forEach((b) => b.classList.toggle("active", b === btn));
      loadLeaderboard(btn.dataset.mode);
    });
  });

  // ---------- 管理员模式 ----------
  function hashStr(s) {
    let h = 5381;
    for (let i = 0; i < s.length; i++) h = ((h << 5) + h) ^ s.charCodeAt(i);
    return (h >>> 0).toString(16);
  }

  function loadAdminSettings() {
    triggerbot = localStorage.getItem("aimtrainer-triggerbot") === "1";
    assist = localStorage.getItem("aimtrainer-assist") === "1";
    assistFov = (Number(localStorage.getItem("aimtrainer-assist-fov")) || 12) * Math.PI / 180;
    assistStrength = Number(localStorage.getItem("aimtrainer-assist-strength")) || 0.4;
    ui.setTriggerbot.checked = triggerbot;
    ui.setAssist.checked = assist;
    ui.setAssistFov.value = Math.round(assistFov * 180 / Math.PI);
    ui.setAssistStrength.value = assistStrength;
    ui.fovValue.textContent = Math.round(assistFov * 180 / Math.PI) + "°";
    ui.strengthValue.textContent = Math.round(assistStrength * 100) + "%";
    if (sessionStorage.getItem("aimtrainer-admin") === "1") {
      adminUnlocked = true;
      ui.adminLogin.classList.add("hidden");
      ui.adminPanel.classList.remove("hidden");
    }
  }

  function checkAdminPass() {
    if (hashStr(ui.adminPass.value) === ADMIN_PASS_HASH) {
      adminUnlocked = true;
      sessionStorage.setItem("aimtrainer-admin", "1");
      ui.adminMsg.textContent = "";
      ui.adminLogin.classList.add("hidden");
      ui.adminPanel.classList.remove("hidden");
      ui.adminPass.value = "";
    } else {
      ui.adminMsg.textContent = "密码错误";
    }
  }

  ui.adminBtn.addEventListener("click", () => {
    if (adminUnlocked) {
      ui.adminPanel.classList.remove("hidden");
    } else {
      ui.adminLogin.classList.toggle("hidden");
    }
  });
  ui.adminOk.addEventListener("click", checkAdminPass);
  ui.adminPass.addEventListener("keydown", (e) => {
    if (e.key === "Enter") checkAdminPass();
  });
  ui.adminExit.addEventListener("click", () => {
    adminUnlocked = false;
    sessionStorage.removeItem("aimtrainer-admin");
    ui.adminPanel.classList.add("hidden");
  });
  ui.setTriggerbot.addEventListener("change", (e) => {
    triggerbot = e.target.checked;
    localStorage.setItem("aimtrainer-triggerbot", triggerbot ? "1" : "0");
  });
  ui.setAssist.addEventListener("change", (e) => {
    assist = e.target.checked;
    localStorage.setItem("aimtrainer-assist", assist ? "1" : "0");
  });
  ui.setAssistFov.addEventListener("input", (e) => {
    assistFov = Number(e.target.value) * Math.PI / 180;
    ui.fovValue.textContent = e.target.value + "°";
    localStorage.setItem("aimtrainer-assist-fov", e.target.value);
  });
  ui.setAssistStrength.addEventListener("input", (e) => {
    assistStrength = Number(e.target.value);
    ui.strengthValue.textContent = Math.round(assistStrength * 100) + "%";
    localStorage.setItem("aimtrainer-assist-strength", e.target.value);
  });
  loadAdminSettings();

  function applySens(value) {
    const n = Number(value);
    if (!Number.isFinite(n) || n <= 0) return;
    const v = Math.max(0.05, Math.min(10, n));
    sens = v;
    $("set-sens").value = v;
    ui.sensInput.value = v.toFixed(2);
  }

  $("set-sens").addEventListener("input", (e) => applySens(e.target.value));
  ui.sensInput.addEventListener("input", (e) => applySens(e.target.value));
  ui.sensInput.addEventListener("blur", () => {
    ui.sensInput.value = sens.toFixed(2);
  });

  window.addEventListener("resize", () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });

  // ---------- 音效 ----------
  let audio = null;
  function ensureAudio() {
    if (!audio) {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (Ctx) audio = new Ctx();
    }
    if (audio && audio.state === "suspended") audio.resume();
  }

  function tone(freq, endFreq, dur, vol, delay = 0) {
    if (!audio) return;
    const t = audio.currentTime + delay;
    const o = audio.createOscillator();
    o.type = "sine";
    o.frequency.setValueAtTime(freq, t);
    if (endFreq) o.frequency.exponentialRampToValueAtTime(endFreq, t + dur);
    const g = audio.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(audio.destination);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  function playShot() {
    if (!audio) return;
    const t = audio.currentTime;
    const o = audio.createOscillator();
    o.type = "square";
    o.frequency.setValueAtTime(320, t);
    o.frequency.exponentialRampToValueAtTime(90, t + 0.06);
    const g = audio.createGain();
    g.gain.setValueAtTime(0.12, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.08);
    o.connect(g).connect(audio.destination);
    o.start(t);
    o.stop(t + 0.09);
  }

  function playHit() {
    tone(880, 1100, 0.07, 0.15);
  }

  function playKill() {
    tone(1040, null, 0.08, 0.18);
    tone(1560, null, 0.12, 0.18, 0.08);
  }

  function playMiss() {
    tone(160, 80, 0.1, 0.1);
  }

  function playStart() {
    tone(520, null, 0.1, 0.2);
    tone(780, null, 0.12, 0.2, 0.1);
  }

  function playEnd() {
    tone(660, null, 0.12, 0.2);
    tone(440, null, 0.2, 0.2, 0.12);
  }

  // ---------- 主循环 ----------
  function animate(now) {
    requestAnimationFrame(animate);
    const dt = Math.min(0.05, (now - lastNow) / 1000);
    lastNow = now;

    if (running && !paused) {
      timeLeft -= dt;
      if (mode === "tracking") updateTracking(dt);
      // 触发扳机：准星压到靶子上时自动开枪
      if (triggerbot && mode !== "tracking") {
        if (now - lastAutoFire > 200 && (controlMode !== "lock" || locked)) {
          const hit = castRay();
          if (hit && hitTargetOf(hit.object)) {
            lastAutoFire = now;
            fire();
          }
        }
      }
      for (const t of targets) {
        if (!t.alive && now >= t.respawnAt) spawnTarget(t);
      }
      // 靶子呼吸光效
      for (const t of targets) {
        if (t.alive) {
          t.sphere.material.emissiveIntensity = 0.45 + 0.25 * (0.5 + 0.5 * Math.sin(now / 260 + t.pulsePhase));
        }
      }
      updateParticles(dt);
      updateHud();
      updateAssist(dt);
      if (timeLeft <= 0) {
        timeLeft = 0;
        endRound();
      }
    } else {
      updateParticles(dt);
    }

    // 线性限速跟随：小幅移动即时到位（跟手），大幅甩动按单帧上限平滑追，防跳变
    if (running && !paused) {
      const preset = SMOOTH_PRESETS[smoothingMode] || SMOOTH_PRESETS.balanced;
      const maxTurn = Math.min(preset.step, preset.vel * dt);
      yaw += Math.max(-maxTurn, Math.min(maxTurn, targetYaw - yaw));
      pitch += Math.max(-maxTurn, Math.min(maxTurn, targetPitch - pitch));
    }
    camera.rotation.y = yaw;
    camera.rotation.x = pitch;
    renderer.render(scene, camera);
  }

  requestAnimationFrame(animate);
})();
