#!/bin/bash
# Copyright (C) 2026 M.Angel Juan <m.angel.juan@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script using sudo or as root."
    exit 1
fi

BASE_DIR="/opt/ai/krita"
PLUG_DIR="$BASE_DIR/plugin"
PATH_FLAT="/share/krita/pykrita"
VENV_DIR="$BASE_DIR/venv"
COMFY_DIR="$BASE_DIR/ComfyUI"
GLOBAL_CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
MODELS_DIR="$BASE_DIR/models"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

VENV_DEPS="torch torchvision torchaudio"
PIP_EXTRA="https://download.pytorch.org/whl/cpu"

FL_NAME="org.kde.krita"
KRITA_CONF_REL=".var/app/org.kde.krita/config"
KRITARC_NAME="kritarc"

PLUGIN_REPO="Acly/krita-ai-diffusion"
COMFYUI_REPO="comfyanonymous/ComfyUI"
UV_VERSION="0.9.26"

DECOMPRESS_DIR=""

download_plugin() {
    echo ">>> Downloading plugin from GitHub..."
    
    local api_url="https://api.github.com/repos/$PLUGIN_REPO/releases/latest"
    local tmpdir
    tmpdir=$(mktemp -d /tmp/krita_plugin_XXXXXX)
    
    echo "Checking latest version..."
    local download_url
    download_url=$(curl -sL -H "User-Agent: Linux" "$api_url" | jq -r '.assets[0].browser_download_url')
    local filename
    filename=$(basename "$download_url")
    
    echo "Downloading $filename..."
    curl -L -# -o "$tmpdir/$filename" "$download_url"
    
    echo "Decompressing..."
    mkdir -p "$tmpdir/decompressed"
    unzip -qo "$tmpdir/$filename" -d "$tmpdir/decompressed"
    rm -f "$tmpdir/$filename"
    
    DECOMPRESS_DIR="$tmpdir/decompressed"
}

install_comfyui() {
    if [ -d "$COMFY_DIR/.git" ]; then
        echo ">>> ComfyUI already downloaded at $COMFY_DIR. Skipping download."
        return
    fi

    if [ -d "$COMFY_DIR" ]; then
        echo ">>> ComfyUI directory exists but is incomplete (missing .git)."
        local model_backup="/tmp/krita_comfyui_models_backup"
        if [ -d "$COMFY_DIR/models" ] && [ "$(ls -A "$COMFY_DIR/models" 2>/dev/null)" ]; then
            echo ">>> Preserving downloaded models..."
            mkdir -p "$model_backup"
            mv "$COMFY_DIR/models" "$model_backup/"
        fi
        rm -rf "$COMFY_DIR"
        echo ">>> Downloading ComfyUI engine..."
        git clone "https://github.com/$COMFYUI_REPO.git" "$COMFY_DIR"
        if [ -d "$model_backup/models" ]; then
            echo ">>> Restoring preserved models..."
            rm -rf "$COMFY_DIR/models"
            mv "$model_backup/models" "$COMFY_DIR/"
            rm -rf "$model_backup"
        fi
        return
    fi

    echo ">>> Downloading ComfyUI engine..."
    git clone "https://github.com/$COMFYUI_REPO.git" "$COMFY_DIR"
}

download_models() {
    local checkpoint="$COMFY_DIR/models/diffusion_models/flux-2-klein-4b-Q6_K.gguf"
    
    if [ -f "$checkpoint" ]; then
        echo ">>> Flux2 models already downloaded. Skipping download."
        return
    fi
    
    echo ">>> Downloading Flux2 models and checkpoints (~8 GB, this may take a while)..."
    local dl_venv="/tmp/dl_venv_krita"
    python3 -m venv --clear "$dl_venv"
    "$dl_venv/bin/pip" install --no-cache-dir aiohttp tqdm
    
    echo ">>> Starting file download..."
    "$dl_venv/bin/python3" \
        "$PLUG_DIR/$PATH_FLAT/ai_diffusion/download_models.py" \
        "$COMFY_DIR" \
        --flux2 \
        --checkpoints \
        --backend cpu \
        --verbose \
        --retry-attempts 10 \
        --continue-on-error \
        --jobs 4
    local exit_code=$?
    rm -rf "$dl_venv"
    
    if [ $exit_code -ne 0 ]; then
        echo ">>> WARNING: Model download had errors (code $exit_code)."
        echo ">>> You can download them from the plugin (Settings > Server > Install)."
    else
        echo ">>> Models downloaded successfully."
    fi
}

