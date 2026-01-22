#!/bin/bash
# PPTAgent - Ollama Setup Script for macOS
# This script sets up PPTAgent to run entirely locally with Ollama
# No external APIs required!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script is designed for macOS. For other platforms, please install Ollama manually."
    exit 1
fi

echo ""
echo "=========================================="
echo "  PPTAgent - Ollama Setup for macOS"
echo "=========================================="
echo ""

# Get system info
TOTAL_RAM=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
CPU_BRAND=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")

print_status "System Information:"
echo "  - CPU: $CPU_BRAND"
echo "  - RAM: ${TOTAL_RAM}GB"
echo ""

# Determine recommended models based on RAM
if [ "$TOTAL_RAM" -ge 64 ]; then
    RECOMMENDED_LLM="llama3.3:70b"
    RECOMMENDED_VISION="llava:34b"
    RAM_TIER="high"
elif [ "$TOTAL_RAM" -ge 32 ]; then
    RECOMMENDED_LLM="llama3.2"
    RECOMMENDED_VISION="llava:13b"
    RAM_TIER="medium"
elif [ "$TOTAL_RAM" -ge 16 ]; then
    RECOMMENDED_LLM="llama3.2:3b"
    RECOMMENDED_VISION="llava:7b"
    RAM_TIER="low"
else
    RECOMMENDED_LLM="llama3.2:1b"
    RECOMMENDED_VISION="llava:7b"
    RAM_TIER="minimal"
fi

print_status "Recommended models for your system (${TOTAL_RAM}GB RAM):"
echo "  - LLM: $RECOMMENDED_LLM"
echo "  - Vision: $RECOMMENDED_VISION"
echo ""

# Step 1: Check/Install Homebrew
print_status "Checking for Homebrew..."
if ! command -v brew &> /dev/null; then
    print_warning "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    print_success "Homebrew installed!"
else
    print_success "Homebrew is already installed"
fi

# Step 2: Check/Install Ollama
print_status "Checking for Ollama..."
if ! command -v ollama &> /dev/null; then
    print_warning "Ollama not found. Installing..."
    brew install ollama
    print_success "Ollama installed!"
else
    print_success "Ollama is already installed"
fi

# Step 3: Start Ollama service
print_status "Starting Ollama service..."
if pgrep -x "ollama" > /dev/null; then
    print_success "Ollama is already running"
else
    # Start ollama in the background
    ollama serve &> /dev/null &
    sleep 3
    if pgrep -x "ollama" > /dev/null; then
        print_success "Ollama service started"
    else
        print_error "Failed to start Ollama. Please run 'ollama serve' manually"
    fi
fi

# Step 4: Pull recommended models
echo ""
print_status "Pulling recommended models (this may take a while)..."
echo ""

read -p "Do you want to pull the LLM model ($RECOMMENDED_LLM)? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    print_status "Pulling $RECOMMENDED_LLM..."
    ollama pull $RECOMMENDED_LLM
    print_success "LLM model pulled!"
fi

read -p "Do you want to pull the Vision model ($RECOMMENDED_VISION)? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    print_status "Pulling $RECOMMENDED_VISION..."
    ollama pull $RECOMMENDED_VISION
    print_success "Vision model pulled!"
fi

# Image generation models (experimental, Ollama v0.14.3+)
echo ""
print_status "Image Generation (Experimental - Ollama v0.14.3+ required)"
echo "  Available models:"
echo "    1) x/flux2-klein - Fast image generation (Black Forest Labs)"
echo "    2) x/z-image-turbo - Photorealistic images (Alibaba Tongyi Lab)"
echo ""
read -p "Do you want to pull an image generation model? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Select model:"
    echo "  1) x/flux2-klein (recommended, faster)"
    echo "  2) x/z-image-turbo (photorealistic)"
    read -p "Enter choice [1/2]: " -n 1 -r IMG_CHOICE
    echo
    case $IMG_CHOICE in
        1)
            print_status "Pulling x/flux2-klein..."
            ollama pull x/flux2-klein
            RECOMMENDED_T2I="x/flux2-klein"
            print_success "Image generation model pulled!"
            ;;
        2)
            print_status "Pulling x/z-image-turbo..."
            ollama pull x/z-image-turbo
            RECOMMENDED_T2I="x/z-image-turbo"
            print_success "Image generation model pulled!"
            ;;
        *)
            print_warning "Skipping image generation model"
            ;;
    esac
