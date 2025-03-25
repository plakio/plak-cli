#!/bin/bash
# Development Setup Script for Plak CLI
#
# This script helps set up a development environment for Plak CLI
# It installs dependencies using uv and sets up the project for development

set -e

# Check if Python 3.12+ is available
python_version=$(python3 --version 2>&1)
if [[ ! $python_version =~ Python\ 3.1[2-9] ]]; then
    echo "Error: Plak requires Python 3.12 or newer"
    echo "Current version: $python_version"
    exit 1
fi

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "uv is not installed. Installing..."
    curl -fsSL https://astral.sh/uv/install.sh | bash
fi

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    uv venv
fi

# Activate virtual environment (this is a bit tricky in a script)
echo "Activating virtual environment..."
source .venv/bin/activate || source .venv/Scripts/activate

# Install dependencies
echo "Installing dependencies..."
uv pip install -e .

# Setup pre-commit if available
if command -v pre-commit &> /dev/null; then
    echo "Setting up pre-commit hooks..."
    pre-commit install
fi

echo "Development setup complete!"
echo "You can now run 'plak' command for development"
echo ""
echo "Don't forget to activate the virtual environment with:"
echo "  source .venv/bin/activate  # On Linux/MacOS"
echo "  .venv\\Scripts\\activate     # On Windows"
