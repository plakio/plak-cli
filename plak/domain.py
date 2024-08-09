import typer
import os

app = typer.Typer()


@app.command()
def create():
    """
    Add a domain to hosts.
    """
    print(f"Opening hosts file...")
    print(f"Adding a domain...")
    os.system("cd; sudo code /etc/hosts")

@app.command()
def view():
    """
    View domains from hosts.
    """
    print(f"Opening hosts file...")
    print(f"Viewing domains...")
    os.system("cd; cat /etc/hosts")
    
@app.command()
def delete():
    """
    Delete a domain from hosts.
    """
    print(f"Opening hosts file...")
    print(f"Removing a domain...")
    os.system("cd; sudo code /etc/hosts")  