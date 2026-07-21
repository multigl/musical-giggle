# Handoff: permanent fix for boot-hang ordering cycle (`/var` on LUKS + TPM2)

**Date:** 2026-07-13
**Affected host:** `mini-pc-server`
**Image:** `ghcr.io/multigl/musical-giggle:latest` (uCore / Fedora CoreOS OCI)
**Status:** host recovered with a temporary on-host mitigation; this doc is the permanent fix to bake into the image build.

---

## TL;DR

The host stopped booting: it hangs forever on `dev-mapper-data.device/start` after logging
`Ordering cycle found, skipping blockdev@dev-mapper-data.target`.

Root cause is a systemd **ordering cycle** that appears when **`/var` is on a LUKS volume** *and* systemd's
**TPM2 measured-boot units** are active. A firmware update that exposed/enabled the TPM2 flipped those units
on and triggered a previously-latent cycle. systemd breaks the cycle by cutting the data-device job, so `/var`
never mounts.

**Permanent fix (add to the image Containerfile):**

```dockerfile
# See handoff doc: break /var-on-LUKS ↔ TPM2 measured-boot ordering cycle.
RUN ln -sf /dev/null /etc/systemd/system/systemd-pcrnvdone.service
```

This host does **not** use systemd's TPM2 sealing to unlock any disk (root = clevis, `/var`/data = keyfile),
so the masked unit is dead weight. No security or unlock regression.

---

## Symptom

Boot stalls indefinitely. Console shows:

```
[ SKIP ] Ordering cycle found, skipping blockdev@dev-mapper-data.target
...
[ **  ] Job dev-mapper-data.device/start running (Xs / no limit)
```

`no limit` = no timeout, so it never falls through to emergency on its own.

## Host storage layout (context for why this host is affected)

- `/var` lives on a **separate 1.8T LUKS2 volume**, `/dev/mapper/data` (backing part `nvme1n1p1`):
  - `var.mount`: `What=/dev/mapper/data  Where=/var  Type=xfs`, `RequiredBy=local-fs.target`
- `/etc/crypttab`:
  ```
  root UUID=d1e2ec7f-3372-4970-abdf-d12c0e6a4cc4 none            luks   # root: clevis-unlocked
  data UUID=68eed4b1-eafc-49ea-ac8e-88cb9599dbaf /etc/luks/data  luks   # /var: keyfile-unlocked
  ```
- Neither volume uses `systemd-cryptenroll`/TPM2/pcrlock. Root unlocks via **clevis** (`clevis-luks-askpass.path`),
  `/var`/data unlocks via a **keyfile** in `/etc/luks/data`.

The LUKS header, keyfile, and xfs on the data disk are all healthy — this was never a disk problem.

## The exact cycle

From `journalctl` (reproduced on the host by `systemctl --no-block start local-fs.target`):

```
cryptsetup-pre.target: Found ordering cycle:
  systemd-pcrnvdone.service/start
    after systemd-tpm2-setup.service/start
    after var.mount/start
    after blockdev@dev-mapper-data.target/start
    after systemd-cryptsetup@data.service/start
    after cryptsetup-pre.target/start
    after systemd-pcrnvdone.service
Job systemd-pcrnvdone.service/start deleted to break ordering cycle starting with cryptsetup-pre.target/start
```

As a loop:

```
cryptsetup-pre.target
  → systemd-cryptsetup@data.service   (unlock /var's LUKS disk; ordered after cryptsetup-pre)
  → blockdev@dev-mapper-data.target
  → var.mount                         (/var)
  → systemd-tpm2-setup.service        (TPM2 SRK/measured-boot setup; writes to /var/lib/systemd → after /var)
  → systemd-pcrnvdone.service         (TPM2 PCR NV finalization)
  → cryptsetup-pre.target             (measured boot ordered *before* LUKS unlock → closes the loop)
```

## Root cause

1. `/var` is on a **LUKS** volume, so mounting `/var` requires `cryptsetup-pre.target` →
   `systemd-cryptsetup@data.service` → device → `var.mount`.
2. systemd's **TPM2 measured-boot** units (`systemd-tpm2-setup.service`, `systemd-pcrnvdone.service`) write
   state under `/var/lib/systemd`, so they are ordered **after `var.mount`**.
3. Those same TPM2 units are ordered **before `cryptsetup-pre.target`** (measured boot is meant to finalize
   before TPM2-based unlocking).
4. (2) + (3) + (1) = an unsatisfiable cycle. systemd breaks it by deleting an arbitrary job in the loop. At
   real boot it cut **`blockdev@dev-mapper-data.target`**, so `/dev/mapper/data` never activates and boot hangs.

**Trigger:** a **firmware/BIOS update exposed or enabled the TPM2**, which made
`systemd-tpm2-setup.service` / `systemd-pcrnvdone.service` pass their `Condition*` checks and enter the boot
transaction for the first time. Same systemd version was already present in the prior image
(`latest.20260712`), which is why **rolling back the OS image did not help** — the cycle lives in the unit
graph, not the image bits.

> This is latent: even absent a firmware change, a future systemd bump that activates these units would
> trigger the identical hang. Baking the fix protects regardless of trigger.

## Temporary mitigation already applied on the host

