# Xaloqi Compatibility Tests

[![Compatibility](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/workflows/compat.yml/badge.svg)](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/workflows/compat.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

One campaign. Four ECU simulators. Same result, every time.

This repository runs an identical [Xaloqi TestLab](https://github.com/Xaloqi/TestLab)
campaign against all four Xaloqi ECU simulator variants and proves they produce
equivalent diagnostic behaviour regardless of transport (CAN / DoIP) or RTOS
(Zephyr / FreeRTOS).

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

Requires only Python 3.9+ and Xaloqi TestLab:

```bash
git clone https://github.com/Xaloqi/xaloqi-compatibility-tests
cd xaloqi-compatibility-tests

# Install TestLab (or: pip install xaloqi-tester if you have a license key)
pip install -e ../TestLab

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
directory (`../EDS`):

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
│ CAN/vcan0    │     │ DoIP 127.0.0.1   │     │ CAN/vcan0          │
└──────┬───────┘     └──────────┬───────┘     └────────┬───────────┘
       │ JSON report            │ JSON report           │ JSON report
       └────────────────────────┼───────────────────────┘
                                ▼
                    testlab compare (cross-target)
                    testlab report  (HTML matrix)
```

Each ECU simulator is built from the same Xaloqi EDS C source — same UDS stack,
same AES-128-CMAC security, same 14 service handlers. The transport layer (ISO-TP
CAN or ISO 13400-2 DoIP) and RTOS are the only variables. The campaign proves they
are externally indistinguishable at the UDS protocol level.

---

## Why this matters

Automotive ECU software is validated on one hardware/OS combination and then
deployed to production variants that may differ in RTOS or connectivity.
This test suite provides continuous, machine-verifiable proof that the Xaloqi
EDS implementation behaves identically across all supported configurations.

---

## Related

- [Xaloqi TestLab](https://github.com/Xaloqi/TestLab) — campaign runner and UDS library used here
- [Xaloqi EDS](https://xaloqi.com/eds) — the ECU firmware this tests (commercial)

---

## License

MIT — see [LICENSE](LICENSE). Campaign YAML, configs, and scripts are freely
reusable. The Xaloqi TestLab runner and EDS firmware are separately licensed.
