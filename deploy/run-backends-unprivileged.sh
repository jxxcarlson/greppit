#!/usr/bin/env bash
# Run the greppit, cloudelog and scripta backends on rose2 as unprivileged
# system users instead of root, in the same systemd sandbox as pdfServer.
# Run from your Mac, in the greppit repo:
#
#   ssh root@147.182.143.224 'bash -s' < deploy/run-backends-unprivileged.sh
#
# The backends write no files, open no .env themselves (systemd reads
# EnvironmentFile as root before dropping privileges) and run no other
# programs, so their sandbox allows no writes at all.
#
# scripta logs in to Postgres over the local socket with no password, as
# the system user it runs as. Its database objects move from the role
# `root` to a new role `scripta`. A pg_ident map lets both the system user
# `scripta` (the app) and `root` (the nightly dump and migrate.sh) log in
# as that role. Its .env then names the role (&user=scripta).
#
# Everything is backed up to /root/migration-backups/unprivileged-<time>/.
# Each app is switched and checked on its own; if a check fails, that app
# is put back as it was and the script stops. Running it twice is safe.
set -euo pipefail
# Your Mac's ssh passes LC_CTYPE=UTF-8, which Ubuntu doesn't know; psql (a
# perl wrapper) then prints locale warnings that pollute captured output.
export LC_ALL=C.UTF-8 LANG=C.UTF-8
unset LC_CTYPE

BK=/root/migration-backups/unprivileged-$(date +%Y-%m-%d-%H%M%S)
mkdir -p "$BK"
PGCONF=/etc/postgresql/16/main
cp -p /etc/systemd/system/{greppit,cloudelog,scripta}-backend.service "$PGCONF/pg_hba.conf" "$PGCONF/pg_ident.conf" /root/scripta-app-v4/.env "$BK/"
echo "Backups: $BK"

HARDENING='NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet='

make_user() {
    id "$1" >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$1"
}

# Rewrite a unit in place: User=root becomes the app's user, and the old
# partial hardening is replaced by the full sandbox after ExecStart.
harden_unit() {   # unit user
    python3 - "/etc/systemd/system/$1.service" "$2" "$HARDENING" <<'PY'
import sys
path, user, hardening = sys.argv[1], sys.argv[2], sys.argv[3]
old = ("NoNewPrivileges=", "ProtectSystem=", "PrivateTmp=", "PrivateDevices=", "ProtectHome=",
       "ProtectKernelTunables=", "ProtectKernelModules=", "ProtectControlGroups=",
       "RestrictSUIDSGID=", "LockPersonality=", "RestrictAddressFamilies=", "CapabilityBoundingSet=",
       "User=", "Group=", "# Unprivileged")
out = []
for line in open(path).read().split("\n"):
    if line.startswith(old):
        continue
    out.append(line)
    if line.startswith("[Service]"):
        out.append("# Unprivileged and sandboxed (greppit deploy/run-backends-unprivileged.sh).")
        out.append(f"User={user}")
        out.append(f"Group={user}")
    if line.startswith("ExecStart="):
        out.extend(hardening.split("\n"))
open(path, "w").write("\n".join(out))
PY
}

health() {   # unit port user
    systemctl daemon-reload
    systemctl restart "$1" || true    # a failed start is caught below, then rolled back
    sleep 4
    local active code who
    active=$(systemctl is-active "$1" || true)
    code=$(curl -s -m 5 -o /dev/null -w "%{http_code}" "http://127.0.0.1:$2/api/health" || true)
    who=$(ps -o user= -p "$(systemctl show -p MainPID --value "$1")" 2>/dev/null || true)
    echo "  $1: $active, /api/health $code, running as ${who:-?}"
    [ "$active" = active ] && [ "$code" = 200 ] && [ "$who" = "$3" ]
}

restore_unit() {   # unit
    cp -p "$BK/$1.service" "/etc/systemd/system/$1.service"
    systemctl daemon-reload
    systemctl restart "$1"
    echo "  $1 put back as it was: $(systemctl is-active "$1")"
}

