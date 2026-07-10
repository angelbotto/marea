# 🌊 Marea

**Prende y apaga tus stacks de Docker automáticamente, según lo que estás trabajando en [Orca](https://onorca.dev).**

Marea es una app nativa de barra de menú para macOS. Observa qué proyectos tienes activos en Orca (agentes corriendo, actividad reciente) y prende/apaga sus stacks de Docker en consecuencia — para que dejes de tener contenedores comiéndote RAM y calentando el Mac por proyectos que ya no estás tocando.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![SwiftUI](https://img.shields.io/badge/SwiftUI-MenuBarExtra-orange) ![WidgetKit](https://img.shields.io/badge/WidgetKit-widget-purple) ![license](https://img.shields.io/badge/license-MIT-green)

> **Proyecto personal.** Nació de un dolor real: dejo muchos proyectos abiertos a la vez y sus contenedores de Docker me comían la RAM y calentaban el Mac. Marea lo resuelve conectándose a mi flujo de trabajo.

## 🧰 Mi flujo (de dónde sale Marea)

Marea está pensada alrededor de las herramientas con las que trabajo a diario:

- **[Orca](https://onorca.dev)** — mi terminal/workspace de agentes. Es la fuente de verdad de "qué estoy trabajando": Marea lee sus worktrees y el estado de los agentes.
- **[Claude Code](https://claude.com/claude-code)** — con quien construí Marea (de cero, en varias sesiones). Los hooks de agentes de Orca reportan a `last-status.json`, que Marea usa para saber si un agente está ejecutando.
- **GSD — Get Shit Done** — mi sistema de planificación por fases (basado en un directorio `.planning/`). Marea lee el `.planning/STATE.md` de cada proyecto y muestra el milestone y la fase actual junto a sus contenedores.

## ✨ Qué hace

- **Tri-fuente: ~/Dev + Orca + Docker.** Reconcilia tus proyectos desde las 3 fuentes por carpeta, así ves *todos* los que trabajas — no solo los que tienen Docker.
- **Detecta servidores host (con o sin Docker).** Vía `lsof` sabe qué corre y en qué puerto aunque sea un `pnpm dev`/`cargo run`/`caddy` fuera de Docker (ej. `oniria :3001`).
- **Sincroniza Orca ↔ Docker.** Si hay un agente ejecutando o actividad reciente en un proyecto, mantiene su stack prendido; si lo dejaste abierto pero ocioso, lo apaga.
- **Consciente de recursos.** Si el swap está apretado, apaga los stacks ociosos más rápido.
- **Anti-flapping.** Periodo de gracia configurable para no prender/apagar en bucle.
- **Métricas en vivo.** CPU y RAM por stack y por contenedor, con sparklines en el menú.
- **Detalle por contenedor.** Imagen, puertos, uptime, CPU/RAM — expandible por stack.
- **Pin manual.** Fija un stack siempre prendido (ej. una DB compartida).
- **Modo observación.** Con `Auto` apagado solo muestra qué haría, sin tocar nada.

## 🧠 Cómo decide

Por cada stack, en orden:

1. 📌 **Pin** → siempre prendido.
2. ⚡ **Agente ejecutando o esperando input** → prendido.
3. 🕐 **Actividad reciente** (< 30 min; < 8 min si el swap aprieta) → prendido.
4. 💤 **Ocioso / no abierto en Orca** → apagar, tras un periodo de gracia.

Siempre usa `docker compose stop` (nunca `down`): conserva tus datos, arranque instantáneo.

## 📦 Instalación

Requiere macOS 13+, [Docker](https://docker.com) y (opcional) [Orca](https://onorca.dev).

```bash
git clone <este-repo> marea && cd marea
./build-app.sh --install      # compila, arma Marea.app y la instala en /Applications
open /Applications/Marea.app
```

Para desarrollo:

```bash
swift build && swift run
```

## ⚙️ Configuración

Al primer arranque genera `~/.config/marea/config.json` con tus stacks detectados. Edítalo ahí o desde **Preferencias** (⚙️ en el menú):

- **Comportamiento** — modo auto, ventanas de inactividad, gracia, umbral de swap, frecuencia.
- **Stacks** — nombre, ruta de Orca (`orcaPath`) y si es gestionado, por proyecto.
- **Acerca de** — arranque al iniciar sesión.

Cada stack mapea a:
- **compose** — un directorio con `docker-compose.yml` (se opera con `docker compose up -d` / `stop`).
- **standalone** — contenedores sueltos por nombre (`docker start` / `stop`).

Y a un `orcaPath`: la ruta del worktree en Orca que significa "estoy trabajando en esto".

## 🏗️ Arquitectura

Swift Package ejecutable, SwiftUI `MenuBarExtra`. Sin dependencias externas.

| Archivo | Rol |
|---|---|
| `Models.swift` | Tipos: config, estados, métricas, snapshot |
| `Probes.swift` | Lectura de Orca (`last-status.json`, `orca terminal list`), Docker (`docker compose ls`, `ps`, `stats`) y sistema (swap) |
| `Engine.swift` | Motor de decisión: fusiona señales y decide prender/apagar |
| `AppState.swift` | Estado observable, ciclo de polling, historial, snapshot |
| `MenuView.swift` | Menú de barra con lista de stacks y detalle |
| `MetricsView.swift` | Sparklines de CPU/RAM (Swift Charts) |
| `PreferencesView.swift` | Ventana de preferencias |
| `About.swift` | Créditos + login item (ServiceManagement) |

También escribe `~/.config/marea/snapshot.json` cada ciclo (para widgets / integraciones).

## 🗺️ Roadmap

Ideas para seguir mejorando Marea:

- [ ] **Widget con datos en vivo** — activar la capability *App Group* para que el widget de WidgetKit lea el snapshot (hoy compila y aparece, falta el permiso).
- [ ] **Notificaciones** — avisar cuando prende/apaga un stack ("apagué `plane`, liberé 1.2 GB").
- [ ] **Icono propio** en la barra (hoy usa un SF Symbol).
- [ ] **Persistir el estado de gracia** entre reinicios.
- [ ] **Acciones GSD** — abrir la fase actual o disparar `/gsd-*` desde el menú.
- [ ] **Notarización** para poder compartir el `.app` fuera de mi Mac.
- [ ] **Historial más largo** y gráficas por stack.

## 👤 Créditos

Hecho por **[Angel Botto](https://github.com/angelbotto)** · 2026.
Construido en pareja con **Claude Code** 🤖, sobre **Orca** y **GSD**.

## 📄 Licencia

MIT.
