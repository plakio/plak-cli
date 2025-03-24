import typer
import subprocess
import os
import re
from pathlib import Path
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt
from typing import List, Dict, Optional

app = typer.Typer()
console = Console()

def get_ssh_config_path():
    """Get path to SSH config file."""
    return os.path.expanduser("~/.ssh/config")

def parse_ssh_config() -> List[Dict[str, str]]:
    """Parse SSH config file and return list of servers."""
    config_path = get_ssh_config_path()
    if not os.path.exists(config_path):
        return []
    
    with open(config_path, 'r') as f:
        content = f.read()
    
    # Parse Host blocks
    hosts = []
    host_blocks = re.split(r'(?i)^Host\s+', content, flags=re.MULTILINE)
    for block in host_blocks[1:]:  # Skip first empty block
        lines = block.splitlines()
        if not lines:
            continue
        
        host_name = lines[0].strip()
        host_info = {'Name': host_name}
        
        for line in lines[1:]:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            parts = line.split(' ', 1)
            if len(parts) != 2:
                continue
            
            key, value = parts
            host_info[key.strip()] = value.strip()
        
        hosts.append(host_info)
    
    return hosts

def add_ssh_config(name: str, hostname: str, user: str, port: int = 22, identity_file: Optional[str] = None):
    """Add a new entry to SSH config."""
    config_path = get_ssh_config_path()
    
    # Ensure SSH directory exists
    ssh_dir = os.path.dirname(config_path)
    if not os.path.exists(ssh_dir):
        os.makedirs(ssh_dir, mode=0o700)
    
    # Create config file if it doesn't exist
    if not os.path.exists(config_path):
        open(config_path, 'w').close()
        os.chmod(config_path, 0o600)
    
    with open(config_path, 'a') as f:
        f.write(f"\nHost {name}\n")
        f.write(f"    HostName {hostname}\n")
        f.write(f"    User {user}\n")
        f.write(f"    Port {port}\n")
        if identity_file:
            f.write(f"    IdentityFile {identity_file}\n")

def delete_ssh_config(name: str):
    """Delete an entry from SSH config."""
    config_path = get_ssh_config_path()
    if not os.path.exists(config_path):
        console.print("[bold red]SSH config file does not exist.[/bold red]")
        return
    
    with open(config_path, 'r') as f:
        lines = f.readlines()
    
    # Find Host block to delete
    i = 0
    while i < len(lines):
        if lines[i].strip().startswith(f"Host {name}"):
            # Found the host, now find where this block ends
            j = i + 1
            while j < len(lines) and (lines[j].startswith(' ') or lines[j].startswith('\t') or not lines[j].strip()):
                j += 1
            # Delete the block
            del lines[i:j]
            break
        i += 1
    
    # Write back the modified config
    with open(config_path, 'w') as f:
        f.writelines(lines)

@app.command()
def create():
    """Create a new remote connection interactively."""
    console.print("[bold blue]Adding a new SSH connection...[/bold blue]")
    
    name = Prompt.ask("Connection name")
    hostname = Prompt.ask("Hostname/IP")
    user = Prompt.ask("Username")
    port = int(Prompt.ask("Port", default="22"))
    use_key = Prompt.ask("Use identity file?", choices=["y", "n"], default="n")
    
    identity_file = None
    if use_key == "y":
        identity_file = Prompt.ask("Path to identity file", default="~/.ssh/id_rsa")
    
    add_ssh_config(name, hostname, user, port, identity_file)
    console.print(f"[bold green]SSH connection '{name}' added successfully![/bold green]")

@app.command()
def view():
    """View remote connections."""
    console.print("[bold blue]SSH Connections:[/bold blue]")
    
    hosts = parse_ssh_config()
    if not hosts:
        console.print("[italic yellow]No SSH connections found in config.[/italic yellow]")
        return
    
    table = Table(show_header=True)
    table.add_column("Name", style="cyan")
    table.add_column("Hostname", style="green")
    table.add_column("User", style="yellow")
    table.add_column("Port", style="magenta")
    table.add_column("Identity File", style="blue")
    
    for host in hosts:
        table.add_row(
            host.get('Name', ''),
            host.get('HostName', ''),
            host.get('User', ''),
            host.get('Port', '22'),
            host.get('IdentityFile', '')
        )
    
    console.print(table)

@app.command()
def delete():
    """Delete a remote connection interactively."""
    console.print("[bold blue]Delete SSH Connection[/bold blue]")
    
    hosts = parse_ssh_config()
    if not hosts:
        console.print("[italic yellow]No SSH connections found in config.[/italic yellow]")
        return
    
    # Show available connections
    table = Table(show_header=True)
    table.add_column("#", style="dim")
    table.add_column("Name", style="cyan")
    table.add_column("Hostname", style="green")
    
    for i, host in enumerate(hosts, 1):
        table.add_row(
            str(i),
            host.get('Name', ''),
            host.get('HostName', '')
        )
    
    console.print(table)
    
    # Get user selection
    choice = Prompt.ask(
        "Enter number of connection to delete (or 'q' to quit)",
        default="q"
    )
    
    if choice.lower() == 'q':
        return
    
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(hosts):
            name = hosts[idx].get('Name')
            confirm = Prompt.ask(
                f"Are you sure you want to delete '{name}'?",
                choices=["y", "n"],
                default="n"
            )
            
            if confirm.lower() == 'y':
                delete_ssh_config(name)
                console.print(f"[bold green]SSH connection '{name}' deleted successfully![/bold green]")
        else:
            console.print("[bold red]Invalid selection.[/bold red]")
    except ValueError:
        console.print("[bold red]Please enter a valid number.[/bold red]")

@app.command()
def connect():
    """Connect to a server interactively."""
    console.print("[bold blue]Connect to SSH Server[/bold blue]")
    
    hosts = parse_ssh_config()
    if not hosts:
        console.print("[italic yellow]No SSH connections found in config.[/italic yellow]")
        return
    
    # Show available connections
    table = Table(show_header=True)
    table.add_column("#", style="dim")
    table.add_column("Name", style="cyan")
    table.add_column("Hostname", style="green")
    table.add_column("User", style="yellow")
    
    for i, host in enumerate(hosts, 1):
        table.add_row(
            str(i),
            host.get('Name', ''),
            host.get('HostName', ''),
            host.get('User', '')
        )
    
    console.print(table)
    
    # Get user selection
    choice = Prompt.ask(
        "Enter number of connection to connect (or 'q' to quit)",
        default="q"
    )
    
    if choice.lower() == 'q':
        return
    
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(hosts):
            name = hosts[idx].get('Name')
            console.print(f"[bold green]Connecting to {name}...[/bold green]")
            
            # Use subprocess.run instead of os.system
            subprocess.run(["ssh", name])
        else:
            console.print("[bold red]Invalid selection.[/bold red]")
    except ValueError:
        console.print("[bold red]Please enter a valid number.[/bold red]")
