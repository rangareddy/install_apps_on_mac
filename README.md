# Install Applications on Mac

## Introduction

Simple script to install all the development related applications on Mac

## Usage

Download the `Install_Apps_on_Mac.sh` file from `https://github.com/rangareddy/install_apps_on_mac/blob/master/Install_Apps_on_Mac.sh` location.

According to your requirements, you can specify the application list using the following two parameters:

```sh
INSTALL_BASIC_APPS_LIST=("git" "wget" "telnet" "netcat" "jq" "bash-completion" "iterm2" "tree")
INSTALL_ADVANCED_APPS_LIST=("code" "java" "maven" "idea" "mysql" "sublime")
```

```sh
sh Install_Apps_on_Mac.sh
```

> You need to run the above script with root user. For example 'sudo -u rangareddy sh Install_Apps_on_Mac.sh'

By default, the following applications will be installed.

* brew
* git
* wget
* telnet
* netcat
* jq
* bash-completion
* iterm2
* tree
* Visual studio code
* Java
* Intellij Idea community
* Maven
* Mysql
* Sublime