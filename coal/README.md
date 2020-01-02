### Using coal-computenode files

This directory contains the following VMWare image files:

- coal-computenode.vmwarevm.tbz2
- coal-computenode.vmwarevm.14.tbz2

Both files are similar and intended to be used as Compute Nodes
with an already existing COAL headnode.

The main difference between them is that while the former is
compatible with older VMWare versions (VMWare fusion 8 and above),
the later adds compatibility with USB type C devices and requires
support for VMWare `virtualHW.version` of 14 or greater (which in
practice means VMWare Fusion 10+ or Workstation 14+).

The addition of this new file is intended to simplify the process
of booting a new CN using a type c Yubikey when booting new encrypted
CNs when working into EDAR development.
