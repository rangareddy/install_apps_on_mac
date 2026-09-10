# Install Applications on Mac

Install your development applications on macOS with one script, on both
**Apple Silicon** (arm64: M1/M2/M3/M4) and **Intel** (x86_64) Macs.

## Introduction

`Install_Apps_on_Mac.sh` installs Homebrew if it is missing, then installs a
configurable list of formulae and casks. It detects the machine architecture and
adapts: the correct Homebrew prefix, an architecture-appropriate JDK, Rosetta 2
only when an application genuinely needs it, and environment variables written
to the profile your login shell actually reads.

It is safe to re-run. Anything already installed is reported and skipped.

## Requirements

* macOS on Apple Silicon or Intel
* `curl` and `unzip`, both preinstalled on macOS (SDKMAN needs them)
* An administrator account (Homebrew and some casks ask for your password)
* Xcode Command Line Tools (the script installs them if missing)

Run it as your **normal user**, not with `sudo`. Homebrew refuses to run as
root, and the script stops early if you try.

## Usage

```sh
git clone https://github.com/rangareddy/install_apps_on_mac.git
cd install_apps_on_mac
chmod +x Install_Apps_on_Mac.sh
./Install_Apps_on_Mac.sh
```

Preview the whole run without changing anything:

```sh
./Install_Apps_on_Mac.sh --dry-run
```

### Options

| Option | Description |
| --- | --- |
| `-b`, `--basic` | Install the basic application list only. |
| `-a`, `--advanced` | Install the advanced application list only. |
| `--all` | Install both lists. Default when nothing else is given. |
| `-j`, `--jdk-versions LIST` | Comma-separated JDK feature versions to install via SDKMAN. Default `11,17,21`. |
| `--jdk-default VER` | Which of those becomes the SDKMAN default. Default: the highest installed. |
| `--jdk-version VER` | Alias for installing a single JDK and defaulting to it. |
| `-n`, `--dry-run` | Print what would happen, change nothing. |
| `-l`, `--list` | Show the detected system and the resolved application lists, then exit. |
| `-s`, `--skip-update` | Do not run `brew update` first. |
| `-y`, `--yes` | Do not prompt for confirmation. |
| `-h`, `--help` | Show help. |
| `-v`, `--version` | Show the script version. |

### Examples

```sh
./Install_Apps_on_Mac.sh                      # everything
./Install_Apps_on_Mac.sh --basic              # basic list only
./Install_Apps_on_Mac.sh --dry-run --all      # preview the full run
./Install_Apps_on_Mac.sh java maven gradle    # just the JVM toolchain
./Install_Apps_on_Mac.sh -j 11,17,21 java     # three JDKs, newest as default
./Install_Apps_on_Mac.sh --jdk-default 17 java
./Install_Apps_on_Mac.sh docker rectangle     # any Homebrew formula or cask
```

## Choosing what gets installed

Edit the two lists at the top of the script:

```sh
BASIC_APPS_LIST=(git wget telnet netcat jq bash-completion iterm2 tree)
ADVANCED_APPS_LIST=(code java maven idea mysql sublime)
```

Entries can be an alias from the table below, or **any Homebrew formula or cask
token**. Unknown names are resolved against Homebrew at run time (formula first,
then cask), so you can add `docker`, `postgresql@16`, `rectangle` and so on
without touching any other part of the script.

| Alias | Installs | Also sets |
| --- | --- | --- |
| `code`, `vscode` | `visual-studio-code` | |
| `idea`, `intellij` | `intellij-idea` | |
| `sublime` | `sublime-text` | |
| `iterm`, `iterm2` | `iterm2` | |
| `java`, `jdk` | SDKMAN plus the JDKs in `--jdk-versions` | `JAVA_HOME` (by SDKMAN) |
| `maven`, `mvn` | `maven` | `M2_HOME` |
| `gradle` | `gradle` | `GRADLE_HOME` |
| `scala` | `scala@2.12` | `SCALA_HOME` |
| `mysql` | `mysql` server + MySQL Workbench | |

## How architecture support works

| | Apple Silicon (arm64) | Intel (x86_64) |
| --- | --- | --- |
| Homebrew prefix | `/opt/homebrew` | `/usr/local` |
| SDKMAN platform | `darwinarm64` | `darwinx64` |
| JDK 8 | `8.x-zulu` (native aarch64) | `8.x-tem` |
| JDK 11 and later | `<version>-tem` | `<version>-tem` |
| Rosetta 2 | installed on demand, per application | not applicable |

A few details worth knowing:

* **The physical CPU is detected, not the emulated one.** `uname -m` reports
  `x86_64` for any process running under Rosetta 2, which would send the script
  to the Intel Homebrew prefix on an Apple Silicon Mac. The script reads
  `sysctl hw.optional.arm64` instead, and warns you if the shell itself is
  translated.
* **JDK 8 on Apple Silicon uses Azul Zulu.** Eclipse Temurin publishes no
  macOS aarch64 build for Java 8, so Temurin would give you an Intel JDK running
  under Rosetta. Zulu ships a native aarch64 build. Asking SDKMAN for Java 8
  resolves to `8.0.504+1-zulu` on Apple Silicon and `8.0.502-tem` on Intel.
