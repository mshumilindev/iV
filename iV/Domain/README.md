# Domain

Pure **models and enums** for iV's editorial workstation.

## Rules

- No SwiftUI imports.
- No URLSession or network calls.
- No FileManager or other I/O side effects.
- Codable/value types, identifiers, and invariants only.
- When a data contract changes, update domain types here once — features and services import them.

## Note

`DomainModels.swift` and `DomainEnums.swift` are consolidated files pending optional future split by bounded context.
