# Plant Catalog Workbench Plan v2

## Summary

Build **Plant Catalog Workbench** as a **separate macOS Xcode project**. It is a local desktop workbench for opening an exported plant catalog SQLite database, creating or reopening a working database workspace, running **on-device Foundation Models** parsing workflows, reviewing results, and editing catalog data safely.

Key decisions now locked:
- product name: **Plant Catalog Workbench**
- platform: **macOS**
- project shape: **separate Xcode project**
- write model: **working-copy workspace**
- AI mode: **on-device only**
- audit persistence: **JSON sidecar files**
- source layout: **feature-first inside `src/`**
- implementation language for code, comments, UI copy keys, tests, prompt wrappers, and technical docs: **English**

Foundation Models tools are ordinary application source code. They belong inside the source tree, not as a separate repo-level tooling area.

## Repo and Project Structure

Top-level app folder:
- `Apps/PlantCatalogWorkbench/`

Top-level project layout:
- `Apps/PlantCatalogWorkbench/src/`
- `Apps/PlantCatalogWorkbench/tests/`
- `Apps/PlantCatalogWorkbench/data/`
- `Apps/PlantCatalogWorkbench/resources/`

Inside `src/`, use a feature-first structure:

- `src/App/`
  - app entry
  - app coordinator / navigation shell
  - dependency container
  - workspace session state
- `src/Features/WorkspaceSelection/`
  - create new working DB
  - open existing working DB
- `src/Features/PlantList/`
  - search, filters, list/table UI
- `src/Features/PlantDetail/`
  - plant detail inspector
  - editable fields
- `src/Features/NameParsing/`
  - parse actions
  - batch execution
  - review queue
- `src/Features/AuditViewer/`
  - session list
  - pretty JSON viewer
  - raw payload inspector
- `src/Shared/Database/`
  - GRDB setup
  - catalog queries
  - write/update services
- `src/Shared/ModelTools/`
  - Foundation Models session setup
  - tool-calling implementations such as fetch/save helpers
- `src/Shared/Prompts/`
  - prompt files
  - prompt loading/versioning
- `src/Shared/UI/`
  - reusable SwiftUI components
- `src/Shared/Models/`
  - domain models
  - structured output models
  - audit models

This keeps repo layout clean first, and architecture-specific organization inside `src/`.

## Coding Language, Style Guides, and Tools

All implementation work should be done in **English**:
- source code identifiers
- type and file names
- comments and doc comments
- test names
- prompt wrapper code
- commit-facing technical docs inside the project
- UI copy keys and internal labels

Recommended style guides:
- **Swift API Design Guidelines** for naming and API shape
  - https://www.swift.org/documentation/api-design-guidelines/
- **Apple Human Interface Guidelines** for macOS UI behavior and interaction patterns
  - https://developer.apple.com/design/human-interface-guidelines/
- **Apple Interface Fundamentals** and SwiftUI platform guidance for windowing, navigation, and accessibility
  - https://developer.apple.com/documentation/technologyoverviews/interface-fundamentals
  - https://developer.apple.com/documentation/technologyoverviews/swiftui

Recommended development tools and enforcement:
- **swift-format** as the canonical formatter
  - use the official `swiftlang/swift-format`
  - commit a project formatter config and run it in CI and locally
- **SwiftLint** for style/lint enforcement
  - enforce naming, file length, function length, discouraged patterns, and documentation expectations
- **XCTest** for unit/integration/UI tests
- **GRDB** for SQLite access consistency with the wider repo direction

Recommended defaults for style enforcement:
- format-on-save in Xcode if practical
- `swift-format` in a pre-commit or CI check
- `SwiftLint` in build phases or CI
- all new public APIs documented with concise English doc comments
- avoid ad-hoc style rules unless they are written down in-project

## Key App Behavior

### Workspace model
Support two entry paths:
- **Create new working DB**
  - select exported SQLite file
  - copy it into a new workspace folder
  - create workspace metadata and audit storage
- **Open existing working DB**
  - select an existing Plant Catalog Workbench workspace
  - restore catalog, audit sessions, and review state

Recommended workspace folder contents:
- `catalog.sqlite`
- `workspace-metadata.json`
- `audit/`
- `exports/` reserved for later

### Foundation Models workflow
Use the standard on-device model in v1.

The app should:
- fetch `plant_id` and `botanical_name` from the working DB
- run the botanical parser prompt
- decode structured JSON output
- write supported parsed fields back into SQLite
- store full session output in JSON audit files
- surface low-confidence rows for manual review

The app must not overwrite `botanical_name`.

### Parsed-field writeback
Write into the current nullable split-name columns:
- `genus`
- `hybrid_marker_genus`
- `species`
- `hybrid_marker_species`
- `subspecies`
- `variety`
- `forma`
- `cultivar`
- `group_name`
- `authority`

Keep the richer model output in audit JSON as well, including:
- `Grex`
- `TradeDesignation`
- `InformalQualifier`
- `Parent1`
- `Parent2`
- `Notes`
- `Confidence`

## Audit JSON and Viewer

Use **JSON sidecar files**, not audit tables inside the catalog DB.

Recommended format:
- one JSON file per parse session
- optional lightweight index JSON for fast listing

Each session JSON should contain:
- session id
- timestamp
- prompt version
- model identifier/version if available
- selected plant ids
- structured outputs per plant
- raw response if available
- review status
- errors/warnings

Include a built-in JSON viewer in v1:
- list sessions
- open formatted JSON
- inspect one plant result
- copy raw JSON
- filter by date / confidence / plant id

## Tests and Acceptance

### Tests
- unit tests for:
  - workspace creation
  - workspace reopening
  - GRDB read/write
  - structured output decoding
  - audit JSON encoding/decoding
- integration tests for:
  - import export-DB into working workspace
  - reopen existing workspace
  - run small parse session
  - persist parsed values into SQLite
  - persist audit JSON
- UI tests for:
  - workspace selection flow
  - plant list search
  - parse selected plant(s)
  - open audit JSON viewer

### Acceptance scenarios
- user can create a new working workspace from an export DB
- user can reopen an existing working workspace
- user can inspect plant rows and edit data
- user can run on-device parsing for one or more plants
- parsed values are written into SQLite
- audit JSON is created and viewable in-app
- low-confidence rows are easy to review

## Assumptions and Defaults

- macOS first, not iOS first
- separate Xcode project, not merged into `PlantGuide2`
- Foundation Models tool-calling code lives inside `src/Shared/ModelTools/`
- prompt resources live inside `src/Shared/Prompts/` or `resources/` depending on packaging needs, but are loaded by source code from the app
- internet verification is out of scope for v1
- if shared code with `PlantGuide2` becomes useful later, extract a local Swift package rather than collapsing the projects together
