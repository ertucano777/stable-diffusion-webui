#!/usr/bin/env bash
set -euo pipefail

# Bootstraps a local Stable Diffusion WebUI installation.
# This script creates a virtual environment, installs dependencies, optionally
# downloads a Stable Diffusion model checkpoint, and can run a one-off startup
# smoke test of the WebUI.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-$PROJECT_ROOT/venv}"
REPOS_DIR="${REPOS_DIR:-$PROJECT_ROOT/repositories}"
MODEL_DIR="${MODEL_DIR:-$PROJECT_ROOT/models/Stable-diffusion}"
MODEL_URL="${MODEL_URL:-}"
MODEL_FILENAME="${MODEL_FILENAME:-}"
RUN_WEBUI="${RUN_WEBUI:-0}"
EXTRA_REQUIREMENTS_FILE="${EXTRA_REQUIREMENTS_FILE:-requirements_versions.txt}"

log() {
    echo "[bootstrap] $*"
}

ensure_python() {
    if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
        echo "Python interpreter '$PYTHON_BIN' not found." >&2
        echo "Set PYTHON_BIN to point to a valid Python 3 interpreter." >&2
        exit 1
    fi
}

ensure_git() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git is required to clone WebUI repositories." >&2
        exit 1
    fi
}

create_venv() {
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        log "Creating virtual environment in $VENV_DIR"
        "$PYTHON_BIN" -m venv "$VENV_DIR"
    else
        log "Virtual environment already exists at $VENV_DIR"
    fi
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
}

install_requirements() {
    log "Upgrading pip tooling"
    python -m pip install --upgrade pip setuptools wheel

    log "Installing core requirements"
    python -m pip install -r requirements.txt

    if [ -f "$PROJECT_ROOT/$EXTRA_REQUIREMENTS_FILE" ]; then
        log "Installing additional requirements from $EXTRA_REQUIREMENTS_FILE"
        python -m pip install -r "$PROJECT_ROOT/$EXTRA_REQUIREMENTS_FILE"
    else
        log "No additional requirements file found at $EXTRA_REQUIREMENTS_FILE; skipping"
    fi
}

sync_repositories() {
    mkdir -p "$REPOS_DIR"

    # name=url
    local repos=(
        "stable-diffusion-stability-ai=https://github.com/Stability-AI/stablediffusion.git"
        "taming-transformers=https://github.com/CompVis/taming-transformers.git"
        "k-diffusion=https://github.com/crowsonkb/k-diffusion.git"
        "CodeFormer=https://github.com/sczhou/CodeFormer.git"
        "BLIP=https://github.com/salesforce/BLIP.git"
        "clip=https://github.com/openai/CLIP.git"
        "generative-models=https://github.com/Stability-AI/generative-models.git"
    )

    for repo_def in "${repos[@]}"; do
        local name="${repo_def%%=*}"
        local url="${repo_def#*=}"
        local target="$REPOS_DIR/$name"

        if [ -d "$target/.git" ]; then
            log "Repository $name already present; skipping clone"
            continue
        fi

        log "Cloning $name from $url"
        git clone --depth 1 "$url" "$target"
    done
}

download_model() {
    if [ -z "$MODEL_URL" ]; then
        log "MODEL_URL not provided; skipping model download"
        return 0
    fi

    mkdir -p "$MODEL_DIR"

    local target_name
    if [ -n "$MODEL_FILENAME" ]; then
        target_name="$MODEL_FILENAME"
    else
        target_name="$(basename "$MODEL_URL")"
    fi

    local target_path="$MODEL_DIR/$target_name"
    if [ -f "$target_path" ]; then
        log "Model already present at $target_path; skipping download"
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        log "Downloading model from $MODEL_URL"
        curl -L "$MODEL_URL" -o "$target_path"
    elif command -v wget >/dev/null 2>&1; then
        log "Downloading model from $MODEL_URL"
        wget -O "$target_path" "$MODEL_URL"
    else
        echo "Neither curl nor wget is available to download the model." >&2
        exit 1
    fi

    log "Model saved to $target_path"
}

run_smoke_test() {
    if [ "$RUN_WEBUI" -ne 1 ]; then
        log "RUN_WEBUI not set to 1; skipping WebUI startup test"
        return 0
    fi

    log "Starting WebUI smoke test (will exit after initialization)"
    python webui.py --skip-torch-cuda-test --exit
}

main() {
    ensure_python
    ensure_git
    create_venv
    sync_repositories
    install_requirements
    download_model
    run_smoke_test
    log "Bootstrap complete. Activate the environment with: source $VENV_DIR/bin/activate"
    log "Then start the WebUI with: python webui.py"
}

main "$@"
