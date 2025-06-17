#!/bin/bash

# OpenVoice Deployment Script for Ubuntu 22.04 with NVIDIA/CUDA 12.1
# This script automates the installation and setup of OpenVoice V1 and V2

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONDA_ENV_NAME="openvoice"
PYTHON_VERSION="3.9"
OPENVOICE_DIR="OpenVoice"
REPO_URL="https://github.com/myshell-ai/OpenVoice.git"

# Model download URLs
V1_CHECKPOINT_URL="https://myshell-public-repo-host.s3.amazonaws.com/openvoice/checkpoints_1226.zip"
V2_CHECKPOINT_URL="https://myshell-public-repo-host.s3.amazonaws.com/openvoice/checkpoints_v2_0417.zip"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Ubuntu 22.04
check_os() {
    log "Checking operating system..."
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$NAME" == "Ubuntu" && "$VERSION_ID" == "22.04" ]]; then
            log_success "Running on Ubuntu 22.04"
        else
            log_warning "Not running on Ubuntu 22.04. Current OS: $NAME $VERSION_ID"
            log_warning "Script may still work but is optimized for Ubuntu 22.04"
        fi
    else
        log_warning "Cannot determine OS version"
    fi
}

# Check CUDA installation
check_cuda() {
    log "Checking CUDA installation..."
    if command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]*\.[0-9]*\).*/\1/')
        log_success "CUDA $CUDA_VERSION detected"
        if [[ "$CUDA_VERSION" == "12.1" ]]; then
            log_success "CUDA 12.1 confirmed"
        else
            log_warning "Expected CUDA 12.1, found CUDA $CUDA_VERSION"
        fi
    else
        log_error "CUDA not found. Please install CUDA 12.1 first."
        exit 1
    fi
}

# Check if conda is installed
check_conda() {
    log "Checking for conda installation..."
    if command -v conda &> /dev/null; then
        CONDA_VERSION=$(conda --version)
        log_success "Found $CONDA_VERSION"
        return 0
    else
        log_warning "Conda not found"
        return 1
    fi
}

# Install miniconda
install_conda() {
    log "Installing Miniconda..."
    
    # Download miniconda installer
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    INSTALLER_PATH="/tmp/miniconda_installer.sh"
    
    log "Downloading Miniconda installer..."
    wget -q $MINICONDA_URL -O $INSTALLER_PATH
    
    # Make installer executable
    chmod +x $INSTALLER_PATH
    
    # Install miniconda
    log "Running Miniconda installer..."
    bash $INSTALLER_PATH -b -p $HOME/miniconda3
    
    # Initialize conda
    log "Initializing conda..."
    source $HOME/miniconda3/etc/profile.d/conda.sh
    conda init bash
    
    # Clean up
    rm $INSTALLER_PATH
    
    log_success "Miniconda installed successfully"
}

# Create conda environment
create_conda_env() {
    log "Creating conda environment: $CONDA_ENV_NAME"
    
    # Source conda
    source $HOME/miniconda3/etc/profile.d/conda.sh || source $(conda info --base)/etc/profile.d/conda.sh
    
    # Check if environment already exists
    if conda env list | grep -q "^$CONDA_ENV_NAME "; then
        log_warning "Environment $CONDA_ENV_NAME already exists"
        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Removing existing environment..."
            conda env remove -n $CONDA_ENV_NAME -y
        else
            log "Using existing environment"
            return 0
        fi
    fi
    
    # Create new environment
    log "Creating new conda environment with Python $PYTHON_VERSION..."
    conda create -n $CONDA_ENV_NAME python=$PYTHON_VERSION -y
    
    log_success "Conda environment created successfully"
}

# Install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Update package list
    sudo apt update
    
    # Install required packages
    sudo apt install -y \
        git \
        wget \
        unzip \
        build-essential \
        libsndfile1 \
        ffmpeg \
        espeak-ng \
        espeak-ng-data
    
    log_success "System dependencies installed"
}

# Clone OpenVoice repository
clone_repository() {
    log "Cloning OpenVoice repository..."
    
    if [[ -d "$OPENVOICE_DIR" ]]; then
        log_warning "OpenVoice directory already exists"
        read -p "Do you want to remove and re-clone it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf $OPENVOICE_DIR
        else
            log "Using existing repository"
            cd $OPENVOICE_DIR
            git pull origin main
            cd ..
            return 0
        fi
    fi
    
    git clone $REPO_URL $OPENVOICE_DIR
    log_success "Repository cloned successfully"
}

# Install OpenVoice dependencies
install_openvoice() {
    log "Installing OpenVoice dependencies..."
    
    # Source conda and activate environment
    source $HOME/miniconda3/etc/profile.d/conda.sh || source $(conda info --base)/etc/profile.d/conda.sh
    conda activate $CONDA_ENV_NAME
    
    # Navigate to OpenVoice directory
    cd $OPENVOICE_DIR
    
    # Install PyTorch with CUDA 12.1 support
    log "Installing PyTorch with CUDA 12.1 support..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    
    # Install OpenVoice
    log "Installing OpenVoice..."
    pip install -e .
    
    # Install MeloTTS for V2
    log "Installing MeloTTS for OpenVoice V2..."
    pip install git+https://github.com/myshell-ai/MeloTTS.git
    python -m unidic download
    
    cd ..
    log_success "OpenVoice dependencies installed successfully"
}