* **Rosetta 2 is installed only when needed.** Before installing a cask, the
  script asks Homebrew for the download URL it resolved for this architecture.
  If that URL is an Intel-only build, Rosetta 2 is installed first; universal and
  native builds need nothing.
* **A native Homebrew wins over an Intel one.** If both `/opt/homebrew` and
  `/usr/local` contain a `brew`, the architecture-native prefix is used.

## Java: multiple JDKs, switchable

Java is installed with [SDKMAN](https://sdkman.io) rather than Homebrew casks,
so several JDKs coexist and you can switch between them. A cask installs one JDK
per formula and has no switching story.

By default **JDK 11, 17 and 21** are installed and the highest (21) becomes the
default:

```sh
./Install_Apps_on_Mac.sh java                      # 11, 17, 21; default 21
./Install_Apps_on_Mac.sh -j 11,17,21,25 java       # add 25
./Install_Apps_on_Mac.sh -j 11,17,21 --jdk-default 17 java
```

Switching afterwards is plain SDKMAN:

```sh
sdk list java                     # what is installed and what is available
sdk use java 17.0.20-tem          # this shell only
sdk default java 21.0.12+1.1-tem  # the default for new shells
sdk current java                  # what is active now
sdk home java 11.0.32-tem         # print that JDK's home directory
```

### Version identifiers are resolved, not hardcoded

You give feature versions (`17`); the script asks SDKMAN which builds exist for
your architecture and picks the newest patch release from the first vendor that
has one. Vendor order is Temurin, then Zulu, Corretto and Liberica. Nothing in
the script goes stale when a new patch release lands, and early-access builds
are excluded.

If a JDK for that feature version is **already installed**, it is reused rather
than re-downloaded just because a newer patch exists.

### Java 22 is not installable

Java 22 was a non-LTS release and is now past end of life, so no vendor still
publishes it through SDKMAN, on either architecture. Asking for it reports what
*is* available instead of failing obscurely:

```
[FAIL]  No Java 22 build is available for darwinarm64. Available: 8 11 17 21 25 26
```

Use 21 (LTS) or 25 (LTS) instead.

### JAVA_HOME

SDKMAN exports `JAVA_HOME` itself, pointing at
`~/.sdkman/candidates/java/current`, a symlink that follows whatever you set as
the default. The script does not set `JAVA_HOME`, so nothing fights over it.

## Environment variables

Two files are used, because they serve different purposes.

**The login profile** carries `PATH` and `*_HOME` exports: `~/.zprofile` for zsh
(the macOS default since Catalina), `~/.bash_profile` for bash, `~/.profile`
otherwise.

**The interactive rc file** carries SDKMAN's init line: `~/.zshrc` for zsh,
`~/.bashrc` for bash. This matters because `sdk` is a shell *function*, so it has
to be defined in every interactive shell. Putting it only in the login profile
leaves `sdk` missing from any non-login shell.

Each gets a single managed block:

```sh
# ~/.zprofile
# >>> install_apps_on_mac >>>
eval "$(/opt/homebrew/bin/brew shellenv)"
export M2_HOME="/opt/homebrew/opt/maven/libexec"
export PATH="$M2_HOME/bin:$PATH"
# <<< install_apps_on_mac <<<

# ~/.zshrc
# >>> install_apps_on_mac-sdkman >>>
export SDKMAN_DIR="$HOME/.sdkman"
[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"
# <<< install_apps_on_mac-sdkman <<<
```

Each block is rewritten in place on every run, so repeat runs never pile up
duplicate `PATH` and `*_HOME` entries, and a block that is no longer needed is
removed rather than left stale. Anything outside a block is left alone, and the
file's permissions are preserved.

A block reflects **what the current run configured**. If you run
`--basic` only, the profile block will not contain `M2_HOME`, because that run
did not set up Maven. Run the script with the app selection you want reflected
there.

If your profile already evaluates `brew shellenv`, the script notices and does
not add a second copy.

After the script finishes, either open a new terminal or run:

```sh
source ~/.zprofile   # or ~/.bash_profile
```

## Defaults installed

**Basic:** git, wget, telnet, netcat, jq, bash-completion, iTerm2, tree

**Advanced:** Visual Studio Code, SDKMAN with JDK 11/17/21 (default 21), Maven,
IntelliJ IDEA, MySQL + Workbench, Sublime Text

## MySQL

The MySQL server is installed and started via `brew services`. The script does
**not** set a root password. Secure the new server yourself:

```sh
mysql_secure_installation
```

## Notes

* Written for `bash` 3.2, the version macOS ships at `/bin/bash`, so it runs
  without installing a newer bash.
* Passes `shellcheck` with no findings.
* If an application fails, the run continues and the failures are listed at the
  end with a ready-to-paste retry command.
* `Install_Apps_on_Mac_Old.sh` is the original version, kept for reference.

## License

[Apache License 2.0](LICENSE)
