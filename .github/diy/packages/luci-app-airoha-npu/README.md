# LuCI Airoha SoC status

A status page and CPU controls for Airoha systems. Original project:
[rchen14b/luci-app-airoha-npu](https://github.com/rchen14b/luci-app-airoha-npu).
The Apache-2.0 license and existing bounded hardware-probe protections are retained.

## Status interpretation

- Discover native netdev, device-tree PON/PHY mode and DSA conduit relationships
  once per page load. PHY mode is not cable link speed. Unknown topology stays
  unknown; reload after driver changes. Query wireless tokens only when a PHY is
  registered. CDM4/P7 is an internal DMA port, not an absent radio.
- Prefer cached driver `fw_version` / `num_cores`. Absent attributes fall back to
  device-scoped logs and explicitly labelled firmware-file versions. ENODATA is
  not replaced with a file version. These describe boot-time identity, not health.
- Calculate CPU usage in the browser from cumulative ticks, boot ID and monotonic
  time, without double-counting guest ticks. Missing/reset samples invalidate the
  baseline. There is no background sampler or shared history.
- Keep GDM/CDM drop classes separate; display raw counts and interval deltas.
  Decreases and long sampling gaps invalidate deltas. Undetectable reset and
  regrowth remains a limitation. Counts from different blocks cannot establish
  a global offload ratio. Reserved-memory discovery still depends on boot logs.
- Suppress incorrect IPv6 source-MAC decoding on old kernels; accept newer
  debugfs `smac_id` / `pppoe_sid` fields without guessing an address.
- Fetch the bounded PPE snapshot only on explicit refresh, marking unavailable
  and stale output. General polling remains ten seconds while the page is open.
- Describe VLAN/PPPoE bridge controls as bridge Netfilter filtering, not hardware
  offload. Historical RPC names and inverse `enabled` semantics remain compatible.

The inherited probe deadlines, timeout disable-until-reboot behavior, FE readiness
checks and bounded PPE reads are baseline protections, not newly added features.

## CPU controls

Use CPUFreq when the device advertises native direct-PLL support; maximum
frequency follows its exposed OPP table without forcing the performance governor.
Otherwise restrict the inherited direct-PLL path to AN/EN7581. The page does not
establish that an arbitrary frequency is safe for a board.

## Optional multicast diagnostics

If installed, `airoha-mcastctl` supplies scoped multicast state and refusal
counters. A compatible `pon_multicast_filter` debugfs file supplies applied
VLAN/group generations and hardware drops. Missing interfaces report unavailable,
not zero or inactive. Large counters use decimal strings. Rates are invalidated
across boot, generation, counter or sample discontinuities. Old admissions are
not shown as currently active during updates. Polling makes no filter writes.
The matching kernel/control components are proposed separately to PonWrt;
they are not hard dependencies. Structured optional replies require `jshn`.

## Source layout and validation

The sync workflow overlays `.github/diy/packages/luci-app-airoha-npu` onto the
top-level package; keep both copies synchronized. Existing fixtures are retained
in `tests/airoha-npu/`. The RPC fixture needs Python, `/usr/bin/busybox` ash and
libubox jshn: set `HG_JSHN_SH` to `jshn.sh`; the inferred host-bin path must contain
its `jshn` binary. The JavaScript fixture needs Node.js and mocks LuCI/DOM.
These fixtures do not validate physical hardware or real browser scheduling.

Earlier PonWrt versions were deployed on Nokia XG-040G-MD / AN7581; cached identity
returned version 1456.62 and eight initialized NPU cores. This is historical
evidence. No new tests, build, browser or hardware verification were performed
for this export. AN7583 and wireless-equipped boards need maintainer validation.
