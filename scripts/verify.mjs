import fs from "fs";
import * as THREE from "three";

const names = [
  "WebGLRenderer", "Scene", "PerspectiveCamera", "Raycaster",
  "MeshStandardMaterial", "SpriteMaterial", "CanvasTexture",
  "BoxGeometry", "SphereGeometry", "PlaneGeometry",
  "HemisphereLight", "DirectionalLight", "Fog", "AdditiveBlending"
];
const missing = names.filter((n) => typeof THREE[n] === "undefined");
console.log("Three.js API missing:", missing.length ? missing.join(", ") : "none");

const app = fs.readFileSync("public/app.js", "utf8");
const html = fs.readFileSync("public/index.html", "utf8");
const ids = [...app.matchAll(/\$\("([^"]+)"\)/g)].map((m) => m[1]);
const missingIds = [...new Set(ids)].filter((id) => !html.includes(`id="${id}"`));
console.log("Referenced DOM ids:", new Set(ids).size, "| missing:", missingIds.length ? missingIds.join(", ") : "none");

process.exit(missing.length || missingIds.length ? 1 : 0);
