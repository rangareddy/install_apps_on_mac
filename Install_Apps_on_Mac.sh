#!/usr/bin/env bash
#
# Name         : Install_Apps_on_Mac.sh
# Purpose      : Install development applications on macOS, on both Apple Silicon
#                (arm64: M1/M2/M3/M4) and Intel (x86_64) Macs.
# Author       : Ranga Reddy
# Created Date : 27-Sep-2020
# Updated Date : 10-Sep-2026
# Version      : v2.1
#
# Usage        : ./Install_Apps_on_Mac.sh [OPTIONS] [APP ...]
#                ./Install_Apps_on_Mac.sh --help
#
# Notes        : Written for bash 3.2, the version macOS ships in /bin/bash, so no
#                associative arrays or other bash 4+ syntax is used.
#

# No `set -e`: a single failing app must not abort the whole run. Return codes are
# checked explicitly and every failure is collected into the closing summary.
set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.1"
MANAGED_BLOCK_TAG="install_apps_on_mac"
MANAGED_RC_TAG="install_apps_on_mac-sdkman"

HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

# ------------------------------------------------------------------------------
# Default application lists
#
# Entries are short aliases resolved by resolve_app(); anything not listed there
# is looked up in Homebrew directly, so you can add arbitrary formulae or casks.
# ------------------------------------------------------------------------------
BASIC_APPS_LIST=(git wget telnet netcat jq bash-completion iterm2 tree)
ADVANCED_APPS_LIST=(code java maven idea mysql sublime)

# JDKs the `java` app installs, via SDKMAN. Comma-separated feature versions;
# override with --jdk-versions. JDK_DEFAULT is the one made the SDKMAN default
# and defaults to the highest version in the list.
JDK_VERSIONS="11,17,21"
JDK_DEFAULT=""

# SDKMAN vendor preference, highest first. Order matters for Java 8 on Apple
# Silicon: Temurin publishes no macOS aarch64 build for 8, Zulu does. Early
# access builds (the `open` vendor) are deliberately excluded.
SDKMAN_JAVA_VENDORS="tem zulu amzn librca"

SDKMAN_INSTALL_URL="https://get.sdkman.io"
SDKMAN_API_URL="https://api.sdkman.io/2"

# ------------------------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------------------------
MAC_ARCH=""
MAC_CHIP=""
IS_APPLE_SILICON=0
RUNNING_UNDER_ROSETTA=0
HOMEBREW_PREFIX=""
BREW_BIN=""
SHELL_PROFILE=""
SHELL_RC=""
SDKMAN_JAVA_LIST_FILE=""

DRY_RUN=0
LIST_ONLY=0
DO_BASIC=0
DO_ADVANCED=0
SKIP_BREW_UPDATE=0
ASSUME_YES=0
REQUESTED_APPS=()

INSTALLED_APPS=()
SKIPPED_APPS=()
FAILED_APPS=()

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

log_info()  { printf '%s\n' "${C_BLUE}[INFO]${C_RESET}  $*"; }
log_ok()    { printf '%s\n' "${C_GREEN}[ OK ]${C_RESET}  $*"; }
log_warn()  { printf '%s\n' "${C_YELLOW}[WARN]${C_RESET}  $*" >&2; }
log_error() { printf '%s\n' "${C_RED}[FAIL]${C_RESET}  $*" >&2; }
log_step()  { printf '\n%s\n' "${C_BOLD}==> $*${C_RESET}"; }

die() { log_error "$*"; exit 1; }

cleanup() {
  [ -n "${SDKMAN_JAVA_LIST_FILE:-}" ] && rm -f "$SDKMAN_JAVA_LIST_FILE"
  return 0
}
trap cleanup EXIT

# Print the command instead of running it when --dry-run is active.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  $*"
    return 0
  fi
  "$@"
}

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
${C_BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${C_RESET} - install development applications on macOS
(Apple Silicon and Intel).

${C_BOLD}USAGE${C_RESET}
  $SCRIPT_NAME [OPTIONS] [APP ...]

${C_BOLD}OPTIONS${C_RESET}
  -b, --basic              Install the basic application list only.
  -a, --advanced           Install the advanced application list only.
      --all                Install both lists. This is the default when no
                           option and no APP argument is given.
  -j, --jdk-versions LIST  Comma-separated JDK feature versions to install via
                           SDKMAN (for example 11,17,21). Default: $JDK_VERSIONS
      --jdk-default VER    Which of those becomes the SDKMAN default.
                           Default: the highest version installed.
      --jdk-version VER    Alias for installing a single JDK and defaulting to
                           it, kept for compatibility.
  -n, --dry-run            Print what would be installed, change nothing.
  -l, --list               Show the resolved application lists and exit.
  -s, --skip-update        Do not run 'brew update' before installing.
  -y, --yes                Do not prompt for confirmation.
  -h, --help               Show this help and exit.
  -v, --version            Show the script version and exit.

${C_BOLD}APP${C_RESET}
  One or more application names to install instead of the default lists. An
  alias from the table below, or any Homebrew formula or cask token; the script
  resolves formula first, then cask.

${C_BOLD}ALIASES${C_RESET}
  code, vscode      -> visual-studio-code (cask)
  idea, intellij    -> intellij-idea (cask)
  sublime           -> sublime-text (cask)
  java, jdk         -> SDKMAN plus the JDKs in --jdk-versions
  maven, mvn        -> maven + M2_HOME
  gradle            -> gradle + GRADLE_HOME
  scala             -> scala@2.12 + SCALA_HOME
  mysql             -> mysql server + MySQL Workbench

${C_BOLD}EXAMPLES${C_RESET}
  $SCRIPT_NAME                          # install everything
  $SCRIPT_NAME --basic                  # basic list only
  $SCRIPT_NAME --dry-run --all          # preview the full run
  $SCRIPT_NAME java maven gradle        # just the JVM toolchain
  $SCRIPT_NAME -j 11,17,21 java         # three JDKs, newest as default
  $SCRIPT_NAME --jdk-default 17 java    # install the list, default to 17
  $SCRIPT_NAME docker rectangle         # arbitrary casks

${C_BOLD}JAVA${C_RESET}
  Java is installed with SDKMAN so several JDKs can coexist and be switched:

    sdk list java                 show installed and available builds
    sdk use java 17.0.20-tem      switch this shell only
    sdk default java 21.0.12-tem  change the default for new shells

  Vendors are tried in this order: $SDKMAN_JAVA_VENDORS. That order matters on
  Apple Silicon, where Temurin has no macOS aarch64 build for Java 8 and Zulu
  does. Exact identifiers are resolved from SDKMAN at run time, so they do not
  go stale.

${C_BOLD}NOTES${C_RESET}
  Run as a normal user, not with sudo. Homebrew refuses to run as root and will
  ask for your password only when a cask needs it.
EOF
}

