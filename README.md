# envman

**Environment Manager for Your Needs.**

`envman` is a lightweight, purely D-based developer environment toolkit and global package manager. It acts as both a system-wide "path aliases" tool and a local project package manager bridging the gap between local boilerplates, remote dependency scaffolding, and project setups.

*Created By Kerem ATA (zoda), and published under the MIT License*

---

## Features of envman

### 1. Global Path Registery (`envman path`)
Manage quick-references to important directories on your machine globally.
- Store deep filesystem paths under short "slugs"
- Fuzzy search through stored paths (Levenshtein distance + substring match highlighting)
- Open paths in your file explorer or inject them into the system `PATH`

### 2. Global & Local Package Manager (`envman pkg`)
Store raw files, directories, or URLs in a central registry, and pull them dynamically into individual project folders using a `project.envman` TOML configuration.
- **Intelligent Updating**: Checks modification timestamps to selectively upgrade parts of your boilerplates.
- **URL Handling**: Scaffolds files directly from web URLs effortlessly.
- **Check Command**: Scan a project directory to see if packages are mismatched, out of date, or missing.

### 3. Project Management (`envman project`)
Manage project-level metadata (name, version, authors, license, etc.) stored in `project.envman`.

---

## Usage

### Path Management

```bash
# Add a new path entry
envman path add <slug> <path>
envman path add my-framework C:\Path\To\MyFramework

# Edit an existing entry
envman path edit <slug> <new-path>

# Delete an entry
envman path delete <slug>

# Get the stored path for a slug
envman path get <slug>
envman path get <slug> --open    # Open in system's default explorer
envman path get <slug> --cd      # Change directory to the path

# List all stored paths
envman path list

# Fuzzy search by slug or path value (highlighted )
envman path search <query>

# Add a stored slug to the current shell PATH (prints set command)
envman path set <slug> --path

# Add a stored slug to the system PATH permanently (Windows, via setx)
envman path set <slug> --global

# Show the envman data file location
envman path
```

### Package Management

**Global Registry Commands:**
```bash
# Register a local file, directory, or URL as a global package
envman pkg register <alias> <path>
envman pkg register argd source/argd.d
envman pkg register my-utils C:\Path\To\Utils
envman pkg register remote-lib https://example.com/src/lib.d

# Import from a .envman.package file or a registry list .toml
envman pkg import <file>

# List all registered packages
envman pkg list

# Show info about a registered package
envman pkg info <alias>
envman pkg info <alias> --path   # Print only the path

# Remove a package from the global registry
envman pkg remove <alias>
```

**Project Commands (Using `project.envman`):**

Drop a TOML file in any project folder mapping registered packages to local destinations:
```toml
# project.envman
[packages]
argd = "source/argd.d"
"my-utils" = { path = "source/utils", type = "dir" }
"remote-lib" = { path = "source/lib.d", obtain = "https://example.com/lib.d" }
```

```bash
# Add a package requirement to project.envman
envman pkg add <alias> <destination>

# Remove a package requirement from project.envman
envman pkg drop <alias>

# Install all missing packages defined in project.envman
envman pkg install [directory?]
envman pkg install --symlink     # Use symlinks instead of copying

# Upgrade packages by detecting source modifications
envman pkg upgrade [directory?]
envman pkg upgrade --symlink

# Check project.envman status without modifying anything
envman pkg check [directory?]
envman pkg check --details       # Show project metadata too
envman pkg check --fix           # Remove unregistered entries from project.envman

# Run a command defined in a package's metadata
envman pkg run <alias> [action] [args...]
```

### Project Commands

```bash
# Initialize a new project.envman in the current directory
envman project init

# Show project metadata from project.envman
envman project info
```

### General

```bash
# Show envman version and build info (build date etc.)
envman info
envman --version

# Generates Markdown documentation for all commands
envman --gen-docs

# Generates HTML documentation for all commands
envman --gen-html
```

---

## Building envman
- Envman uses **The D Programming Language** with envman

```bash
# Use --parallel for building faster
dub build --parallel
```

## Preparing for a commit
- Envman uses `prepare.nu` file to do the actions thats needs to be done before committing.

```nushell
nu prepare.nu
```
## License
Licensed under the **MIT License**.
© 2026 Kerem ATA (zoda).
