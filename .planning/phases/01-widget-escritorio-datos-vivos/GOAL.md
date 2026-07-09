# Phase 1 — Widget de escritorio con datos vivos

**Goal:** El widget de WidgetKit muestra datos reales y se puede agregar al escritorio.

**Bloqueador actual:** falta la capability **App Group** (`group.is.botto.marea`) en ambos
targets; el hook file-guardian vacía los `.entitlements` que se escriben desde el agente,
así que hay que aplicarla en Xcode (Signing & Capabilities → +App Groups) o aprobar el hook.

**Success:** App Group aplicado · app escribe al contenedor · widget lee y muestra
RAM/CPU/stacks/GSD con datos vivos · instalable en el escritorio (Sonoma+) · documentado.

Detalle completo en `../../ROADMAP.md` (Phase 1). Correr `/gsd-plan-phase 1`.
