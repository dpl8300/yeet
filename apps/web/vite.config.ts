import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("@supabase")) return "supabase";
          if (id.includes("@tanstack")) return "query";
          if (id.includes("@radix-ui") || id.includes("lucide-react")) return "ui";
          if (id.includes("react") || id.includes("scheduler")) return "react";
        }
      }
    }
  },
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["icons/yeet-192.png", "icons/yeet-512.png"],
      manifest: {
        name: "YEET — Airtime Challenge",
        short_name: "YEET",
        description: "Throw your phone. Catch your phone. Own the leaderboard.",
        theme_color: "#fffef9",
        background_color: "#fffef9",
        display: "standalone",
        orientation: "portrait",
        start_url: "/",
        icons: [
          { src: "/icons/yeet-192.png", sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: "/icons/yeet-512.png", sizes: "512x512", type: "image/png", purpose: "any maskable" }
        ]
      },
      workbox: {
        navigateFallback: "/index.html",
        globPatterns: ["**/*.{js,css,html,ico,png,svg,woff2}"],
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/.*\.supabase\.co\/rest\/v1\//,
            handler: "NetworkFirst",
            options: { cacheName: "yeet-leaderboard", networkTimeoutSeconds: 4 }
          }
        ]
      }
    })
  ]
});
