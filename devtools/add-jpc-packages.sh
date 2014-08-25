#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

. /lib/sdc/config.sh
load_sdc_config

[[ -z "$CONFIG_ufds_admin_uuid" ]] && echo "Unable to find ufds_admin_uuid in usbkey config!" && exit 1

sdc-ldap add <<EOF
dn: uuid=cd594f6e-b22d-4d32-baa0-0361e0d91a53, ou=packages, o=smartdc
active: true
common_name: Standard 4
cpu_burst_ratio: 1
cpu_cap: 100
default: false
description: Standard 4 GB RAM 1 vCPU 131 GB Disk
fss: 100
group: Standard
max_lwps: 4000
max_physical_memory: 4096
max_swap: 8192
name: g3-standard-4-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 134144
ram_ratio: 3.980099502
uuid: cd594f6e-b22d-4d32-baa0-0361e0d91a53
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=f70b436c-615c-4814-b07f-e92af5e798da, ou=packages, o=smartdc
active: true
common_name: Standard 3.75
cpu_burst_ratio: 1
cpu_cap: 100
default: false
description: Standard 3.75 GB RAM 1 vCPU 123 GB Disk
fss: 100
group: Standard
max_lwps: 4000
max_physical_memory: 3840
max_swap: 7680
name: g3-standard-3.75-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 125952
ram_ratio: 3.731343284
uuid: f70b436c-615c-4814-b07f-e92af5e798da
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=2c82f840-7abb-4735-b073-6fc8ff7a1415, ou=packages, o=smartdc
active: true
common_name: Standard 2
cpu_burst_ratio: 1
cpu_cap: 100
default: false
description: Standard 2 GB RAM 1 vCPU 66 GB Disk
fss: 100
group: Standard
max_lwps: 4000
max_physical_memory: 2048
max_swap: 4096
name: g3-standard-2-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 67584
ram_ratio: 1.990049751
uuid: 2c82f840-7abb-4735-b073-6fc8ff7a1415
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=85a1baa9-df22-4e7a-a0ba-86ab77fd2f70, ou=packages, o=smartdc
active: true
common_name: Standard 1.75
cpu_burst_ratio: 1
cpu_cap: 100
default: false
description: Standard 1.7 GB RAM 1 vCPU 56 GB Disk
fss: 100
group: Standard
max_lwps: 4000
max_physical_memory: 1792
max_swap: 3584
name: g3-standard-1.75-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 57344
ram_ratio: 1.741293532
uuid: 85a1baa9-df22-4e7a-a0ba-86ab77fd2f70
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=25b3abff-1efb-40de-8abf-570741a368ab, ou=packages, o=smartdc
active: true
common_name: Standard 1
cpu_burst_ratio: 1
cpu_cap: 25
default: false
description: Standard 1 GB RAM 1 vCPU 33 GB Disk
fss: 25
group: Standard
max_lwps: 4000
max_physical_memory: 1024
max_swap: 2048
name: g3-standard-1-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 33792
ram_ratio: 3.980099502
uuid: 25b3abff-1efb-40de-8abf-570741a368ab
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=a641d2ea-f220-4c39-a9e7-c689625b3c7d, ou=packages, o=smartdc
active: true
common_name: Standard 0.625
cpu_burst_ratio: 1
cpu_cap: 20
default: false
description: Standard 0.6 GB RAM 1 vCPU 20 GB Disk
fss: 15
group: Standard
max_lwps: 4000
max_physical_memory: 640
max_swap: 1280
name: g3-standard-0.625-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 20480
ram_ratio: 4.145936982
uuid: a641d2ea-f220-4c39-a9e7-c689625b3c7d
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=17cc6cd5-2aa0-4540-89b5-8b2667c16411, ou=packages, o=smartdc
active: true
common_name: Standard 0.5
cpu_burst_ratio: 1
cpu_cap: 20
default: false
description: Micro 0.5 GB RAM 1 vCPU 16 GB Disk
fss: 12
group: Standard
max_lwps: 4000
max_physical_memory: 512
max_swap: 1024
name: g3-standard-0.5-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 16384
ram_ratio: 3.980099502
uuid: 17cc6cd5-2aa0-4540-89b5-8b2667c16411
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=8f27f91d-7994-4b89-93e3-a63e3479b6e8, ou=packages, o=smartdc
active: true
common_name: Standard 0.25
cpu_burst_ratio: 1
cpu_cap: 20
default: false
description: Micro 0.25 GB RAM 1 vCPU 16 GB Disk
fss: 12
group: Standard
max_lwps: 4000
max_physical_memory: 256
max_swap: 512
name: g3-standard-0.25-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 16384
ram_ratio: 1.990049751
uuid: 8f27f91d-7994-4b89-93e3-a63e3479b6e8
vcpus: 1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=a8a2c001-89b7-4351-97c8-7bbbb0d18918, ou=packages, o=smartdc
active: true
common_name: Standard 4
cpu_burst_ratio: 0.5
cpu_cap: 200
default: false
description: Standard 4 GB RAM 1 vCPU and bursting 131 GB Disk
fss: 200
group: Standard
max_lwps: 4000
max_physical_memory: 4096
max_swap: 8192
name: g3-standard-4-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 134144
ram_ratio: 3.990024938
uuid: a8a2c001-89b7-4351-97c8-7bbbb0d18918
version: 1.0.0
zfs_io_priority: 100

