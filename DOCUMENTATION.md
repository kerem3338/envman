# `envman`

Envman 0.0.2, environment/package manager

**Usage:** `envman [options]`

## Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-V, --verbose` | Enable verbose output |
| `-q, --quiet` | Suppress output |
| `-gd, --gen-docs` | Generate markdown documentation for all commands |
| `-gh, --gen-html` | Generate HTML documentation for all commands |
| `-v, --version` | Version of the envman |

## Subcommands

## `info`

Information about the envman

**Usage:** `info [options]`

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

## `config`

Manage user configuration

**Usage:** `config [options]`

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### Subcommands

### `list`

List all configuration values

**Usage:** `list [options]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `set`

Set a configuration value

**Usage:** `set <key> <value>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `get`

Get a configuration value

**Usage:** `get <key>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-e, --execute` | Execute value of the config key as a shell command |

### `delete`

Delete a configuration value

**Usage:** `delete <key>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

## `set`

Sets the path for the current shell or permanently

**Usage:** `set <slug> [-p|--path] [-g|--global]`

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-p, --path` | Adds to current shell PATH (prints set command) |
| `-g, --global` | Adds with setx permanently (Windows only) |

## `pkg`

Onefile package system

**Usage:** `pkg [options]`

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### Subcommands

### `import`

Imports and registers multiple packages from a registry list file

**Usage:** `import <registry_list_file>.toml`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `info`

Information about a registery package

**Usage:** `info <package name>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-p, --path` | Get path of the package |
| `-d, --dir` | Give the directory path of the package (for local packages) |
| `-e, --edit` | Open the path in users text editor |

### `add`

Adds a package requirement to project.envman in the current directory

**Usage:** `add <package alias> <destination path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `drop`

Removes a package entry from project.envman in the current directory

**Usage:** `drop <package alias>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `register`

Registers a file/directory/url or .envman.package as a package on global package registery

**Usage:** `register <package alias> <package path> OR <package_file>.envman.package`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `inspect`

Shows detailed information about a local project package dependency

**Usage:** `inspect [options]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `run`

Runs an action (like 'run' or 'build') defined in a package's metadata

**Usage:** `run <package alias> [action] [args...]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `check`

Checks packages in project.envman without installing

**Usage:** `check [target directory path]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-fix, --fix` | Removes unregistered (unknown) packages from packages.envman file |
| `-d, --details` | Gives more details about the project |

### `install`

Installs packages from project.envman into the current directory

**Usage:** `install [target directory path]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-s, --symlink` | Use symlinks for local packages instead of copying |

### `upgrade`

Upgrades packages from project.envman by checking if the source is modified

**Usage:** `upgrade [target directory path]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-s, --symlink` | Use symlinks for local packages instead of copying |

### `remove`

Removes a package from the global registry

**Usage:** `remove <package alias>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `list`

List all packages in global registery

**Usage:** `list [options]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

## `project`

Manage project configuration (project.envman)

**Usage:** `project [options]`

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### Subcommands

### `info`

Display information about the current project

**Usage:** `info [options]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `init`

Initialize a new project in the current directory

**Usage:** `init [options]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

## `path`

Show the save path of envman or manage paths

**Usage:** `path `

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### Subcommands

### `add`

Add a directory or file path with a slug

**Usage:** `add <slug> <path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `delete`

Delete a directory or file path for a slug

**Usage:** `delete <slug>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `set`

Sets the path for the current shell or permanently

**Usage:** `set <slug> [-p|--path] [-g|--global]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-p, --path` | Adds to current shell PATH (prints set command) |
| `-g, --global` | Adds with setx permanently (Windows only) |

### `search`

Search paths by slug or value

**Usage:** `search <query>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `get`

Gets the path of a slug entry

**Usage:** `get <slug>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-o, --open` | Open the path in default application |
| `-p, --path` | Adds the path to system path |
| `-c, --cd` | Change directory |
| `-e, --edit` | Open the path in a editor |

### `edit`

Edit an existing path for a slug

**Usage:** `edit <slug> <path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `list`

Lists all paths

**Usage:** `list `

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