patch_plugin() {
    echo ">>> Applying patches to plugin..."
    
    local plug_root="$PLUG_DIR/$PATH_FLAT/ai_diffusion"
    local root_py="$plug_root/model/root.py"
    local server_py="$plug_root/backend/server.py"
    local init_py="$plug_root/__init__.py"
    local model_py="$plug_root/model/model.py"
    
    if [ ! -f "$init_py" ]; then
        echo ">>> Plugin __init__.py not found at $init_py. Skipping patches."
        return
    fi
    
    sed -i 's|and self._server.state is ServerState.stopped|and self._server.state in [ServerState.stopped, ServerState.missing_resources]|' "$root_py"
    sed -i 's|if text.startswith("To see the GUI go to:")|if "To see the GUI go to:" in text|' "$server_py"
    
    rm -f "$plug_root"/styles/anime*.json \
          "$plug_root"/styles/anima.json \
          "$plug_root"/styles/chroma*.json \
          "$plug_root"/styles/cinematic*.json \
          "$plug_root"/styles/digital*.json \
          "$plug_root"/styles/ernie*.json \
          "$plug_root"/styles/flux.json \
          "$plug_root"/styles/flux-*.json 
    
    if ! grep -qF "_KRITA_AI_PATCH_V6" "$init_py" 2>/dev/null; then
        # ── Strip any old patch blocks from previous installer versions ──
        python3 "$SCRIPTS_DIR/patch_cleanup.py" "$init_py" 2>/dev/null || true

        # ── Inject new init patch code (settings + docker) ──
        sed "s|REPLACE_ME_BASE_DIR|$BASE_DIR|g" "$SCRIPTS_DIR/patch_init.py" > /tmp/patch_init_final.py
        cat /tmp/patch_init_final.py "$init_py" > /tmp/final_temp.py
        mv /tmp/final_temp.py "$init_py"
        rm -f /tmp/patch_init_final.py
    fi

    # ── Inject NSFW prompt filter via helper module + minimal model.py edits ──
    if [ ! -f "$model_py" ]; then
        echo ">>> model.py not found at $model_py. Skipping NSFW patch."
        return
    fi

    local nsfw_filter_py="$plug_root/model/nsfw_filter.py"

    sed "s|REPLACE_ME_BASE_DIR|$BASE_DIR|g" "$SCRIPTS_DIR/nsfw_filter.py" > "$nsfw_filter_py"
    chmod 644 "$nsfw_filter_py"
    echo ">>> nsfw_filter.py installed."

    python3 "$SCRIPTS_DIR/patch_model.py" "$model_py" 2>/dev/null || {
        echo ">>> WARNING: Failed to apply NSFW patch to model.py"
    }
}

install_plugin() {
    if [ -d "$PLUG_DIR/$PATH_FLAT/ai_diffusion" ] && [ -f "$PLUG_DIR/$PATH_FLAT/ai_diffusion.desktop" ]; then
        echo ">>> Plugin already installed. Skipping download."
        return
    fi
    
    download_plugin
    
    echo ">>> Moving plugin to its directory..."
    mkdir -p "$PLUG_DIR/$PATH_FLAT"
    mkdir -p "$VENV_DIR"
    
    if [ -d "$PLUG_DIR/$PATH_FLAT/ai_diffusion" ]; then
        echo "Removing previous plugin installation..."
        rm -rf "$PLUG_DIR/$PATH_FLAT/ai_diffusion"
        rm -f "$PLUG_DIR/$PATH_FLAT/ai_diffusion.desktop"
    fi
    
    mv "$DECOMPRESS_DIR"/ai_diffusion* "$PLUG_DIR/$PATH_FLAT/"
    rm -rf "$DECOMPRESS_DIR" "$(dirname "$DECOMPRESS_DIR")" 2>/dev/null || true
    
    local desktop_file="$PLUG_DIR/$PATH_FLAT/ai_diffusion.desktop"
    if [ -f "$desktop_file" ] && ! grep -qF "X-KDE-PluginInfo-EnabledByDefault" "$desktop_file"; then
        echo ">>> Enabling plugin by default in .desktop..."
        sed -i '/^\[Desktop Entry\]/a X-KDE-PluginInfo-EnabledByDefault=true' "$desktop_file"
    fi
    
    chmod -R 755 "$PLUG_DIR"
}

