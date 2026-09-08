#!/usr/bin/env bash
#
# Name         : Install_Apps_on_Mac.sh
# Purpose      : Install development applications on macOS, on both Apple Silicon
#                (arm64: M1/M2/M3/M4) and Intel (x86_64) Macs.
# Author       : Ranga Reddy
# Created Date : 27-Sep-2020
# Updated Date : 08-Sep-2026
# Version      : v2.0
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
SCRIPT_VERSION="2.0"
MANAGED_BLOCK_TAG="install_apps_on_mac"

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

# Java version installed by the `java` app. Override with --jdk-version.
JDK_VERSION="17"

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
  -j, --jdk-version VER    JDK feature version for the 'java' app
                           (8, 11, 17, 21, ...). Default: $JDK_VERSION
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
  java, jdk         -> architecture-appropriate JDK + JAVA_HOME
  maven, mvn        -> maven + M2_HOME
  gradle            -> gradle + GRADLE_HOME
  scala             -> scala@2.12 + SCALA_HOME
  mysql             -> mysql server + MySQL Workbench

${C_BOLD}EXAMPLES${C_RESET}
  $SCRIPT_NAME                          # install everything
  $SCRIPT_NAME --basic                  # basic list only
  $SCRIPT_NAME --dry-run --all          # preview the full run
  $SCRIPT_NAME java maven gradle        # just the JVM toolchain
  $SCRIPT_NAME --jdk-version 21 java    # JDK 21 instead of $JDK_VERSION
  $SCRIPT_NAME docker rectangle         # arbitrary casks

${C_BOLD}NOTES${C_RESET}
  Run as a normal user, not with sudo. Homebrew refuses to run as root and will
  ask for your password only when a cask needs it.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -b|--basic)       DO_BASIC=1 ;;
      -a|--advanced)    DO_ADVANCED=1 ;;
      --all)            DO_BASIC=1; DO_ADVANCED=1 ;;
      -j|--jdk-version)
        [ "$#" -ge 2 ] || die "--jdk-version needs a value (for example: 17)"
        case "$2" in
          ''|*[!0-9]*) die "--jdk-version must be a feature number such as 8, 11, 17 or 21; got '$2'" ;;
        esac
        JDK_VERSION="$2"; shift ;;
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

# Pick the profile the user's login shell actually reads. The original script
# hardcoded ~/.bash_profile, which zsh (the macOS default since Catalina) never
# sources.
detect_shell_profile() {
  case "${SHELL##*/}" in
    zsh)  SHELL_PROFILE="$HOME/.zprofile" ;;
    bash) SHELL_PROFILE="$HOME/.bash_profile" ;;
    *)    SHELL_PROFILE="$HOME/.profile" ;;
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
  printf '  JDK version      : %s\n' "$JDK_VERSION"
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
  add_managed_line "eval \"\$($HOMEBREW_PREFIX/bin/brew shellenv)\""
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

add_managed_line() {
  local line="$1" existing
  for existing in ${MANAGED_LINES[@]+"${MANAGED_LINES[@]}"}; do
    [ "$existing" = "$line" ] && return 0
  done
  MANAGED_LINES+=("$line")
}

set_env_var() {
  local name="$1" value="$2"
  [ -n "$value" ] || return 0
  add_managed_line "export $name=\"$value\""
  add_managed_line "export PATH=\"\$$name/bin:\$PATH\""
  # Make it available to the rest of this run too.
  export "$name=$value"
}

