#!/bin/sh

#################################################################################################################################                                                                                                 
#    Name: Install_Apps_on_Mac.sh                                                                                               #
#    Purpose: Installing Development Applications on Mac OS                                                                     #
#    Author: Ranga Reddy                                                                                                        #
#    Created Date: 27-Sep-2020                                                                                                  #
#    Updated Date: 12-Feb-2023                                                                                                  #      
#    Version: v1.0                                                                                                              #
#                                                                                                                               #
#################################################################################################################################

echo ""
echo "==================================="
echo "Installing Applications on Mac"
echo "==================================="

export HOMEBREW_URL='https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
export HOMEBREW_CELLAR_PATH='/opt/homebrew/Cellar/'
export HOMEBREW_NO_INSTALL_CLEANUP=true
export ENV_FILE_PATH=~/.bash_profile

#INSTALL_BASIC_APPS_LIST=("telnet" "git" "wget" "jq" "bash-completion" "iterm2" "tree" "youtube-dl" "nmap" "git-lfs" "p7zip" "netcat" "htop" "tmux" "task" "imagemagick")
INSTALL_BASIC_APPS_LIST=("git" "wget" "telnet" "netcat" "jq" "bash-completion" "iterm2" "tree")

#INSTALL_ADVANCED_APPS_LIST=("code" "java" "scala" "maven" "idea" "gradle" "mysql" "sublime" "sbt" "cmake" "firefox" "vlc" "gimp")
INSTALL_ADVANCED_APPS_LIST=("code" "java" "maven" "idea" "mysql" "sublime")

# Checking commands exists or not
command_exists () {
  type "$1" &> /dev/null ;
}

# Install Brew
install_brew_software() {
  # brew
  if ! command_exists brew ; then
    echo "Installing the HomeBrew..." 
    # supress the need to press 'return' when in the install script runs. 
    yes '' | /bin/bash -c "$(curl -fsSL $HOMEBREW_URL)"
    (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> "$HOME"/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

# Update Brew
update_brew_software() {
  if ! command_exists brew ; then
    echo "Brew not installed... exiting"
    exit 0
  fi
  brew update > /dev/null 2>&1 &
}

# Install applications
brew_install() {
  app_name=$1
  if ! brew list "$app_name" &>/dev/null; then
    echo "Installing $app_name ..."
    brew install "$app_name" && echo "$app_name is installed"
  fi
}

# Install applications using cask
brew_cask_install() {
  app_name=$1
  if ! brew list "$app_name" &>/dev/null; then
    echo "Installing $app_name ..."
    brew install --cask --appdir='/Applications' "$app_name" && echo "$app_name is installed"
  fi
}

# Install Sublime
install_sublime() {
  brew_cask_install 'sublime-text'
}

# Install Visual studio
install_code() {
  brew_cask_install 'visual-studio-code'
}

# Install intellij idea
install_idea() {
  brew_cask_install 'intellij-idea-ce'
}

# Install mysql --> username: root and password: root
install_mysql() {
  brew_install 'mysql'
  mysqladmin -u root password 'root' > /dev/null 2>&1 &
  brew_cask_install 'mysqlworkbench'
}

# Install sbt
install_sbt() {
  brew_install 'sbt'
}

# Updating the variable in Env file
update_path() {
  VARIABLE_NAME="$1"
  VARIABLE_VALUE="$2"
  echo "export $VARIABLE_NAME=$VARIABLE_VALUE" >> $ENV_FILE_PATH
  path_info=$(cat ~/.bash_profile | grep -i 'export PATH=')
  if [ -z "$path_info" ]; then
    echo "export PATH=\$PATH:\$${VARIABLE_NAME}/bin" >> $ENV_FILE_PATH
  else 
    sed -i '' '/export PATH=/d' $ENV_FILE_PATH
    echo "$path_info:\$${VARIABLE_NAME}/bin" >> $ENV_FILE_PATH
  fi
  source $ENV_FILE_PATH
}

# Source the Env file
source_env_file() {
  if [ -f "$ENV_FILE_PATH" ]; then
    source "$ENV_FILE_PATH"
  fi
}

# Install java8
install_java() {
  source_env_file
  if [ -z "$JAVA_HOME" ]; then
    JAVA_HOME_PATH=(/Library/Java/JavaVirtualMachines/*jdk*/Contents/Home)
    if [ ! -d "$JAVA_HOME_PATH" ]; then
      DMG_FILE="jdk-8u321-macosx-x64.dmg"
      JAVA_DMG_PATH="https://javadl.oracle.com/webapps/download/GetFile/1.8.0_321-b07/df5ad55fdd604472a86a45a217032c7d/unix-i586/$DMG_FILE"
      wget $JAVA_DMG_PATH &> /dev/null
      if [[ "$?" != 0 ]]; then
        brew_cask_install 'adoptopenjdk8'
      else
        listing=$(hdiutil attach ${DMG_FILE} | grep Volumes)
        volume=$(echo "$listing" | cut -f 3)
        if [ -e "$volume"/*.app ]; then
          cp -rf "$volume"/*.app /Applications
        elif [ -e "$volume"/*.pkg ]; then
          package=$(ls -1 "$volume" | grep .pkg | head -1)
          installer -pkg "$volume"/"$package" -target /
        fi
        hdiutil detach "$(echo "$listing" | cut -f 3)"
      fi
    fi
    update_path "JAVA_HOME" "$JAVA_HOME_PATH"
  fi
}

# Install scala
install_scala() {
  brew_install "scala@2.12"
  source_env_file
  if [ -z "$SCALA_HOME" ]; then
    SCALA_HOME_DIR=(${HOMEBREW_CELLAR_PATH}/scala*/*)
    update_path "SCALA_HOME" "$SCALA_HOME_DIR"
  fi
}

# Install maven
install_maven() {
  brew_install "maven"
  source_env_file
  if [ -z "$M2_HOME" ]; then
      MAVEN_HOME=$(mvn --version | grep 'Maven home:' | cut -d ':' -f 2  | cut -d ' ' -f 2)
      update_path "M2_HOME" "$MAVEN_HOME"
  fi
}

# Install gradle
install_gradle() {
  brew_install "gradle"
  source_env_file
  if [ -z "$GRADLE_HOME" ]; then
    GRADLE_VERSION=$(gradle --version | grep 'Gradle ' | cut -d ' ' -f 2)
    GRADLE_HOME_DIR=${HOMEBREW_CELLAR_PATH}/gradle/$GRADLE_VERSION/
    update_path "GRADLE_HOME" "$GRADLE_HOME_DIR"
  fi
}

# Install Basic Applications
install_basic_apps() {
  echo ""
  echo "Installing basic applications"
  for app_name in "${INSTALL_BASIC_APPS_LIST[@]}"
  do
     brew_install "$app_name"
  done
  echo "Successfully installed the basic applications."
}

fn_exists() { declare -F "$1" > /dev/null; }

# Install Advanced Applications
install_advanced_apps() {
  echo ""
  echo "Installing advanced applications"
  for app_name in "${INSTALL_ADVANCED_APPS_LIST[@]}"
  do
     if ! fn_exists "install_$app_name"; then
        brew_cask_install "$app_name"
     else
        install_"$app_name"
     fi
  done
  echo "Successfully installed the advanced applications."
}

install_brew_software
update_brew_software
install_basic_apps
install_advanced_apps