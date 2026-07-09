# Phase 2 — Orca a fondo

**Goal:** Que Marea comunique de verdad qué está corriendo en Orca, no solo CPU/RAM.

**Datos a explotar** (`orca worktree list --json`): branch · workspaceStatus · comment
(resumen GSD sincronizado) · linkedPR/linkedIssue/linkedLinearIssue · git ahead/behind/dirty ·
lastActivityAt · isUnread · childWorktreeIds (agentes paralelos).

**Success:** nuevo `OrcaWorktreeProbe` · el menú muestra branch + estado + PR + git state por
stack · el widget lista worktrees activos con rama/estado/agente · indicador de worktrees hijos.

Detalle completo en `../../ROADMAP.md` (Phase 2). Correr `/gsd-plan-phase 2`.
