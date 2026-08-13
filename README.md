These are the basic needed files and folders to build CachyOS system.

### buildiso

buildiso is used to build CachyOS ISO.

#### Arguments

~~~
$ ./buildiso.sh -h
Usage: buildiso [options]
    -c                 Disable clean work dir
    -r                 Enable building in RAM on systems with more than 23GB RAM
    -w                 Remove build directory (not the ISO) after ISO file is built
    -F                 Force refresh of the frozen package cache
    -t <hours>         Package cache lifetime [default: 48]
    -h                 This help
    -p <profile>       Buildset or profile [default: desktop]
    -v                 Verbose output to log file, show profile detail (-q)
~~~

* Uses the same signature that normal repo and has no mirrors package to install.

```bash
sudo pacman -Syy
```

### Install necessary packages:
```bash
sudo pacman -S archiso mkinitcpio-archiso git squashfs-tools --needed
```

### Clone:
```bash
git clone https://github.com/cachyos/cachyos-live-iso.git cachyos-archiso
cd cachyos-archiso
```

### Build
```bash
./buildiso.sh -p desktop -v -w
```

The build keeps a complete pacman snapshot in `.build-cache/pacman`. The
snapshot is reused for 48 hours by default, so repeated builds do not refresh
rolling package versions or download packages again. Use `-F` to refresh it
immediately or `-t <hours>` to change the lifetime.

AgentOS uses Calamares offline mode. Installation copies the package versions
embedded in the ISO and does not refresh repositories or download a newer
installer at launch time.

The AgentOS branch builds a UEFI-only systemd-boot image without GRUB or
Syslinux boot paths. The resulting ISO appears in the `out` folder.
