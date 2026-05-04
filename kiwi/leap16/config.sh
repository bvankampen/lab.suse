#!/bin/bash
# Copyright (c) 2015 SUSE LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# 
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

set -euxo pipefail

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]-[$kiwi_profiles]..."

#======================================
# add missing fonts
#--------------------------------------
CONSOLE_FONT="eurlatgr.psfu"

#======================================
# prepare for setting root pw, timezone
#--------------------------------------
echo "** reset machine settings"
rm -f /etc/machine-id \
      /var/lib/zypp/AnonymousUniqueId \
      /var/lib/systemd/random-seed

echo "** Running ldconfig..."
/sbin/ldconfig


#======================================
# Setup baseproduct link
#--------------------------------------
suseSetupProduct

#======================================
# Specify default runlevel
#--------------------------------------
baseSetRunlevel 3

#======================================
# Add missing gpg keys to rpm
#--------------------------------------
suseImportBuildKey

#======================================
# Vagrant
#--------------------------------------
function vagrantSetup {
    # This function configures the image to work as a vagrant box.
    # These are the following steps:
    # - add the vagrant user
    # - add the vagrant user to /etc/sudoers
    # - insert the insecure vagrant ssh key
    # - create the default /vagrant share
    # - apply some recommended ssh settings

    echo "Add user vagrant"
    # create vagrant user
    useradd vagrant

    # insert the default insecure ssh key from here:
    # https://github.com/hashicorp/vagrant/blob/master/keys/vagrant.pub
    mkdir -p /home/vagrant/.ssh/
    chmod 0700 /home/vagrant/.ssh/
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" > /home/vagrant/.ssh/authorized_keys
    chmod 0600 /home/vagrant/.ssh/authorized_keys
    chown -R vagrant:vagrant /home/vagrant/

    # apply recommended ssh settings for vagrant boxes
    SSHD_CONFIG=/etc/ssh/sshd_config.d/99-vagrant.conf
    if [[ ! -d "$(dirname ${SSHD_CONFIG})" ]]; then
        SSHD_CONFIG=/etc/ssh/sshd_config
        # prepend the settings, so that they take precedence
        echo -e "UseDNS no\nGSSAPIAuthentication no\n$(cat ${SSHD_CONFIG})" > ${SSHD_CONFIG}
    else
        echo -e "UseDNS no\nGSSAPIAuthentication no" > ${SSHD_CONFIG}
    fi

    # vagrant assumes that it can sudo without a password
    # => add the vagrant user to the sudoers list
    echo "vagrant ALL=(ALL)NOPASSWD:ALL" > /etc/sudoers.d/vagrant
    visudo -cf /etc/sudoers.d/vagrant
    chmod 440 /etc/sudoers.d/vagrant

    # the default shared folder
    mkdir -p /vagrant
    chown -R vagrant:vagrant /vagrant

    # SSH service
    baseInsertService sshd

    # start vboxsf service only if the guest tools are present
    if rpm -q virtualbox-guest-tools 2> /dev/null; then
        echo vboxsf > /etc/modules-load.d/vboxsf.conf
    fi

    # drop any network udev rules for libvirt, so that the networks are called
    # ethX
    # this is not required for Virtualbox as it handles networking differently
    # and doesn't need this hack
    if [ "${kiwi_profiles}" != "virtualbox" ]; then
        rm -f /etc/udev/rules.d/*-net.rules
    fi

    # setup DHCP on eth0 properly
    mkdir /etc/sysconfig/network/
    cat << EOF > /etc/sysconfig/network/ifcfg-eth0
STARTMODE=auto
BOOTPROTO=dhcp
EOF
}

#======================================
# Configure Vagrant specifics
#--------------------------------------
if [[ "$kiwi_profiles" == *"Vagrant"* ]]; then
vagrantSetup
fi

#======================================
# Enable sshd
#--------------------------------------
baseInsertService sshd

if [ -e /etc/cloud/cloud.cfg ]; then
    systemctl enable cloud-init-local
    systemctl enable cloud-init
    systemctl enable cloud-config
    systemctl enable cloud-final
fi

# On those s390 targets the console is not capable of running jeos-firstboot,
# use systemd-firstboot as minimal alternative.
if [[ "$kiwi_profiles" =~ s390x-(dasd|fba|fcp) ]]; then
    systemctl enable systemd-firstboot
    # Enable prompting for the root password
    echo 'root:!unprovisioned' | chpasswd -e
elif [[ "$kiwi_profiles" =~ Vagrant ]]; then

    echo "Disable jeos-firstboot.service for Vagrant boxes"
    systemctl disable jeos-firstboot.service
    systemctl mask jeos-firstboot.service
    echo "Disable systemd-firstboot.service for Vagrant boxes"
    systemctl disable systemd-firstboot.service
    systemctl mask systemd-firstboot.service

elif rpm -q --whatprovides jeos-firstboot >/dev/null; then
    # Enable jeos-firstboot
    mkdir -p /var/lib/YaST2
    touch /var/lib/YaST2/reconfig_system

    systemctl mask systemd-firstboot.service
    systemctl enable jeos-firstboot.service
fi

# Enable firewalld if installed except on VMware
if [ -x /usr/sbin/firewalld ] && [ "$kiwi_profiles" != "VMware" ]; then
    echo 'Enabling firewall...'
    baseInsertService firewalld
fi

# Enable NetworkManager if installed
if rpm -q --whatprovides NetworkManager >/dev/null; then
        systemctl enable NetworkManager.service
fi

# Systemd controls the console font now
echo FONT="$CONSOLE_FONT" >> /etc/vconsole.conf

#======================================
# SSL Certificates Configuration
#--------------------------------------
echo '** Rehashing SSL Certificates...'
update-ca-certificates

if [ ! -s /var/log/zypper.log ]; then
	> /var/log/zypper.log
fi

#======================================
# Import trusted rpm keys
#--------------------------------------
for i in /usr/lib/rpm/gnupg/keys/gpg-pubkey*asc; do
    # importing can fail if it already exists
    rpm --import $i || true
done

# only for debugging
#systemctl enable debug-shell.service

#=====================================
# Configure snapper
#-------------------------------------
if [ -x /usr/bin/snapper ]; then
        echo "creating initial snapper config ..."
        # we can't call snapper here as the .snapshots subvolume
        # already exists and snapper create-config doens't like
        # that.
        cp /usr/share/snapper/config-templates/default /etc/snapper/configs/root
        # Change configuration to match SLES12-SP1 values
        # Adjust parameters
        sed -i'' 's/^TIMELINE_CREATE=.*$/TIMELINE_CREATE="no"/g' /etc/snapper/configs/root
        sed -i'' 's/^NUMBER_LIMIT=.*$/NUMBER_LIMIT="2-10"/g' /etc/snapper/configs/root
        sed -i'' 's/^NUMBER_LIMIT_IMPORTANT=.*$/NUMBER_LIMIT_IMPORTANT="4-10"/g' /etc/snapper/configs/root

        baseUpdateSysConfig /etc/sysconfig/snapper SNAPPER_CONFIGS root
fi

#=====================================
# Enable chrony if installed
#-------------------------------------
if [ -f /etc/chrony.conf ]; then
	suseInsertService chronyd
fi

#======================================
# Add default kernel boot options
#--------------------------------------
cmdline=('rw' 'quiet' 'systemd.show_status=1')

if [[ "$kiwi_profiles" == *"s390x"* ]] && ! [[ "$kiwi_profiles" == *"kvm"* ]]; then
	cmdline+=('hvc_iucv=8')
fi

if [[ "$kiwi_profiles" == *"s390x-fba"* ]] || [[ "$kiwi_profiles" == *"s390x-dasd"* ]]; then
	cmdline+=('dasd_mod.dasd=ipldev')
fi

if ! [[ "$kiwi_profiles" == *"s390x"* ]]; then
	cmdline+=('console=ttyS0,115200' 'console=tty0')
fi

if [[ "$kiwi_profiles" == *"Cloud"* ]]; then
	cmdline+=('net.ifnames=0')
fi

if [[ "$kiwi_profiles" == *"HyperV"* ]]; then
	cmdline+=('earlyprintk=ttyS0,115200' 'rootdelay=300')
fi

# Configure SELinux if installed
if [[ -e /etc/selinux/config ]]; then
	cmdline+=('security=selinux' 'selinux=1')

	sed -i -e 's|^SELINUX=.*|SELINUX=enforcing|g' \
	       -e 's|^SELINUXTYPE=.*|SELINUXTYPE=targeted|g' \
	       "/etc/selinux/config"
fi

if rpm -q sdbootutil; then
	mkdir -p /etc/kernel
	echo "${cmdline[*]}" > /etc/kernel/cmdline
elif [ -e /etc/default/grub ]; then
	sed -i "s#^GRUB_CMDLINE_LINUX_DEFAULT=.*\$#GRUB_CMDLINE_LINUX_DEFAULT=\"${cmdline[*]}\"#" /etc/default/grub

	# Set GRUB2 to boot graphically (bsc#1097428)
	sed -Ei"" "s/#?GRUB_TERMINAL=.+$/GRUB_TERMINAL=gfxterm/g" /etc/default/grub
	sed -Ei"" "s/#?GRUB_GFXMODE=.+$/GRUB_GFXMODE=auto/g" /etc/default/grub
else
	echo "Unknown bootloader"
	exit 1
fi

cat >>/etc/fstab.script <<"EOF"
# Relabel /etc. While kiwi already relabelled it earlier, there are some files created later (boo#1210604).
if [ -e /etc/selinux/config ]; then
       . /etc/selinux/config
       touch /etc/sysconfig/bootloader # Make sure this exists so it gets labelled
       setfiles -e /proc -e /sys -e /dev /etc/selinux/${SELINUXTYPE}/contexts/files/file_contexts /etc
fi
EOF

chmod a+x /etc/fstab.script

#======================================
# Disable recommends on virtual images (keep hardware supplements, see bsc#1089498)
#--------------------------------------
sed -i 's/.*solver.onlyRequires.*/solver.onlyRequires = true/g' /etc/zypp/zypp.conf

#======================================
# Disable installing documentation
#--------------------------------------
sed -i 's/.*rpm.install.excludedocs.*/rpm.install.excludedocs = yes/g' /etc/zypp/zypp.conf

#======================================
# Configure Raspberry Pi specifics
#--------------------------------------
if [[ "$kiwi_profiles" == *"RaspberryPi"* ]]; then
	# Also show WLAN interfaces in /etc/issue
	baseUpdateSysConfig /etc/sysconfig/issue-generator NETWORK_INTERFACE_REGEX '^[bew]'

	# Add necessary kernel modules to initrd (will disappear with bsc#1084272)
	echo 'add_drivers+=" bcm2835_dma dwc2 "' > /etc/dracut.conf.d/raspberrypi_modules.conf

	# Work around network issues
  	cat > /etc/modprobe.d/50-rpi3.conf <<-EOF
		# Prevent too many page allocations (bsc#1012449)
		options smsc95xx turbo_mode=N
	EOF

	cat > /usr/lib/sysctl.d/50-rpi3.conf <<-EOF
		# Avoid running out of DMA pages for smsc95xx (bsc#1012449)
		vm.min_free_kbytes = 2048
	EOF
fi

# Enable multipathd for MP images
if [ "${kiwi_oemmultipath_scan-false}" = 'true' ]; then
        systemctl enable multipathd.service
fi

#======================================
# Configure FDE/BLS specifics
#--------------------------------------

if rpm -q sdbootutil; then
	# FIXME: kiwi needs /boot/efi to exist before syncing the disk image
	mkdir -p /boot/efi

	[ -e /var/lib/YaST2/reconfig_system ] && systemctl enable sdbootutil-enroll.service
fi

exit 0
