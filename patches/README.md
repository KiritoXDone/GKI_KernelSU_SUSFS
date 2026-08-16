# Kernel patch sets

The Android 12 5.10.257 build layers two independently auditable patch sets on
top of the AOSP manifest source, in this order:

1. `ztc/` reproduces the ztc optimization tree from its exact AOSP release
   base. It is applied as one squashed source patch because the archived ztc
   repository imported AOSP history instead of retaining a shared Git base.
2. `wild/` contains the WildKernels source features and compatibility patches.
   BBRv3, ptrace and BTF members remain individually selectable by the build
   workflow and are always applied after the ztc set.

Both sets pin their upstream commits and validate patch checksums before they
modify the kernel tree. See each directory's README for provenance.
