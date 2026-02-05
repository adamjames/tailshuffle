#!/usr/bin/env bash
# Tailshuffle.sh — Download Tailwind UI components and package them for Shuffle.dev
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="tailshuffle"
CONTAINER_NAME="tailshuffle-builder"
WORK_DIR="$SCRIPT_DIR/cache"
DOCKER_USER="--user $(id -u):$(id -g)"

# ── Helpers ──────────────────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
cyan()  { printf '\033[36m%s\033[0m' "$*"; }

step()  { printf '\n  %s %s\n' "$(cyan "[$1]")" "$(bold "$2")"; }
info()  { printf '        %s\n' "$*"; }
ok()    { printf '        %s %s\n' "$(green "✓")" "$*"; }
fail()  { printf '        %s %s\n' "$(red "✗")" "$*"; }

require() {
    local check="$1" prereq="$2" msg="$3"
    if ! eval "$check" &>/dev/null; then
        fail "$msg"
        if confirm "Run '$0 $prereq' first?"; then
            info ""
            "stage_$prereq"
        else
            exit 1
        fi
    fi
}

ask() {
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        printf '        %s [%s]: ' "$prompt" "$default"
    else
        printf '        %s: ' "$prompt"
    fi
    read -r REPLY
    [ -z "$REPLY" ] && REPLY="$default"
}

confirm() {
    printf '        %s [Y/n] ' "$1"
    read -r REPLY
    case "$REPLY" in
        [nN]*) return 1 ;;
        *)     return 0 ;;
    esac
}

# ── Stages ───────────────────────────────────────────────────────────

stage_prerequisites() {
    step "1/5" "Checking prerequisites"

    if command -v podman &>/dev/null; then
        DOCKER=podman
    elif command -v docker &>/dev/null; then
        DOCKER=docker
    else
        fail "Neither podman nor docker is installed."
        info "Install one of them:"
        info "  Podman:  https://podman.io/getting-started/installation"
        info "  Docker:  https://docs.docker.com/get-docker/"
        exit 1
    fi
    ok "$DOCKER is installed"

    if ! $DOCKER info &>/dev/null; then
        fail "$DOCKER daemon is not running."
        info "Start $DOCKER and try again."
        exit 1
    fi
    ok "$DOCKER daemon is running"
}

stage_credentials() {
    step "2/5" "Tailwind UI credentials"

    setup_env() {
        info "You need an active Tailwind UI subscription."
        info "Credentials are stored locally in .env and never leave this machine."
        echo ""

        ask "Tailwind UI email"
        local email="$REPLY"
        printf '        %s: ' "Tailwind UI password"
        read -rs REPLY
        echo ""
        local password="$REPLY"

        cat > .env <<EOF
EMAIL=$email
PASSWORD=$password
OUTPUT=/app/output
LANGUAGES=html
COMPONENTS=all
BUILDINDEX=0
TEMPLATES=0
EOF

        echo ""
        ok "Credentials saved to .env"
    }

    if [ -f .env ] && grep -q '^EMAIL=.' .env && grep -q '^PASSWORD=.' .env \
       && ! grep -q '^EMAIL=your-tailwindui-email@example.com' .env; then
        ok "Using existing credentials ($(grep '^EMAIL=' .env | cut -d= -f2-))"
        if ! confirm "Continue with these?"; then
            setup_env
        fi
    else
        if [ -f .env ]; then
            info "Existing .env is incomplete or has placeholder values."
        else
            info "No .env file found."
        fi
        setup_env
    fi

    # Component selection
    info ""
    info "Which component categories do you want?"
    info ""
    info "  1) $(bold "all")              – everything"
    info "  2) $(bold "application-ui")   – dashboards, forms, navigation, etc."
    info "  3) $(bold "marketing")        – landing pages, heroes, pricing, etc."
    info "  4) $(bold "ecommerce")        – product pages, carts, checkout, etc."
    info ""
    ask "Choose categories (comma-separated, e.g. 2,3)" "1"

    case "$REPLY" in
        1|all)                  components="all" ;;
        2|application-ui)       components="application-ui" ;;
        3|marketing)            components="marketing" ;;
        4|ecommerce)            components="ecommerce" ;;
        *)
            components=""
            IFS=',' read -ra picks <<< "$REPLY"
            for p in "${picks[@]}"; do
                p=$(echo "$p" | tr -d ' ')
                case "$p" in
                    1|all)            components="all"; break ;;
                    2|application-ui) components="${components:+$components,}application-ui" ;;
                    3|marketing)      components="${components:+$components,}marketing" ;;
                    4|ecommerce)      components="${components:+$components,}ecommerce" ;;
                    *) fail "Unknown option: $p"; exit 1 ;;
                esac
            done
            ;;
    esac

    sed -i "s/^COMPONENTS=.*/COMPONENTS=$components/" .env
    ok "Components: $components"
}

