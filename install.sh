#!/usr/bin/env bash
# devflow installer — safe to run multiple times (idempotent)
set -euo pipefail

REPO="https://github.com/AndreJorgeLopes/devflow.git"
INSTALL_DIR="${HOME}/.local/share/devflow"
BIN_DIR="${HOME}/.local/bin"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Pre-flight checks -------------------------------------------------------
command -v git >/dev/null 2>&1 || error "git is required. Install it first."

# --- Clone or update ----------------------------------------------------------
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  info "Updating existing devflow installation..."
  git -C "${INSTALL_DIR}" pull --ff-only --quiet
else
  if [[ -d "${INSTALL_DIR}" ]]; then
    warn "${INSTALL_DIR} exists but is not a git repo. Backing up and re-cloning."
    mv "${INSTALL_DIR}" "${INSTALL_DIR}.bak.$(date +%s)"
  fi
  info "Cloning devflow..."
  git clone --quiet "${REPO}" "${INSTALL_DIR}"
fi

# --- Create wrapper symlink ---------------------------------------------------
mkdir -p "${BIN_DIR}"

# Create a wrapper (not just a symlink) so DEVFLOW_ROOT is always set
cat > "${BIN_DIR}/devflow" <<WRAPPER
#!/usr/bin/env bash
export DEVFLOW_ROOT="${INSTALL_DIR}"
exec "${INSTALL_DIR}/bin/devflow" "\$@"
WRAPPER
chmod 755 "${BIN_DIR}/devflow"

# --- Verify -------------------------------------------------------------------
info "devflow installed to ${BIN_DIR}/devflow"

if ! echo "${PATH}" | tr ':' '\n' | grep -qx "${BIN_DIR}"; then
  warn "${BIN_DIR} is not in your PATH."
  echo ""
  echo "  Add this to your shell profile (~/.zshrc or ~/.bashrc):"
  echo ""
  echo "    export PATH=\"\${HOME}/.local/bin:\${PATH}\""
  echo ""
fi

echo ""
info "Done. Run 'devflow init' to set up all 6 layers (tools, plugins, commands, MCP, skills)."
echo ""
echo "  devflow init            # Initialize for the current directory"
echo "  devflow init ~/myapp    # Initialize for a specific project"
echo ""
