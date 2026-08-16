# ztc optimization patch provenance

`0001-ztc-android12-5.10-2026-07-optimizations.patch` is the squashed source
diff for the ztc optimization stack repaired on 5.10.252 by Star-ZER0 and
forward-ported to 5.10.257:

- AOSP base tag: `android12-5.10-2026-07_r1` (`5.10.257`)
- AOSP base commit: `b14525331e0d5d335b037d6ed17d40424ed47b0a`
- AOSP base tree: `9abb9c0d6b0a69b141ae0ed990e4134406c1f253`
- original ztc source commit: `ad7de5b742db00d6bc1587a80e81f10c877b31d9`
- migration repository: `Star-ZER0/android_gki_kernel_5.10_common`
- migration result commit: `990dd017c9fdc82d903d72f94cdd87b64863c726`
- resulting 5.10.257 tree: `b96e4445196ab40158bde0c47117630577fbeca0`
- patch SHA-256: `0449d772730c9895c890fa0e78d6541b9416180eab9b01fda4fcd6bb1f279d06`

The selected migration result includes Star-ZER0's LZ4HC compilation fix
(`f883dbb8`), regenerated defconfig (`217cc37e`) and F2FS sysfs build fix
(`990dd017`). It was cleanly three-way merged with the July 2026 AOSP release.
It deliberately stops before that repository adds
DroidSpaces and NTSync, because those belong to the separately selectable
WildKernels/feature layer in this repository.

`scripts/apply_ztc_patchset.sh` requires the exact clean AOSP base, validates
the patch checksum in advance, and verifies that a temporary patched index
produces the recorded result tree.