# Every entry must be a bare feature number: 8, 11, 17, 21.
validate_jdk_list() {
  local list="$1" flag="$2" entry
  [ -n "$list" ] || die "$flag needs at least one version"
  for entry in $(printf '%s' "$list" | tr ',' ' '); do
    case "$entry" in
      ''|*[!0-9]*) die "$flag takes feature numbers such as 8, 11, 17 or 21; got '$entry'" ;;
    esac
  done
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -b|--basic)       DO_BASIC=1 ;;
      -a|--advanced)    DO_ADVANCED=1 ;;
      --all)            DO_BASIC=1; DO_ADVANCED=1 ;;
      -j|--jdk-versions)
        [ "$#" -ge 2 ] || die "--jdk-versions needs a value (for example: 11,17,21)"
        validate_jdk_list "$2" "--jdk-versions"
        JDK_VERSIONS="$2"; shift ;;
      --jdk-default)
        [ "$#" -ge 2 ] || die "--jdk-default needs a value (for example: 21)"
        validate_jdk_list "$2" "--jdk-default"
        JDK_DEFAULT="$2"; shift ;;
      --jdk-version)
        [ "$#" -ge 2 ] || die "--jdk-version needs a value (for example: 17)"
        validate_jdk_list "$2" "--jdk-version"
        JDK_VERSIONS="$2"; JDK_DEFAULT="$2"; shift ;;
      -n|--dry-run)     DRY_RUN=1 ;;
      -s|--skip-update) SKIP_BREW_UPDATE=1 ;;
      -y|--yes)         ASSUME_YES=1 ;;
      -l|--list)        LIST_ONLY=1 ;;
      -h|--help)        usage; exit 0 ;;
      -v|--version)     printf '%s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      -*)               die "Unknown option: $1 (run '$SCRIPT_NAME --help' for usage)" ;;
      *)                REQUESTED_APPS+=("$1") ;;
    esac
    shift
  done

  # No selection at all means install both default lists.
  if [ "${#REQUESTED_APPS[@]}" -eq 0 ] && [ "$DO_BASIC" -eq 0 ] && [ "$DO_ADVANCED" -eq 0 ]; then
    DO_BASIC=1
    DO_ADVANCED=1
  fi
}

# ------------------------------------------------------------------------------
# Platform detection
# ------------------------------------------------------------------------------

# Identify the *physical* CPU, not the emulated one. `uname -m` reports x86_64
# for a process running under Rosetta 2 on an Apple Silicon Mac, which would
# otherwise send us to the Intel Homebrew prefix on an arm64 machine.
detect_architecture() {
  [ "$(uname -s)" = "Darwin" ] || die "This script only supports macOS. Detected: $(uname -s)"

  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    RUNNING_UNDER_ROSETTA=1
  fi

  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
    MAC_ARCH="arm64"
    IS_APPLE_SILICON=1
  else
    MAC_ARCH="x86_64"
    IS_APPLE_SILICON=0
  fi

  MAC_CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown CPU')"
}

# Apple Silicon installs Homebrew under /opt/homebrew; Intel uses /usr/local.
# Check the prefix native to this machine first, so an Intel Homebrew kept around
# for Rosetta-only packages on an Apple Silicon Mac cannot win over the native
# install. Once a brew binary is found, ask it for its own prefix so a
# non-standard install location is respected.
detect_homebrew_prefix() {
  local candidates candidate
  if [ "$IS_APPLE_SILICON" -eq 1 ]; then
    candidates="/opt/homebrew /usr/local"
  else
    candidates="/usr/local /opt/homebrew"
  fi

  for candidate in $candidates; do
    if [ -x "$candidate/bin/brew" ]; then
      BREW_BIN="$candidate/bin/brew"
      HOMEBREW_PREFIX="$("$BREW_BIN" --prefix)"
      return 0
    fi
  done

  # Nothing installed yet: fall back to the documented default for this arch.
  if [ "$IS_APPLE_SILICON" -eq 1 ]; then
    HOMEBREW_PREFIX="/opt/homebrew"
  else
    HOMEBREW_PREFIX="/usr/local"
  fi
  BREW_BIN="$HOMEBREW_PREFIX/bin/brew"
  return 1
}