dn: uuid=e8981c6f-99d6-46dc-9ffd-f84478901109, ou=packages, o=smartdc
active: true
common_name: Standard 3.75
cpu_burst_ratio: 0.5
cpu_cap: 200
default: false
description: Standard 3.75 GB RAM 1 vCPU and bursting 123 GB Disk
fss: 200
group: Standard
max_lwps: 4000
max_physical_memory: 3840
max_swap: 7680
name: g3-standard-3.75-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 125952
ram_ratio: 3.740648379
uuid: e8981c6f-99d6-46dc-9ffd-f84478901109
version: 1.0.0
zfs_io_priority: 100

dn: uuid=ba42e517-b1fa-4a27-8c69-d554d5db4fa3, ou=packages, o=smartdc
active: true
common_name: Standard 2
cpu_burst_ratio: 0.5
cpu_cap: 200
default: false
description: Standard 2 GB RAM 1 vCPU and bursting 66 GB Disk
fss: 200
group: Standard
max_lwps: 4000
max_physical_memory: 2048
max_swap: 4096
name: g3-standard-2-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 67584
ram_ratio: 1.995012469
uuid: ba42e517-b1fa-4a27-8c69-d554d5db4fa3
version: 1.0.0
zfs_io_priority: 100

dn: uuid=6838ad95-22c0-4fa7-b73a-9f6c8637f321, ou=packages, o=smartdc
active: true
common_name: Standard 1.75
cpu_burst_ratio: 0.5
cpu_cap: 200
default: false
description: Standard 1.7 GB RAM 1 vCPU and bursting 56 GB Disk
fss: 200
group: Standard
max_lwps: 4000
max_physical_memory: 1792
max_swap: 3584
name: g3-standard-1.75-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 57344
ram_ratio: 1.74563591
uuid: 6838ad95-22c0-4fa7-b73a-9f6c8637f321
version: 1.0.0
zfs_io_priority: 100

dn: uuid=6f759167-0dc4-4edd-a16f-f75e138a4751, ou=packages, o=smartdc
active: true
common_name: Standard 1
cpu_burst_ratio: 0.5
cpu_cap: 50
default: false
description: Standard 1 GB RAM 0.25 vCPU and bursting 33 GB Disk
fss: 50
group: Standard
max_lwps: 4000
max_physical_memory: 1024
max_swap: 2048
name: g3-standard-1-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 33792
ram_ratio: 3.990024938
uuid: 6f759167-0dc4-4edd-a16f-f75e138a4751
version: 1.0.0
zfs_io_priority: 100

dn: uuid=f98e4d7a-88d2-445a-af5d-45606180f0b8, ou=packages, o=smartdc
active: true
common_name: Standard 0.625
cpu_burst_ratio: 0.5
cpu_cap: 30
default: false
description: Micro 0.6 GB RAM 0.15 vCPU and bursting 20 GB Disk
fss: 30
group: Standard
max_lwps: 4000
max_physical_memory: 640
max_swap: 1280
name: g3-standard-0.625-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 20480
ram_ratio: 4.156275977
uuid: f98e4d7a-88d2-445a-af5d-45606180f0b8
version: 1.0.0
zfs_io_priority: 100

