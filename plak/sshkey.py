import typer
import os
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Union
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt

# Inicializar la aplicación Typer y la consola Rich
app = typer.Typer()
console = Console()

def get_ssh_dir() -> str:
    """
    Obtiene la ruta al directorio SSH del usuario.
    
    Returns:
        str: Ruta absoluta al directorio ~/.ssh
    """
    return os.path.expanduser("~/.ssh")

def list_ssh_keys() -> List[Dict[str, Union[str, bool]]]:
    """
    Lista todas las claves SSH en el directorio .ssh.
    
    Busca archivos que probablemente sean claves privadas (excluyendo archivos
    conocidos como authorized_keys, known_hosts, etc.) y comprueba si tienen
    una clave pública correspondiente (.pub).
    
    Returns:
        List[Dict[str, Union[str, bool]]]: Lista de diccionarios con información de claves.
            Cada diccionario contiene:
            - 'name': Nombre del archivo de clave
            - 'path': Ruta completa al archivo de clave
            - 'has_public': Booleano indicando si tiene archivo .pub
    """
    ssh_dir = get_ssh_dir()
    if not os.path.exists(ssh_dir):
        return []
    
    keys = []
    for file in os.listdir(ssh_dir):
        file_path = os.path.join(ssh_dir, file)
        # Look for private keys (without .pub extension)
        if os.path.isfile(file_path) and not file.endswith('.pub') and not file in ['authorized_keys', 'known_hosts', 'config']:
            # Check if there's a corresponding .pub file
            pub_file = f"{file}.pub"
            pub_path = os.path.join(ssh_dir, pub_file)
            has_public = os.path.exists(pub_path)
            
            keys.append({
                'name': file,
                'path': file_path,
                'has_public': has_public
            })
    
    return keys

