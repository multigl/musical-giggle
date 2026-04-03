# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A custom [Universal Blue](https://universal-blue.org/) image built on top of `ghcr.io/ublue-os/ucore-hci:stable` (Fedora-based, immutable OS). It produces an OCI container image published to GHCR, which can then be converted to bootable disk images (qcow2, ISO).

## Common Commands

All workflows go through `just` (the Justfile):

```bash
just build              # Build container image locally with Podman
just lint               # Run shellcheck on all .sh files
just format             # Run shfmt on bash scripts
just check              # Check Just syntax

just build-qcow2        # Build QCOW2 VM image (alias: just build-vm)
just build-iso          # Build Anaconda installer ISO
just run-vm-qcow2       # Run QCOW2 image in QEMU/KVM (8GB RAM, 4 CPUs)
just run-vm-iso         # Boot ISO installer in QEMU/KVM
just spawn-vm           # Launch with systemd-vmspawn
just clean              # Remove build outputs and manifests
```

## Architecture

The build pipeline has three layers:

1. **`Containerfile`** — OCI build definition. Pulls the uCore base image, runs `build_files/build.sh`, integrates Homebrew from `ublue-os/brew`, and adds xterm-ghostty terminal support.

2. **`build_files/build.sh`** — Main package install script. Adds the 1Password YUM repo and installs packages (certbot, just, starship, step-cli, tuned, vim, zsh, etc.) via `rpm-ostree`.

3. **`system_files/`** — Static config dropped into the image:
   - `etc/sysctl.d/99-rootless.conf` — enables rootless container networking
   - `etc/polkit-1/rules.d/10-reboot.rules` — passwordless reboot for sudo users
   - `etc/yum.repos.d/1password.repo` — 1Password CLI repo

**CI/CD** (`.github/workflows/`):
- `build.yml` — Builds and pushes container image to `ghcr.io/$owner/musical-giggle` on push to main, daily at 10:05 UTC, or manual trigger. Signs with Cosign.
- `build-disk.yml` — Manual-only; builds qcow2 and ISO disk images using `bootc-image-builder`. Supports optional S3 upload.