install_custom_node() {
    local name="$1" folder="$2" url="$3" commit="$4"
    local custom_nodes_dir="$COMFY_DIR/custom_nodes"
    
    if [ -d "$custom_nodes_dir/$folder" ]; then
        echo "  [OK] $name already installed."
        return 0
    fi
    
    echo "  Downloading $name..."
    local zip_path="$COMFY_DIR/downloads/${folder}.zip"
    mkdir -p "$(dirname "$zip_path")"
    curl -fL --retry 5 -o "$zip_path" "${url}/archive/${commit}.zip" || {
        echo "  [ERROR] Failed to download $name"
        return 1
    }
    unzip -qo "$zip_path" -d "$custom_nodes_dir/"
    rm -f "$zip_path"
    
    local extracted="$custom_nodes_dir/${folder}-${commit}"
    if [ -d "$extracted" ]; then
        mv "$extracted" "$custom_nodes_dir/$folder"
    fi
    echo "  [OK] $name installed."
}

install_custom_nodes() {
    echo ">>> Installing ComfyUI custom nodes..."
    mkdir -p "$COMFY_DIR/custom_nodes"
    
    install_custom_node "ControlNet Preprocessors" "comfyui_controlnet_aux" \
        "https://github.com/Fannovel16/comfyui_controlnet_aux" \
        "83463c2e4b04e729268e57f638b4212e0da4badc" || true
    install_custom_node "IP-Adapter" "ComfyUI_IPAdapter_plus" \
        "https://github.com/cubiq/ComfyUI_IPAdapter_plus" \
        "b188a6cb39b512a9c6da7235b880af42c78ccd0d" || true
    install_custom_node "External Tooling Nodes" "comfyui-tooling-nodes" \
        "https://github.com/Acly/comfyui-tooling-nodes" \
        "a1e51904dec9a73b92865b512aa417f10938d608" || true
    install_custom_node "Inpaint Nodes" "comfyui-inpaint-nodes" \
        "https://github.com/Acly/comfyui-inpaint-nodes" \
        "12937559e1aea4bb073e9e82f915d1dab92f248b" || true
    install_custom_node "GGUF" "ComfyUI-GGUF" \
        "https://github.com/city96/ComfyUI-GGUF" \
        "01f8845bf30d89fff293c7bd50187bc59d9d53ea" || true
    
    echo ">>> Custom nodes ready."
}

setup_flatpak_overrides() {
    echo ">>> Linking directories with Flatpak container..."
    flatpak override --system --filesystem="$PLUG_DIR" "$FL_NAME"
    flatpak override --system --filesystem="$VENV_DIR" "$FL_NAME"
    flatpak override --system --filesystem="$COMFY_DIR" "$FL_NAME"
    flatpak override --system --filesystem="$GLOBAL_CONFIG_DIR:ro" "$FL_NAME"
    flatpak override --system --filesystem="$LOG_DIR" "$FL_NAME"
    flatpak override --system --filesystem="$MODELS_DIR" "$FL_NAME"
    flatpak override --system --env="XDG_DATA_DIRS=/app/share:/usr/share:$PLUG_DIR/share" "$FL_NAME"
    flatpak override --system --env="XDG_CONFIG_DIRS=$GLOBAL_CONFIG_DIR:/etc/xdg" "$FL_NAME"
}

VENV_HASH_FILE="$VENV_DIR/.venv_deps_hash"

compute_venv_hash() {
    echo "v3 $VENV_DEPS $PIP_EXTRA transformers optimum onnxruntime numpy aiohttp tqdm" | sha256sum | cut -d' ' -f1
}

