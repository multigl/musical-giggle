# image-template

Created from [uCore](https://github.com/ublue-os/ucore?tab=readme-ov-file#installation) from [image-template](https://github.com/ublue-os/image-template)

# Purpose

Create a tailored uCore image with the following items I always use:

## Packages
* 1password cli
* just
* powerstat
* starship
* step-cli & step-ca
* tuned & profiles
* ublue brew
* vim
* zsh
* tuned & profiles

# Extras
* xterm-ghostty profile 
* [rootless containers](https://rootlesscontaine.rs/getting-started/common/sysctl/#allowing-listening-on-tcp--udp-ports-below-1024)
  * enable port 80 (and above)
  * enable ping
* allow any `sudo` users to reboot the system without entering a password (when I forget sudo)