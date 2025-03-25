import typer
from typing import Optional

from plak import server, domain, sshkey
from plak import __app_name__, __version__


app = typer.Typer()
app.add_typer(server.app, name="server", help="Manage server connections in the SSH config file." )
app.add_typer(domain.app, name="domain", help="Manage domains in the hosts file.")
app.add_typer(sshkey.app, name="sshkey", help="Manage SSH key in the .ssh directory.")

def _version_callback(value: bool) -> None:
    if value:
        typer.echo(f"{__app_name__} v{__version__}")
        raise typer.Exit()

@app.callback()
def main(
    version: Optional[bool] = typer.Option(
        None,
        "--version",
        "-v",
        help="Show the application's version.",
        callback=_version_callback,
        is_eager=True,
    )
) -> None:
    return

if __name__ == "__main__":
    app()