dn: uuid=5cd7b8db-779e-466a-b974-6c80ca4930c5, ou=packages, o=smartdc
active: true
common_name: Standard 0.5
cpu_burst_ratio: 0.5
cpu_cap: 25
default: false
description: Micro 0.5 GB RAM 0.125 vCPU and bursting 16 GB Disk
fss: 25
group: Standard
max_lwps: 4000
max_physical_memory: 512
max_swap: 1024
name: g3-standard-0.5-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 16384
ram_ratio: 3.990024938
uuid: 5cd7b8db-779e-466a-b974-6c80ca4930c5
version: 1.0.0
zfs_io_priority: 100

dn: uuid=8c556858-8137-4b97-9970-d741a96e4e75, ou=packages, o=smartdc
active: true
common_name: Standard 0.25
cpu_burst_ratio: 0.5
cpu_cap: 25
default: false
description: Micro 0.25 GB RAM 0.125 vCPU and bursting 16 GB Disk
fss: 25
group: Standard
max_lwps: 4000
max_physical_memory: 256
max_swap: 512
name: g3-standard-0.25-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 16384
ram_ratio: 1.995012469
uuid: 8c556858-8137-4b97-9970-d741a96e4e75
version: 1.0.0
zfs_io_priority: 100

dn: uuid=ed56214a-ec70-40b1-924f-0335e4bf4fc9, ou=packages, o=smartdc
active: false
common_name: Standard 128
cpu_burst_ratio: 1
cpu_cap: 3300
default: false
description: Standard-CC 128 GB RAM 32 vCPUs 4200 GB Disk
fss: 3300
group: Standard
max_lwps: 4000
max_physical_memory: 131072
max_swap: 262144
name: g3-standard-128-kvm-cc
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 4300800
ram_ratio: 3.878787879
uuid: ed56214a-ec70-40b1-924f-0335e4bf4fc9
vcpus: 16
version: 1.0.0
zfs_io_priority: 100
owner_uuid: $CONFIG_ufds_admin_uuid

dn: uuid=6185b42c-3079-4b73-be33-6c11f024d8d7, ou=packages, o=smartdc
active: true
common_name: Standard 32
cpu_burst_ratio: 0.5
cpu_cap: 1700
default: false
description: Standard 32 GB RAM 8 vCPUs and bursting 1683 GB Disk
fss: 1700
group: Standard
max_lwps: 4000
max_physical_memory: 32768
max_swap: 65536
name: g3-standard-32-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.764705882
uuid: 6185b42c-3079-4b73-be33-6c11f024d8d7
version: 1.0.0
zfs_io_priority: 100

dn: uuid=ade42bfd-84be-41a6-b522-4efa18eff969, ou=packages, o=smartdc
active: true
common_name: Standard 8
cpu_burst_ratio: 1
cpu_cap: 201
default: false
description: Standard 8 GB RAM 2 vCPUs 789 GB Disk
fss: 201
group: Standard
max_lwps: 4000
max_physical_memory: 8192
max_swap: 16384
name: g3-standard-8-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 807936
ram_ratio: 3.980099502
uuid: ade42bfd-84be-41a6-b522-4efa18eff969
vcpus: 2
version: 1.0.0
zfs_io_priority: 100

dn: uuid=d7796cea-6ca8-46bf-9a19-3c7f30d69fdc, ou=packages, o=smartdc
active: true
common_name: Standard 8
cpu_burst_ratio: 0.5
cpu_cap: 401
default: false
description: Standard 8 GB RAM 2 vCPUs and bursting 789 GB Disk
fss: 401
group: Standard
max_lwps: 4000
max_physical_memory: 8192
max_swap: 16384
name: g3-standard-8-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 807936
ram_ratio: 3.990024938
uuid: d7796cea-6ca8-46bf-9a19-3c7f30d69fdc
version: 1.0.0
zfs_io_priority: 100