fi

# Step 5: Install Python dependencies
echo ""
print_status "Installing Python dependencies for local operation..."

# Check if we're in a virtual environment
if [[ -z "$VIRTUAL_ENV" ]]; then
    print_warning "No virtual environment detected. It's recommended to use a virtual environment."
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please create and activate a virtual environment first:"
        echo "  python -m venv venv"
        echo "  source venv/bin/activate"
        exit 1
    fi
fi

# Install dependencies for local operation
pip install duckduckgo-search pymupdf4llm

print_success "Python dependencies installed!"

# Step 6: Copy configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_SOURCE="$PROJECT_ROOT/deeppresenter/deeppresenter/config.ollama.yaml"
CONFIG_DEST="$PROJECT_ROOT/deeppresenter/deeppresenter/config.yaml"

echo ""
print_status "Setting up configuration..."

if [ -f "$CONFIG_DEST" ]; then
    read -p "config.yaml already exists. Overwrite with Ollama config? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$CONFIG_SOURCE" "$CONFIG_DEST"
        print_success "Configuration updated with Ollama settings"
    else
        print_warning "Keeping existing configuration"
    fi
else
    cp "$CONFIG_SOURCE" "$CONFIG_DEST"
    print_success "Ollama configuration created"
fi

# Step 7: Update config with correct model names
if [ -f "$CONFIG_DEST" ]; then
    # Update model names based on what was pulled
    sed -i '' "s/model: \"llama3.2\"/model: \"$RECOMMENDED_LLM\"/g" "$CONFIG_DEST"
    sed -i '' "s/model: \"llava\"/model: \"$RECOMMENDED_VISION\"/g" "$CONFIG_DEST"
    print_success "Configuration updated with recommended models"
fi

# Step 8: Set environment variables
echo ""
print_status "Environment variable setup..."
echo ""
echo "Add these environment variables to your shell profile (~/.zshrc or ~/.bashrc):"
echo ""
echo "  # PPTAgent Ollama Configuration"
echo "  export PPTAGENT_OFFLINE_MODE=true"
echo "  export USE_LOCAL_PDF_PARSER=true"
echo "  export PPTAGENT_MODEL=$RECOMMENDED_LLM"
echo "  export PPTAGENT_API_BASE=http://localhost:11434/v1"
echo "  export PPTAGENT_API_KEY=ollama"
echo ""

# Offer to add to shell profile
read -p "Add these to your ~/.zshrc automatically? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "" >> ~/.zshrc
    echo "# PPTAgent Ollama Configuration" >> ~/.zshrc
    echo "export PPTAGENT_OFFLINE_MODE=true" >> ~/.zshrc
    echo "export USE_LOCAL_PDF_PARSER=true" >> ~/.zshrc
    echo "export PPTAGENT_MODEL=$RECOMMENDED_LLM" >> ~/.zshrc
    echo "export PPTAGENT_API_BASE=http://localhost:11434/v1" >> ~/.zshrc
    echo "export PPTAGENT_API_KEY=ollama" >> ~/.zshrc
    print_success "Environment variables added to ~/.zshrc"
    echo "Run 'source ~/.zshrc' to apply changes"
fi

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
print_success "PPTAgent is now configured to run locally with Ollama!"
echo ""
echo "To start using PPTAgent:"
echo "  1. Make sure Ollama is running: ollama serve"
echo "  2. Run the web UI: python webui.py"
echo "  3. Or use the MCP server for integration"
echo ""
echo "Available models on your system:"
ollama list
echo ""
print_status "For more options, edit: $CONFIG_DEST"
echo ""
