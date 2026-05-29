# Features

Feature folders own **UI and application workflow** for one user-facing area of iV.

## Rules

- Put SwiftUI screens, feature-specific presentation components, and feature coordinators here.
- **Domain models stay in `Domain/`** — do not duplicate shared types inside feature folders.
- **Side effects stay in `Services/`** — views must not read/write storage or call network APIs directly.
- For a feature ticket, work **primarily inside that feature folder**.
- Touch `Domain/` only when the data contract changes.
- Touch `Services/` only when behavior or side effects change.
- Do not scatter changes across unrelated features.

## Layout

Each feature subfolder (e.g. `ProjectFlow/ProjectLibrary`) should remain a small, reviewable touch area for atomic tasks.
