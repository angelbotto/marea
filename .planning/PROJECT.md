# Marea

## Core value

Marea mantiene el Mac liviano y fresco **prendiendo y apagando los stacks de Docker
según lo que realmente estoy trabajando en Orca**. Deja de haber contenedores
comiéndose la RAM por proyectos que ya no toco, sin que yo tenga que acordarme de
apagarlos a mano.

## Quién lo usa

Yo (Angel), en un Mac con muchos proyectos abiertos a la vez. El flujo:
**Orca** (workspace de agentes, fuente de verdad de "qué trabajo") + **Claude Code**
(construcción) + **GSD** (planificación por fases en `.planning/`) + **Docker** (stacks
por proyecto).

## Cómo funciona hoy (v0.1)

- App nativa de barra de menú (SwiftUI `MenuBarExtra`, Swift Package + build a `.app`).
- Motor que fusiona señales: agente ejecutando (`~/Library/Application Support/Orca/agent-hooks/last-status.json`),
  actividad reciente (`orca terminal list`), presión de swap. Con gracia anti-flapping
  y consciente de recursos.
- Métricas en vivo (Swift Charts), detalle por contenedor, badge de fase GSD por proyecto.
- Panel flotante de escritorio (NSPanel) y widget de WidgetKit (compila y firma; falta
  el App Group para datos vivos).
- Escribe `snapshot.json` (en `~/.config/marea` y en el App Group) para el widget.

## Arquitectura

Swift Package ejecutable + proyecto Xcode (xcodegen desde `project.yml`) para el widget.
`Models` / `Probes` (Orca, Docker, sistema, GSD) / `Engine` (decisión) / `AppState`
(polling, historial, snapshot) / vistas (`MenuView`, `MetricsView`, `DesktopWidget`,
`PreferencesView`) / `Widget/` (extensión WidgetKit).

## Constraints / decisiones

- Siempre `docker compose stop` (nunca `down`): conserva datos, arranque instantáneo.
- El widget está sandboxeado → solo lee datos vía **App Group** (`group.is.botto.marea`),
  no puede ejecutar `docker`/`orca`.
- Firma con identidad Apple Development (Team `22R43BN2XG`).
- Sin dependencias externas de terceros; solo frameworks de Apple.

## Repo

Público: https://github.com/angelbotto/marea
