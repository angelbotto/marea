# Phase 4 — Icono propio

**Goal:** Identidad visual: AppIcon (Dock/Finder/galería del widget) + icono de barra propio.
Base: el SF Symbol `water.waves` (la "onda" de Marea) que ya gusta en la status bar.

**Success:** `AppIcon.icns` con todos los tamaños en el bundle + Info.plist · icono de barra
template (monocromo, claro/oscuro) · proceso reproducible · README con el arte.

**Cómo generar el icono (a decidir en el plan):**
- **SVG procedural** (determinista, on-brand con la onda) → `iconutil`. Sin IA, reproducible.
- **Modelo de imagen** para algo ilustrado: **Ideogram** (buen texto/formas), **DALL·E 3**
  (vía ChatGPT), o **Midjourney**. Prompt sugerido: "minimal macOS app icon, stylized teal
  ocean wave / orca fin, rounded-square, soft gradient, flat, Apple HIG style".
  (Claude no genera imágenes; para eso se usa uno de esos.)

Detalle completo en `../../ROADMAP.md` (Phase 4). Correr `/gsd-plan-phase 4`.