def get_key_details(key_path: str) -> Optional[Dict[str, str]]:
    """
    Obtiene detalles técnicos de una clave SSH.
    
    Para claves públicas (.pub), utiliza ssh-keygen para extraer información
    como tipo de clave, bits, huella digital y comentario. Para claves privadas
    o cuando no puede obtener detalles, devuelve información básica.
    
    Args:
        key_path (str): Ruta al archivo de clave (pública o privada)
        
    Returns:
        Optional[Dict[str, str]]: Diccionario con detalles de la clave o None si
                                la clave no existe. El diccionario contiene:
                                - 'bits': Número de bits de la clave
                                - 'fingerprint': Huella digital de la clave
                                - 'comment': Comentario (normalmente user@host)
                                - 'type': Tipo de clave (RSA, ED25519, etc.)
    """
    if not os.path.exists(key_path):
        return None
    
    # For public keys, we can extract more information
    if key_path.endswith('.pub'):
        try:
            result = subprocess.run(
                ['ssh-keygen', '-l', '-f', key_path],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                # Parse the output: "2048 SHA256:abcdef... user@host (RSA)"
                parts = result.stdout.strip().split()
                if len(parts) >= 4:
                    return {
                        'bits': parts[0],
                        'fingerprint': parts[1],
                        'comment': parts[2],
                        'type': parts[3].strip('()')
                    }
        except Exception as e:
            console.print(f"[bold red]Error getting key details: {str(e)}[/bold red]")
    
    # For private keys or if we couldn't get details
    return {
        'bits': '?',
        'fingerprint': '?',
        'comment': os.path.basename(key_path),
        'type': '?'
    }

@app.command()
def create():
    """
    Crea una clave SSH de forma interactiva.
    
    Guía al usuario a través del proceso de creación de una clave SSH,
    solicitando información como nombre, tipo de clave, bits y passphrase.
    Al finalizar, muestra la clave pública generada.
    """
    console.print("[bold blue]Creating an SSH key...[/bold blue]")
    
    key_name = Prompt.ask("Key name (e.g., id_rsa)", default="id_rsa")
    key_path = os.path.join(get_ssh_dir(), key_name)
    
    # Check if key already exists
    if os.path.exists(key_path):
        overwrite = Prompt.ask(
            f"Key '{key_name}' already exists. Overwrite?",
            choices=["y", "n"],
            default="n"
        )
        if overwrite.lower() != 'y':
            console.print("[bold yellow]Operation cancelled.[/bold yellow]")
            return
    
    key_type = Prompt.ask(
        "Key type",
        choices=["rsa", "ed25519", "ecdsa", "dsa"],
        default="ed25519"
    )
    
    bits = ""
    if key_type == "rsa":
        bits = Prompt.ask("Key bits", choices=["2048", "4096"], default="4096")
    
    passphrase = Prompt.ask("Passphrase (empty for no passphrase)", password=True, default="")
    
    # Build the ssh-keygen command
    cmd = ['ssh-keygen', '-t', key_type]
    if bits:
        cmd.extend(['-b', bits])
    cmd.extend(['-f', key_path, '-N', passphrase])
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            console.print(f"[bold green]SSH key '{key_name}' created successfully![/bold green]")
            pub_path = f"{key_path}.pub"
            if os.path.exists(pub_path):
                with open(pub_path, 'r') as f:
                    public_key = f.read().strip()
                console.print("\n[bold blue]Your public key:[/bold blue]")
                console.print(public_key)
        else:
            console.print(f"[bold red]Error creating key: {result.stderr}[/bold red]")
    except Exception as e:
        console.print(f"[bold red]Error creating key: {str(e)}[/bold red]")

@app.command()
def view():
    """
    Muestra las claves SSH de forma interactiva.
    
    Lista todas las claves SSH encontradas en el directorio ~/.ssh
    y permite al usuario seleccionar una para ver más detalles.
    Para claves con archivo .pub, muestra información técnica y
    el contenido de la clave pública.
    """
    console.print("[bold blue]SSH Keys:[/bold blue]")
    
    keys = list_ssh_keys()
    if not keys:
        console.print("[italic yellow]No SSH keys found in ~/.ssh directory.[/italic yellow]")
        return
    
    table = Table(show_header=True)
    table.add_column("#", style="dim")
    table.add_column("Name", style="cyan")
    table.add_column("Has Public Key", style="green")
    
    for i, key in enumerate(keys, 1):
        table.add_row(
            str(i),
            key['name'],
            "Yes" if key['has_public'] else "No"
        )
    
    console.print(table)
    
    # Get user selection to view details
    choice = Prompt.ask(
        "Enter number of key to view details (or 'q' to quit)",
        default="q"
    )
    
    if choice.lower() == 'q':
        return
    
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(keys):
            key = keys[idx]
            console.print(f"\n[bold blue]Details for key: {key['name']}[/bold blue]")
            
            if key['has_public']:
                pub_path = f"{key['path']}.pub"
                details = get_key_details(pub_path)
                
                if details:
                    console.print(f"Type: {details['type']}")
                    console.print(f"Bits: {details['bits']}")
                    console.print(f"Fingerprint: {details['fingerprint']}")
                    console.print(f"Comment: {details['comment']}")
                
                with open(pub_path, 'r') as f:
                    public_key = f.read().strip()
                console.print("\n[bold blue]Public Key:[/bold blue]")
                console.print(public_key)
            else:
                console.print("[italic yellow]No public key found for this private key.[/italic yellow]")
        else:
            console.print("[bold red]Invalid selection.[/bold red]")
    except ValueError:
        console.print("[bold red]Please enter a valid number.[/bold red]")

@app.command()
def delete():
    """
    Elimina una clave SSH de forma interactiva.
    
    Muestra una lista de las claves SSH disponibles y permite al usuario
    seleccionar cuál eliminar. Solicita confirmación antes de proceder
    y elimina tanto la clave privada como la pública si existe.
    
    Esta operación es irreversible y no puede deshacerse, por lo que
    se requiere confirmación explícita.
    """
    console.print("[bold blue]Delete SSH Key[/bold blue]")
    
    keys = list_ssh_keys()
    if not keys:
        console.print("[italic yellow]No SSH keys found in ~/.ssh directory.[/italic yellow]")
        return
    
    table = Table(show_header=True)
    table.add_column("#", style="dim")
    table.add_column("Name", style="cyan")
    table.add_column("Has Public Key", style="green")
    
    for i, key in enumerate(keys, 1):
        table.add_row(
            str(i),
            key['name'],
            "Yes" if key['has_public'] else "No"
        )
    
    console.print(table)
    
    # Get user selection
    choice = Prompt.ask(
        "Enter number of key to delete (or 'q' to quit)",
        default="q"
    )
    
    if choice.lower() == 'q':
        return
    
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(keys):
            key = keys[idx]
            confirm = Prompt.ask(
                f"Are you sure you want to delete '{key['name']}'? This cannot be undone.",
                choices=["y", "n"],
                default="n"
            )
            
            if confirm.lower() == 'y':
                # Delete the private key
                try:
                    os.remove(key['path'])
                    console.print(f"[bold green]Deleted private key: {key['name']}[/bold green]")
                    
                    # Delete the public key if it exists
                    pub_path = f"{key['path']}.pub"
                    if os.path.exists(pub_path):
                        os.remove(pub_path)
                        console.print(f"[bold green]Deleted public key: {key['name']}.pub[/bold green]")
                    
                    console.print(f"[bold green]SSH key '{key['name']}' deleted successfully![/bold green]")
                except Exception as e:
                    console.print(f"[bold red]Error deleting key: {str(e)}[/bold red]")
            else:
                console.print("[bold yellow]Operation cancelled.[/bold yellow]")
        else:
            console.print("[bold red]Invalid selection.[/bold red]")
    except ValueError:
        console.print("[bold red]Please enter a valid number.[/bold red]")
