# WildKernels patch provenance

This directory is the second kernel patch set. It is applied after the ztc
optimization set so that the audited Android 12 5.10/BBRv3 compatibility hunk
can preserve the TCP ACK handling carried by the ztc patch set.

The BTF compatibility patches in this directory are copied from
`WildKernels/GKI_KernelSU_SUSFS` commit
`625d90f863c5a35262fbab57a3513497abbac357`. Patch 0002 also includes the
minimal Android Common Kernel fix from commit
`75f82c6a15c4188cbb32825892fc6ae3e95479f0`, which passes the hermetic host
CFLAGS to `libsubcmd` and avoids glibc `__isoc23_strto*` link failures.

The BBRv3 and ptrace patches are not vendored. The workflow fetches
`WildKernels/kernel_patches` commit
`0bb0203cdfcadbe32bb572af3a52e1c1430c7515` and verifies each patch's SHA-256
before applying it.

`compat/android12-5.10-bbr3-tlp-ack.patch` is the repository-local
compatibility hunk for the 5.10.257 ztc/Star-ZER0 result tree
`b96e4445196ab40158bde0c47117630577fbeca0`. It preserves the additional
`tcp_in_ack_event()` call while adapting BBRv3's TLP ACK rate-sample argument.