# Two different files are needed.
#
# SHELL_PROFILE is the login profile and carries PATH and *_HOME exports. The
# original script hardcoded ~/.bash_profile, which zsh (the macOS default since
# Catalina) never sources.
#
# SHELL_RC is the interactive rc file and carries SDKMAN's init line, because
# `sdk` is a shell function that has to be defined in every interactive shell,
# not only in login shells. Putting it in the profile would leave `sdk` missing
# from any non-login shell.
detect_shell_files() {
  case "${SHELL##*/}" in
    zsh)
      SHELL_PROFILE="$HOME/.zprofile"
      SHELL_RC="${ZDOTDIR:-$HOME}/.zshrc"
      ;;
    bash)
      SHELL_PROFILE="$HOME/.bash_profile"
      SHELL_RC="$HOME/.bashrc"
      ;;
    *)
      SHELL_PROFILE="$HOME/.profile"
      SHELL_RC="$HOME/.profile"
      ;;
  esac
}

rosetta_installed() { /usr/bin/pgrep -q oahd; }

# Rosetta 2 lets an Apple Silicon Mac run Intel-only casks. Only some apps need
# it, so install it on demand rather than up front.
ensure_rosetta() {
  [ "$IS_APPLE_SILICON" -eq 1 ] || return 0
  if rosetta_installed; then
    return 0
  fi
  log_info "Installing Rosetta 2 (needed for Intel-only applications)..."
  if run softwareupdate --install-rosetta --agree-to-license; then
    log_ok "Rosetta 2 is installed"
  else
    log_warn "Could not install Rosetta 2; Intel-only applications may fail"
    return 1
  fi
}

check_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this script as root or with sudo. Homebrew refuses to run as root; re-run it as your normal user."
  fi
}

# Homebrew needs the Xcode Command Line Tools to build anything without a bottle.
ensure_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  log_info "Installing the Xcode Command Line Tools..."
  if ! run xcode-select --install; then
    log_warn "Could not trigger the Command Line Tools install"
    return 1
  fi
  [ "$DRY_RUN" -eq 1 ] && return 0
  log_info "Waiting for the Command Line Tools install to finish (accept the dialog)..."
  # Bounded wait: a cancelled or dismissed dialog must not hang the script.
  local waited=0 timeout=1800
  until xcode-select -p >/dev/null 2>&1; do
    if [ "$waited" -ge "$timeout" ]; then
      log_warn "Command Line Tools still not present after $((timeout / 60)) minutes; continuing anyway"
      return 1
    fi
    sleep 10
    waited=$((waited + 10))
  done
  log_ok "Xcode Command Line Tools are installed"
}

print_system_summary() {
  log_step "System"
  printf '  macOS            : %s (%s)\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
  printf '  Chip             : %s\n' "$MAC_CHIP"
  printf '  Architecture     : %s (%s)\n' "$MAC_ARCH" \
    "$([ "$IS_APPLE_SILICON" -eq 1 ] && echo 'Apple Silicon' || echo 'Intel')"
  printf '  Homebrew prefix  : %s\n' "$HOMEBREW_PREFIX"
  printf '  Shell profile    : %s\n' "$SHELL_PROFILE"
  printf '  Shell rc file    : %s\n' "$SHELL_RC"
  printf '  JDKs to install  : %s (default %s)\n' "$JDK_VERSIONS" \
    "${JDK_DEFAULT:-$(highest_version "$JDK_VERSIONS")}"
  if [ "$RUNNING_UNDER_ROSETTA" -eq 1 ]; then
    log_warn "This shell is running under Rosetta 2. Everything will still be installed natively for $MAC_ARCH, but consider re-running in a native terminal."
  fi
}

# ------------------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------------------
install_homebrew() {
  log_step "Homebrew"

  if detect_homebrew_prefix; then
    log_ok "Homebrew is already installed at $HOMEBREW_PREFIX"
  else
    log_info "Installing Homebrew into $HOMEBREW_PREFIX for $MAC_ARCH..."
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  /bin/bash -c \"\$(curl -fsSL $HOMEBREW_INSTALL_URL)\""
    else
      # NONINTERACTIVE stops the installer waiting on RETURN, which is the
      # supported replacement for piping `yes` into it.
      if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")"; then
        die "Homebrew installation failed"
      fi
      detect_homebrew_prefix || die "Homebrew installed but no brew binary was found under $HOMEBREW_PREFIX"
      log_ok "Homebrew is installed at $HOMEBREW_PREFIX"
    fi
  fi

  # Put brew on PATH for the rest of this run, and record shellenv for the profile.
  if [ -x "$BREW_BIN" ]; then
    eval "$("$BREW_BIN" shellenv)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    log_warn "Homebrew is not installed yet, so this dry run cannot check which applications are already present or resolve unknown names."
  fi
  PROFILE_CONSIDERED=1
  if profile_has_brew_shellenv; then
    log_info "$SHELL_PROFILE already sets up brew shellenv; not adding another copy"
  else
    add_managed_line "eval \"\$($HOMEBREW_PREFIX/bin/brew shellenv)\""
  fi
}

