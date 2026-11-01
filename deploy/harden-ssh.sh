#!/usr/bin/env bash
# Turn off SSH password login on the droplet: root may log in with a key
# only (PermitRootLogin prohibit-password, PasswordAuthentication no).
# See docs/security-fixes-to-do.md, finding 7. Run from your Mac at the
# repo root:
#
#   ssh root@161.35.125.40 'bash -s' < deploy/harden-ssh.sh
#
# Safety net: the old sshd_config comes back by itself after 10 minutes
# unless a NEW key login confirms the change:
#
#   ssh root@161.35.125.40 'systemctl stop ssh-harden-revert.timer'
#
# Existing SSH sessions are not cut off by the reload. The DigitalOcean
# web console still works if everything else fails.
# rose2 (Ubuntu 24.04, production since 2026-11-01) does NOT need this
# script: there the same settings live in
# /etc/ssh/sshd_config.d/00-hardening.conf, set up during the migration.
# On 24.04 the drop-in directory is read first, so this script's edits to
# the main sshd_config would not take effect anyway. Kept as a record of
# what was done on rose (161.35.125.40, Ubuntu 18.04).
set -euo pipefail

C=/etc/ssh/sshd_config
B=/root/sshd_config.$(date +%Y-%m-%d-%H%M%S)-pre-harden

if [ ! -s /root/.ssh/authorized_keys ]; then
    echo "No /root/.ssh/authorized_keys: key login would not work. Stopping."
    exit 1
fi

if sshd -T | grep -qx 'passwordauthentication no' \
   && sshd -T | grep -qx 'permitrootlogin without-password'; then
    echo "Already key-only; nothing to do."
    exit 0
fi

cp -p "$C" "$B"
echo "Backup: $B"

# Comment out the current settings and put ours at the top, before any
# Match block (sshd uses the first value it sees).
python3 - "$C" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
out = []
for line in lines:
    if re.match(r"\s*(PermitRootLogin|PasswordAuthentication)\b", line):
        line = "# (harden-ssh) " + line
    out.append(line)
head = ["# Key-only root login (deploy/harden-ssh.sh in the greppit repo).",
        "PermitRootLogin prohibit-password",
        "PasswordAuthentication no",
        ""]
open(p, "w", encoding="utf-8").write("\n".join(head + out))
PY

if ! sshd -t; then
    cp -p "$B" "$C"
    echo "sshd -t failed: backup restored, ssh not reloaded."
    exit 1
fi

# The undo timer, set before reloading.
systemctl stop ssh-harden-revert.timer 2>/dev/null || true
systemctl reset-failed ssh-harden-revert.service ssh-harden-revert.timer 2>/dev/null || true
systemd-run --unit=ssh-harden-revert --on-active=600 \
    /bin/sh -c "cp -p '$B' '$C' && systemctl reload ssh"
echo "Undo timer set: the old settings return in 10 minutes unless confirmed."

systemctl reload ssh
echo "OK: ssh reloaded."
sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '
echo
echo "Now, from your Mac, confirm with a NEW key login:"
echo "  ssh root@161.35.125.40 'systemctl stop ssh-harden-revert.timer'"