stage_build() {
    step "3/5" "Building Docker image"

    $DOCKER rm -f "$CONTAINER_NAME" 2>/dev/null || true
    mkdir -p "$WORK_DIR"

    cmd="$DOCKER build -t $IMAGE_NAME ."
    info "$(dim "\$ $cmd")"
    eval "$cmd" 2>&1 | while IFS= read -r line; do info "$(dim "$line")"; done
    ok "Docker image ready"
}

stage_download() {
    step "4/5" "Downloading Tailwind UI components"

    require "$DOCKER image inspect $IMAGE_NAME" build "Docker image '$IMAGE_NAME' not found"
    $DOCKER rm -f "$CONTAINER_NAME" 2>/dev/null || true

    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        stage_credentials
    fi

    info "This may take several minutes on first run..."
    echo ""
    cmd="$DOCKER run --name $CONTAINER_NAME $DOCKER_USER -e HOME=/tmp \\
          -v $SCRIPT_DIR/.env:/app/tailwindui-crawler/.env:ro \\
          -v $WORK_DIR:/app/output \\
          $IMAGE_NAME sh -c 'cd tailwindui-crawler && npm start'"
    info "$(dim "\$ $cmd")"
    eval "$cmd" 2>&1 | while IFS= read -r line; do info "$(dim "$line")"; done
    ok "Components downloaded to ./cache/"
}

stage_convert() {
    step "5a" "Converting to Shuffle.dev format"

    require "$DOCKER image inspect $IMAGE_NAME" build "Docker image '$IMAGE_NAME' not found"
    require "test -d $WORK_DIR/html" download "No cached components found"

    rm -rf "$SCRIPT_DIR/output"
    mkdir "$SCRIPT_DIR/output"

    cmd="$DOCKER run --rm $DOCKER_USER -e HOME=/tmp \\
          -v $WORK_DIR/html/ui-blocks:/app/input:ro \\
          -v $SCRIPT_DIR/output:/app/output \\
          -w /app \\
          $IMAGE_NAME shuffle-package-maker /app/input --preset=tailwindui"
    info "$(dim "\$ $cmd")"
    eval "$cmd" 2>&1 | while IFS= read -r line; do info "$(dim "$line")"; done
    ok "Conversion complete"
}

stage_catalog() {
    step "5b" "Generating component catalog (LLM context)"

    require "$DOCKER image inspect $IMAGE_NAME" build "Docker image '$IMAGE_NAME' not found"
    require "test -d $SCRIPT_DIR/output/components" convert "No output found"

    cmd="$DOCKER run --rm $DOCKER_USER -e HOME=/tmp \\
          -v $SCRIPT_DIR:/app/dist -w /app/dist \\
          $IMAGE_NAME node catalog.mjs"
    info "$(dim "\$ $cmd")"
    eval "$cmd" 2>&1 | while IFS= read -r line; do info "$(dim "$line")"; done
    ok "Written to components-catalog.json"
}

stage_package() {
    step "5c" "Packaging"

    require "$DOCKER image inspect $IMAGE_NAME" build "Docker image '$IMAGE_NAME' not found"
    require "test -f $SCRIPT_DIR/output/output.zip" convert "No output.zip found"

    # Brand the library metadata inside the zip
    local email
    email=$(grep '^EMAIL=' "$SCRIPT_DIR/.env" | cut -d= -f2-)

    cmd="$DOCKER run --rm $DOCKER_USER -e HOME=/tmp \\
          -e LIBRARY_NAME='Tailwind UI Pro' \\
          -e LIBRARY_DESC='$email' \\
          -v $SCRIPT_DIR/output:/app/output \\
          -w /tmp \\
          $IMAGE_NAME sh -c '
            unzip -o /app/output/output.zip shuffle.config.json &&
            sed -i \\
              -e \"s|Tailwind UI all components|\$LIBRARY_DESC|\" \\
              -e \"s|Tailwind UI All|\$LIBRARY_NAME|\" \\
              shuffle.config.json &&
            zip -d /app/output/output.zip shuffle.config.json &&
            zip /app/output/output.zip shuffle.config.json'"
    info "$(dim "\$ $cmd")"
    eval "$cmd" 2>&1 | while IFS= read -r line; do info "$(dim "$line")"; done
    ok "Library branded as \"Tailwind UI Pro\" ($email)"

    cp "$SCRIPT_DIR/output/output.zip" "$SCRIPT_DIR/tailwind-shuffle-components.zip"
    ok "Package created"

    html_count=$(unzip -l "$SCRIPT_DIR/tailwind-shuffle-components.zip" | grep -c '\.html$' || true)
    if [ "$html_count" -eq 0 ]; then
        fail "Zip file appears to be empty or invalid"
        exit 1
    fi

    zip_size=$(du -h "$SCRIPT_DIR/tailwind-shuffle-components.zip" | cut -f1)
    ok "Validated: $html_count components, $zip_size"
}

