"""
tests/test_run_compat_matches_ci.py -- run_compat.sh must build what CI builds (compat-tests#18).

compat.yml's full-matrix is the source of truth for how each Zephyr target is
built (EXTRA_CONF_FILE list, whether a zeth bridge is needed). The local runner
repeats that by hand, and had drifted: basic_ecu_doip was built with no conf at
all, so it was a different binary from CI's and unreachable from the host.

Run:  pytest tests/test_run_compat_matches_ci.py -v
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = (ROOT / "run_compat.sh").read_text(encoding="utf-8")
WORKFLOW = yaml.safe_load((ROOT / ".github/workflows/compat.yml").read_text(encoding="utf-8"))
MATRIX = {
    leg["target"]: leg
    for leg in WORKFLOW["jobs"]["full-matrix"]["strategy"]["matrix"]["include"]
}

# build_zephyr <target> <board> ["<conf;conf>" ["<overlay>"]]  (not the definition)
_CALL = re.compile(
    r'^build_zephyr\s+(\w+)\s+(\w+)(?:\s+"([^"]*)")?(?:\s+"([^"]*)")?\s*$', re.M)
SCRIPT_BUILDS = {
    m.group(1): (m.group(2), m.group(3) or "", m.group(4) or "")
    for m in _CALL.finditer(SCRIPT)
}


def test_script_builds_are_found() -> None:
    assert {"basic_ecu", "basic_ecu_doip"} <= set(SCRIPT_BUILDS), SCRIPT_BUILDS


@pytest.mark.parametrize("target", sorted(SCRIPT_BUILDS))
def test_zephyr_build_uses_ci_conf_list(target: str) -> None:
    leg = MATRIX[target]
    board, conf, overlay = SCRIPT_BUILDS[target]
    assert board == leg["board"]
    assert conf == leg["extra_conf"], (
        f"{target}: run_compat.sh passes {conf!r}, compat.yml passes {leg['extra_conf']!r}"
    )
    assert overlay == leg["extra_overlay"], (
        f"{target}: run_compat.sh passes overlay {overlay!r}, "
        f"compat.yml passes {leg['extra_overlay']!r}"
    )


def test_overlay_becomes_dtc_overlay_file() -> None:
    assert '"-DDTC_OVERLAY_FILE=${EDS_ROOT}/${extra_overlay}"' in SCRIPT


def test_can_leg_gets_the_zcan0_altname_like_ci() -> None:
    # compat.yml adds the altname only where needs_zcan_altname is true.
    assert MATRIX["basic_ecu"]["needs_zcan_altname"] is True
    assert "property add dev \"$VCAN_IF\" altname zcan0" in SCRIPT
    assert not MATRIX["basic_ecu_doip"]["needs_zcan_altname"]


def test_doip_leg_sets_up_zeth_like_ci() -> None:
    assert MATRIX["basic_ecu_doip"]["needs_zeth"] is True
    assert "net-setup.sh" in SCRIPT, "local runner never creates the zeth bridge CI creates"


def test_zephyr_doip_wait_targets_the_address_the_workspace_uses() -> None:
    ws = yaml.safe_load((ROOT / "configs/basic_ecu_doip.yaml").read_text(encoding="utf-8"))
    host = ws["ecus"][0]["doip_host"]
    # The FreeRTOS DoIP leg is reached through QEMU hostfwd on 127.0.0.1; only
    # the Zephyr leg talks to the zeth bridge address.
    m = re.search(r'ZETH_HOST="\$\{ZETH_HOST:-([^}]+)\}"', SCRIPT)
    assert m and m.group(1) == host, (
        f"wait_for_port polls {m and m.group(1)!r} but the campaign connects to {host!r}"
    )
