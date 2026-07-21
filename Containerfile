# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/ucore-hci:stable

COPY system_files/etc /etc

# Break the /var-on-LUKS <-> TPM2 measured-boot boot-ordering cycle (systemd #42901 / Fedora BZ #2487442).
# systemd-pcrnvdone.service / systemd-tpm2-setup.service order BEFORE cryptsetup-pre.target, yet they write
# to /var/lib/systemd and so are ordered AFTER var.mount -- unsatisfiable when /var lives on a LUKS volume.
# systemd resolves the cycle by deleting an arbitrary edge, non-deterministically dropping the data device,
# so /var never mounts and boot hangs on dev-mapper-data.device with no timeout.
# This host unlocks root via clevis and /var via a LUKS keyfile -- never systemd-TPM2 sealing -- so both
# units are dead weight here; nothing hard-requires them, so masking cannot make another unit fail.
# Fixed upstream in systemd v261 (pcrnvdone moved into the initrd); remove this once the base image ships
# systemd >= 261. Full write-up: docs/musical-giggle-boot-cycle-handoff.md
RUN ln -sf /dev/null /etc/systemd/system/systemd-pcrnvdone.service && \
    ln -sf /dev/null /etc/systemd/system/systemd-tpm2-setup.service

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit

# Copy Homebrew files from the brew image
# And enable
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /usr/bin/systemctl preset brew-setup.service && \
    /usr/bin/systemctl preset brew-update.timer && \
    /usr/bin/systemctl preset brew-upgrade.timer

# ncurses in 42 is from early 2025, and doesn't have ghostty yet
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    tic -x /ctx/infocmp-xterm-ghostty

# Verify final image and contents are correct.
RUN bootc container lint