stage_done() {
    cat <<EOF

  ┌─────────────────────────────────────────────┐
  │  $(green "Build complete!")                            │
  └─────────────────────────────────────────────┘

  Your package:  $(bold "./tailwind-shuffle-components.zip")  ($zip_size, $html_count components)

  To upload:
    1. Go to $(cyan "https://shuffle.dev/dashboard#/libraries/uploaded")
    2. Upload tailwind-shuffle-components.zip

  Cached downloads are in ./cache/
  Run this script again to rebuild without re-downloading.

EOF
}

# ── Cleanup ──────────────────────────────────────────────────────────

cleanup() {
    [ -n "${DOCKER:-}" ] && $DOCKER rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# ── Main ─────────────────────────────────────────────────────────────

# Detect docker early so all stages can use $DOCKER
if command -v podman &>/dev/null; then
    DOCKER=podman
elif command -v docker &>/dev/null; then
    DOCKER=docker
fi

case "${1:-}" in
    clean)
        info "Removing output, tailwind-shuffle-components.zip, and build container..."
        rm -rf "$SCRIPT_DIR/output" "$SCRIPT_DIR/tailwind-shuffle-components.zip"
        ${DOCKER:-docker} rm -f "$CONTAINER_NAME" 2>/dev/null || true
        ok "Clean"
        ;;
    build)
        stage_prerequisites
        stage_build
        ;;
    download)
        stage_prerequisites
        stage_download
        ;;
    convert)
        stage_prerequisites
        stage_convert
        ;;
    catalog)
        stage_prerequisites
        stage_catalog
        ;;
    package)
        stage_prerequisites
        stage_package
        ;;
    all)
        clear
        cat <<'BANNER'

  ┌─────────────────────────────────────────────┐
  │  Tailshuffle.sh                              │
  └─────────────────────────────────────────────┘

  This script will:

    1. Check prerequisites (Docker)
    2. Set up your Tailwind UI credentials
    3. Download components via tailwindui-crawler
    4. Convert them to Shuffle.dev format
    5. Package everything into a zip

BANNER

        stage_prerequisites

        skip_download=false
        if [ -d "$WORK_DIR" ] && [ -n "$(ls -A "$WORK_DIR" 2>/dev/null)" ]; then
            echo ""
            info "Found cached components in ./cache/"
            if confirm "Re-use cached download? (skip re-downloading)"; then
                skip_download=true
                ok "Will use cached components"
            fi
        fi

        if [ "$skip_download" = false ]; then
            stage_credentials
        fi

        stage_build

        if [ "$skip_download" = true ]; then
            step "4/5" "Downloading Tailwind UI components"
            ok "Skipped (using cache)"
        else
            stage_download
        fi

        stage_convert

        if confirm "Generate component catalog for LLMs?"; then
            stage_catalog
        fi

        stage_package
        rm -rf "$SCRIPT_DIR/output"
        stage_done
        ;;
    *)
        echo "Tailshuffle.sh — Download Tailwind UI components and package them for Shuffle.dev"
        echo ""
        echo "Usage: $0 [build|download|convert|catalog|package|clean|all]"
        echo ""
        echo "  build      Build the Docker image"
        echo "  download   Download components"
        echo "  convert    Convert cached components to shuffle format"
        echo "  catalog    Generate components-catalog.json for LLM context"
        echo "  package    Zip + validate"
        echo "  clean      Remove build artifacts"
        echo "  all        Full pipeline"
        echo ""
        if [ -z "${1:-}" ]; then
            printf 'Run the full pipeline? [Y/n] '
            read -r REPLY
            case "$REPLY" in [nN]*) ;; *) exec "$0" all ;; esac
        fi
        ;;
esac
