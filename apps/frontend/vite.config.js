import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // Local dev: forward /api to a locally running backend (docker run -p 8080:8080 ...).
    proxy: { "/api": "http://localhost:8080" },
  },
});