# True when the login profile already evaluates brew shellenv outside the block
# this script manages. Homebrew's own installer adds that line, and many people
# add it by hand, so a second copy would just be noise.
profile_has_brew_shellenv() {
  [ -f "$SHELL_PROFILE" ] || return 1
  awk -v b="# >>> $MANAGED_BLOCK_TAG >>>" -v e="# <<< $MANAGED_BLOCK_TAG <<<" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip && /brew shellenv/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$SHELL_PROFILE"
}

update_homebrew() {
  if [ "$SKIP_BREW_UPDATE" -eq 1 ]; then
    log_info "Skipping 'brew update' (--skip-update)"
    return 0
  fi
  log_step "Updating Homebrew"
  # Run in the foreground. The original backgrounded this, so installs raced
  # against a half-finished update.
  if run brew update; then
    log_ok "Homebrew is up to date"
  else
    log_warn "'brew update' failed; continuing with the current formula index"
  fi
}

# ------------------------------------------------------------------------------
# Shell profile management
#
# All exports live inside a single managed block that is rewritten in place on
# every run. The original appended to the profile each time, so PATH and *_HOME
# entries piled up on repeat runs.
# ------------------------------------------------------------------------------
MANAGED_LINES=()
MANAGED_RC_LINES=()
PROFILE_CONSIDERED=0
RC_CONSIDERED=0

# Append $1 to the named buffer if it is not already there. $2 selects the
# buffer: "profile" for the login profile, "rc" for the interactive rc file.
add_managed_line() {
  local line="$1" existing
  for existing in ${MANAGED_LINES[@]+"${MANAGED_LINES[@]}"}; do
    [ "$existing" = "$line" ] && return 0
  done
  MANAGED_LINES+=("$line")
}

add_managed_rc_line() {
  local line="$1" existing
  for existing in ${MANAGED_RC_LINES[@]+"${MANAGED_RC_LINES[@]}"}; do
    [ "$existing" = "$line" ] && return 0
  done
  MANAGED_RC_LINES+=("$line")
}

set_env_var() {
  local name="$1" value="$2"
  [ -n "$value" ] || return 0
  add_managed_line "export $name=\"$value\""
  add_managed_line "export PATH=\"\$$name/bin:\$PATH\""
  # Make it available to the rest of this run too.
  export "$name=$value"
}

# Write a managed block into $1, replacing any previous block carrying marker
# $2. The remaining arguments are the lines of the block.
write_managed_block() {
  local file="$1" tag="$2"
  shift 2

  local begin="# >>> $tag >>>"
  local end="# <<< $tag <<<"

  # No lines means the block is no longer needed. Strip a previous one if it is
  # there, otherwise there is nothing to do. Leaving a stale block behind would
  # keep re-applying settings this run decided against.
  if [ "$#" -eq 0 ]; then
    [ -f "$file" ] || return 0
    grep -qxF "$begin" "$file" 2>/dev/null || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  would remove the now-empty $tag block from $file"
      return 0
    fi
  elif [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  would write this block to $file:"
    printf '  %s\n' "$begin"
    printf '  %s\n' "$@"
    printf '  %s\n' "$end"
    return 0
  fi

  touch "$file" || { log_warn "Cannot write $file"; return 1; }

  # Stage the rewrite next to the target so the final mv is atomic and cannot
  # cross a filesystem boundary, and carry the original file mode over so the
  # file does not silently become mktemp's 0600.
  local tmp mode
  tmp="$(mktemp "$(dirname "$file")/.${MANAGED_BLOCK_TAG}.XXXXXX")" || return 1
  mode="$(stat -f '%Lp' "$file" 2>/dev/null)"

  # Copy the file, dropping any previous block with this marker.
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$file" > "$tmp"

  if [ "$#" -gt 0 ]; then
    {
      printf '%s\n' "$begin"
      printf '# Managed by %s - edits inside this block are overwritten.\n' "$SCRIPT_NAME"
      printf '%s\n' "$@"
      printf '%s\n' "$end"
    } >> "$tmp"
  fi

  [ -n "$mode" ] && chmod "$mode" "$tmp"

  if mv "$tmp" "$file"; then
    if [ "$#" -gt 0 ]; then
      log_ok "Updated $file ($# managed lines)"
    else
      log_ok "Removed the now-empty $tag block from $file"
    fi
    return 0
  fi
  rm -f "$tmp"
  log_warn "Could not update $file"
  return 1
}

write_shell_files() {
  local wrote=0

  if [ "$PROFILE_CONSIDERED" -eq 1 ]; then
    log_step "Shell profile"
    write_managed_block "$SHELL_PROFILE" "$MANAGED_BLOCK_TAG" \
      ${MANAGED_LINES[@]+"${MANAGED_LINES[@]}"} && wrote=1
  fi

  if [ "$RC_CONSIDERED" -eq 1 ]; then
    log_step "Shell rc file"
    write_managed_block "$SHELL_RC" "$MANAGED_RC_TAG" \
      ${MANAGED_RC_LINES[@]+"${MANAGED_RC_LINES[@]}"} && wrote=1
  fi

  if [ "$wrote" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    log_info "Open a new terminal, or run 'exec $(basename "$SHELL") -l', to pick up the changes"
  fi
}

# ------------------------------------------------------------------------------
# Install primitives
# ------------------------------------------------------------------------------
formula_installed() { brew list --formula --versions "$1" >/dev/null 2>&1; }
cask_installed()    { brew list --cask --versions "$1" >/dev/null 2>&1; }

formula_exists() { brew info --formula "$1" >/dev/null 2>&1; }
cask_exists()    { brew info --cask "$1" >/dev/null 2>&1; }

# Set by brew_install_formula / brew_install_cask so callers can tell a fresh
# install from an already-present one.
LAST_INSTALL_WAS_NEW=0

record_installed() { INSTALLED_APPS+=("$1"); }
record_skipped()   { SKIPPED_APPS+=("$1"); }
record_failed()    { FAILED_APPS+=("$1"); }

brew_install_formula() {
  local token="$1"
  LAST_INSTALL_WAS_NEW=0
  if formula_installed "$token"; then
    log_ok "$token is already installed"
    record_skipped "$token"
    return 0
  fi
  log_info "Installing formula $token ..."
  if run brew install --formula "$token"; then
    log_ok "$token is installed"
    record_installed "$token"
    LAST_INSTALL_WAS_NEW=1
    return 0
  fi
  log_error "Failed to install $token"
  record_failed "$token"
  return 1
}

# Decide whether a cask needs Rosetta 2 on Apple Silicon.
#
# `brew info --cask` resolves the download URL for the *current* architecture,
# so on an arm64 machine a URL that carries an Intel marker and no arm marker
# means the cask has no native Apple Silicon build. Casks with no arch marker in
# the URL are universal builds and need nothing.
cask_needs_rosetta() {
  [ "$IS_APPLE_SILICON" -eq 1 ] || return 1
  local url
  # grep -o returns matches in document order, and "url" is the first key of
  # that name in the cask JSON, so head -1 is the download URL. Matching the
  # key with optional whitespace handles both pretty and compact JSON output.
  url="$(brew info --cask --json=v2 "$1" 2>/dev/null \
        | grep -o '"url":[[:space:]]*"[^"]*"' | head -1)"
  [ -n "$url" ] || return 1
  case "$url" in
    *arm64*|*aarch64*|*universal*) return 1 ;;
    *x64*|*x86_64*|*amd64*|*intel*) return 0 ;;
    *) return 1 ;;
  esac
}

