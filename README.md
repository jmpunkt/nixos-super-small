# NixOS Super Small

POC building small images with NixOS infrastructure. The goal is to build small
images like Buildroot for embedded devices, but keep the whole Nix
infrastructure and benefits. We assume that embedded systems use a different
update method (e.g. swupdate or RAUC), thus we exclude all the Nix machinery
which runs during run-time.

The goal is to get as close as possible to Buildroot images, while using
Nix. Maybe this also useful for Docker images or other tasks where small images
are required.

## How It Works

We use Busybox for almost everything and make sure no unnecessary closure leak
into the final image. This requires overriding the existing modules and packages
at some point. Additionally, SWupdate nad U-Boot is used. U-Boot replaces the
two staged NixOS boot. SWupdate allows to update the system afterwards. The
whole rootfs is read-only. Changes can only be made through SWupdate. So this is
only feasibly for devices that do not rely on the normal Nix command line
goodies.

Almost everything that is not strictly needed is removed. This includes some locales,
some timezone, some systemd targets and so on.

## Current Status

Right now we can build, boot, and update on an RaspberryPi 2B.

There are still some artifacts that leak into the closure, where Buildroot does
not have them. Also the version for some programs is important. Higher versions
usually mean more disk usage. To get a 1:1 comparison between Buildroot and
this approach, the exact same versions are required.

Since we are heavily patching, you will most likely need to rebuild most
packages. However, the total amount of packages is pretty low, so its bearable.

|Board                         |SWU   |SD Card Image|
|------------------------------|------|-------------|
|Raspberry Pi 2B (32 bit ARMv7)|~14 MB|~27 MB       |