dn: uuid=2472994f-032f-4ed3-a71e-af6068b50bc1, ou=packages, o=smartdc
active: true
common_name: Standard 128
cpu_burst_ratio: 0.5
cpu_cap: 6500
default: false
description: Standard-CC 128 GB RAM 32 vCPUs and bursting 4200 GB Disk
fss: 6500
group: Standard
max_lwps: 4000
max_physical_memory: 131072
max_swap: 262144
name: g3-standard-128-smartos-cc
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 4300800
ram_ratio: 3.938461538
uuid: 2472994f-032f-4ed3-a71e-af6068b50bc1
version: 1.0.0
zfs_io_priority: 100
owner_uuid: $CONFIG_ufds_admin_uuid

dn: uuid=1f0e09a9-eda6-4f2b-9e88-5009ecbe58e4, ou=packages, o=smartdc
active: false
common_name: Standard 120
cpu_burst_ratio: 0.5
cpu_cap: 6100
default: false
description: Standard 120 GB RAM 30 vCPUs and bursting 3938 GB Disk
fss: 6100
group: Standard
max_lwps: 4000
max_physical_memory: 122880
max_swap: 245760
name: g3-standard-120-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 4032512
ram_ratio: 3.93442623
uuid: 1f0e09a9-eda6-4f2b-9e88-5009ecbe58e4
version: 1.0.0
zfs_io_priority: 100

dn: uuid=d90d3a95-bd11-45a5-9d28-07c86934a5cc, ou=packages, o=smartdc
active: false
common_name: Standard 112
cpu_burst_ratio: 0.5
cpu_cap: 5700
default: false
description: Standard 112 GB RAM 28 vCPUs and bursting 3675 GB Disk
fss: 5700
group: Standard
max_lwps: 4000
max_physical_memory: 114688
max_swap: 229376
name: g3-standard-112-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 3763200
ram_ratio: 3.929824561
uuid: d90d3a95-bd11-45a5-9d28-07c86934a5cc
version: 1.0.0
zfs_io_priority: 100

dn: uuid=dbcb41fb-5a5a-4431-99e9-d89aebee561c, ou=packages, o=smartdc
active: false
common_name: Standard 104
cpu_burst_ratio: 0.5
cpu_cap: 5300
default: false
description: Standard 104 GB RAM 26 vCPUs and bursting 3413 GB Disk
fss: 5300
group: Standard
max_lwps: 4000
max_physical_memory: 106496
max_swap: 212992
name: g3-standard-104-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 3494912
ram_ratio: 3.924528302
uuid: dbcb41fb-5a5a-4431-99e9-d89aebee561c
version: 1.0.0
zfs_io_priority: 100

dn: uuid=26f63b4d-170b-46e5-ab90-35e7d5259f18, ou=packages, o=smartdc
active: false
common_name: Standard 96
cpu_burst_ratio: 0.5
cpu_cap: 4900
default: false
description: Standard 96 GB RAM 24 vCPUs and bursting 3150 GB Disk
fss: 4900
group: Standard
max_lwps: 4000
max_physical_memory: 98304
max_swap: 196608
name: g3-standard-96-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 3225600
ram_ratio: 3.918367347
uuid: 26f63b4d-170b-46e5-ab90-35e7d5259f18
version: 1.0.0
zfs_io_priority: 100
owner_uuid: $CONFIG_ufds_admin_uuid

dn: uuid=3df66c45-068b-4dfe-848a-35ae1e08745b, ou=packages, o=smartdc
active: false
common_name: Standard 88
cpu_burst_ratio: 0.5
cpu_cap: 4500
default: false
description: Standard 88 GB RAM 22 vCPUs and bursting 2888 GB Disk
fss: 4500
group: Standard
max_lwps: 4000
max_physical_memory: 90112
max_swap: 180224
name: g3-standard-88-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 2957312
ram_ratio: 3.911111111
uuid: 3df66c45-068b-4dfe-848a-35ae1e08745b
version: 1.0.0
zfs_io_priority: 100

dn: uuid=367b0eba-f00d-41a7-a1a0-cf44c6ba800f, ou=packages, o=smartdc
active: true
common_name: Standard 80
cpu_burst_ratio: 0.5
cpu_cap: 4100
default: false
description: Standard 80 GB RAM 20 vCPUs and bursting 2625 GB Disk
fss: 4100
group: Standard
max_lwps: 4000
max_physical_memory: 81920
max_swap: 163840
name: g3-standard-80-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 2688000
ram_ratio: 3.902439024
uuid: 367b0eba-f00d-41a7-a1a0-cf44c6ba800f
version: 1.0.0
zfs_io_priority: 100

