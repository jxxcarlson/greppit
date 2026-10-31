#!/usr/bin/env bash
# Read-only security checks on the greppit droplet (see
# docs/security-fixes-to-do.md, "Server checks to run"). Changes nothing,
# and never prints the JWT secret, only its length. Run from your Mac at
# the repo root:
#
#   ssh root@161.35.125.40 'bash -s' < scripts/server-security-check.sh

echo "== JWT secret (want: 32+ characters, not DEFAULT)"
s=$(grep '^JWT_SECRET=' /root/greppit/.env | cut -d= -f2-)
echo "length=${#s}"
[ "$s" = "dev-secret-change-in-production-min-32-chars!!" ] && echo "DEFAULT"

echo "== .env permissions (want: 600)"
stat -c %a /root/greppit/.env

echo "== firewall"
ufw status

echo "== listening ports (want: postgres and 8086 on 127.0.0.1 only)"
ss -tlnp

echo "== ssh (want: passwordauthentication no, permitrootlogin prohibit-password or no)"
sshd -T | grep -E '^(passwordauthentication|permitrootlogin) '

echo "== fail2ban (want: active)"
systemctl is-active fail2ban

echo "== pending security updates"
apt list --upgradable 2>/dev/null | grep -i security
