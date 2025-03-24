import os
import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path
from plak.server import parse_ssh_config, add_ssh_config, delete_ssh_config, get_ssh_config_path

# Crear datos de prueba
SAMPLE_SSH_CONFIG = """Host testserver1
    HostName 192.168.1.10
    User testuser
    Port 22

Host testserver2
    HostName 10.0.0.1
    User admin
    Port 2222
    IdentityFile ~/.ssh/special_key
"""

@pytest.fixture
def mock_ssh_config(tmp_path):
    """Crear un archivo SSH config temporal para pruebas"""
    config_file = tmp_path / "config"
    config_file.write_text(SAMPLE_SSH_CONFIG)
    return str(config_file)

def test_get_ssh_config_path():
    """Test que la función devuelve una ruta válida"""
    path = get_ssh_config_path()
    assert isinstance(path, str)
    assert path.endswith('.ssh/config')

def test_parse_ssh_config(mock_ssh_config):
    """Test que la función parse_ssh_config analiza correctamente el archivo de configuración"""
    with patch('plak.server.get_ssh_config_path', return_value=mock_ssh_config):
        hosts = parse_ssh_config()
        
        assert len(hosts) == 2
        
        # Verificar el primer host
        assert hosts[0]['Name'] == 'testserver1'
        assert hosts[0]['HostName'] == '192.168.1.10'
        assert hosts[0]['User'] == 'testuser'
        assert hosts[0]['Port'] == '22'
        
        # Verificar el segundo host
        assert hosts[1]['Name'] == 'testserver2'
        assert hosts[1]['HostName'] == '10.0.0.1'
        assert hosts[1]['User'] == 'admin'
        assert hosts[1]['Port'] == '2222'
        assert hosts[1]['IdentityFile'] == '~/.ssh/special_key'

def test_add_ssh_config(tmp_path):
    """Test que la función add_ssh_config agrega correctamente un nuevo host"""
    config_file = tmp_path / "config"
    config_file.write_text("")
    
    with patch('plak.server.get_ssh_config_path', return_value=str(config_file)):
        add_ssh_config("newserver", "192.168.1.100", "admin", 2222, "~/.ssh/id_rsa")
        
        content = config_file.read_text()
        assert "Host newserver" in content
        assert "HostName 192.168.1.100" in content
        assert "User admin" in content
        assert "Port 2222" in content
        assert "IdentityFile ~/.ssh/id_rsa" in content

def test_delete_ssh_config(mock_ssh_config):
    """Test que la función delete_ssh_config elimina correctamente un host"""
    with patch('plak.server.get_ssh_config_path', return_value=mock_ssh_config):
        # Eliminar el primer host
        delete_ssh_config("testserver1")
        
        # Verificar que el contenido del archivo haya cambiado
        with open(mock_ssh_config, 'r') as f:
            content = f.read()
            assert "Host testserver1" not in content
            assert "HostName 192.168.1.10" not in content
            assert "Host testserver2" in content  # El segundo host debe seguir ahí
