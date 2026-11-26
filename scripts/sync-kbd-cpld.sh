#!/usr/bin/env bash
# Copy the MEGA65 keyboard CPLD source into third_party/mega65-keyboard-cpld
# for the nvc testbenches (issue 0046, ADR 0014):
#   top_2ed09bd.vhd  upstream master 2ed09bd (entity megakey_2ed09bd), the
#                    MK-I reference for tb_megakey_mk1_compat
#   top_type3.vhd    the type-3 firmware (entity megakey_t3), from the
#                    given ref of the CPLD repo (default: branch type3;
#                    WORKTREE = the uncommitted working copy)
# The entity is renamed so both can be simulated side by side; nothing else
# changes. Usage: scripts/sync-kbd-cpld.sh [CPLD_REPO] [REF]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
CPLD=${1:-$HOME/Projects/mega65/mega65-keyboard-cpld}
REF=${2:-type3}
OUT=$REPO/third_party/mega65-keyboard-cpld
mkdir -p "$OUT"

rename() {
	sed -e "s/^ENTITY top IS/ENTITY $1 IS/" \
	    -e "s/^END ENTITY top;/END ENTITY $1;/" \
	    -e "s/ OF top IS/ OF $1 IS/"
}

git -C "$CPLD" show 2ed09bd:src/top.vhd | rename megakey_2ed09bd > "$OUT/top_2ed09bd.vhd"
if [[ $REF == WORKTREE ]]; then
	# uncommitted working copy (for trying changes before committing)
	rename megakey_t3 < "$CPLD/src/top.vhd" > "$OUT/top_type3.vhd"
	rev="$(git -C "$CPLD" rev-parse HEAD)+uncommitted"
else
	git -C "$CPLD" show "$REF:src/top.vhd" | rename megakey_t3 > "$OUT/top_type3.vhd"
	rev=$(git -C "$CPLD" rev-parse "$REF")
fi
{
	echo "2ed09bd (upstream master, MK-I reference): top_2ed09bd.vhd"
	echo "$rev ($REF): top_type3.vhd"
} > "$OUT/UPSTREAM_COMMIT"
grep -q "ENTITY megakey_t3 IS" "$OUT/top_type3.vhd"
grep -q "ENTITY megakey_2ed09bd IS" "$OUT/top_2ed09bd.vhd"
echo "synced from $CPLD ($REF)"
