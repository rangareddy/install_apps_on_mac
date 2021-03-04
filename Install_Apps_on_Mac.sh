#!/bin/sh


#################################################################################################################################                                                                                                 
#    Name: Install_Apps_on_Mac.sh                                                                                               #
#    Purpose: Installing Development Applications on Mac OS                                                                     #
#    Author: Ranga Reddy                                                                                                        #
#    Created Date: 27-Sep-2020                                                                                                  #   
#    Version: v1.0                                                                                                              #
#                                                                                                                               #
#################################################################################################################################

echo ""
echo "Installing Applications"

HOMEBREW_URL='https://raw.githubusercontent.com/Homebrew/install/master/install'
JAVA_HOME_PATH="/Library/Java/JavaVirtualMachines/adoptopenjdk-8.jdk/Contents/Home"

command_exists () {
  type "$1" &> /dev/null ;
}

# brew
if ! command_exists brew ; then
  echo "Installing HomeBrew..." 
  # supress the need to press 'return' when in the install script runs. 
  yes '' | /bin/bash -c "$(curl -fsSL $HOMEBREW_URL)"
fi

if ! command_exists brew ; then
  echo "Brew not installed... exiting"
  exit 0
fi

brew update

# telnet
if ! command_exists telnet ; then
  echo "Installing telnet..."
  brew install telnet
fi

# git version tool
if ! command_exists git ; then
  echo "Installing git..."
  brew install git
fi

# wget
if ! command_exists wget ; then
  echo "Installing wget..."
  brew install wget
fi

# visual studio
if ! command_exists code ; then
  echo "Installing Visual Studio code..."
  brew cask install --appdir='/Applications' 'visual-studio-code'
fi

# java8
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

# scala
if ! command_exists scala ; then
  echo "Installing Scala"
  brew install 'scala@2.12'

  source ~/.bash_profile;
  if [ -z "$SCALA_HOME" ]; then
    
    SCALA_HOME_DIR=(/usr/local/Cellar/scala*/*)
    echo "Exporting the SCALA_HOME=$SCALA_HOME_DIR to .bash_profile"
    echo "export SCALA_HOME=$SCALA_HOME_DIR" >> ~/.bash_profile
    echo "export PATH=\$SCALA_HOME/bin:\$PATH" >> ~/.bash_profile
    source ~/.bash_profile
    echo "Verifying SCALA_HOME path"
    echo $SCALA_HOME
  fi

fi

# maven
if ! command_exists mvn ; then
  echo "Installing Maven build tool"
  brew install 'maven'

  MAVEN_HOME=`mvn --version | grep 'Maven home:' | cut -d ':' -f 2  | cut -d ' ' -f 2`
  source ~/.bash_profile;

  if [ -z "$M2_HOME" ]; then
      echo "export M2_HOME=$MAVEN_HOME" >> ~/.bash_profile;
      echo "export PATH=\$M2_HOME/bin:\$PATH" >> ~/.bash_profile;
  fi
  cp $MAVEN_HOME/conf/settings.xml ~/.m2/
fi

## gradle
if ! command_exists gradle ; then
  echo "Installing Gradle build tool"
  brew install gradle
  GRADLE_VERSION=`gradle --version | grep 'Gradle ' | cut -d ' ' -f 2`
  GRADLE_HOME_DIR='/usr/local/Cellar/gradle/$GRADLE_VERSION/'

  if [ -z "$GRADLE_HOME" ]; then
      echo "export GRADLE_HOME=$GRADLE_HOME_DIR" >> ~/.bash_profile;
      echo "export PATH=\$GRADLE_HOME/bin:\$PATH" >> ~/.bash_profile;
  fi
fi

# sbt
if ! command_exists sbt ; then
  echo "Installing sbt build tool"
  brew install sbt
fi

# intellij idea
if ! command_exists idea ; then
  echo "Installing IntelliJ Community Edition..."
  brew cask install --appdir='/Applications' 'intellij-idea-ce'
  sudo ln -s "/Applications/IntelliJ\ IDEA\ CE.app/Contents/MacOS/idea" /usr/local/bin/idea
fi

# sublime text editor
if ! command_exists subl ; then
  echo "Installing Sublime text..."
  brew cask install  --appdir='/Applications' 'sublime-text'
fi

# mysql --> username root and password root
if ! command_exists mysql ; then
  echo "Installing MySQL..."
  brew install mysql@5.7
  echo 'export PATH="/usr/local/opt/mysql@5.7/bin:$PATH"' >> ~/.bash_profile
  source ~/.bash_profile;
  brew services start mysql@5.7
  /usr/local/opt/mysql@5.7/bin/mysqladmin -u root password 'root'
fi

# docker
if ! command_exists docker ; then
  #brew --cask install --appdir='/Applications' 'docker'
  brew install docker docker-compose docker-machine
  brew install --cask virtualbox
fi

#brew cask install docker
#brew install kubectl
#brew cask install minikube

echo "Applications installed successfully"    
