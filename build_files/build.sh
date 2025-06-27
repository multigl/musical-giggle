#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# 1password repo setup
rpm --import https://downloads.1password.com/linux/keys/1password.asc

dnf5 install -y 1password-cli just powerstat step-cli step-ca tuned tuned-ppd tuned-profiles-atomic vim zsh