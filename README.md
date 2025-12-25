# RecastNavigationKit

Swift-friendly wrapper around Recast/Detour for iOS, shipped as xcframeworks and a small ObjC/Swift API layer.

## Features
- Build navmeshes from triangle meshes
- Query paths via Detour
- Swift convenience wrappers

## Requirements
- iOS 13+
- Xcode 15+

## Installation (Swift Package Manager)
In Xcode: **File > Add Packages...** and use:

```
https://github.com/tatsuya-ogawa/RecastNavigationKit
```

Then add the product **RecastNavigationKit** to your target.

## Usage
Import the module:

```swift
import RecastNavigationKit
```

See `example/RecastNavigationExample` for a complete sample.

## Building xcframeworks (maintainers)
Regenerate binaries and sync into the package:

```bash
./framework-build/make-xcframeworks.sh
```

GitHub Actions also builds release assets (zip + checksums) from tags.

## License
MIT. See `LICENSE`.
