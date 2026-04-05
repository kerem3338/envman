# envman

**Environment Manager for Your Needs.**

`envman` is a lightweight, purely D-based developer environment toolkit and global package manager. It acts as both a system-wide "path aliases" tool and a local project package manager bridging the gap between local boilerplates, remote dependency scaffolding, and project setups.

*Created By Kerem ATA (zoda).*

---

## 🚀 Features

### 1. Global Path Aliasing (`envman path`)
Manage quick-references to important directories on your machine globally.
- Store deep filesystem paths under short "slugs"
- Quickly open them in your file explorer
- Search through your stored paths using queries

### 2. Global & Local Package Manager (`envman pkg`)
Store raw files, directories, or URLs in a central registry, and pull them dynamically into individual project folders using a `packages.envman` TOML configuration.
- **Intelligent Updating**: Recursively hashes checks or parses modification timestamps to selectively upgrade parts of your boilerplates, keeping dependencies up to date.
- **URL Handling**: Scaffolds files directly from web URLs effortlessly.
- **Check Command**: Quickly scan a project directory to see if packages are mismatched, out of date, or completely missing.

---

## 📦 Usage

### Path Management
```bash
# Add a path to the registry
envman path add my-framework C:\Path\To\MyFramework

# Get the path mapping
envman path get my-framework

# Open a path directly in your system's default explorer
envman path get my-framework --open

# List all stored paths
envman path list

# Search for a specific path 
envman path search "framework"

# Delete a path
envman path delete my-framework
```

### Package Management

**Global Registry Commands:**
```bash
# Register a local directory or file as a global package
envman pkg register argd source/argd.d
envman pkg register my-utils C:\Path\To\Utils
envman pkg register remote-lib https://example.com/lib.d

# Interrogate the registry
envman pkg list
envman pkg info argd
envman pkg remove argd
```

**Project Commands (Using `packages.envman`):**
In any project folder, drop a TOML file mapping registered packages to local directories:
```toml
# packages.envman
[packages]
argd = "source/argd.d"

"my-utils" = { path = "source/utils", type = "dir" }
```

```bash
# Verify the current directory against the packages.envman spec
envman pkg check .

# Securely install all missing packages
envman pkg install .

# Smart-upgrade all packages by detecting edit-time modifications
envman pkg upgrade .
```

### General
```bash
envman info
```

---

## 🛠 Building envman
- Envman is using **The D Programming Language**

**Build:**
```bash
dub build
```

## 📄 License
Licensed under the **MIT License**.
© 2026 Kerem ATA (zoda).
