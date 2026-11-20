# KeyboardShortcuts 3.1.0 (vendored)

Upstream: https://github.com/sindresorhus/KeyboardShortcuts at tag 3.1.0 (772133d), MIT license (`license`).
Only `Package.swift`, `Sources` and `license` are kept. `ghostwriter.patch` holds every change from upstream:

- `@Entry` and `#Preview` are written out or removed. The Command Line Tools have no SwiftUI macro plugins, so
  `scripts/spm-bundle.sh` cannot build them.
- Strings load from `Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle`. SwiftPM's `Bundle.module`
  only looks at the .app root and the absolute `.build` path, and traps when neither exists.
- The test target is dropped from `Package.swift`.

The Xcode project keeps using the upstream package; this copy only serves the SwiftPM build.
