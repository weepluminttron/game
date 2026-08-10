import http from "http";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// 纯 API 服务器：账号注册/登录、成绩上传、排行榜（Godot 客户端专用）

const DATA_DIR = path.join(__dirname, "data");
const USERS_FILE = path.join(DATA_DIR, "users.json");
const SCORES_FILE = path.join(DATA_DIR, "scores.json");

function ensureData() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(USERS_FILE)) fs.writeFileSync(USERS_FILE, "{}");
  if (!fs.existsSync(SCORES_FILE)) fs.writeFileSync(SCORES_FILE, "{}");
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
}

function writeJson(file, obj) {
  fs.writeFileSync(file, JSON.stringify(obj, null, 2));
}

const sha256 = (s) => crypto.createHash("sha256").update(String(s)).digest("hex");

function sendJson(res, code, obj) {
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 64 * 1024) req.destroy();
    });
    req.on("end", () => resolve(data));
  });
}

function apiLeaderboard(mode) {
  const scores = readJson(SCORES_FILE, {});
  const entries = [];
  for (const [name, s] of Object.entries(scores)) {
    const best = (s.best && s.best[mode]) || 0;
    if (best > 0) entries.push({ name, score: best });
  }
  entries.sort((a, b) => b.score - a.score);
  return entries.slice(0, 10);
}

async function handleApi(req, res, urlPath) {
  ensureData();
  const bodyText = await readBody(req);
  let body = {};
  try {
    body = JSON.parse(bodyText || "{}");
  } catch {
    sendJson(res, 400, { ok: false, error: "无效请求" });
    return;
  }
  const users = readJson(USERS_FILE, {});
  const scores = readJson(SCORES_FILE, {});
  const name = String(body.name || "").trim().slice(0, 12);
  const password = String(body.password || "");
  if (!name || !password) {
    sendJson(res, 400, { ok: false, error: "请输入用户名和密码" });
    return;
  }
  if (urlPath === "/api/register") {
    if (users[name]) {
      sendJson(res, 409, { ok: false, error: "用户名已存在" });
      return;
    }
    users[name] = { pass: sha256(password), created: Date.now() };
    scores[name] = { best: {}, history: [] };
    writeJson(USERS_FILE, users);
    writeJson(SCORES_FILE, scores);
    sendJson(res, 200, { ok: true, name });
  } else if (urlPath === "/api/login") {
    const u = users[name];
    if (!u || u.pass !== sha256(password)) {
      sendJson(res, 401, { ok: false, error: "用户名或密码错误" });
      return;
    }
    sendJson(res, 200, { ok: true, name, best: (scores[name] && scores[name].best) || {}, history: (scores[name] && scores[name].history) || [] });
  } else if (urlPath === "/api/score") {
    const u = users[name];
    if (!u || u.pass !== sha256(password)) {
      sendJson(res, 401, { ok: false, error: "登录已失效，请重新登录" });
      return;
    }
    const mode = String(body.mode || "sixshot");
    const score = Math.max(0, Math.floor(Number(body.score) || 0));
    const s = scores[name] || { best: {}, history: [] };
    if (!s.best[mode] || score > s.best[mode]) s.best[mode] = score;
    if (!Array.isArray(s.history)) s.history = [];
    s.history.push({
      mode,
      score,
      kills: Number(body.kills) || 0,
      acc: Number(body.acc) || 0,
      avg: Number(body.avg) || 0,
      date: new Date().toISOString()
    });
    if (s.history.length > 20) s.history = s.history.slice(-20);
    scores[name] = s;
    writeJson(SCORES_FILE, scores);
    sendJson(res, 200, { ok: true, best: s.best[mode] });
  } else {
    sendJson(res, 404, { ok: false, error: "未知接口" });
  }
}

const server = http.createServer((req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    const urlPath = decodeURIComponent(url.pathname);
    if (urlPath === "/api/version" && req.method === "GET") {
      sendJson(res, 200, { ok: true, version: "1.0.4", download: "/download/aim-trainer.zip" });
      return;
    }
    if (urlPath === "/api/leaderboard" && req.method === "GET") {
      ensureData();
      sendJson(res, 200, { ok: true, entries: apiLeaderboard(url.searchParams.get("mode") || "sixshot") });
      return;
    }
    if (urlPath === "/download/aim-trainer.zip" && req.method === "GET") {
      const zipPath = path.join(__dirname, "downloads", "aim-trainer.zip");
      fs.stat(zipPath, (err, stat) => {
        if (err) {
          sendJson(res, 404, { ok: false, error: "文件不存在" });
          return;
        }
        res.writeHead(200, {
          "Content-Type": "application/zip",
          "Content-Length": stat.size,
          "Content-Disposition": 'attachment; filename="AimTrainer-Windows.zip"'
        });
        fs.createReadStream(zipPath).pipe(res);
      });
      return;
    }
    if (urlPath.startsWith("/api/") && req.method === "POST") {
      handleApi(req, res, urlPath);
      return;
    }
    sendJson(res, 200, { ok: true, name: "Aim Trainer API", note: "Godot 客户端专用账号与排行榜服务" });
  } catch {
    res.writeHead(400);
    res.end("Bad Request");
  }
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Aim Trainer 已启动：http://localhost:${PORT}`);
});
