# Complete-payload benchmark receipts

These raw reports come from the [complete-payload workload](../StreamPayload.md)
on one Ubuntu 24.04 x64 WSL2 host. Each run used an owned tmux server, one
installed `LibTmux` module package, 12-, 256- and 768-line bodies, three
warmups per size and 20 timed rounds per size. Event output and rendered
capture matched the same canonical payload hash in every round. The reports
include first calls, raw samples, medians, nearest-rank p95, binary hashes and
cleanup results.

| Package | tmux | Raw report | SHA-256 |
| --- | --- | --- | --- |
| Source-verified rebuild | 3.2a | [60 samples](stream-payload-20260927-b609-ps4-3.2a.json) | `1f633f56076527164f95b16ad34323b3901e7a38c33b54601656d0cd81554a2f` |
| Source-verified rebuild | 3.7c | [60 samples](stream-payload-20260927-b609-ps4-3.7c.json) | `3aca6a7275c595839dc7196bd6661efc84a4c1bc73be1c7040ed7a4b0e5e5b05` |
| Exact pinned ps.4 archive | 3.2a | [60 samples](stream-payload-20260927-b609-pinned-ps4-3.2a.json) | `08fb0ea97abfad3e396d5e6cd75843f0c0f7972072e91b8a4e38612bc08351f0` |
| Exact pinned ps.4 archive | 3.7c | [60 samples](stream-payload-20260927-b609-pinned-ps4-3.7c.json) | `55312341c7b0f41d984958995a4801e62add17e6b56452173b0cb94fb5658ed6` |

The [rebuild](stream-payload-20260927-b609-ps4-environment.json) and
[pinned-archive](stream-payload-20260927-b609-pinned-ps4-environment.json)
receipts record host class and whole-command wall time. Their SHA-256 values
are `3b2a515eda613187c1ab0882a05d99ed8fdf120e4aca919b41d640fa94f67653`
and `5362317d6acead9059cb03a58c715d61d776499826d270c823d40a3bb413a3e8`.

The clean runner was PowerShell port commit `b609ce2` with .NET source
`e80a6c3`. The source-verified rebuild used a unique review version and a
bootstrap receipt. Its module archive SHA-256 is
`ee850a0c2b64ce023ad56cf0ce45d0380ef6044ca0f1ab251b4aeb10c8932e06`.
The exact pinned `0.0.0-alpha.17.ps.4` module archive SHA-256 is
`3259aa70b04af9bbd13b3de160ec7daa9134be567e97f0b4fb8a61626dad1646`.
Its embedded .NET assemblies match the inspected ps.4 feed, but no bootstrap
receipt ties its PowerShell binary to source; its raw reports correctly record
`sourceProvenance=unverified`.

The timed interval starts before one payload write. It includes producer time,
tmux, observer scheduling and the 10 ms capture poll interval. These are
single-host observations, not raw transport throughput or a speed ratio.