brew_install_cask() {
  local token="$1"
  LAST_INSTALL_WAS_NEW=0
  if cask_installed "$token"; then
    log_ok "$token is already installed"
    record_skipped "$token"
    return 0
  fi
  if cask_needs_rosetta "$token"; then
    log_info "$token has no native $MAC_ARCH build and runs through Rosetta 2"
    ensure_rosetta
  fi

  log_info "Installing cask $token ..."
  # --no-quarantine is deliberately not used: leaving Gatekeeper quarantine in
  # place is the safer default.
  if run brew install --cask "$token"; then
    log_ok "$token is installed"
    record_installed "$token"
    LAST_INSTALL_WAS_NEW=1
    return 0
  fi
  log_error "Failed to install $token"
  record_failed "$token"
  return 1
}

# Resolve an unknown token: formula first, then cask. Lets the app lists carry
# any Homebrew package without the script needing to know its kind.
brew_install_auto() {
  local token="$1"
  if formula_installed "$token" || cask_installed "$token"; then
    log_ok "$token is already installed"
    record_skipped "$token"
    return 0
  fi
  if formula_exists "$token"; then
    brew_install_formula "$token"
  elif cask_exists "$token"; then
    brew_install_cask "$token"
  else
    log_error "$token is neither a Homebrew formula nor a cask"
    record_failed "$token"
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Application handlers
# ------------------------------------------------------------------------------

# Echoes "<kind> <token>" where kind is formula, cask, custom or auto.
resolve_app() {
  case "$1" in
    code|vscode)        echo "cask visual-studio-code" ;;
    idea|intellij)      echo "cask intellij-idea" ;;
    sublime|sublimetext) echo "cask sublime-text" ;;
    iterm|iterm2)       echo "cask iterm2" ;;
    java|jdk)           echo "custom java" ;;
    maven|mvn)          echo "custom maven" ;;
    gradle)             echo "custom gradle" ;;
    scala)              echo "custom scala" ;;
    sbt)                echo "formula sbt" ;;
    mysql)              echo "custom mysql" ;;
    *)                  echo "auto $1" ;;
  esac
}

# ------------------------------------------------------------------------------
# Java, via SDKMAN
#
# SDKMAN is used instead of Homebrew casks so several JDKs can live side by side
# and be switched per shell (`sdk use java ...`) or globally (`sdk default
# java ...`). Homebrew casks install one JDK per formula into
# /Library/Java/JavaVirtualMachines and have no switching story.
# ------------------------------------------------------------------------------

sdkman_dir() { printf '%s\n' "${SDKMAN_DIR:-$HOME/.sdkman}"; }

sdkman_installed() { [ -s "$(sdkman_dir)/bin/sdkman-init.sh" ]; }

# SDKMAN's own platform token, which decides which builds the API offers.
sdkman_platform() {
  if [ "$IS_APPLE_SILICON" -eq 1 ]; then
    echo "darwinarm64"
  else
    echo "darwinx64"
  fi
}

install_sdkman() {
  if sdkman_installed; then
    log_ok "SDKMAN is already installed at $(sdkman_dir)"
    return 0
  fi

  log_info "Installing SDKMAN into $(sdkman_dir) ..."
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  curl -fsSL $SDKMAN_INSTALL_URL | bash"
    return 0
  fi

  if ! curl -fsSL "$SDKMAN_INSTALL_URL" | bash; then
    log_error "SDKMAN installation failed"
    return 1
  fi
  if ! sdkman_installed; then
    log_error "SDKMAN ran but $(sdkman_dir)/bin/sdkman-init.sh is missing"
    return 1
  fi
  log_ok "SDKMAN is installed at $(sdkman_dir)"
}