dn: uuid=c4340884-7a8c-4d1f-8320-85a2ca256b83, ou=packages, o=smartdc
active: false
common_name: Standard 72
cpu_burst_ratio: 0.5
cpu_cap: 3700
default: false
description: Standard 72 GB RAM 18 vCPUs and bursting 2363 GB Disk
fss: 3700
group: Standard
max_lwps: 4000
max_physical_memory: 73728
max_swap: 147456
name: g3-standard-72-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 2419712
ram_ratio: 3.891891892
uuid: c4340884-7a8c-4d1f-8320-85a2ca256b83
version: 1.0.0
zfs_io_priority: 100

dn: uuid=678999e8-b69f-4fd7-af14-f1f737cef964, ou=packages, o=smartdc
active: true
common_name: Standard 64
cpu_burst_ratio: 0.5
cpu_cap: 3300
default: false
description: Standard 64 GB RAM 16 vCPUs and bursting 2100 GB Disk
fss: 3300
group: Standard
max_lwps: 4000
max_physical_memory: 65536
max_swap: 131072
name: g3-standard-64-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 2150400
ram_ratio: 3.878787879
uuid: 678999e8-b69f-4fd7-af14-f1f737cef964
version: 1.0.0
zfs_io_priority: 100

dn: uuid=8261a8f4-56b6-4f43-9bbb-9bf389e04fe8, ou=packages, o=smartdc
active: false
common_name: Standard 56
cpu_burst_ratio: 0.5
cpu_cap: 2900
default: false
description: Standard 56 GB RAM 14 vCPUs and bursting 1838 GB Disk
fss: 2900
group: Standard
max_lwps: 4000
max_physical_memory: 57344
max_swap: 114688
name: g3-standard-56-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1882112
ram_ratio: 3.862068966
uuid: 8261a8f4-56b6-4f43-9bbb-9bf389e04fe8
version: 1.0.0
zfs_io_priority: 100

dn: uuid=f81c1ce7-79fe-4068-ad12-9087c28c5e5f, ou=packages, o=smartdc
active: true
common_name: Standard 48
cpu_burst_ratio: 0.5
cpu_cap: 2500
default: false
description: Standard 48 GB RAM 12 vCPUs and bursting 1683 GB Disk
fss: 2500
group: Standard
max_lwps: 4000
max_physical_memory: 49152
max_swap: 98304
name: g3-standard-48-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.84
uuid: f81c1ce7-79fe-4068-ad12-9087c28c5e5f
version: 1.0.0
zfs_io_priority: 100

dn: uuid=68ce3237-8299-43b7-a9c8-6060590427ad, ou=packages, o=smartdc
active: false
common_name: Standard 40
cpu_burst_ratio: 0.5
cpu_cap: 2100
default: false
description: Standard 40 GB RAM 10 vCPUs and bursting 1683 GB Disk
fss: 2100
group: Standard
max_lwps: 4000
max_physical_memory: 40960
max_swap: 81920
name: g3-standard-40-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.80952381
uuid: 68ce3237-8299-43b7-a9c8-6060590427ad
version: 1.0.0
zfs_io_priority: 100

dn: uuid=7b58cf0e-d08b-4ce8-b87a-bcff3e5be257, ou=packages, o=smartdc
active: true
common_name: Standard 30
cpu_burst_ratio: 0.5
cpu_cap: 1700
default: false
description: Standard 30 GB RAM 8 vCPUs and bursting 1683 GB Disk
fss: 1700
group: Standard
max_lwps: 4000
max_physical_memory: 30720
max_swap: 61440
name: g3-standard-30-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.529411765
uuid: 7b58cf0e-d08b-4ce8-b87a-bcff3e5be257
version: 1.0.0
zfs_io_priority: 100

