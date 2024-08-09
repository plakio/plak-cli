import typer
import os

app = typer.Typer()


@app.command()
def create():
    """
    Create an SSH key.
    """
    print(f"Creating an SSH key...")
    os.system("ssh-keygen")

@app.command()
def view():
    """
    View SSH key.
    """
    print(f"Opening id_rsa.pub directory...")
    print(f"Viewing SSH key...")
    os.system("cd; cd .ssh; cat id_rsa.pub")