install_custom_nodes_deps() {
    echo ">>> Installing custom nodes dependencies..."
    local custom_nodes_dir="$COMFY_DIR/custom_nodes"
    if [ -d "$custom_nodes_dir" ]; then
        for node_dir in "$custom_nodes_dir"/*/; do
            [ -d "$node_dir" ] || continue
            local req_file="${node_dir}requirements.txt"
            if [ -f "$req_file" ]; then
                local node_name
                node_name=$(basename "$node_dir")
                echo "  Installing dependencies for $node_name..."
                flatpak run --command=bash "$FL_NAME" -c "
                    export PIP_NO_CACHE_DIR=1
                    export UV_NO_CACHE=1
                    source $VENV_DIR/bin/activate && \
                    uv pip install --no-cache --only-binary :all: opencv-python-headless scipy scikit-image && \
                    uv pip install --no-cache -r '$req_file' 2>/dev/null || true
                " || echo "  [WARNING] Failed installing dependencies for $node_name"
            fi
        done
    fi
    echo ">>> Custom nodes dependencies ready."
}

setup_venv() {
    local expected_hash
    expected_hash=$(compute_venv_hash)

    if [ -f "$VENV_HASH_FILE" ] && [ "$(cat "$VENV_HASH_FILE")" = "$expected_hash" ]; then
        echo ">>> Venv dependencies verified. Skipping package installation."
        return
    fi

    if [ ! -d "$VENV_DIR/bin" ]; then
        echo ">>> Setting up Python virtual environment and downloading libraries..."
        flatpak run --command=python3 "$FL_NAME" -m venv --clear "$VENV_DIR"
        flatpak run --command=bash "$FL_NAME" -c "
            export PIP_NO_CACHE_DIR=1
            export UV_NO_CACHE=1
            source $VENV_DIR/bin/activate && \
            python3 -m pip install --no-cache-dir --upgrade pip uv && \
            uv pip install --no-cache $VENV_DEPS --extra-index-url $PIP_EXTRA && \
            uv pip install --no-cache -r $COMFY_DIR/requirements.txt && \
            uv pip install --no-cache aiohttp tqdm numpy transformers optimum[onnxruntime]
        "
        install_custom_nodes_deps
        echo "$expected_hash" > "$VENV_HASH_FILE"
        return
    fi

    echo ">>> Venv exists. Verifying critical dependencies..."
    flatpak run --command=bash "$FL_NAME" -c "
        export PIP_NO_CACHE_DIR=1
        export UV_NO_CACHE=1
        source $VENV_DIR/bin/activate
        python3 -m pip install --no-cache-dir --upgrade pip uv 2>/dev/null
        if ! python3 -c 'import torch, torchvision, torchaudio' 2>/dev/null; then
            echo '[INSTALL] torch'
            uv pip install --no-cache $VENV_DEPS --extra-index-url $PIP_EXTRA
        fi
        if ! python3 -c 'import optimum.onnxruntime, transformers' 2>/dev/null; then
            echo '[INSTALL] optimum transformers onnxruntime'
            uv pip install --no-cache transformers optimum[onnxruntime]
        fi
        if ! python3 -c 'import aiohttp, tqdm' 2>/dev/null; then
            echo '[INSTALL] aiohttp tqdm'
            uv pip install --no-cache aiohttp tqdm
        fi
        if ! python3 -c 'import numpy' 2>/dev/null; then
            echo '[INSTALL] numpy'
            uv pip install --no-cache numpy
        fi
    "

    install_custom_nodes_deps
    echo "$expected_hash" > "$VENV_HASH_FILE"
}

install_uv() {
    if [ -f "$BASE_DIR/uv/uv" ]; then
        return
    fi
    
    echo ">>> Installing uv (standalone package manager)..."
    curl -LsSf "https://astral.sh/uv/$UV_VERSION/install.sh" | env UV_UNMANAGED_INSTALL="$BASE_DIR/uv" UV_NO_CACHE=1 sh
}

set_permissions() {
    echo ">>> Adjusting security permissions..."
    chmod -R 777 "$VENV_DIR"
    chmod -R 777 "$COMFY_DIR"
    mkdir -p "$LOG_DIR"
    chmod -R 777 "$LOG_DIR"
}

convert_nsfw_model() {
    local onnx_dir="$BASE_DIR/models/nsfw_onnx"
    local model_id="unitary/multilingual-toxic-xlm-roberta"

    if [ -f "$onnx_dir/model.onnx" ]; then
        echo ">>> ONNX NSFW model already exists. Skipping conversion."
        return
    fi

    echo ">>> Converting NSFW model to ONNX INT8 (~250 MB, one-time)..."
    mkdir -p "$onnx_dir"

    cp "$SCRIPTS_DIR/convert_nsfw_model.py" "$MODELS_DIR/convert_nsfw_model.py"
    flatpak run --command=bash "$FL_NAME" -c "
        export PIP_NO_CACHE_DIR=1
        export UV_NO_CACHE=1
        source $VENV_DIR/bin/activate
        python3 $MODELS_DIR/convert_nsfw_model.py '$model_id' '$onnx_dir'
    "
    rm -f "$MODELS_DIR/convert_nsfw_model.py"

    chmod -R 755 "$onnx_dir"
    echo ">>> ONNX NSFW model ready at $onnx_dir"
}

enable_plugin_in_kritarc() {
    local kritarc="$1"
    
    if [ ! -f "$kritarc" ]; then
        printf '[python]\nenable_ai_diffusion=true\n' > "$kritarc"
        return
    fi
    
    if grep -qF "enable_ai_diffusion=true" "$kritarc" 2>/dev/null; then
        return
    fi
    
    if grep -qF "[python]" "$kritarc" 2>/dev/null; then
        sed -i '/^\[python\]/a enable_ai_diffusion=true' "$kritarc"
    else
        printf '\n[python]\nenable_ai_diffusion=true\n' >> "$kritarc"
    fi
}

setup_global_config() {
    echo ">>> Setting up global Krita configuration..."
    mkdir -p "$GLOBAL_CONFIG_DIR"
    enable_plugin_in_kritarc "$GLOBAL_CONFIG_DIR/$KRITARC_NAME"

    local skel_krita="/etc/skel/$KRITA_CONF_REL"
    mkdir -p "$skel_krita"
    enable_plugin_in_kritarc "$skel_krita/$KRITARC_NAME"
}

do_install() {
    echo ">>> Starting Krita AI Diffusion installation (CPU Mode)..."
    
    install_plugin
    patch_plugin
    install_comfyui
    install_custom_nodes
    setup_flatpak_overrides
    setup_venv
    convert_nsfw_model
    install_uv
    
    echo ">>> Creating server version file..."
    echo "1.51.0 cpu" > "$BASE_DIR/.version"
    
    set_permissions
    download_models
    setup_global_config
    
    echo ">>> Installation completed successfully!"
}

cleanup_user_configs() {
    echo ">>> Cleaning up user configurations..."
    rm -rf "$GLOBAL_CONFIG_DIR"

    local skel_kritarc="/etc/skel/.var/app/org.kde.krita/config/kritarc"
    if [ -f "$skel_kritarc" ]; then
        sed -i '/^enable_ai_diffusion=true/d' "$skel_kritarc"
    fi
}

reset_flatpak_overrides() {
    echo ">>> Resetting Flatpak permissions..."
    flatpak override --system --reset "$FL_NAME" 2>/dev/null || {
        flatpak override --system --nofilesystem="$PLUG_DIR" "$FL_NAME"
        flatpak override --system --nofilesystem="$VENV_DIR" "$FL_NAME"
        flatpak override --system --nofilesystem="$COMFY_DIR" "$FL_NAME"
        flatpak override --system --nofilesystem="$GLOBAL_CONFIG_DIR" "$FL_NAME"
        flatpak override --system --nofilesystem="$LOG_DIR" "$FL_NAME"
        flatpak override --system --nofilesystem="$MODELS_DIR" "$FL_NAME"
        flatpak override --system --unset-env=XDG_DATA_DIRS "$FL_NAME"
        flatpak override --system --unset-env=XDG_CONFIG_DIRS "$FL_NAME"
    }
}

do_uninstall() {
    echo ">>> Starting uninstallation (keeping downloaded models)..."

    if [ -d "$BASE_DIR" ]; then
        echo ">>> Removing Krita AI components..."
        rm -rf "$PLUG_DIR"
        rm -rf "$VENV_DIR"
        rm -rf "$GLOBAL_CONFIG_DIR"
        rm -rf "$LOG_DIR"
        rm -rf "$MODELS_DIR"
        rm -rf "$BASE_DIR/uv"
        rm -f "$BASE_DIR/.version"
        if [ -d "$COMFY_DIR" ]; then
            find "$COMFY_DIR" -mindepth 1 -maxdepth 1 ! -name models -exec rm -rf {} +
        fi
    fi

    cleanup_user_configs
    reset_flatpak_overrides
    rm -rf /tmp/dl_venv_krita 2>/dev/null

    echo ">>> Uninstallation completed. Models preserved at $COMFY_DIR/models/."
}

do_uninstall_purge() {
    echo ">>> Starting uninstallation (purging all data)..."

    if [ -d "$BASE_DIR" ]; then
        echo ">>> Removing all data in $BASE_DIR..."
        rm -rf "$BASE_DIR"
    fi

    cleanup_user_configs
    reset_flatpak_overrides
    rm -rf /tmp/dl_venv_krita 2>/dev/null

    echo ">>> Uninstallation completed and system clean."
}

usage() {
    echo "Usage: sudo $0 {install|uninstall|purge}"
    echo ""
    echo "Commands:"
    echo "  install   - Downloads ComfyUI, the plugin and sets up CPU environment"
    echo "  uninstall - Removes all components but keeps downloaded models (~8 GB)"
    echo "  purge     - Removes everything including models (full cleanup)"
}

case "$1" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    purge)
        do_uninstall_purge
        ;;
    *)
        usage
        exit 1
        ;;
esac
