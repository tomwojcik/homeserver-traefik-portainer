1. VPN_TYPE seems to make no difference. If it loads wrong VPN type, just edit the container env variables. Remember that it has to be stopped first.
2. Tun doesnt exit. Create a bash script
```shell
#!/bin/bash

# insmod /lib/modules/tun.ko

# Create the device node (if it doesn't exist)
mkdir -p /dev/net
mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun

setup_gluetun.sh
```
go to synology task scheduler, and run it on startup, with root.
