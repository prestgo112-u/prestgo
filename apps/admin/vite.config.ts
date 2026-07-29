import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // Le back-office tourne sur le port 5173, l'API sur le 3000.
    // Ce "proxy" transmet tous les appels commençant par /api vers l'API,
    // ce qui évite les problèmes de CORS et garde des URLs relatives simples.
    proxy: {
      "/api": {
        target: "http://localhost:3000",
        changeOrigin: true
      }
    }
  }
});