write_shell_profile() {
  [ "${#MANAGED_LINES[@]}" -gt 0 ] || return 0

  log_step "Shell profile"

  local begin="# >>> $MANAGED_BLOCK_TAG >>>"
  local end="# <<< $MANAGED_BLOCK_TAG <<<"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${C_YELLOW}[DRY ]${C_RESET}  would write this block to $SHELL_PROFILE:"
    printf '  %s\n' "$begin"
    printf '  %s\n' ${MANAGED_LINES[@]+"${MANAGED_LINES[@]}"}
    printf '  %s\n' "$end"
    return 0
  fi

  touch "$SHELL_PROFILE" || { log_warn "Cannot write $SHELL_PROFILE"; return 1; }

  # Stage the rewrite next to the profile so the final mv is atomic and cannot
  # cross a filesystem boundary, and carry the original file mode over so the
  # profile does not silently become mktemp's 0600.
  local tmp mode
  tmp="$(mktemp "$(dirname "$SHELL_PROFILE")/.${MANAGED_BLOCK_TAG}.XXXXXX")" || return 1
  mode="$(stat -f '%Lp' "$SHELL_PROFILE" 2>/dev/null)"

  # Copy the profile, dropping any previous managed block.
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$SHELL_PROFILE" > "$tmp"

  {
    printf '%s\n' "$begin"
    printf '# Managed by %s - edits inside this block are overwritten.\n' "$SCRIPT_NAME"
    printf '%s\n' ${MANAGED_LINES[@]+"${MANAGED_LINES[@]}"}
    printf '%s\n' "$end"
  } >> "$tmp"

  [ -n "$mode" ] && chmod "$mode" "$tmp"

  if mv "$tmp" "$SHELL_PROFILE"; then
    log_ok "Updated $SHELL_PROFILE (${#MANAGED_LINES[@]} managed lines)"
    log_info "Run 'source $SHELL_PROFILE' or open a new terminal to pick up the changes"
  else
    rm -f "$tmp"
    log_warn "Could not update $SHELL_PROFILE"
    return 1
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

# Choose a JDK cask that has a native build for this architecture.
#
# Verified against the Homebrew cask index: temurin@8 ships only an x64 pkg, so
# on Apple Silicon it would install an Intel JDK that needs Rosetta. zulu@8 ships
# a native aarch64 dmg. For 11 and later, temurin publishes aarch64 builds and is
# used on both architectures.
jdk_cask_for_arch() {
  local version="$1"
  if [ "$version" = "8" ] && [ "$IS_APPLE_SILICON" -eq 1 ]; then
    echo "zulu@8"
  else
    echo "temurin@$version"
  fi
}

# `/usr/libexec/java_home` wants "1.8" for Java 8 and the bare feature number
# from 9 onwards.
java_home_spec() {
  if [ "$1" = "8" ]; then echo "1.8"; else echo "$1"; fi
}

# Feature version of the JDK installed at $1: 8 for 1.8.0_292, 17 for 17.0.15.
jdk_feature_version() {
  local version=""
  if [ -r "$1/release" ]; then
    version="$(sed -n 's/^JAVA_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$1/release" | head -1)"
  fi
  if [ -z "$version" ] && [ -x "$1/bin/java" ]; then
    version="$("$1/bin/java" -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1)"
  fi
  case "$version" in
    1.8*) echo 8 ;;
    "")   echo "" ;;
    *)    echo "${version%%.*}" ;;
  esac
}

# JAVA_HOME of an installed JDK matching feature version $1, or empty.
#
# `java_home -v N` cannot be trusted on its own: when version N is absent it
# silently returns the newest installed JDK and exits 0, so `-v 21` answers with
# a JDK 17 path on a machine that has no JDK 21. The candidate it returns is
# therefore verified against the JDK's own release metadata.
find_installed_jdk() {
  local want="$1" home actual
  home="$(/usr/libexec/java_home -v "$(java_home_spec "$want")" 2>/dev/null)"
  [ -n "$home" ] || return 0
  actual="$(jdk_feature_version "$home")"
  [ "$actual" = "$want" ] && printf '%s\n' "$home"
  return 0
}

install_java() {
  local existing cask_token
  existing="$(find_installed_jdk "$JDK_VERSION")"

  if [ -n "$existing" ]; then
    log_ok "JDK $JDK_VERSION is already installed at $existing"
    record_skipped "java (jdk $JDK_VERSION)"
  else
    cask_token="$(jdk_cask_for_arch "$JDK_VERSION")"
    log_info "No JDK $JDK_VERSION found; selected $cask_token for $MAC_ARCH"
    if ! brew_install_cask "$cask_token"; then
      log_error "Could not install a JDK $JDK_VERSION"
      return 1
    fi
    if [ "$DRY_RUN" -eq 0 ]; then
      existing="$(find_installed_jdk "$JDK_VERSION")"
      if [ -z "$existing" ]; then
        log_warn "$cask_token installed but no JDK $JDK_VERSION is visible to /usr/libexec/java_home; JAVA_HOME was not set"
        return 1
      fi
    fi
  fi

  # Export JAVA_HOME through java_home rather than a literal path so the value
  # keeps working across JDK patch upgrades, which move the Cellar path.
  add_managed_line "export JAVA_HOME=\"\$(/usr/libexec/java_home -v $(java_home_spec "$JDK_VERSION"))\""
  add_managed_line "export PATH=\"\$JAVA_HOME/bin:\$PATH\""
  [ -n "$existing" ] && export JAVA_HOME="$existing"
  log_ok "JAVA_HOME -> ${existing:-resolved at shell startup}"
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
  detect_shell_profile
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
  detect_shell_profile
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

  write_shell_profile
  print_summary
}

main "$@"