dn: uuid=295572f5-b1a2-41cf-9f8c-dc1a57fc06a1, ou=packages, o=smartdc
active: false
common_name: Standard 17.125
cpu_burst_ratio: 0.5
cpu_cap: 1100
default: false
description: Standard 17.1 GB RAM 5 vCPUs and bursting 1683 GB Disk
fss: 1100
group: Standard
max_lwps: 4000
max_physical_memory: 17536
max_swap: 35072
name: g3-standard-17.125-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.113636364
uuid: 295572f5-b1a2-41cf-9f8c-dc1a57fc06a1
version: 1.0.0
zfs_io_priority: 100

dn: uuid=3f99b9f6-2d45-4b02-8d72-061a376cf1b7, ou=packages, o=smartdc
active: false
common_name: Standard 16
cpu_burst_ratio: 0.5
cpu_cap: 900
default: false
description: Standard 16 GB RAM 4 vCPUs and bursting 1575 GB Disk
fss: 900
group: Standard
max_lwps: 4000
max_physical_memory: 16384
max_swap: 32768
name: g3-standard-16-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1612800
ram_ratio: 3.555555556
uuid: 3f99b9f6-2d45-4b02-8d72-061a376cf1b7
version: 1.0.0
zfs_io_priority: 100

dn: uuid=3c680d23-d4c9-4e49-9822-ab9e15c14304, ou=packages, o=smartdc
active: true
common_name: Standard 15
cpu_burst_ratio: 0.5
cpu_cap: 900
default: false
description: Standard 15 GB RAM 4 vCPUs and bursting 1467 GB Disk
fss: 900
group: Standard
max_lwps: 4000
max_physical_memory: 15360
max_swap: 30720
name: g3-standard-15-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 1502208
ram_ratio: 3.333333333
uuid: 3c680d23-d4c9-4e49-9822-ab9e15c14304
version: 1.0.0
zfs_io_priority: 100

dn: uuid=52778ba9-1265-4339-8da6-a69d6fdcfdf3, ou=packages, o=smartdc
active: true
common_name: Standard 7.5
cpu_burst_ratio: 0.5
cpu_cap: 401
default: false
description: Standard 7.5 GB RAM 2 vCPUs and bursting 738 GB Disk
fss: 401
group: Standard
max_lwps: 4000
max_physical_memory: 7680
max_swap: 15360
name: g3-standard-7.5-smartos
objectclass: sdcpackage
overprovision_cpu: 2
overprovision_memory: 1
quota: 755712
ram_ratio: 3.740648379
uuid: 52778ba9-1265-4339-8da6-a69d6fdcfdf3
version: 1.0.0
zfs_io_priority: 100

