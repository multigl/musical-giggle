#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# ensure 1password repo is loaded so we can install it
rpm --import https://downloads.1password.com/linux/keys/1password.asc
echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo

# this installs a package from fedora repos
dnf5 install -y 1password-cli zsh vim tuned tuned-ppd tuned-profiles-atomic

echo "export EDITOR=vim" > /etc/profile.d/zz-default-editor.sh

# simple file to signify we've been installed
mkdir /etc/ucore-autorebase
touch /etc/ucore-autorebase/musical-giggle