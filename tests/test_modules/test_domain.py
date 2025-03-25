import os
import pytest
from unittest.mock import patch, MagicMock, mock_open
from plak.domain import parse_hosts, get_hosts_path

# Datos de prueba para el archivo hosts
SAMPLE_HOSTS_FILE = """127.0.0.1       localhost
::1             localhost
127.0.1.1       myhostname

# Development sites
192.168.1.10    dev.example.com
192.168.1.10    test.example.com staging.example.com

# Production site
203.0.113.10    example.com www.example.com
"""

@pytest.fixture
def mock_hosts_file(tmp_path):
    """Crear un archivo hosts temporal para pruebas"""
    hosts_file = tmp_path / "hosts"
    hosts_file.write_text(SAMPLE_HOSTS_FILE)
    return str(hosts_file)

def test_get_hosts_path():
    """Test que la función devuelve una ruta válida dependiendo del sistema operativo"""
    path = get_hosts_path()
    assert isinstance(path, str)
    
    # En sistemas Unix/Linux/macOS
    if os.name != 'nt':
        assert path == "/etc/hosts"
    else:
        # En Windows
        assert path == r"C:\Windows\System32\drivers\etc\hosts"

def test_parse_hosts(mock_hosts_file):
    """Test que la función parse_hosts analiza correctamente el archivo hosts"""
    with patch('plak.domain.get_hosts_path', return_value=mock_hosts_file):
        entries = parse_hosts()
        
        assert len(entries) == 7  # Hay 7 entradas de dominio en el archivo de muestra
        
        # Verificar que localhost existe
        localhost_entries = [entry for entry in entries if entry['Domain'] == 'localhost']
        assert len(localhost_entries) == 2  # IPv4 e IPv6
        
        # Verificar el dominio de desarrollo
        dev_entry = next(entry for entry in entries if entry['Domain'] == 'dev.example.com')
        assert dev_entry['IP'] == '192.168.1.10'
        
        # Verificar dominios múltiples en la misma línea
        staging_entry = next(entry for entry in entries if entry['Domain'] == 'staging.example.com')
        assert staging_entry['IP'] == '192.168.1.10'
        
        # Verificar producción
        www_entry = next(entry for entry in entries if entry['Domain'] == 'www.example.com')
        assert www_entry['IP'] == '203.0.113.10'

# Los tests para add_hosts_entry y delete_hosts_entry serían más complejos
# ya que estas funciones utilizan comandos sudo en Linux/macOS.
# Para una cobertura completa, necesitarían mocks más avanzados.