dn: uuid=968c2e95-40dd-4e07-916a-84231c624763, ou=packages, o=smartdc
active: false
common_name: Standard 120
cpu_burst_ratio: 1
cpu_cap: 3100
default: false
description: Standard 120 GB RAM 30 vCPUs 3938 GB Disk
fss: 3100
group: Standard
max_lwps: 4000
max_physical_memory: 122880
max_swap: 245760
name: g3-standard-120-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 4032512
ram_ratio: 3.870967742
uuid: 968c2e95-40dd-4e07-916a-84231c624763
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=c2358341-7e44-4eba-8b08-6b66fa2d082c, ou=packages, o=smartdc
active: false
common_name: Standard 112
cpu_burst_ratio: 1
cpu_cap: 2900
default: false
description: Standard 112 GB RAM 28 vCPUs 3675 GB Disk
fss: 2900
group: Standard
max_lwps: 4000
max_physical_memory: 114688
max_swap: 229376
name: g3-standard-112-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 3763200
ram_ratio: 3.862068966
uuid: c2358341-7e44-4eba-8b08-6b66fa2d082c
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=274e353f-0f91-46d2-b3d4-8887de08ef7f, ou=packages, o=smartdc
active: false
common_name: Standard 104
cpu_burst_ratio: 1
cpu_cap: 2700
default: false
description: Standard 104 GB RAM 26 vCPUs 3413 GB Disk
fss: 2700
group: Standard
max_lwps: 4000
max_physical_memory: 106496
max_swap: 212992
name: g3-standard-104-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 3494912
ram_ratio: 3.851851852
uuid: 274e353f-0f91-46d2-b3d4-8887de08ef7f
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=bfc3c753-efb2-4692-b86d-02639196030a, ou=packages, o=smartdc
active: false
common_name: Standard 96
cpu_burst_ratio: 1
cpu_cap: 2500
default: false
description: Standard 96 GB RAM 24 vCPUs 3150 GB Disk
fss: 2500
group: Standard
max_lwps: 4000
max_physical_memory: 98304
max_swap: 196608
name: g3-standard-96-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 3225600
ram_ratio: 3.84
uuid: bfc3c753-efb2-4692-b86d-02639196030a
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=097d1103-cbfb-4bc0-8a77-f8b482e7615c, ou=packages, o=smartdc
active: false
common_name: Standard 88
cpu_burst_ratio: 1
cpu_cap: 2300
default: false
description: Standard 88 GB RAM 22 vCPUs 2888 GB Disk
fss: 2300
group: Standard
max_lwps: 4000
max_physical_memory: 90112
max_swap: 180224
name: g3-standard-88-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 2957312
ram_ratio: 3.826086957
uuid: 097d1103-cbfb-4bc0-8a77-f8b482e7615c
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=6b06ba33-a1de-4d18-a49c-371b8410d303, ou=packages, o=smartdc
active: false
common_name: Standard 80
cpu_burst_ratio: 1
cpu_cap: 2100
default: false
description: Standard 80 GB RAM 20 vCPUs 2625 GB Disk
fss: 2100
group: Standard
max_lwps: 4000
max_physical_memory: 81920
max_swap: 163840
name: g3-standard-80-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 2688000
ram_ratio: 3.80952381
uuid: 6b06ba33-a1de-4d18-a49c-371b8410d303
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=f36e8728-a9de-4a72-9166-017a68c108d2, ou=packages, o=smartdc
active: false
common_name: Standard 72
cpu_burst_ratio: 1
cpu_cap: 1900
default: false
description: Standard 72 GB RAM 18 vCPUs 2363 GB Disk
fss: 1900
group: Standard
max_lwps: 4000
max_physical_memory: 73728
max_swap: 147456
name: g3-standard-72-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 2419712
ram_ratio: 3.789473684
uuid: f36e8728-a9de-4a72-9166-017a68c108d2
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=fe34a720-d7bc-4353-a669-a66600e7448b, ou=packages, o=smartdc
active: false
common_name: Standard 64
cpu_burst_ratio: 1
cpu_cap: 1700
default: false
description: Standard 64 GB RAM 16 vCPUs 2100 GB Disk
fss: 1700
group: Standard
max_lwps: 4000
max_physical_memory: 65536
max_swap: 131072
name: g3-standard-64-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 2150400
ram_ratio: 3.764705882
uuid: fe34a720-d7bc-4353-a669-a66600e7448b
vcpus: 16
version: 1.0.0
zfs_io_priority: 100

dn: uuid=ecbdcfc8-650c-42b8-984a-85c7af14d7da, ou=packages, o=smartdc
active: false
common_name: Standard 56
cpu_burst_ratio: 1
cpu_cap: 1500
default: false
description: Standard 56 GB RAM 14 vCPUs 1838 GB Disk
fss: 1500
group: Standard
max_lwps: 4000
max_physical_memory: 57344
max_swap: 114688
name: g3-standard-56-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1882112
ram_ratio: 3.733333333
uuid: ecbdcfc8-650c-42b8-984a-85c7af14d7da
vcpus: 14
version: 1.0.0
zfs_io_priority: 100

dn: uuid=f98e51c4-a273-4f6e-8c20-a3ae2d8972e8, ou=packages, o=smartdc
active: false
common_name: Standard 48
cpu_burst_ratio: 1
cpu_cap: 1300
default: false
description: Standard 48 GB RAM 12 vCPUs 1683 GB Disk
fss: 1300
group: Standard
max_lwps: 4000
max_physical_memory: 49152
max_swap: 98304
name: g3-standard-48-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.692307692
uuid: f98e51c4-a273-4f6e-8c20-a3ae2d8972e8
vcpus: 12
version: 1.0.0
zfs_io_priority: 100

