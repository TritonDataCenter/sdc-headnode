@echo off
rem coal-vmware-setup.bat: sets up VMWare Workstation / Player
rem so you can use CoaL (Cloud on a Laptop) with it.
rem
rem Copyright (c) 2011 Joyent Inc., All rights reserved.

reg query "HKU\S-1-5-19" >nul 2>nul
if "%errorlevel%" NEQ "0" (
	echo You must run this program as an Administrator.  Please re-run by
	echo right-clicking this file, and then clicking "Run as Administrator"
	goto:EOF
)

set vmdir="\Program Files (x86)\VMware\VMware Player"
echo before: %vmdir%
if exist "\Program Files (x86)\VMware\VMware Workstation" set vmdir="\Program Files (x86)\VMware\VMware Workstation"
echo after: %vmdir%

cd %vmdir%
echo Stopping VMware networking services...
start /wait vnetlib.exe -- stop dhcp
start /wait vnetlib.exe -- stop nat

echo Backing up VMware networking files...
cd \ProgramData\VMware
copy vmnetdhcp.conf vmnetdhcp.conf.pre_coal
copy vmnetnat.conf vmnetnat.conf.pre_coal

cd %vmdir%
echo Changing VMware settings...
start /wait vnetlib.exe -- set vnet vmnet8 mask 255.255.255.0
start /wait vnetlib.exe -- set vnet vmnet8 addr 10.88.88.0
start /wait vnetlib.exe -- add dhcp vmnet8
start /wait vnetlib.exe -- add nat vmnet8
start /wait vnetlib.exe -- update dhcp vmnet8
start /wait vnetlib.exe -- update nat vmnet8
start /wait vnetlib.exe -- update adapter vmnet8

start /wait vnetlib.exe -- set vnet vmnet1 mask 255.255.255.0 
start /wait vnetlib.exe -- set vnet vmnet1 addr 10.99.99.0
start /wait vnetlib.exe -- remove dhcp vmnet1
start /wait vnetlib.exe -- remove nat vmnet1
start /wait vnetlib.exe -- update dhcp vmnet1
start /wait vnetlib.exe -- update nat vmnet1
start /wait vnetlib.exe -- update adapter vmnet1

echo Starting VMware networking services...
start /wait vnetlib.exe -- start dhcp
start /wait vnetlib.exe -- start nat

echo Done
pause
