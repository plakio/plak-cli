# `plak`

**Usage**:

```console
$ plak [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `-v, --version`: Show the application's version.
* `--install-completion`: Install completion for the current shell.
* `--show-completion`: Show completion for the current shell, to copy it or customize the installation.
* `--help`: Show this message and exit.

**Commands**:

* `domain`: Manage domains in the hosts file.
* `server`: Manage server connections in the SSH...
* `sshkey`: Manage SSH key in the .ssh directory.

## `plak domain`

Manage domains in the hosts file.

**Usage**:

```console
$ plak domain [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `--help`: Show this message and exit.

**Commands**:

* `create`: Add a domain to hosts.
* `delete`: Delete a domain from hosts.
* `view`: View domains from hosts.

### `plak domain create`

Add a domain to hosts.

**Usage**:

```console
$ plak domain create [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

### `plak domain delete`

Delete a domain from hosts.

**Usage**:

```console
$ plak domain delete [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

### `plak domain view`

View domains from hosts.

**Usage**:

```console
$ plak domain view [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

## `plak server`

Manage server connections in the SSH config file.

**Usage**:

```console
$ plak server [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `--help`: Show this message and exit.

**Commands**:

* `create`: Create a new remote connection.
* `delete`: Delete a remote connection.
* `view`: View remote connections.

### `plak server create`

Create a new remote connection.

**Usage**:

```console
$ plak server create [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

### `plak server delete`

Delete a remote connection.

**Usage**:

```console
$ plak server delete [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

### `plak server view`

View remote connections.

**Usage**:

```console
$ plak server view [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

## `plak sshkey`

Manage SSH key in the .ssh directory.

**Usage**:

```console
$ plak sshkey [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `--help`: Show this message and exit.

**Commands**:

* `create`: Create an SSH key.
* `view`: View SSH key.

### `plak sshkey create`

Create an SSH key.

**Usage**:

```console
$ plak sshkey create [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.

### `plak sshkey view`

View SSH key.

**Usage**:

```console
$ plak sshkey view [OPTIONS]
```

**Options**:

* `--help`: Show this message and exit.
