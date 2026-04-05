# `envman`

Envman 0.0.1, environment/package manager

**Usage:** `envman [options]`

## Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-v, --verbose` | Enable verbose output |
| `-q, --quiet` | Suppress output |
| `-gd, --gen-docs` | Generate markdown documentation for all commands |
| `-v, --version` | Version of the envman |

## Subcommands

## `info`

Information about the envman

**Usage:** `info [options]`

### Options

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

### `info`

Information about a registery package

**Usage:** `info <package name>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `add`

Adds a package requirement to packages.envman in the current directory

**Usage:** `add <package alias> <destination path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `drop`

Removes a package entry from packages.envman in the current directory

**Usage:** `drop <package alias>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `register`

Registers a file/directory as a package on global package registery

**Usage:** `register <package alias> <package path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `check`

Checks packages in packages.envman without installing

**Usage:** `check [target directory path]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |
| `-fix, --fix` | Removes unregistered (unknown) packages from packages.envman file |

### `install`

Installs packages from packages.envman into the current directory

**Usage:** `install [target directory path]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `upgrade`

Upgrades packages from packages.envman by checking if the source is modified

**Usage:** `upgrade [target directory path]`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

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

## `path`

Show the save path of envman or manage paths

**Usage:** `path `

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### Subcommands

### `delete`

Delete a directory or file path for a slug

**Usage:** `delete <slug>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `append`

Append a directory or file path with a slug

**Usage:** `append <slug> <path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

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

### `list`

Lists all paths

**Usage:** `list `

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

### `edit`

Edit an existing path for a slug

**Usage:** `edit <slug> <path>`

#### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show this help message |

