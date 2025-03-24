# `plak`

Plak CLI es una herramienta interactiva para gestionar servidores en la nube y sitios WordPress. Proporciona comandos para administrar conexiones SSH, dominios en el archivo hosts, y claves SSH de forma sencilla y visual.

![Plak CLI Demo](https://github.com/plakio/plak-cli/raw/main/docs/images/demo.png)

## Requisitos

- Python 3.12 o superior
- Permisos de administrador para algunas operaciones (modificación de hosts)

## Instalación

```bash
pip install plak
```

O desde el código fuente:

```bash
pip install -e .
```

## Características

- **Interfaz interactiva**: Todos los comandos utilizan interfaces textuales mejoradas con colores y tablas
- **Gestión SSH**: Crear, ver, eliminar y conectarse a servidores SSH configurados
- **Gestión de dominios**: Administrar entradas en el archivo hosts del sistema
- **Gestión de claves SSH**: Crear, ver y eliminar claves SSH con manejo detallado de configuraciones

**Usage**:

```console
$ plak [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `-v, --version`: Muestra la versión de la aplicación.
* `--install-completion`: Instala la autocompletación para la shell actual.
* `--show-completion`: Muestra la autocompletación para la shell actual.
* `--help`: Muestra ayuda y sale.

**Commands**:

* `domain`: Gestiona dominios en el archivo hosts.
* `server`: Gestiona conexiones de servidor en el archivo de configuración SSH.
* `sshkey`: Gestiona claves SSH en el directorio .ssh.

## `plak server`

Gestiona conexiones de servidor en el archivo de configuración SSH (~/.ssh/config).

**Usage**:

```console
$ plak server [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `--help`: Muestra ayuda y sale.

**Commands**:

* `create`: Crea una nueva conexión remota de forma interactiva.
* `connect`: Conecta a un servidor existente de forma interactiva.
* `delete`: Elimina una conexión remota seleccionándola de una lista.
* `view`: Muestra las conexiones remotas en un formato tabulado.

### `plak server create`

Crea una nueva conexión SSH interactivamente. El comando te guiará a través de una serie de preguntas para configurar el servidor.

**Ejemplo**:
```
$ plak server create

Adding a new SSH connection...
Connection name: myserver
Hostname/IP: 192.168.1.100
Username: admin
Port: 22
Use identity file? [y/n]: y
Path to identity file: ~/.ssh/id_rsa
SSH connection 'myserver' added successfully!
```

### `plak server connect`

Conecta a un servidor SSH eligiéndolo de una lista interactiva.

**Ejemplo**:
```
$ plak server connect

Connect to SSH Server
┏━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┓
┃ # ┃ Name     ┃ Hostname       ┃ User         ┃
┡━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━┩
│ 1 │ server1  │ 192.168.1.10   │ admin        │
│ 2 │ webserver│ 203.0.113.10   │ ubuntu       │
└───┴──────────┴────────────────┴──────────────┘
Enter number of connection to connect (or 'q' to quit):
```

### `plak server delete`

Elimina una conexión SSH seleccionándola de una lista interactiva.

### `plak server view`

Muestra todas las conexiones SSH configuradas en una tabla con formato.

**Ejemplo**:
```
$ plak server view

SSH Connections:
┏━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━┳━━━━━━━━━━━━━━━━━┓
┃ Name     ┃ Hostname     ┃ User       ┃ Port ┃ Identity File   ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━╇━━━━━━━━━━━━━━━━━┩
│ server1  │ 192.168.1.10 │ admin      │ 22   │ ~/.ssh/id_rsa   │
│ webserver│ 203.0.113.10 │ ubuntu     │ 22   │                 │
└──────────┴──────────────┴────────────┴──────┴─────────────────┘
```

## `plak domain`

Gestiona dominios en el archivo hosts.

**Usage**:

```console
$ plak domain [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `--help`: Muestra ayuda y sale.

**Commands**:

* `create`: Añade un dominio al archivo hosts de forma interactiva.
* `delete`: Elimina un dominio del archivo hosts a través de un menú interactivo.
* `view`: Muestra los dominios del archivo hosts en formato tabulado.

### `plak domain create`

Añade un nuevo dominio al archivo hosts. Solicitará privilegios sudo en sistemas Unix/Linux/macOS.

**Ejemplo**:
```
$ plak domain create

Adding a new domain to hosts...
Domain name: mysite.local
IP address: 127.0.0.1
Adding mysite.local with IP 127.0.0.1 to hosts file...
This operation requires sudo privileges.
Domain 'mysite.local' added successfully!
```

### `plak domain delete`

Elimina un dominio del archivo hosts seleccionándolo de una lista interactiva.

### `plak domain view`

Muestra todos los dominios configurados en el archivo hosts en una tabla formateada.

**Ejemplo**:
```
$ plak domain view

Domains in hosts file:
┏━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┓
┃ IP        ┃ Domain          ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━┩
│ 127.0.0.1 │ localhost       │
│ 127.0.0.1 │ mysite.local    │
│ ::1       │ localhost       │
└───────────┴─────────────────┘
```

## `plak sshkey`

Gestiona claves SSH en el directorio ~/.ssh.

**Usage**:

```console
$ plak sshkey [OPTIONS] COMMAND [ARGS]...
```

**Options**:

* `--help`: Muestra ayuda y sale.

**Commands**:

* `create`: Crea una nueva clave SSH con opciones interactivas.
* `view`: Muestra y permite examinar las claves SSH existentes.
* `delete`: Elimina una clave SSH existente (nuevo comando).

### `plak sshkey create`

Crea una nueva clave SSH con opciones interactivas para tipo de clave, bits y passphrase.

**Ejemplo**:
```
$ plak sshkey create

Creating an SSH key...
Key name (e.g., id_rsa): my_new_key
Key type [rsa/ed25519/ecdsa/dsa]: ed25519
Passphrase (empty for no passphrase):
SSH key 'my_new_key' created successfully!

Your public key:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII9... user@host
```

### `plak sshkey view`

Muestra y permite examinar en detalle las claves SSH existentes.

**Ejemplo**:
```
$ plak sshkey view

SSH Keys:
┏━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
┃ # ┃ Name    ┃ Has Public Key ┃
┡━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
│ 1 │ id_rsa  │ Yes            │
│ 2 │ my_key  │ Yes            │
└───┴─────────┴────────────────┘
Enter number of key to view details (or 'q' to quit): 1

Details for key: id_rsa
Type: RSA
Bits: 4096
Fingerprint: SHA256:abc123...
Comment: user@host

Public Key:
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDJlG... user@host
```

### `plak sshkey delete`

Elimina una clave SSH seleccionándola de una lista interactiva.

**Ejemplo**:
```
$ plak sshkey delete

Delete SSH Key
┏━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
┃ # ┃ Name    ┃ Has Public Key ┃
┡━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
│ 1 │ id_rsa  │ Yes            │
│ 2 │ my_key  │ Yes            │
└───┴─────────┴────────────────┘
Enter number of key to delete (or 'q' to quit): 2
Are you sure you want to delete 'my_key'? This cannot be undone. [y/n]: y
Deleted private key: my_key
Deleted public key: my_key.pub
SSH key 'my_key' deleted successfully!
```

## Contribuir

Las contribuciones son bienvenidas. Por favor, envía un Pull Request o abre un Issue en [GitHub](https://github.com/plakio/plak-cli).

## Licencia

MIT
