# WildKernels patch provenance

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

`compat/ztc-5.10-bbr3-tlp-ack.patch` is the repository-local compatibility
hunk for ztc commit `ad7de5b742db00d6bc1587a80e81f10c877b31d9`. It preserves ztc's additional
`tcp_in_ack_event()` call while adapting BBRv3's TLP ACK rate-sample argument.