# Load SDKMAN into this shell so the `sdk` function exists.
#
# sdkman-init.sh reads variables that it does not define first, so it aborts
# under `set -u` with "SDKMAN_CANDIDATES_API: unbound variable". Nounset is
# lifted around the source and restored afterwards.
sdkman_load() {
  sdkman_installed || return 1
  local dir
  dir="$(sdkman_dir)"
  export SDKMAN_DIR="$dir"
  set +u
  # shellcheck disable=SC1091
  . "$SDKMAN_DIR/bin/sdkman-init.sh"
  set -u
  command -v sdk >/dev/null 2>&1
}

# Cache SDKMAN's remote java list for this platform. Called from the main shell,
# never a subshell, so the cache path survives.
sdkman_fetch_java_list() {
  [ -n "$SDKMAN_JAVA_LIST_FILE" ] && [ -s "$SDKMAN_JAVA_LIST_FILE" ] && return 0
  [ -n "$SDKMAN_JAVA_LIST_FILE" ] && rm -f "$SDKMAN_JAVA_LIST_FILE"
  SDKMAN_JAVA_LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/${MANAGED_BLOCK_TAG}-java.XXXXXX")" || return 1
  curl -fsSL "$SDKMAN_API_URL/candidates/java/$(sdkman_platform)/versions/list?installed=" \
    > "$SDKMAN_JAVA_LIST_FILE" 2>/dev/null
  [ -s "$SDKMAN_JAVA_LIST_FILE" ]
}

# The Identifier column of the remote list, one identifier per line.
sdkman_java_identifiers() {
  [ -s "$SDKMAN_JAVA_LIST_FILE" ] || return 1
  awk -F'|' '
    NF >= 4 {
      id = $NF
      gsub(/[ \t]/, "", id)
      if (id != "" && id != "Identifier") print id
    }
  ' "$SDKMAN_JAVA_LIST_FILE"
}

# Identifiers from the preferred vendors, excluding JavaFX bundles.
#
# The full remote list mixes real JDK feature versions with product versions
# from other tools, so it cannot be read naively. Liberica NIK, for instance,
# publishes "23.1.12-fx+1.1.r21-nik", which is NIK 23.1 built on Java 21 and
# not a Java 23 at all. Restricting to the preferred vendors keeps the numbers
# meaningful, and dropping "fx" identifiers avoids picking a JavaFX bundle when
# a plain JDK was asked for.
sdkman_java_candidates() {
  local vendor_re
  vendor_re="$(printf '%s' "$SDKMAN_JAVA_VENDORS" | tr ' ' '|')"
  sdkman_java_identifiers | grep -Ev 'fx' | grep -E -- "-(${vendor_re})$"
}

# Feature versions SDKMAN can actually install on this platform.
sdkman_available_majors() {
  sdkman_java_candidates | sed 's/[.+-].*//' | grep -E '^[0-9]+$' | sort -un | tr '\n' ' '
}

# Newest identifier for feature version $1, honouring SDKMAN_JAVA_VENDORS.
#
# Identifiers are matched anchored at the start so that asking for 21 cannot
# match 8.0.21, and `sort -V` then picks the highest patch release.
sdkman_resolve_java() {
  local major="$1" vendor id
  for vendor in $SDKMAN_JAVA_VENDORS; do
    id="$(sdkman_java_candidates \
          | grep -E "^${major}([.+-]|$)" \
          | grep -E -- "-${vendor}$" \
          | sort -V | tail -1)"
    if [ -n "$id" ]; then
      printf '%s\n' "$id"
      return 0
    fi
  done
  return 1
}

# True when the startup files this shell actually reads already source SDKMAN's
# init, ignoring the block this script manages.
#
# SDKMAN's own installer appends that snippet to ~/.zshrc and, on macOS, to
# ~/.bash_profile. Only the files the current shell reads count: a snippet in
# ~/.bash_profile does nothing for a zsh user, which is exactly how a machine
# ends up with SDKMAN installed but no working `sdk` command.
shell_files_have_sdkman_init() {
  local file
  for file in "$SHELL_RC" "$SHELL_PROFILE"; do
    [ -f "$file" ] || continue
    awk -v b="# >>> $MANAGED_RC_TAG >>>" -v e="# <<< $MANAGED_RC_TAG <<<" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip && /sdkman-init\.sh/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$file" && return 0
  done
  return 1
}

java_installed_via_sdkman() { [ -d "$(sdkman_dir)/candidates/java/$1" ]; }

