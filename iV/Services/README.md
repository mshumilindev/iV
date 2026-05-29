# Services

Services isolate **side effects and orchestration** from SwiftUI.

## Rules

- Storage, indexing, diagnostics, rules, pipeline, AI, import/export, and snapshots live here.
- Views and feature UI **must not** perform FileManager, SQLite, or URLSession work directly.
- Services are called by `AppState`, view models, or coordinators in `App/` and `Features/`.
- Keep services focused: one responsibility per type or small module group.
- Shared domain types consumed/produced by services belong in `Domain/`, not duplicated here.
