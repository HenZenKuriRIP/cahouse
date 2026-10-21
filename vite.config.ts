import { defineConfig } from "vite";
// base "./" so the same build works from any sub-path and inside the Capacitor Android WebView.
export default defineConfig({
  base: "./",
  build: { target: "es2022", chunkSizeWarningLimit: 1200, assetsInlineLimit: 0 },
  server: { host: true },
});
