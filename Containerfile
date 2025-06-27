# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/ucore-hci:stable

COPY system_files/etc /etc

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit

# ncurses in 42 is from early 2025, and doesn't have ghostty yet
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    tic -x /ctx/infocmp-xterm-ghostty

# Verify final image and contents are correct.
RUN bootc container lint