# Download model checkpoints
download_models() {
    log "Downloading model checkpoints..."
    
    cd $OPENVOICE_DIR
    
    # Download V1 checkpoints
    log "Downloading OpenVoice V1 checkpoints..."
    if [[ ! -d "checkpoints" ]]; then
        wget -q $V1_CHECKPOINT_URL -O checkpoints_v1.zip
        unzip -q checkpoints_v1.zip
        rm checkpoints_v1.zip
        log_success "V1 checkpoints downloaded and extracted"
    else
        log_warning "V1 checkpoints directory already exists"
    fi
    
    # Download V2 checkpoints
    log "Downloading OpenVoice V2 checkpoints..."
    if [[ ! -d "checkpoints_v2" ]]; then
        wget -q $V2_CHECKPOINT_URL -O checkpoints_v2.zip
        unzip -q checkpoints_v2.zip
        rm checkpoints_v2.zip
        log_success "V2 checkpoints downloaded and extracted"
    else
        log_warning "V2 checkpoints directory already exists"
    fi
    
    cd ..
}

# Test installation
test_installation() {
    log "Testing OpenVoice installation..."
    
    # Source conda and activate environment
    source $HOME/miniconda3/etc/profile.d/conda.sh || source $(conda info --base)/etc/profile.d/conda.sh
    conda activate $CONDA_ENV_NAME
    
    cd $OPENVOICE_DIR
    
    # Test Python imports
    python -c "
import torch
import openvoice
print(f'PyTorch version: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA version: {torch.version.cuda}')
    print(f'GPU count: {torch.cuda.device_count()}')
print('OpenVoice imported successfully!')
"
    
    cd ..
    log_success "Installation test completed successfully"
}

# Create launcher scripts
create_launchers() {
    log "Creating launcher scripts..."
    
    # Create gradio launcher
    cat > launch_gradio.sh << 'EOF'
#!/bin/bash
source $HOME/miniconda3/etc/profile.d/conda.sh || source $(conda info --base)/etc/profile.d/conda.sh
conda activate openvoice
cd OpenVoice
python -m openvoice_app --share
EOF
    
    # Create jupyter launcher
    cat > launch_jupyter.sh << 'EOF'
#!/bin/bash
source $HOME/miniconda3/etc/profile.d/conda.sh || source $(conda info --base)/etc/profile.d/conda.sh
conda activate openvoice
cd OpenVoice
jupyter notebook
EOF
    
    chmod +x launch_gradio.sh launch_jupyter.sh
    
    log_success "Launcher scripts created:"
    log "  - launch_gradio.sh: Start Gradio web interface"
    log "  - launch_jupyter.sh: Start Jupyter notebook for demos"
}

# Print usage instructions
print_usage() {
    echo
    log_success "OpenVoice deployment completed successfully!"
    echo
    echo -e "${GREEN}=== Usage Instructions ===${NC}"
    echo
    echo "1. Activate the conda environment:"
    echo "   conda activate $CONDA_ENV_NAME"
    echo
    echo "2. Navigate to OpenVoice directory:"
    echo "   cd $OPENVOICE_DIR"
    echo
    echo "3. Run demos:"
    echo "   - V1 Flexible Voice Control: jupyter notebook demo_part1.ipynb"
    echo "   - V1 Cross-Lingual Cloning: jupyter notebook demo_part2.ipynb"
    echo "   - V2 Demo: jupyter notebook demo_part3.ipynb"
    echo "   - Gradio Web Interface: python -m openvoice_app --share"
    echo
    echo "4. Or use the launcher scripts:"
    echo "   - ./launch_gradio.sh"
    echo "   - ./launch_jupyter.sh"
    echo
    echo -e "${YELLOW}=== Available Models ===${NC}"
    echo "- OpenVoice V1: checkpoints/ (flexible style control)"
    echo "- OpenVoice V2: checkpoints_v2/ (multi-language support)"
    echo
    echo -e "${BLUE}=== Supported Languages (V2) ===${NC}"
    echo "English, Spanish, French, Chinese, Japanese, Korean"
    echo
}

# Main deployment function
main() {
    echo
    echo -e "${BLUE}=== OpenVoice Deployment Script ===${NC}"
    echo -e "${BLUE}Target: NVIDIA/CUDA 12.1 Ubuntu 22.04${NC}"
    echo
    
    # Run checks and installations
    check_os
    check_cuda
    
    if ! check_conda; then
        install_conda
        # Source conda after installation
        source $HOME/miniconda3/etc/profile.d/conda.sh
    fi
    
    install_system_deps
    create_conda_env
    clone_repository
    install_openvoice
    download_models
    test_installation
    create_launchers
    print_usage
}

# Handle script arguments
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "OpenVoice Deployment Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --test-only    Only run installation test"
    echo "  --no-models    Skip model download"
    echo
    echo "This script will:"
    echo "1. Check system requirements (Ubuntu 22.04, CUDA 12.1)"
    echo "2. Install conda if not present"
    echo "3. Create OpenVoice conda environment"
    echo "4. Install system dependencies"
    echo "5. Clone OpenVoice repository"
    echo "6. Install OpenVoice and dependencies"
    echo "7. Download model checkpoints"
    echo "8. Test installation"
    echo "9. Create launcher scripts"
    exit 0
fi

if [[ "$1" == "--test-only" ]]; then
    test_installation
    exit 0
fi

if [[ "$1" == "--no-models" ]]; then
    # Run main without model download
    check_os
    check_cuda
    
    if ! check_conda; then
        install_conda
        source $HOME/miniconda3/etc/profile.d/conda.sh
    fi
    
    install_system_deps
    create_conda_env
    clone_repository
    install_openvoice
    test_installation
    create_launchers
    
    log_warning "Skipped model download. Run 'bash $0' without --no-models to download models."
    exit 0
fi

# Run main deployment
main