import typer
import os

app = typer.Typer()


@app.command()
def create():
    """
    Create a new remote connection.
    """
    print(f"Opening SSH config file....")
    print(f"Adding remote SSH connection...")
    os.system("cd; cd .ssh; code config") 

@app.command()
def view():
    """
    View remote connections.
    """
    print(f"Opening SSH config file....")
    print(f"Viewing SSH connections...")
    os.system("cd; cd .ssh; cat config") 

@app.command()
def delete():
    """
    Delete a remote connection.
    """
    print(f"Opening SSH config file....")
    print(f"Removing remote SSH connection...")
    os.system("cd; cd .ssh; code config") 

