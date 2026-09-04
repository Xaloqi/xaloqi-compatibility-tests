# Validation coverage statement

**What this repository proves, and what it does not.**

Last verified: **2026-09-04**, against
[workflow run 33850310832](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/runs/33850310832)
on `main`, with `Xaloqi/EDS` at `main`.

This document exists so that anyone relying on this repository as validation
evidence can see the boundary without reading CI logs. Every figure below is
taken from that run, not from a specification or a previous campaign.

---

## Summary

The compatibility matrix has four target variants: **CAN and DoIP × Zephyr and
FreeRTOS**. Two are validated end to end against real transports in CI. Two are
not, for reasons that are understood and recorded rather than open questions.

| Variant | Target | Status |
|---|---|---|
| CAN × Zephyr | `basic_ecu` | ✅ **Validated** — real host SocketCAN |
| DoIP × Zephyr | `basic_ecu_doip` | ✅ **Validated** — real host Ethernet bridge |
| DoIP × FreeRTOS | `basic_ecu_doip_freertos` | ❌ Not validated — [#7](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/7) |
| CAN × FreeRTOS | `basic_ecu_freertos` | ❌ Not validated — [#3](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/3) |

Additionally, a **transport-independent** virtual validation runs on every
commit and every scheduled run, using only the free, public `xaloqi-tester`
package with no credentials — which is what the repository's status badge
reflects.

---

## What is validated

Both validated variants run the **byte-for-byte identical** campaign,
[`campaigns/core_validation.yaml`](campaigns/core_validation.yaml). Only the
transport configuration differs. That identity is the point: it is what makes a
behavioural comparison across variants meaningful.

The campaign exercises eight steps across six UDS services: TesterPresent
(`0x3E`), DiagnosticSessionControl (`0x10`), SecurityAccess with AES-128-CMAC
(`0x27`), ReadDataByIdentifier (`0x22`, VIN), ReadDTCInformation (`0x19`, read
before and after clear) and ClearDiagnosticInformation (`0x14`).

### CAN × Zephyr — `basic_ecu`

Runs against a **real host SocketCAN interface**, not an in-process loopback.
The distinction is load-bearing, and the ECU's own boot log records which
device it bound:

```
<inf> zephyr_can: CAN: Transport initialized (device: can).
<inf> zephyr_can: CAN: functional filter installed (ID=0x7DF, slot 0).
<inf> basic_ecu: UDS stack ready: 5 DIDs  2 DTCs  RX=0x7DF TX=0x7E8
```

`device: can` — the real controller behind the `native_sim_realcan` overlay, not
`can_loopback0`. The host side is a `vcan0` interface created by the job itself.

```
[01/08] tester_present                     → OK  (1 ms)
[02/08] session(extended)                  → OK  (2 ms)
[03/08] security_access(level=1)           → OK  (34 ms)
[04/08] read_did(0xF190)                   → OK  (6 ms)
[05/08] read_dtc                           → OK  (2 ms)
[06/08] clear_dtc                          → OK  (2 ms)
[07/08] read_dtc                           → OK  (2 ms)
[08/08] session(default)                   → OK  (2 ms)
```

**8/8 steps, 1–34 ms.**

### DoIP × Zephyr — `basic_ecu_doip`

Runs over **real DoIP/TCP across a host `zeth` TAP bridge**, with real Ethernet
ARP resolution — not a Zephyr-internal loopback interface.

```
[01/08] tester_present                     → OK  (102 ms)
[02/08] session(extended)                  → OK  (102 ms)
[03/08] security_access(level=1)           → OK  (204 ms)
[04/08] read_did(0xF190)                   → OK  (102 ms)
[05/08] read_dtc                           → OK  (102 ms)
[06/08] clear_dtc                          → OK  (102 ms)
[07/08] read_dtc                           → OK  (102 ms)
[08/08] session(default)                   → OK  (102 ms)
```

**8/8 steps, 102–204 ms.** The timings differ from the CAN leg by roughly two
orders of magnitude because they are real network round trips, which is itself
evidence that the transport is not being short-circuited.

---

## What is not validated, and why

Neither gap is an unknown. Both were investigated and the causes are recorded.

### DoIP × FreeRTOS — [#7](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/7)

**Cause:** the FreeRTOS DoIP example builds against a **compile-only lwIP stub**.
The stub satisfies the includes so the DoIP sources compile; there is no
Ethernet driver behind it, so lwIP brings up no network interface and nothing
in the guest listens on port 13400. The host-side port forward is reached and
refused.

**Feasible?** Yes. QEMU's `lm3s6965evb` machine emulates a Stellaris Ethernet
MAC, and the CI job already attaches it (`-net nic,model=stellaris`). The
missing piece is guest-side: an lwIP driver for that MAC, wired up in place of
the stub. Bounded, conventional driver work.

### CAN × FreeRTOS — [#3](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/3)

**Cause:** the QEMU machine used for the FreeRTOS targets, `lm3s6965evb`,
**emulates no CAN controller**, and none is attached — the job's QEMU invocation
provides an Ethernet NIC and a TCP port forward only. Meanwhile the campaign
addresses a host `vcan0` interface. There is no path between them.

**Feasible?** **Not in this CI model.** This is not a missing bridge program or
an unwritten driver: with no emulated CAN controller in the guest, there is
nothing for either to attach to. Closing it would require either a different
QEMU machine that emulates CAN — which changes the platform under test, and so
weakens rather than strengthens a "same behaviour across variants" claim — or
real FreeRTOS hardware on a bench, which is outside this repository's
CI-only model.

---

## What we do not claim

Stated explicitly, because a coverage document that only lists successes is not
evidence:

- **We do not claim four-variant equivalence.** Two variants are validated. Any
  statement about FreeRTOS diagnostic behaviour is not supported by this
  repository.
- **We do not claim hardware validation.** Both validated variants run on
  Zephyr's `native_sim` against real host transports. That exercises the real
  ISO-TP and DoIP/TCP paths and real driver bindings; it is not a silicon
  target, and timing figures here are not WCET evidence.
- **We do not claim protocol conformance certification.** This is a behavioural
  regression suite over six services, not an ISO 14229 conformance test suite.
- **The status badge covers virtual validation only.** It deliberately reflects
  the credential-free job so that anyone forking this repository reproduces it.
  It is not a claim about the full matrix, which is reported separately in each
  run's **Matrix summary**.

---

## Reproducing this

The virtual validation needs nothing but Python:

```bash
pip install xaloqi-tester
testlab-run --config configs/basic_ecu.yaml \
            --campaign campaigns/core_validation.yaml \
            --job core_validation --virtual
```

The two validated real-transport legs need TestLab Pro for real `socketcan` and
`doip` transports, plus a Linux host for `vcan0` / `zeth`. See
[README](README.md) → *Run it yourself*, option B.

Every run publishes a **Matrix summary** listing each leg's real result, so the
state above can be re-checked without reading logs.

---

## Change policy

This document is only meaningful if it stays true. It states the run it was
verified against, and it should be re-verified whenever a matrix leg changes
state. If a claim here does not match current CI,
[open an issue](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues) —
a stale coverage statement is worse than none.
