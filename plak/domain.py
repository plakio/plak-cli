import typer
import os
import re
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt

# Inicializar la aplicación Typer y la consola Rich
app = typer.Typer()
console = Console()

def get_hosts_path() -> str:
    """
    Obtiene la ruta al archivo hosts del sistema.
    
    Determina la ubicación del archivo hosts según el sistema operativo.
    En Windows es C:\\Windows\\System32\\drivers\\etc\\hosts,
    en Unix/Linux/MacOS es /etc/hosts.
    
    Returns:
        str: Ruta absoluta al archivo hosts
    """
    if os.name == 'nt':  # Windows
        return r"C:\Windows\System32\drivers\etc\hosts"
    else:  # Unix/Linux/MacOS
        return "/etc/hosts"

def parse_hosts() -> List[Dict[str, str]]:
    """
    Analiza el archivo hosts y devuelve una lista de entradas.
    
    Cada entrada es un diccionario con las claves 'IP' y 'Domain'.
    Si hay múltiples dominios en la misma línea, se crean entradas
    separadas para cada uno con la misma IP.
    
    Returns:
        List[Dict[str, str]]: Lista de diccionarios con entradas del hosts.
    """
    hosts_path = get_hosts_path()
    if not os.path.exists(hosts_path):
        return []
    
    entries = []
    with open(hosts_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            parts = re.split(r'\s+', line)
            if len(parts) < 2:
                continue
            
            ip = parts[0]
            domains = parts[1:]
            
            for domain in domains:
                entries.append({
                    'IP': ip,
                    'Domain': domain
                })
    
    return entries

def add_hosts_entry(ip: str, domain: str) -> bool:
    """
    Añade una nueva entrada al archivo hosts.
    
    En sistemas Unix/Linux/MacOS, utiliza sudo para modificar el archivo hosts.
    Crea un archivo temporal, lo modifica y luego lo mueve al lugar correcto
    con privilegios de superusuario.
    
    Args:
        ip (str): Dirección IP para el dominio
        domain (str): Nombre de dominio a añadir
        
    Returns:
        bool: True si se añadió correctamente, False si hubo un error
    """
    hosts_path = get_hosts_path()
    
    # Check if entry already exists
    entries = parse_hosts()
    for entry in entries:
        if entry['Domain'] == domain:
            console.print(f"[bold yellow]Domain '{domain}' already exists in hosts file with IP {entry['IP']}.[/bold yellow]")
            return False
    
    # For safety, we'll create a temporary file and then use sudo to move it
    temp_file = "/tmp/hosts.new"
    
    try:
        # Copy existing hosts file
        subprocess.run(["sudo", "cp", hosts_path, temp_file], check=True)
        # Make it writable
        subprocess.run(["sudo", "chmod", "666", temp_file], check=True)
        
        # Add the new entry
        with open(temp_file, 'a') as f:
            f.write(f"\n{ip}\t{domain}\n")
        
        # Replace the hosts file
        subprocess.run(["sudo", "mv", temp_file, hosts_path], check=True)
        return True
    except subprocess.SubprocessError as e:
        console.print(f"[bold red]Error updating hosts file: {str(e)}[/bold red]")
        return False

def delete_hosts_entry(domain: str) -> bool:
    """
    Elimina una entrada del archivo hosts.
    
    En sistemas Unix/Linux/MacOS, utiliza sudo para modificar el archivo hosts.
    Si el dominio es uno de varios en la misma línea, solo elimina ese dominio
    y mantiene los demás con la misma IP.
    
    Args:
        domain (str): Nombre de dominio a eliminar
        
    Returns:
        bool: True si se eliminó correctamente, False si hubo un error
    """
    hosts_path = get_hosts_path()
    temp_file = "/tmp/hosts.new"
    
    try:
        # Copy existing hosts file
        subprocess.run(["sudo", "cp", hosts_path, temp_file], check=True)
        # Make it writable
        subprocess.run(["sudo", "chmod", "666", temp_file], check=True)
        
        # Read current hosts file
        with open(temp_file, 'r') as f:
            lines = f.readlines()
        
        # Filter out the domain
        new_lines = []
        modified = False
        
        for line in lines:
            if domain in line and not line.strip().startswith('#'):
                # Remove just this domain from the line
                parts = re.split(r'\s+', line.strip())
                if len(parts) > 2:  # Multiple domains on this line
                    ip = parts[0]
                    domains = [d for d in parts[1:] if d != domain]
                    if domains:  # Still have domains left
                        new_lines.append(f"{ip}\t{' '.join(domains)}\n")
                    # If no domains left, skip this line entirely
                modified = True
            else:
                new_lines.append(line)
        
        if not modified:
            console.print(f"[bold yellow]Domain '{domain}' not found in hosts file.[/bold yellow]")
            return False
        
        # Write back the modified hosts file
        with open(temp_file, 'w') as f:
            f.writelines(new_lines)
        
        # Replace the hosts file
        subprocess.run(["sudo", "mv", temp_file, hosts_path], check=True)
        return True
    except subprocess.SubprocessError as e:
        console.print(f"[bold red]Error updating hosts file: {str(e)}[/bold red]")
        return False

@app.command()
def create():
    """
    Añade un dominio al archivo hosts de forma interactiva.
    
    Solicita el nombre de dominio y la dirección IP, y luego añade
    la entrada al archivo hosts del sistema. En sistemas Unix/Linux/MacOS,
    solicitará privilegios sudo para modificar el archivo.
    """
    console.print("[bold blue]Adding a new domain to hosts...[/bold blue]")
    
    domain = Prompt.ask("Domain name")
    ip = Prompt.ask("IP address", default="127.0.0.1")
    
    console.print(f"Adding {domain} with IP {ip} to hosts file...")
    console.print("[bold yellow]This operation requires sudo privileges.[/bold yellow]")
    
    success = add_hosts_entry(ip, domain)
    if success:
        console.print(f"[bold green]Domain '{domain}' added successfully![/bold green]")

@app.command()
def view():
    """
    Muestra los dominios del archivo hosts en formato tabulado.
    
    Muestra una tabla con todas las entradas del archivo hosts,
    incluyendo IP y dominio en columnas separadas.
    """
    console.print("[bold blue]Domains in hosts file:[/bold blue]")
    
    entries = parse_hosts()
    if not entries:
        console.print("[italic yellow]No domain entries found in hosts file.[/italic yellow]")
        return
    
    table = Table(show_header=True)
    table.add_column("IP", style="cyan")
    table.add_column("Domain", style="green")
    
    for entry in entries:
        table.add_row(entry['IP'], entry['Domain'])
    
    console.print(table)

@app.command()
def delete():
    """
    Elimina un dominio del archivo hosts de forma interactiva.
    
    Muestra una lista de todos los dominios configurados y permite
    seleccionar cuál eliminar. Solicita confirmación antes de proceder
    y requiere privilegios sudo en sistemas Unix/Linux/MacOS.
    """
    console.print("[bold blue]Delete Domain from hosts[/bold blue]")
    
    entries = parse_hosts()
    if not entries:
        console.print("[italic yellow]No domain entries found in hosts file.[/italic yellow]")
        return
    
    # Show available domains
    table = Table(show_header=True)
    table.add_column("#", style="dim")
    table.add_column("IP", style="cyan")
    table.add_column("Domain", style="green")
    
    for i, entry in enumerate(entries, 1):
        table.add_row(str(i), entry['IP'], entry['Domain'])
    
    console.print(table)
    
    # Get user selection
    choice = Prompt.ask(
        "Enter number of domain to delete (or 'q' to quit)",
        default="q"
    )
    
    if choice.lower() == 'q':
        return
    
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(entries):
            domain = entries[idx]['Domain']
            confirm = Prompt.ask(
                f"Are you sure you want to delete '{domain}'?",
                choices=["y", "n"],
                default="n"
            )
            
            if confirm.lower() == 'y':
                console.print("[bold yellow]This operation requires sudo privileges.[/bold yellow]")
                success = delete_hosts_entry(domain)
                if success:
                    console.print(f"[bold green]Domain '{domain}' deleted successfully![/bold green]")
        else:
            console.print("[bold red]Invalid selection.[/bold red]")
    except ValueError:
        console.print("[bold red]Please enter a valid number.[/bold red]")
