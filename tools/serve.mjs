// Tiny static server for dist/ (avoids depending on a background `vite preview`).
import http from "node:http"; import fs from "node:fs"; import path from "node:path";
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".glb": "model/gltf-binary", ".json": "application/json", ".woff2": "font/woff2", ".txt": "text/plain", ".png": "image/png" };
export function serve(dir, port = 4173) {
  const srv = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, "http://x").pathname); if (p.endsWith("/")) p += "index.html";
    const f = path.join(dir, p); if (!f.startsWith(path.resolve(dir))) { res.writeHead(403).end(); return; }
    fs.readFile(f, (e, d) => { if (e) { res.writeHead(404).end("nf"); return; } res.writeHead(200, { "content-type": MIME[path.extname(f)] || "application/octet-stream" }); res.end(d); });
  });
  return new Promise((r) => srv.listen(port, "127.0.0.1", () => r(srv)));
}
export const CHROME_ARGS = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--enable-webgl", "--no-sandbox"];