# An already-installed SDKMAN build for feature version $1, or empty. Reusing
# what is present avoids re-downloading a whole JDK only because a newer patch
# release has since appeared.
sdkman_installed_java_for_major() {
  local major="$1" dir entry name
  dir="$(sdkman_dir)/candidates/java"
  [ -d "$dir" ] || return 0
  for entry in "$dir"/*; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    # `current` is SDKMAN's symlink to the default, not a version of its own.
    [ "$name" = "current" ] && continue
    case "$name" in
      "$major"|"$major".*|"$major"+*|"$major"-*) printf '%s\n' "$name" ;;
    esac
  done | sort -V | tail -1
}

# Install one JDK without letting it take over as the default.
#
# `sdk install` asks "Do you want java X to be set as default? (Y/n)" whenever a
# default already exists, which would otherwise prompt once per JDK and let the
# last install decide the default.
#
# Setting sdkman_auto_answer as a prefix assignment does not work here: the
# `sdk` wrapper re-sources $SDKMAN_DIR/etc/config on every invocation
# (sdkman-main.sh), which resets sdkman_auto_answer to its configured value
# before the prompt is reached. SDKMAN's own sdkman-env.sh gets away with it
# only because it calls the private __sdk_install directly and bypasses that
# wrapper. Answering "n" on stdin needs no private functions and no edit to the
# user's config, and --jdk-default is then applied explicitly afterwards.
sdkman_install_java() {
  local identifier="$1" major="$2" rc

  if java_installed_via_sdkman "$identifier"; then
    log_ok "Java $major ($identifier) is already installed"
    record_skipped "java $major"
    return 0
  fi

  log_info "Installing Java $major ($identifier) ..."
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  sdk install java $identifier"
    record_installed "java $major"
    return 0
  fi

  set +u
  printf 'n\n' | sdk install java "$identifier"
  rc=$?
  set -u

  if [ "$rc" -ne 0 ] || ! java_installed_via_sdkman "$identifier"; then
    log_error "Failed to install Java $major ($identifier)"
    record_failed "java $major"
    return 1
  fi
  log_ok "Java $major ($identifier) is installed"
  record_installed "java $major"
}

# Highest feature version in a comma or space separated list.
highest_version() {
  printf '%s\n' "$1" | tr ',' '\n' | grep -E '^[0-9]+$' | sort -n | tail -1
}

install_java() {
  local majors major identifier default_identifier="" default_major="" rc

  install_sdkman || { record_failed "java (sdkman)"; return 1; }

  # `sdk` is a shell function, so it must be defined in every interactive
  # shell, not just login shells. SDKMAN's own installer adds this to the rc
  # file too; the guard makes a duplicate harmless.
  RC_CONSIDERED=1
  if shell_files_have_sdkman_init; then
    log_info "SDKMAN init is already in your shell startup files; not adding another copy"
  else
    add_managed_rc_line "export SDKMAN_DIR=\"$(sdkman_dir)\""
    add_managed_rc_line "[ -s \"\$SDKMAN_DIR/bin/sdkman-init.sh\" ] && . \"\$SDKMAN_DIR/bin/sdkman-init.sh\""
  fi

  if [ "$DRY_RUN" -eq 0 ] && ! sdkman_load; then
    log_error "SDKMAN is installed but could not be loaded; skipping Java"
    record_failed "java (sdkman)"
    return 1
  fi

  if ! sdkman_fetch_java_list; then
    log_error "Could not reach the SDKMAN API to list available JDKs"
    record_failed "java"
    return 1
  fi

  majors="$(printf '%s' "$JDK_VERSIONS" | tr ',' ' ')"
  default_major="${JDK_DEFAULT:-$(highest_version "$JDK_VERSIONS")}"

  log_info "SDKMAN platform $(sdkman_platform); available Java versions: $(sdkman_available_majors)"

  for major in $majors; do
    identifier="$(sdkman_installed_java_for_major "$major")"

    if [ -n "$identifier" ]; then
      log_ok "Java $major ($identifier) is already installed"
      record_skipped "java $major"
    else
      identifier="$(sdkman_resolve_java "$major")"
      if [ -z "$identifier" ]; then
        # Java 22 lands here. It was a non-LTS release, now past end of life,
        # and no vendor still publishes it, so it cannot be installed even
        # though older guides and blog posts still mention it.
        log_error "No Java $major build is available for $(sdkman_platform). Available: $(sdkman_available_majors)"
        record_failed "java $major"
        continue
      fi
      sdkman_install_java "$identifier" "$major" || continue
    fi

    [ "$major" = "$default_major" ] && default_identifier="$identifier"
  done

  # SDKMAN exports JAVA_HOME itself, pointing at the stable
  # candidates/java/current symlink, so the script must not export it too.
  if [ -n "$default_identifier" ]; then
    log_info "Setting Java $default_major ($default_identifier) as the default ..."
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  sdk default java $default_identifier"
    else
      set +u
      sdk default java "$default_identifier"
      rc=$?
      set -u
      if [ "$rc" -eq 0 ]; then
        log_ok "Default Java is now $default_major ($default_identifier)"
      else
        log_warn "Could not set Java $default_major as the default"
      fi
    fi
  elif [ -n "$default_major" ]; then
    log_warn "Java $default_major was requested as the default but is not installed; the default is unchanged"
  fi

  log_info "Switch for this shell only : sdk use java <identifier>"
  log_info "Change the default         : sdk default java <identifier>"
  log_info "See what is installed      : sdk list java"
}

# Home directory of a Homebrew-installed tool: the directory that holds bin/.
#
# Homebrew keeps most JVM tools under <prefix>/libexec and links only wrapper
# scripts into <prefix>/bin, but the layout is not uniform across formulae, so
# both candidates are probed instead of assumed. `brew --prefix <formula>` is
# used rather than a hardcoded Cellar path, so this resolves correctly under
# both /opt/homebrew and /usr/local, and the opt path it returns stays valid
# across version upgrades.
brew_tool_home() {
  local prefix candidate
  prefix="$(brew --prefix "$1" 2>/dev/null)"
  [ -n "$prefix" ] || return 1
  for candidate in "$prefix/libexec" "$prefix"; do
    if [ -d "$candidate/bin" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Install a formula and publish its home directory as $2.
install_formula_with_home() {
  local formula="$1" var_name="$2" home
  brew_install_formula "$formula" || return 1
  [ "$DRY_RUN" -eq 1 ] && return 0

  home="$(brew_tool_home "$formula")"
  if [ -n "$home" ]; then
    set_env_var "$var_name" "$home"
    log_ok "$var_name -> $home"
  else
    log_warn "Installed $formula but could not locate its home directory; $var_name was not set"
  fi
}

install_maven()  { install_formula_with_home maven M2_HOME; }
install_gradle() { install_formula_with_home gradle GRADLE_HOME; }
install_scala()  { install_formula_with_home "scala@2.12" SCALA_HOME; }

install_mysql() {
  brew_install_formula mysql || return 1
  local server_is_new="$LAST_INSTALL_WAS_NEW"

  brew_install_cask mysqlworkbench

  [ "$DRY_RUN" -eq 1 ] && return 0

  # Only touch the service and print the hardening hint for a fresh server. On a
  # re-run the server is already configured and running.
  if [ "$server_is_new" -eq 1 ]; then
    if run brew services start mysql; then
      log_ok "MySQL service started"
    else
      log_warn "Could not start the MySQL service; start it with 'brew services start mysql'"
    fi
    # The previous version set the root password to 'root'. Choosing a real
    # password is left to the user.
    log_info "Secure the new MySQL server with: mysql_secure_installation"
  fi
}

install_app() {
  local app="$1" resolved kind token
  resolved="$(resolve_app "$app")"
  kind="${resolved%% *}"
  token="${resolved#* }"

  case "$kind" in
    formula) brew_install_formula "$token" ;;
    cask)    brew_install_cask "$token" ;;
    auto)    brew_install_auto "$token" ;;
    custom)
      case "$token" in
        java)   install_java ;;
        maven)  install_maven ;;
        gradle) install_gradle ;;
        scala)  install_scala ;;
        mysql)  install_mysql ;;
        *)      log_error "No handler for custom app '$token'"; record_failed "$app"; return 1 ;;
      esac
      ;;
    *) log_error "Cannot resolve '$app'"; record_failed "$app"; return 1 ;;
  esac
}

install_app_list() {
  local title="$1"; shift
  [ "$#" -gt 0 ] || return 0
  log_step "$title ($# application(s))"
  local app
  for app in "$@"; do
    install_app "$app"
  done
}

# ------------------------------------------------------------------------------
# Reporting
# ------------------------------------------------------------------------------
print_list() {
  local label="$1" color="$2"; shift 2
  [ "$#" -gt 0 ] || return 0
  printf '  %s%s (%d)%s: %s\n' "$color" "$label" "$#" "$C_RESET" "$*"
}

print_summary() {
  log_step "Summary"
  print_list "Installed" "$C_GREEN" ${INSTALLED_APPS[@]+"${INSTALLED_APPS[@]}"}
  print_list "Already present" "$C_BLUE" ${SKIPPED_APPS[@]+"${SKIPPED_APPS[@]}"}
  print_list "Failed" "$C_RED" ${FAILED_APPS[@]+"${FAILED_APPS[@]}"}

  if [ "${#FAILED_APPS[@]}" -gt 0 ]; then
    printf '\n'
    log_warn "${#FAILED_APPS[@]} application(s) failed. Re-run with just those names to retry, for example:"
    printf '    ./%s %s\n' "$SCRIPT_NAME" "${FAILED_APPS[*]}"
    return 1
  fi

  printf '\n'
  log_ok "All requested applications are in place."
  return 0
}

show_lists() {
  detect_architecture
  detect_homebrew_prefix >/dev/null 2>&1 || true
  detect_shell_files
  print_system_summary
  log_step "Basic applications"
  printf '  %s\n' "${BASIC_APPS_LIST[*]}"
  log_step "Advanced applications"
  printf '  %s\n' "${ADVANCED_APPS_LIST[*]}"
  log_step "Resolution"
  local app
  for app in "${BASIC_APPS_LIST[@]}" "${ADVANCED_APPS_LIST[@]}"; do
    printf '  %-18s -> %s\n' "$app" "$(resolve_app "$app")"
  done
}

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ "$DRY_RUN" -eq 1 ] && return 0
  [ -t 0 ] || return 0
  local reply
  printf '\n%sProceed with the installation? [y/N]%s ' "$C_BOLD" "$C_RESET"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) log_info "Aborted."; exit 0 ;;
  esac
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
  parse_args "$@"

  if [ "$LIST_ONLY" -eq 1 ]; then
    show_lists
    exit 0
  fi

  printf '%s\n' "${C_BOLD}Installing applications on macOS${C_RESET}"

  check_not_root
  detect_architecture
  detect_homebrew_prefix >/dev/null 2>&1 || true
  detect_shell_files
  print_system_summary
  confirm

  ensure_command_line_tools
  install_homebrew
  update_homebrew

  if [ "${#REQUESTED_APPS[@]}" -gt 0 ]; then
    install_app_list "Requested applications" "${REQUESTED_APPS[@]}"
  else
    [ "$DO_BASIC" -eq 1 ] && install_app_list "Basic applications" "${BASIC_APPS_LIST[@]}"
    [ "$DO_ADVANCED" -eq 1 ] && install_app_list "Advanced applications" "${ADVANCED_APPS_LIST[@]}"
  fi

  write_shell_files
  print_summary
}

main "$@"