Done live via the PiKVM emergency shell (persists in `/etc`, survives deployment swaps):

```bash
systemctl mask systemd-pcrnvdone.service
```

This forces the cycle to be cut at the harmless `pcrnvdone` edge (matching systemd's own resolution), so the
data device activates and `/var` mounts. Host has since rebooted cleanly multiple times.

Also, unrelated: `zincati.service` was masked during recovery to stop it auto-pulling images mid-triage —
**unmask it once the image fix ships** (`systemctl unmask zincati.service`).

---

## Permanent fix — in the `musical-giggle` image build

Add to the `Containerfile` (or wherever systemd customizations live):

```dockerfile
# Break the /var-on-LUKS ↔ TPM2 measured-boot boot ordering cycle.
#
# systemd's measured-boot finalization units order AFTER /var (they write to /var/lib/systemd)
# but also order BEFORE cryptsetup-pre.target, which must run before unlocking the LUKS volume
# that backs /var. That is an unsatisfiable cycle; systemd breaks it by cutting the data-device
# job, so /var never mounts and boot hangs on dev-mapper-data.device (no timeout).
#
# This host unlocks root via clevis and /var via a LUKS keyfile — it does NOT use systemd's
# TPM2 (systemd-cryptenroll / pcrlock) sealing — so these units are unnecessary here.
# Masking = symlink the unit to /dev/null in /etc/systemd/system (standard mask location).
RUN ln -sf /dev/null /etc/systemd/system/systemd-pcrnvdone.service
```

Notes:
- `ln -sf /dev/null /etc/systemd/system/<unit>` is exactly what `systemctl mask` does; it's the robust form
  for an image build where systemd isn't running. Use this rather than `systemctl mask` unless your build
  layer supports running `systemctl`.
- Masking a **dependency-pulled** unit requires `mask`, not `disable`/preset — the units aren't "enabled",
  they're pulled in by ordering, so a preset `disable` would not stop them.

### Optional hardening (recommended if you never intend to use TPM2 measured boot)

Mask the partner unit too, so a future systemd change that closes the loop through a different node can't
re-trigger it:

```dockerfile
RUN ln -sf /dev/null /etc/systemd/system/systemd-tpm2-setup.service
```

`systemd-pcrnvdone.service` alone was sufficient to fix this host. The partner mask is belt-and-suspenders.

## Verification after rebuild + deploy

On the host, after booting the new image:

```bash
# 1. No cycle anywhere in this boot
journalctl -b | grep -i "ordering cycle"          # expect: no output

# 2. /var mounted from the LUKS device
systemctl is-active var.mount                      # expect: active
findmnt /var                                        # expect: /dev/mapper/data, xfs

# 3. The mask is in place from the image
systemctl status systemd-pcrnvdone.service         # expect: masked
```

## Backout

If the fix ever needs reverting: remove the `RUN ln -sf …` line and rebuild, or on a running host:

```bash
systemctl unmask systemd-pcrnvdone.service
# (and systemd-tpm2-setup.service if you masked it)
```

---

## Decisions for the image maintainer

1. **Do you want TPM2 measured boot at all on this host?**
   - **No (current reality):** masking is the correct, permanent fix. Ship it.
   - **Yes:** masking is wrong long-term. You'd need to remove the cycle's precondition instead — e.g. move
     `/var` off LUKS (biggest change), or otherwise ensure the TPM2 measured-boot units don't depend on a
     LUKS-backed `/var`. That's a larger design change; out of scope for this fix.

2. **`/var`-on-LUKS is inherently fragile** w.r.t. systemd's growing set of "runs early, writes to `/var`"
   units. If you're attached to encrypting `/var`, expect to re-encounter this class of cycle on systemd
   bumps. A mask (this doc) is the pragmatic guard; long term consider whether `/var` needs to be a separate
   LUKS volume at all.

3. **Reconcile host state once the image ships the fix:** the manual `/etc` mask on `mini-pc-server` and the
   image-supplied mask both point the same unit at `/dev/null`, so they merge cleanly (no conflict). Leaving
   the host mask in place is harmless; the image is the source of truth going forward. Remember to
   `systemctl unmask zincati.service` on the host after confirming the new image boots.

## Appendix — diagnosis commands (for future reference)

```bash
# Get an emergency root shell on FCOS (no root password): at GRUB press `e`, append to the linux line:
#   systemd.unit=emergency.target systemd.debug_shell=1
# then Ctrl-X, and switch to the shell with Ctrl-Alt-F9.

# Prove the disk/keyfile are fine (isolate fault to systemd, not storage):
cryptsetup luksDump /dev/nvme1n1p1
cryptsetup open --key-file /etc/luks/data /dev/nvme1n1p1 data && echo UNLOCK_OK

# Reproduce the exact cycle without a full boot (does not hang the shell):
systemctl --no-block start local-fs.target
journalctl -b --no-pager | grep -iB3 -A25 "ordering cycle"

# Inspect the loaded ordering edges of the units involved:
systemctl show var.mount systemd-cryptsetup@data.service \
  'blockdev@dev-mapper-data.target' systemd-fsck@dev-mapper-data.service \
  -p After -p Before -p Requires -p BindsTo -p RequiresMountsFor
```
