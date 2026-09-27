# Fedora 40 Server kickstart (Sing3PO base image)
# Docs: https://pykickstart.readthedocs.io/

text
lang en_US.UTF-8
keyboard us
timezone UTC --utc
network --bootproto=dhcp --device=link --activate --hostname=sing3po

# Disk: wipe and use whole disk with automatic partitioning.
zerombr
clearpart --all --initlabel
autopart --type=lvm

bootloader --location=mbr

# Root password matches the Packer ssh_password used for build handoff.
# TODO: parameterize / vault before any non-throwaway use.
rootpw packer
sshpw --username=root packer --plaintext

firstboot --disable
selinux --enforcing
firewall --enabled --service=ssh

%packages
@^server-product-environment
openssh-server
python3
sudo
%end

%post
systemctl enable sshd
%end

reboot
