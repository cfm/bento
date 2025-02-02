#!/bin/bash

# Getting script directory location
SCRIPT_RELATIVE_DIR=$(dirname "${BASH_SOURCE[0]}")
cd "$SCRIPT_RELATIVE_DIR" || exit

# set tmp dir for files
AMZDIR="$(pwd)/packer_templates/amz_working_files"

# Get virtualbox vdi file name with latest version number
IMG="$(wget -q https://cdn.amazonlinux.com/os-images/latest/virtualbox/ -O - | grep ".vdi" | cut -d "\"" -f 2)"

# Download vbox vdi
wget -q -O "$AMZDIR"/amazon.vdi -c https://cdn.amazonlinux.com/os-images/latest/virtualbox/"$IMG"

if [ ! -f "$AMZDIR"/amazon.vdi ]; then
  echo There must be a file named amazon.vdi in "$AMZDIR"!
  echo You can download the vdi file at https://cdn.amazonlinux.com/os-images/latest/virtualbox/
  exit 1
fi

echo "Cleaning up old files"
rm "$AMZDIR"/*.iso "$AMZDIR"/*.ovf "$AMZDIR"/*.vmdk

echo "Creating ISO"
hdiutil makehybrid -o "$AMZDIR"/seed.iso -hfs -joliet -iso -default-volume-name cidata seed_iso

VM="AmazonLinuxBento"
echo Powering off and deleting any existing VMs named $VM
VBoxManage controlvm $VM poweroff --type headless 2> /dev/null
vboxmanage unregistervm $VM --delete 2> /dev/null
sleep 5

echo "Creating the VM"
# from https://www.perkin.org.uk/posts/create-virtualbox-vm-from-the-command-line.html
VBoxManage createvm --name $VM --ostype "RedHat_64" --register
VBoxManage storagectl $VM --name "SATA Controller" --add sata --controller IntelAHCI
VBoxManage storageattach $VM --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$AMZDIR"/amazon.vdi
VBoxManage storagectl $VM --name "IDE Controller" --add ide
VBoxManage storageattach $VM --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$AMZDIR"/seed.iso
VBoxManage modifyvm $VM --memory 1024
VBoxManage modifyvm $VM --cpus 2
VBoxManage modifyvm $VM --audio none
VBoxManage modifyvm $VM --ioapic on
sleep 5

echo Sleeping for 120 seconds to let the system boot and cloud-init to run
VBoxManage startvm $VM --type headless
sleep 120
VBoxManage controlvm $VM poweroff --type headless
VBoxManage storageattach $VM --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium none
sleep 5

echo Exporting the VM to an OVF file
vboxmanage export $VM -o "$AMZDIR"/amazon2.ovf
sleep 5

echo Deleting the VM
vboxmanage unregistervm $VM --delete

echo starting packer build of amazonlinux
if packer build -only=virtualbox-ovf.amazonlinux -var-file="$SCRIPT_RELATIVE_DIR"/os_pkrvars/amazonlinux/amazonlinux-2-x86_64.pkrvars.hcl "$SCRIPT_RELATIVE_DIR"/packer_templates; then
  echo "Cleaning up files"
  rm "$AMZDIR"/*.ovf "$AMZDIR"/*.vmdk "$AMZDIR"/*.iso
fi
