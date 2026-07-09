# 🌊 Marea

**Prende y apaga tus stacks de Docker automáticamente, según lo que estás trabajando en [Orca](https://onorca.dev).**

Marea es una app nativa de barra de menú para macOS. Observa qué proyectos tienes activos en Orca (agentes corriendo, actividad reciente) y prende/apaga sus stacks de Docker en consecuencia — para que dejes de tener contenedores comiéndote RAM y calentando el Mac por proyectos que ya no estás tocando.

![menu bar app](https://img.shields.io/badge/macOS-13%2B-blue) ![SwiftUI](https://img.shields.io/badge/SwiftUI-MenuBarExtra-orange)

## ✨ Qué hace

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

## 👤 Créditos

Hecho por **Angel Botto** · 2026. Construido con Claude Code.

## 📄 Licencia

MIT.
