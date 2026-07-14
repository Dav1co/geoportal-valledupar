import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  // Rutas relativas: funciona en https://usuario.github.io/cualquier-repo/
  base: "./",
  plugins: [react()],
  server: { port: 5173 },
});