dn: uuid=c9b0575e-7cf2-4103-9ce0-bf77473ee41f, ou=packages, o=smartdc
active: false
common_name: Standard 40
cpu_burst_ratio: 1
cpu_cap: 1100
default: false
description: Standard 40 GB RAM 10 vCPUs 1683 GB Disk
fss: 1100
group: Standard
max_lwps: 4000
max_physical_memory: 40960
max_swap: 81920
name: g3-standard-40-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.636363636
uuid: c9b0575e-7cf2-4103-9ce0-bf77473ee41f
vcpus: 10
version: 1.0.0
zfs_io_priority: 100

dn: uuid=687daf62-4726-4c28-9b1f-3454bebaa7ae, ou=packages, o=smartdc
active: false
common_name: Standard 32
cpu_burst_ratio: 1
cpu_cap: 900
default: false
description: Standard 32 GB RAM 8 vCPUs 1683 GB Disk
fss: 900
group: Standard
max_lwps: 4000
max_physical_memory: 32768
max_swap: 65536
name: g3-standard-32-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.555555556
uuid: 687daf62-4726-4c28-9b1f-3454bebaa7ae
vcpus: 8
version: 1.0.0
zfs_io_priority: 100

dn: uuid=9177dc65-195a-484a-bec3-c6aa6498db37, ou=packages, o=smartdc
active: true
common_name: Standard 30
cpu_burst_ratio: 1
cpu_cap: 900
default: false
description: Standard 30 GB RAM 8 vCPUs 1683 GB Disk
fss: 900
group: Standard
max_lwps: 4000
max_physical_memory: 30720
max_swap: 61440
name: g3-standard-30-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1723392
ram_ratio: 3.333333333
uuid: 9177dc65-195a-484a-bec3-c6aa6498db37
vcpus: 8
version: 1.0.0
zfs_io_priority: 100

dn: uuid=96110066-bb48-41ed-9122-1723d7066fe6, ou=packages, o=smartdc
active: false
common_name: Standard 17.125
cpu_burst_ratio: 1
cpu_cap: 600
default: false
description: Standard 17.1 GB RAM 5 vCPUs 1683 GB Disk
fss: 600
group: Standard
max_lwps: 4000
max_physical_memory: 17536
max_swap: 35072
name: g3-standard-17.125-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1723392
ram_ratio: 2.854166667
uuid: 96110066-bb48-41ed-9122-1723d7066fe6
vcpus: 5
version: 1.0.0
zfs_io_priority: 100

dn: uuid=80ce5293-da87-418a-8396-e58bdc7c372d, ou=packages, o=smartdc
active: false
common_name: Standard 16
cpu_burst_ratio: 1
cpu_cap: 500
default: false
description: Standard 16 GB RAM 4 vCPUs 1575 GB Disk
fss: 500
group: Standard
max_lwps: 4000
max_physical_memory: 16384
max_swap: 32768
name: g3-standard-16-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1612800
ram_ratio: 3.2
uuid: 80ce5293-da87-418a-8396-e58bdc7c372d
vcpus: 4
version: 1.0.0
zfs_io_priority: 100

dn: uuid=805bdab2-9abd-4e05-8255-c5e3bf1f110c, ou=packages, o=smartdc
active: true
common_name: Standard 15
cpu_burst_ratio: 1
cpu_cap: 500
default: false
description: Standard 15 GB RAM 4 vCPUs 1467 GB Disk
fss: 500
group: Standard
max_lwps: 4000
max_physical_memory: 15360
max_swap: 30720
name: g3-standard-15-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 1502208
ram_ratio: 3
uuid: 805bdab2-9abd-4e05-8255-c5e3bf1f110c
vcpus: 4
version: 1.0.0
zfs_io_priority: 100

dn: uuid=eb2a298e-36d3-42cb-8b73-f4847e9f3ecb, ou=packages, o=smartdc
active: true
common_name: Standard 7.5
cpu_burst_ratio: 1
cpu_cap: 201
default: false
description: Standard 7.5 GB RAM 2 vCPUs 738 GB Disk
fss: 201
group: Standard
max_lwps: 4000
max_physical_memory: 7680
max_swap: 15360
name: g3-standard-7.5-kvm
objectclass: sdcpackage
overprovision_cpu: 1
overprovision_memory: 1
quota: 755712
ram_ratio: 3.731343284
uuid: eb2a298e-36d3-42cb-8b73-f4847e9f3ecb
vcpus: 2
version: 1.0.0
zfs_io_priority: 100
EOF
