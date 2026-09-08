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
| `-j`, `--jdk-version VER` | JDK feature version for the `java` app (`8`, `11`, `17`, `21`, ...). Default `17`. |
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
./Install_Apps_on_Mac.sh --jdk-version 21 java
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
| `java`, `jdk` | architecture-appropriate JDK | `JAVA_HOME` |
| `maven`, `mvn` | `maven` | `M2_HOME` |
| `gradle` | `gradle` | `GRADLE_HOME` |
| `scala` | `scala@2.12` | `SCALA_HOME` |
| `mysql` | `mysql` server + MySQL Workbench | |

## How architecture support works

| | Apple Silicon (arm64) | Intel (x86_64) |
| --- | --- | --- |
| Homebrew prefix | `/opt/homebrew` | `/usr/local` |
| JDK 8 | `zulu@8` (native aarch64 build) | `temurin@8` |
| JDK 11 and later | `temurin@<version>` | `temurin@<version>` |
| Rosetta 2 | installed on demand, per application | not applicable |

A few details worth knowing:

* **The physical CPU is detected, not the emulated one.** `uname -m` reports
  `x86_64` for any process running under Rosetta 2, which would send the script
  to the Intel Homebrew prefix on an Apple Silicon Mac. The script reads
  `sysctl hw.optional.arm64` instead, and warns you if the shell itself is
  translated.
* **JDK 8 on Apple Silicon uses Azul Zulu.** Eclipse Temurin publishes no
  macOS aarch64 build for Java 8, so `temurin@8` would install an Intel JDK that
  runs through Rosetta. `zulu@8` ships a native aarch64 build.
* **Rosetta 2 is installed only when needed.** Before installing a cask, the
  script asks Homebrew for the download URL it resolved for this architecture.
  If that URL is an Intel-only build, Rosetta 2 is installed first; universal and
  native builds need nothing.
* **A native Homebrew wins over an Intel one.** If both `/opt/homebrew` and
  `/usr/local` contain a `brew`, the architecture-native prefix is used.

## Environment variables

Variables such as `JAVA_HOME` and `M2_HOME` are written to the profile your
login shell reads: `~/.zprofile` for zsh (the macOS default since Catalina),
`~/.bash_profile` for bash, `~/.profile` otherwise.

They go inside a single managed block:

```sh
# >>> install_apps_on_mac >>>
eval "$(/opt/homebrew/bin/brew shellenv)"
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export PATH="$JAVA_HOME/bin:$PATH"
# <<< install_apps_on_mac <<<
```

The block is rewritten in place on every run, so repeat runs never pile up
duplicate `PATH` and `*_HOME` entries. Anything outside the block is left alone.
`JAVA_HOME` is resolved through `/usr/libexec/java_home` rather than pinned to a
literal path, so it survives JDK patch upgrades.

After the script finishes, either open a new terminal or run:

```sh
source ~/.zprofile   # or ~/.bash_profile
```

## Defaults installed

**Basic:** git, wget, telnet, netcat, jq, bash-completion, iTerm2, tree

**Advanced:** Visual Studio Code, JDK 17, Maven, IntelliJ IDEA, MySQL +
Workbench, Sublime Text

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
