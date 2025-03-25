# Contributing to Plak CLI

Thank you for your interest in contributing to Plak CLI! This document provides guidelines and instructions for contributing to this project.

## Development Setup

1. Clone the repository:
   ```
   git clone https://github.com/plakio/plak-cli.git
   cd plak-cli
   ```

2. Run the development setup script (Linux/MacOS):
   ```
   ./scripts/dev_setup.sh
   ```
   
   For Windows, you'll need to:
   ```
   python -m venv .venv
   .venv\Scripts\activate
   uv pip install -e .
   ```

3. Activate the virtual environment:
   ```
   source .venv/bin/activate  # Linux/MacOS
   .venv\Scripts\activate     # Windows
   ```

## Development Guidelines

### Code Style

- We follow PEP 8 for Python code style
- Use type hints for function parameters and return values
- Document your code with docstrings (following Google style)
- Use meaningful variable and function names

### Testing

- Add tests for new functionality
- Run tests before submitting a pull request:
  ```
  pytest
  ```

### Pull Request Process

1. Fork the repository and create a new branch for your feature
2. Make your changes, following the code style guidelines
3. Add tests for your changes
4. Update documentation if necessary
5. Submit a pull request with a clear description of the changes

### Commit Messages

Follow the conventional commits format:
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

Example: `feat: add server connect command`

## Project Structure

```
plak/
├── plak/               # Main package
│   ├── __init__.py     # Version and package info
│   ├── main.py         # CLI entry point
│   ├── domain.py       # Domain management module
│   ├── server.py       # Server management module
│   └── sshkey.py       # SSH key management module
├── tests/              # Test directory
│   └── test_*.py       # Test files
├── scripts/            # Helper scripts for development
├── pyproject.toml      # Project configuration
└── uv.lock             # Dependency lock file (uv)
```

## License

By contributing, you agree that your contributions will be licensed under the project's MIT License.
