import http from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, "public");
const THREE_BUILD_DIR = path.join(__dirname, "node_modules", "three", "build");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".map": "application/json"
};

const server = http.createServer((req, res) => {
  try {
    const urlPath = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    let root = PUBLIC_DIR;
    let filePath;
    if (urlPath === "/vendor/three.module.js") {
      root = THREE_BUILD_DIR;
      filePath = path.join(root, "three.module.js");
    } else if (urlPath === "/") {
      filePath = path.join(root, "index.html");
    } else {
      filePath = path.join(root, urlPath);
    }

    const rel = path.relative(root, filePath);
    if (rel.startsWith("..") || path.isAbsolute(rel)) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }

    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.writeHead(404);
        res.end("Not Found");
        return;
      }
      res.writeHead(200, {
        "Content-Type": MIME[path.extname(filePath).toLowerCase()] || "application/octet-stream",
        "Cache-Control": "no-cache, no-store, must-revalidate"
      });
      res.end(data);
    });
  } catch {
    res.writeHead(400);
    res.end("Bad Request");
  }
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Aim Trainer 已启动：http://localhost:${PORT}`);
});
