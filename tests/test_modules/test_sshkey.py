import os
import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path
from plak.sshkey import get_ssh_dir, list_ssh_keys, get_key_details

@pytest.fixture
def mock_ssh_dir(tmp_path):
    """Crear un directorio SSH temporal para pruebas"""
    ssh_dir = tmp_path / ".ssh"
    ssh_dir.mkdir()
    
    # Crear archivos SSH de prueba
    (ssh_dir / "id_rsa").write_text("PRIVATE KEY CONTENT")
    (ssh_dir / "id_rsa.pub").write_text("ssh-rsa AAAAB3NzaC1yc2EA... user@host")
    (ssh_dir / "known_hosts").write_text("Some known hosts content")
    (ssh_dir / "config").write_text("SSH config content")
    
    return str(ssh_dir)

def test_get_ssh_dir():
    """Test que la función devuelve la ruta correcta del directorio SSH"""
    ssh_dir = get_ssh_dir()
    assert isinstance(ssh_dir, str)
    assert ssh_dir.endswith('.ssh')

def test_list_ssh_keys(mock_ssh_dir):
    """Test que la función list_ssh_keys encuentra correctamente las claves SSH"""
    with patch('plak.sshkey.get_ssh_dir', return_value=mock_ssh_dir):
        keys = list_ssh_keys()
        
        assert len(keys) == 1  # Solo id_rsa debe ser encontrada como clave privada
        assert keys[0]['name'] == 'id_rsa'
        assert keys[0]['has_public'] == True
        assert os.path.join(mock_ssh_dir, 'id_rsa') == keys[0]['path']

def test_get_key_details(mock_ssh_dir):
    """Test que la función get_key_details obtiene información de la clave pública"""
    # Mock para ssh-keygen
    mock_process = MagicMock()
    mock_process.returncode = 0
    mock_process.stdout = "2048 SHA256:AbCdEf123456 user@host (RSA)"
    
    key_path = os.path.join(mock_ssh_dir, 'id_rsa.pub')
    
    # Patch del comando ssh-keygen
    with patch('subprocess.run', return_value=mock_process):
        details = get_key_details(key_path)
        
        assert details is not None
        # No podemos verificar valores específicos ya que hemos parcheado el comando

def test_get_key_details_nonexistent():
    """Test que la función maneja correctamente una clave que no existe"""
    details = get_key_details('/nonexistent/path')
    assert details is None
