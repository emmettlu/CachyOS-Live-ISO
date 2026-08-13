# CALCULET PCIe DKMS package

This directory is the stable ISO integration boundary for the replaceable
CALCULET KS1 PCIe driver source.

Build from a `cal-pcie` checkout:

```bash
./build-package.sh /path/to/cal-pcie
```

`cal-pcie/driver` and a directory containing the driver files directly are
both accepted. The package version defaults to the three version defines in
`ioctl.h`. Set `CALCULET_PCIE_VERSION` only when the upstream source needs an
explicit packaging version.

The ISO build accepts either input form:

```bash
CALCULET_PCIE_SOURCE_DIR=/path/to/cal-pcie ./buildiso.sh
CALCULET_PCIE_PACKAGE=/path/to/calculet-pcie-dkms.pkg.tar.zst ./buildiso.sh
```

The DKMS recipe deliberately builds with `LLVM=1` because CachyOS kernels are
built with Clang. Replacing the driver should not require changes to the ISO
or Calamares integration as long as the module remains named
`calculet_pci.ko` and the source file contract in `build-package.sh` remains
valid.
