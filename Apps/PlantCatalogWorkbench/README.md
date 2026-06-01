# Plant Catalog Workbench

This folder contains the standalone macOS app scaffold for Plant Catalog Workbench.

## Current scope

- SwiftUI macOS app shell
- feature-first source layout under `src/`
- XcodeGen-based project definition in `project.yml`
- starter test target for future unit coverage

## Generate the Xcode project

```sh
xcodegen generate
```

## Linting

- The app target includes a pre-build `SwiftLint` phase generated from `project.yml`
- After changing `project.yml`, regenerate the Xcode project:

```sh
xcodegen generate
```
