# 0012: UDP checksum policy

Status: Open — review
Opened: 2026-11-25

ADR 0005 sends UDP checksum 0 and ignores RX UDP checksums. Revisit if host stacks or switches complain, or if the owner prefers computed checksums.
