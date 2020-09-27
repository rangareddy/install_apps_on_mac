#!/bin/sh

echo "Installing Applications"

HOMEBREW_URL='https://raw.githubusercontent.com/Homebrew/install/master/install'
JAVA_HOME_PATH="/Library/Java/JavaVirtualMachines/adoptopenjdk-8.jdk/Contents/Home"

command_exists () {
    type "$1" &> /dev/null ;
}

############ Install Homebrew ############
if ! command_exists brew ; then
  echo "Installing HomeBrew..." 
  # supress the need to press 'return' when in the install script runs. 
  yes '' | /bin/bash -c "$(curl -fsSL $HOMEBREW_URL)"
fi

if ! command_exists brew ; then
  echo "Brew not installed... exit"
  exit 0
fi

if ! command_exists git ; then
  echo "Installing git..."
  brew install git
fi

if ! command_exists wget ; then
  echo "Installing wget..."
  brew install wget
fi

if ! command_exists code ; then
  echo "Installing Visual Studio code..."
  brew cask install --appdir='/Applications' 'visual-studio-code'
fi

checkAndInstallJava() {
  source ~/.bash_profile;
  if [ -z "$JAVA_HOME" ]; then
    if [ ! -d "$JAVA_HOME_PATH" ]; then
        echo "Installing OpenJDK8..."
        brew cask install adoptopenjdk8
    fi

    echo "Exporting the JAVA_HOME=$JAVA_HOME_PATH to .bash_profile"
    echo "export JAVA_HOME=$JAVA_HOME_PATH" >> ~/.bash_profile;
    echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> ~/.bash_profile;
    source ~/.bash_profile;
    echo "Verifying JAVA_HOME path"
    echo $JAVA_HOME
  fi
}

checkAndInstallJava

if ! command_exists mvn ; then
  echo "Installing Maven"
  brew install 'maven'

fi

if ! command_exists idea ; then
  echo "Installing IntelliJ Community Edition..."
  brew cask install --appdir='/Applications' 'intellij-idea-ce'
  sudo ln -s "/Applications/IntelliJ\ IDEA\ CE.app/Contents/MacOS/idea" /usr/local/bin/idea
fi

if ! command_exists subl ; then
  echo "Installing Sublime text..."
  brew cask install  --appdir='/Applications' 'sublime-text'
fi

echo "Applications installed successfully"