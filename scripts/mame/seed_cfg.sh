#!/bin/sh
# Seed a fresh MAME cfg directory for windowed nratechu runs so the
# MACHINE_NO_COCKTAIL warning screen (which pauses emulation) is skipped.
# Needs a ui.ini with "skip_warnings 1" on the -inipath (see docs/MAME_REFERENCE.md).
# Usage: seed_cfg.sh <cfg_dir>
d="$1"; mkdir -p "$d"; t=$(date +%s)
cat > "$d/nratechu.cfg" <<CFG
<?xml version="1.0"?>
<mameconfig version="10">
    <system name="nratechu">
        <ui_warnings launched="$t" warned="$t">
            <feature device="nratechu" type="cocktail" status="unemulated" />
        </ui_warnings>
    </system>
</mameconfig>
CFG
