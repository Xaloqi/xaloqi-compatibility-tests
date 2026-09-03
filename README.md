# Xaloqi Compatibility Tests

[![Compatibility](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/workflows/compat.yml/badge.svg)](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/workflows/compat.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

One campaign. Four ECU simulators. Same result, every time.

This repository runs an identical [Xaloqi TestLab](https://github.com/Xaloqi/xaloqi-testlab-core)
campaign against all four Xaloqi ECU simulator variants and proves they produce
equivalent diagnostic behaviour regardless of transport (CAN / DoIP) or RTOS
(Zephyr / FreeRTOS).

**The quick check below (`--virtual`) runs entirely on the free, public
[`xaloqi-tester`](https://pypi.org/project/xaloqi-tester/) package — no
license, no private-repo access.** The full four-target build matrix uses
real transports (`socketcan` for the CAN targets, `doip` for the DoIP
ones) — both are TestLab Pro features and require a license — see
[Core vs. Pro](#core-vs-pro-what-this-repo-needs) below.

---

## Compatibility matrix

| Target | Transport | RTOS | Build |
|---|---|---|---|
| `basic_ecu` | CAN (ISO-TP, vcan0) | Zephyr 3.7 native_sim | `west build` |
| `basic_ecu_doip` | DoIP (ISO 13400, TCP) | Zephyr 3.7 native_sim | `west build` |
| `basic_ecu_freertos` | CAN (ISO-TP, vcan0) | FreeRTOS / QEMU Cortex-M4 | CMake + Ninja |
| `basic_ecu_doip_freertos` | DoIP (ISO 13400, TCP) | FreeRTOS + LwIP / QEMU | CMake + Ninja |

---

## What is tested

Every run exercises the same six UDS services against each ECU variant:

| Service | UDS code | Campaign step |
|---|---|---|
| TesterPresent | 0x3E | `tester_present` |
| DiagnosticSessionControl | 0x10 | `session: extended` |
| SecurityAccess (AES-128-CMAC) | 0x27 | `security_access: level 1` |
| ReadDataByIdentifier — VIN | 0x22 | `read_did: 0xF190` |
| ReadDTCInformation | 0x19 | `read_dtc` |
| ClearDiagnosticInformation | 0x14 | `clear_dtc: 0xFFFFFF` |

The campaign YAML ([`campaigns/core_validation.yaml`](campaigns/core_validation.yaml))
is **byte-for-byte identical** for all four targets. Only the transport config
changes per target.

---

## Run it yourself

### Option A — Quick check (in-process, no builds, no hardware)

Requires only Python 3.9+ and the free, public `xaloqi-tester` package —
no license, no private-repo access:

```bash
git clone https://github.com/Xaloqi/xaloqi-compatibility-tests
cd xaloqi-compatibility-tests

pip install xaloqi-tester

# Run the virtual validation — proves the campaign YAML is correct
XALOQI_LICENSE_SKIP=1 ./run_compat.sh --virtual
```

Expected output:

```
═══════════════════════════════════════════════════════════════
  Xaloqi Compatibility Tests
═══════════════════════════════════════════════════════════════

── Step 1: Virtual validation (in-process VirtualBus + ECU sim) ──

  Running campaign against virtual...
  ✔ virtual → PASS  (reports/virtual_run.json)

  RESULT: virtual validation PASSED  (campaign YAML is correct)
```

### Option B — Full matrix (all four ECU builds)

Requires Zephyr SDK, FreeRTOS-Kernel, QEMU, and the Xaloqi EDS repo as a sibling
directory (`../EDS`). **All four targets connect over a real transport**
(`socketcan` for the CAN targets, `doip` for the DoIP ones) and need
TestLab Pro — see [Core vs. Pro](#core-vs-pro-what-this-repo-needs).

```bash
# Set up vcan0 (once per boot)
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0

# Run everything
EDS_ROOT=../EDS FREERTOS_DIR=/opt/freertos-kernel \
  XALOQI_LICENSE_SKIP=1 ./run_compat.sh
```

Results land in `reports/`:

```
reports/
  virtual_run.json
  basic_ecu_run.json
  basic_ecu_doip_run.json
  basic_ecu_freertos_run.json
  basic_ecu_doip_freertos_run.json
```

Generate an HTML report comparing all four:

```bash
testlab report \
  --results reports/basic_ecu_run.json \
            reports/basic_ecu_doip_run.json \
            reports/basic_ecu_freertos_run.json \
            reports/basic_ecu_doip_freertos_run.json \
  --out reports/compat_matrix.html
```

---

## Repository structure

```
campaigns/
  core_validation.yaml          Identical campaign for all four targets
configs/
  basic_ecu.yaml                TestLab config — CAN, Zephyr native_sim
  basic_ecu_doip.yaml           Workspace config — DoIP, Zephyr native_sim
  basic_ecu_freertos.yaml       TestLab config — CAN, FreeRTOS/QEMU
  basic_ecu_doip_freertos.yaml  Workspace config — DoIP, FreeRTOS+LwIP/QEMU
.github/workflows/
  compat.yml                    GitHub Actions — virtual + full matrix + compare
run_compat.sh                   One-command runner script
LICENSE                         MIT
```

`reports/` is in `.gitignore` — generated at runtime only.

---

## How it works

```
┌─────────────────────────────────────────────────────────────────┐
│  campaigns/core_validation.yaml  (identical for all targets)    │
└───────────────────────────────┬─────────────────────────────────┘
                                │ testlab-run
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌──────────────┐     ┌──────────────────┐     ┌────────────────────┐
│ basic_ecu    │     │ basic_ecu_doip   │     │ basic_ecu_freertos │  ...
│ Zephyr       │     │ Zephyr           │     │ FreeRTOS           │
│ native_sim   │     │ native_sim       │     │ QEMU Cortex-M4     │
│ CAN/vcan0    │     │ DoIP 192.0.2.1   │     │ CAN/vcan0          │
└──────┬───────┘     └──────────┬───────┘     └────────┬───────────┘
       │ JSON report            │ JSON report           │ JSON report
       └────────────────────────┼───────────────────────┘
                                ▼
                    testlab compare (cross-target)
                    testlab report  (HTML matrix)
```

Each ECU simulator is built from the same Xaloqi EDS C source — same UDS stack
(19 services), same AES-128-CMAC security. The transport layer (ISO-TP CAN or
ISO 13400-2 DoIP) and RTOS are the only variables. The campaign proves they
are externally indistinguishable at the UDS protocol level.

---

## Why this matters

Automotive ECU software is validated on one hardware/OS combination and then
deployed to production variants that may differ in RTOS or connectivity.
This test suite provides continuous, machine-verifiable proof that the Xaloqi
EDS implementation behaves identically across all supported configurations.

---

## Core vs. Pro — what this repo needs

This repo tests the same six free UDS actions (session control,
SecurityAccess, DID read, DTC read/clear, TesterPresent) against all four
targets. What differs is the *transport* — and the free/Pro boundary
tracks **`--virtual` vs. any real transport, not CAN vs. DoIP**: the real
`socketcan` transport (what the CAN targets use via `--interface vcan0`)
is Pro-gated exactly like `doip` is.

| | Virtual (this repo's quick check, above) | All four `full-matrix` targets |
|---|---|---|
| Transport | in-process `VirtualBus` | real `socketcan` (vcan0) or real `doip` (TCP) |
| Package | `xaloqi-tester` (free, [PyPI](https://pypi.org/project/xaloqi-tester/)) | TestLab Pro |
| License | None | [xaloqi.com](https://xaloqi.com) |
| Reproducible by anyone | ✅ | Needs Pro |

Virtual validation (the badge above) runs on the free package with no
secret — that's the actual public, independently-reproducible claim this
repo makes. `full-matrix` and the cross-target `compare`/`report` step are
informational, `continue-on-error`, and use TestLab Pro in CI regardless
of target — same boundary as [`xaloqi-testlab-core`](https://github.com/Xaloqi/xaloqi-testlab-core#whats-in-pro).

### Known limitation: `full-matrix` isn't green yet

Some of the real-transport builds (`full-matrix`) still fail — this
doesn't affect the badge above, which is driven by `virtual-validation`
only. Two native_sim targets now build and run against real host bridges
instead of in-process loopback devices: `basic_ecu` (real CAN, `vcan0`,
[EDS#231](https://github.com/Xaloqi/EDS/issues/231)) and `basic_ecu_doip`
(real DoIP, `zeth`, [EDS#230](https://github.com/Xaloqi/EDS/issues/230) /
[#4](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/4)), both
fixed. The remaining gaps are real, tracked infrastructure, not a
mystery: no QEMU↔`vcan0` CAN bridge exists yet
([#3](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/3)),
and QEMU's own `hostfwd` DoIP path is still refused, unrelated to the
native_sim fix above
([#7](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/7)).
Tracking index: [#2](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/2).

---

## Related

- [Xaloqi TestLab Core](https://github.com/Xaloqi/xaloqi-testlab-core) — free, open-source campaign runner and UDS client used here
- [Xaloqi EDS](https://github.com/Xaloqi/EDS) — the ECU firmware this tests (open-core; runtime + examples are free, code generation is commercial)

---

## License

MIT — see [LICENSE](LICENSE). Campaign YAML, configs, and scripts are freely
reusable. The Xaloqi TestLab runner and EDS firmware are separately licensed.