# ---- greppit and cloudelog: password login over TCP, only the unit changes
for app in greppit:8086 cloudelog:8087; do
    name=${app%%:*}; port=${app##*:}
    echo "== $name"
    if grep -qx "User=$name" "/etc/systemd/system/$name-backend.service" \
       && [ "$(ps -o user= -p "$(systemctl show -p MainPID --value "$name-backend")")" = "$name" ]; then
        echo "  already runs as $name; skipped"; continue
    fi
    make_user "$name"
    harden_unit "$name-backend" "$name"
    if ! health "$name-backend" "$port" "$name"; then
        echo "  CHECK FAILED"; journalctl -u "$name-backend" -n 15 --no-pager -o cat
        restore_unit "$name-backend"; exit 1
    fi
done

# ---- scripta: also move its database login from role root to role scripta
echo "== scripta"
make_user scripta
URL='postgresql:///scripta_v4?host=/var/run/postgresql&user=scripta'

sudo -u postgres psql -qc "DO \$\$BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='scripta') THEN CREATE ROLE scripta LOGIN NOSUPERUSER; END IF; END\$\$;"
grep -qE '^scripta[[:space:]]+root[[:space:]]+scripta' "$PGCONF/pg_ident.conf" || printf '%s\n' \
    '# scripta: the app (system user scripta) and root (nightly dump, migrate.sh) log in as role scripta' \
    'scripta         root                    scripta' \
    'scripta         scripta                 scripta' >> "$PGCONF/pg_ident.conf"
grep -q 'map=scripta' "$PGCONF/pg_hba.conf" || python3 - "$PGCONF/pg_hba.conf" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
i = next(n for n, l in enumerate(lines) if l.split()[:3] == ["local", "all", "all"])
lines.insert(i, "local   scripta_v4      scripta                                 peer map=scripta")
open(p, "w").write("\n".join(lines))
PY
systemctl reload postgresql
[ "$(psql "$URL" -Atc 'select current_user')" = scripta ] || { echo "  root can't log in as role scripta; stopping"; exit 1; }

scripta_back() {
    sudo -u postgres psql -d scripta_v4 -qc "REASSIGN OWNED BY scripta TO root" || true
    cp -p "$BK/.env" /root/scripta-app-v4/.env
    restore_unit scripta-backend
}

systemctl stop scripta-backend
sudo -u postgres psql -d scripta_v4 -qc "REASSIGN OWNED BY root TO scripta; ALTER DATABASE scripta_v4 OWNER TO scripta;"
# Not sed: an "&" in the URL would mean "the matched text" in its replacement.
python3 - /root/scripta-app-v4/.env "$URL" <<'PY'
import sys
p, url = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n")
open(p, "w").write("\n".join(("DATABASE_URL=" + url) if l.startswith("DATABASE_URL=") else l for l in lines))
PY
grep -qx "DATABASE_URL=$URL" /root/scripta-app-v4/.env || { echo "  .env not updated as expected"; exit 1; }
harden_unit scripta-backend scripta

# Can the app's user, inside the same sandbox, read its data?
# Only the query's answer is captured; errors go to a file, shown on failure.
inside=$(systemd-run --quiet --wait --pipe --uid=scripta --gid=scripta \
    -p ProtectSystem=strict -p ProtectHome=read-only -p PrivateTmp=yes -p NoNewPrivileges=yes \
    -p "RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX" -E LC_ALL=C.UTF-8 \
    psql "$URL" -Atc 'select count(*) from documents' 2>/tmp/scripta-check.err || true)
asroot=$(psql "$URL" -Atc 'select count(*) from documents' 2>>/tmp/scripta-check.err || true)
echo "  documents, read as scripta in the sandbox: $inside; as root (backups): $asroot"
[ -s /tmp/scripta-check.err ] && { echo "  query errors:"; sed 's/^/    /' /tmp/scripta-check.err; }
rm -f /tmp/scripta-check.err

if ! [[ "$inside" =~ ^[0-9]+$ ]] || [ "$inside" != "$asroot" ] || ! health scripta-backend 8085 scripta; then
    echo "  CHECK FAILED"; journalctl -u scripta-backend -n 15 --no-pager -o cat
    scripta_back; exit 1
fi
pg_dump --schema-only "$URL" > /dev/null && echo "  pg_dump as root works (nightly backup)"

echo
echo "Done. Running as:"
for s in greppit-backend cloudelog-backend scripta-backend pdfServer; do
    printf "  %-18s %s\n" "$s" "$(ps -o user= -p "$(systemctl show -p MainPID --value "$s")")"
done
