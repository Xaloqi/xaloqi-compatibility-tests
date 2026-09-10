# Validation coverage statement

**What this repository proves, and what it does not.**

Last verified: **2026-09-10**, against
[workflow run 34468947722](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/runs/34468947722)
on `main`, with `Xaloqi/EDS` at `main` — the first run of this repository's own
CI after [EDS#267](https://github.com/Xaloqi/EDS/pull/267) merged. All three
figures below, including `basic_ecu_doip_freertos`, come from that single run;
the throwaway branch that proved the fix before EDS#267 merged
([run 34467041139](https://github.com/Xaloqi/xaloqi-compatibility-tests/actions/runs/34467041139))
has been deleted and is cited in this document only where it is the source of
the negative control below.

This document exists so that anyone relying on this repository as validation
evidence can see the boundary without reading CI logs. Every figure below is
taken from that run, not from a specification or a previous campaign.

---

## Summary

The compatibility matrix has four target variants: **CAN and DoIP × Zephyr and
FreeRTOS**. Three are validated end to end against real transports in CI. One is
not, for a reason that is understood and recorded rather than an open question.

| Variant | Target | Status |
|---|---|---|
| CAN × Zephyr | `basic_ecu` | ✅ **Validated** — real host SocketCAN |
| DoIP × Zephyr | `basic_ecu_doip` | ✅ **Validated** — real host Ethernet bridge |
| DoIP × FreeRTOS | `basic_ecu_doip_freertos` | ✅ **Validated** — real firmware on emulated ARM, emulated LAN9118 MAC |
| CAN × FreeRTOS | `basic_ecu_freertos` | ❌ Not validated — [#3](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/3) |

Both RTOSes are now covered by at least one real-transport leg, so the
"same behaviour across variants" claim is no longer resting on Zephyr alone.

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
[01/08] tester_present                     → OK  (2 ms)
[02/08] session(extended)                  → OK  (2 ms)
[03/08] security_access(level=1)           → OK  (42 ms)
[04/08] read_did(0xF190)                   → OK  (6 ms)
[05/08] read_dtc                           → OK  (2 ms)
[06/08] clear_dtc                          → OK  (2 ms)
[07/08] read_dtc                           → OK  (2 ms)
[08/08] session(default)                   → OK  (2 ms)
```

**8/8 steps, 2–42 ms.**

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

### DoIP × FreeRTOS — `basic_ecu_doip_freertos`

Runs a **real FreeRTOS firmware image on emulated ARM hardware**, serving DoIP
over an **emulated SMSC LAN9118 Ethernet MAC** — QEMU `mps2-an386`, Cortex-M4,
with the guest's port 13400 forwarded to the host.

The guest's own boot log records the bring-up:

```
[eds] basic_ecu_doip_freertos boot
[eds] board=qemu mps2-an386 cortex-m4f
[eds] platform init ok
[eds] uds stack init ok
[eds] doip task created, starting scheduler
[net] tcpip_init...
[net] tcpip up, lwip 2.2.1
[net] mac  02:00:00:ed:50:01
[net] chip id_rev 01180001
[net] ip   10.0.2.15
[net] mask 255.255.255.0
[net] gw   10.0.2.2
[net] netif up — DoIP reachable on port 13400
```

`chip id_rev 01180001` is **read back from the emulated MAC's ID_REV register**,
not printed from a constant — the load-bearing detail, because it is what
distinguishes a driver that reached hardware from one that merely initialised
successfully. The CI job asserts on the `netif up` line and fails the leg if it
is absent, so this is a gate, not decoration.

```
[01/08] tester_present                     → OK  (5 ms)
[02/08] session(extended)                  → OK  (4 ms)
[03/08] security_access(level=1)           → OK  (40 ms)
[04/08] read_did(0xF190)                   → OK  (4 ms)
[05/08] read_dtc                           → OK  (4 ms)
[06/08] clear_dtc                          → OK  (4 ms)
[07/08] read_dtc                           → OK  (4 ms)
[08/08] session(default)                   → OK  (4 ms)
```

**8/8 steps, 4–40 ms, 69 ms total.** The SecurityAccess step is ~10× the others
because it is a full AES-128-CMAC seed/key round trip, matching the shape seen
on both Zephyr legs.

#### Why this was blocked for so long, and what the block actually was

[#7](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/7) recorded
the cause as the compile-only lwIP stub. That was true but incomplete — it was
the **last** of five independent blockers, and not the first one reached
([EDS#267](https://github.com/Xaloqi/EDS/pull/267)):

1. **The firmware image was empty.** EDS had no vector table and no
   `Reset_Handler` anywhere, so the linker warned `cannot find entry symbol
   Reset_Handler` and `--gc-sections`, with no root to trace from, discarded the
   entire program. The ELF had **`.text` size 0**. An empty binary links
   cleanly, which is exactly why a compile-only leg reported success.
2. **The wrong QEMU machine.** This job launched `-machine lm3s6965evb`, which
   is **Cortex-M3**, against an image built `-mcpu=cortex-m4
   -mfpu=fpv4-sp-d16 -mfloat-abi=hard` — and whose own linker script and
   `FreeRTOSConfig.h` both already said `mps2-an386`. A hard-float M4 image
   cannot execute on an M3.
3. **The wrong filename.** `-kernel .../basic_ecu.elf` named a file CMake has
   never emitted; the real output is `eds_freertos_doip.elf`.
4. **Missing platform glue** — `EDS_PLATFORM_FREERTOS` undefined, and
   `eds_platform_init()` rejecting the `can_send == NULL` that a DoIP-only
   build passes by design.
5. **The lwIP stub itself**, the one #7 named.

This document previously asserted that `lm3s6965evb`'s Stellaris MAC was the
route in. That was wrong for this binary, and is corrected here: the target is
`mps2-an386` and its **LAN9118** MAC.

#### A false-positive worth recording

**A bare TCP connect to the forwarded host port succeeds even against the stub
build.** QEMU's slirp `hostfwd` accepts on the host side before it can know
whether a guest listener exists. Anyone validating this leg by connecting to
port 13400 gets a green that means nothing. Only a completed DoIP exchange is
evidence — which is why this job asserts on the boot log and on campaign
results, never on reachability.

The negative control was run explicitly: against the stub build the identical
campaign fails at `TransportError: DoIP: Routing Activation Response timed
out`.

---

## What is not validated, and why

One gap remains. It is not an unknown — it was investigated and the cause is
recorded.

### CAN × FreeRTOS — [#3](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues/3)

**Cause:** the QEMU machine used for the FreeRTOS targets **emulates no CAN
controller**, and none is attached — the job's QEMU invocation provides an
Ethernet NIC and a TCP port forward only. Meanwhile the campaign addresses a
host `vcan0` interface. There is no path between them.

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

- **We do not claim four-variant equivalence.** Three variants are validated.
  CAN-on-FreeRTOS behaviour is not supported by this repository, so no claim
  about ISO-TP on FreeRTOS rests on evidence here.
- **We do not claim hardware validation.** The two Zephyr variants run on
  `native_sim` against real host transports; the FreeRTOS DoIP variant runs a
  real cross-compiled ARM image under QEMU against an emulated MAC. All three
  exercise the real ISO-TP or DoIP/TCP paths and real driver bindings. **None
  is a silicon target**, and no timing figure here is WCET evidence — the QEMU
  leg's timings in particular reflect emulated execution, not the wall-clock
  behaviour of a real Cortex-M4.
- **We do not claim the FreeRTOS DoIP leg exercises a production Ethernet
  driver.** It exercises a driver written for QEMU's emulated LAN9118. That
  validates the UDS stack, the DoIP server and the lwIP socket binding above
  it; it says nothing about any particular MCU's Ethernet peripheral.
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

The three validated real-transport legs need TestLab Pro for real `socketcan`
and `doip` transports. The two Zephyr legs additionally need a Linux host for
`vcan0` / `zeth`. See [README](README.md) → *Run it yourself*, option B.

The FreeRTOS DoIP leg needs **no host network setup at all** — QEMU's user-mode
networking provides the forward, so it reproduces anywhere QEMU and an ARM
cross-compiler are installed, without `sudo`:

```bash
git clone --depth=1 -b STABLE-2_2_1_RELEASE \
  https://github.com/lwip-tcpip/lwip.git /opt/lwip
git clone --depth=1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git /opt/freertos-kernel

cmake -S EDS/examples/basic_ecu_doip_freertos -B build -GNinja \
      -DEDS_PLATFORM=freertos -DFREERTOS_DIR=/opt/freertos-kernel \
      -DLWIP_DIR=/opt/lwip -DBOARD=qemu_cortex_m4 \
      -DCMAKE_BUILD_TYPE=Release
ninja -C build

qemu-system-arm -machine mps2-an386 -kernel build/eds_freertos_doip.elf \
  -net nic,model=lan9118 -net user,hostfwd=tcp::13400-:13400 \
  -nographic -serial file:boot.log &

testlab-run --workspace configs/basic_ecu_doip_freertos.yaml \
            --campaign campaigns/core_validation.yaml \
            --job core_validation
```

Omitting `-DLWIP_DIR` builds the compile-only stub instead, and the campaign
then fails at `DoIP: Routing Activation Response timed out` — a useful way to
confirm the leg is testing what it claims to.

Every run publishes a **Matrix summary** listing each leg's real result, so the
state above can be re-checked without reading logs.

---

## Change policy

This document is only meaningful if it stays true. It states the run it was
verified against, and it should be re-verified whenever a matrix leg changes
state. If a claim here does not match current CI,
[open an issue](https://github.com/Xaloqi/xaloqi-compatibility-tests/issues) —
a stale coverage statement is worse than none.
