import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  // Rutas relativas: funciona en https://usuario.github.io/cualquier-repo/
  base: "./",
  plugins: [react()],
  server: { port: 5173 },
  build: {
    rollupOptions: {
      output: {
        // Separar las librerías grandes en archivos aparte (chunks).
        // Así el navegador las cachea por separado y la primera carga
        // se reparte en varios archivos más pequeños que bajan en paralelo.
        manualChunks: {
          maplibre: ["maplibre-gl"],
          react: ["react", "react-dom"],
          supabase: ["@supabase/supabase-js"],
        },
      },
    },
    // MapLibre es grande por naturaleza; subimos el umbral del aviso
    // para que no marque como "problema" algo que ya está separado.
    chunkSizeWarningLimit: 900,
  },
});
