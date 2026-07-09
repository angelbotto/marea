# Roadmap: Marea

## Milestones

- ✅ **v0.1 Base** — App de barra, motor Orca↔Docker, métricas, panel flotante, widget que compila (shipped 2026-07-08)
- 🚧 **v0.2 Escritorio vivo + Orca a fondo** — Phases 1-4 (in progress, started 2026-07-08)

## Phases

<details>
<summary>✅ v0.1 Base — SHIPPED 2026-07-08</summary>

- [x] Motor de decisión Orca↔Docker (agente + actividad + swap, gracia anti-flapping)
- [x] Menú con stacks, detalle por contenedor, métricas (Swift Charts)
- [x] Integración GSD (badge de fase por proyecto)
- [x] Panel flotante de escritorio (NSPanel)
- [x] Widget de WidgetKit (compila y firma; falta App Group)
- [x] Preferencias, arranque al login, snapshot.json, repo público

</details>

### 🚧 v0.2 Escritorio vivo + Orca a fondo (In Progress)

**Milestone Goal:** Que el widget se pueda **agregar al escritorio con datos reales**,
que Marea **comunique de verdad qué está corriendo en Orca** (worktrees, branch, estado,
PR, git), agregar **notificaciones** al prender/apagar, y darle **icono propio**.

- [ ] **Phase 1: Widget de escritorio con datos vivos** — App Group + datos reales + instalable
- [ ] **Phase 2: Orca a fondo** — worktrees, branch, workspaceStatus, comment, PR/issue, git state, hijos
- [ ] **Phase 3: Notificaciones** — avisar en cada acción del motor
- [ ] **Phase 4: Icono propio** — AppIcon + icono de barra con identidad Marea

---

### Phase 1 — Widget de escritorio con datos vivos

**Goal:** El widget de WidgetKit muestra datos reales y se puede agregar al escritorio
(no solo a Notification Center).

**Por qué:** Hoy el widget compila, firma y aparece en la galería, pero está sandboxeado
y no puede leer el `snapshot.json` porque falta la capability **App Group**.

**Success criteria:**
- Capability `App Groups` (`group.is.botto.marea`) aplicada en los targets `Marea` y `MareaWidget`.
- La app escribe el snapshot al contenedor del App Group y el widget lo lee.
- El widget (medium y large) muestra RAM/CPU totales, stacks activos y fase GSD, con datos vivos.
- Documentado en README cómo agregarlo al **escritorio** (Sonoma+: clic derecho → Editar widgets).
- Timeline refresca a intervalo razonable.

**Tareas outline:** resolver el stripping de entitlements por file-guardian (aplicar la
capability manual/Xcode) · verificar flujo App-Group end-to-end · afinar vistas del widget ·
build+firma reproducible (`xcodegen` + `xcodebuild`) · docs.

---

### Phase 2 — Orca a fondo (que el widget comunique qué corre)

**Goal:** Marea aprovecha toda la data de Orca para comunicar claramente el estado de
cada proyecto/worktree, en el menú y sobre todo en el widget.

**Datos de Orca a explotar** (`orca worktree list --json`):
- `branch`, `displayName`, `workspaceStatus` (in-progress / needs-review / ...)
- `comment` (resumen GSD sincronizado por el hook orca-sync)
- `linkedPR` / `linkedIssue` / `linkedLinearIssue`
- `git` (ahead / behind / dirty), `lastActivityAt`, `isUnread`, `isPinned`
- `childWorktreeIds` / `lineage` (sub-worktrees = agentes trabajando en paralelo)

**Success criteria:**
- Nuevo `OrcaWorktreeProbe` que lee `orca worktree list --json` y lo mapea por `orcaPath`.
- El menú muestra por stack: branch + workspaceStatus + PR/issue si hay + git ahead/behind/dirty.
- El widget lista los **worktrees activos** con su rama, estado y si hay agente corriendo —
  no solo memoria/CPU. Comunica "qué estoy trabajando ahora".
- Indicador de worktrees hijos (agentes paralelos) cuando existan.

---

### Phase 3 — Notificaciones

**Goal:** Cuando el modo Auto prende o apaga un stack, avisar con una notificación nativa.

**Success criteria:**
- Permiso de `UserNotifications` solicitado la primera vez.
- Notificación en cada acción: "Apagué `plane` (idle 40 min) → liberé 1.2 GB" / "Prendí `vaekor` (agente ejecutando)".
- Toggle en Preferencias para activarlas/silenciarlas.
- Agrupadas/rate-limited para no spamear.

---

### Phase 4 — Icono propio

**Goal:** Darle identidad visual: AppIcon (Dock/Finder/galería del widget) + icono de barra
propio (hoy usa el SF Symbol `water.waves`, que me gusta como base).

**Success criteria:**
- `AppIcon.icns` con todos los tamaños, incluido en el bundle y referenciado en Info.plist.
- Icono de barra template (monocromo, se adapta a claro/oscuro) con la "onda" de Marea.
- Proceso reproducible (SVG → `iconutil`, o prompt de IA de imagen documentado).
- README con el arte final.

**Nota sobre generación del icono:** se decide en el discuss/plan de la fase —
diseño SVG procedural (determinista, on-brand con la onda) vs. modelo de imagen
(Ideogram / DALL·E / Midjourney) para algo más ilustrado.
