#!/usr/bin/env bash
###############################################################################
##                                                                           ##
## Install Debian Stable with Runit                                          ##
## Author : Pras                                                             ##
## URL : https://github.com/masprast/deru                                    ##
##                                                                           ##
###############################################################################
set -e

# Function for automatically unmount when the script is done/fail
cleanup() {
    echo "=== MEMBERSIHKAN MOUNT POINT & BIND MOUNT ==="
    umount -l /mnt/sys/firmware/efi/efivars 2>/dev/null || true
    umount -l /mnt/sys 2>/dev/null || true
    umount -l /mnt/proc 2>/dev/null || true
    umount -l /mnt/dev 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
}
trap cleanup EXIT

echo "=== STEP 1: Preparation ==="
echo
echo "Installing debootstrap, BTRFS, and other package needed for installation process"
echo
apt update && apt install -y debootstrap btrfs-progs parted arch-install-scripts debian-archive-keyring

echo "=== LANGKAH 2: Partisi SSD & Subvolume Btrfs ==="
# export DISK="/dev/$(lsblk -nd|cut -d' ' -f1)"
export DISK="/dev/nvme0n1"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary btrfs 513MiB 100%

mkfs.vfat -F 32 "${DISK}p1"
mkfs.btrfs -f "${DISK}p2"

# Mount sementara untuk subvolume
mount "${DISK}p2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Mount subvolume akhir
mount -o noatime,compress=zstd,ssd,discard=async,subvol=@ "${DISK}p2" /mnt
mkdir -p /mnt/home /mnt/.snapshots /mnt/boot/efi
mount -o noatime,compress=zstd,ssd,discard=async,subvol=@home "${DISK}p2" /mnt/home
mount -o noatime,compress=zstd,ssd,discard=async,subvol=@snapshots "${DISK}p2" /mnt/.snapshots
mount "${DISK}p1" /mnt/boot/efi

echo "=== LANGKAH 3: Debootstrap & Generate fstab ==="
#debootstrap --arch=amd64 trixie /mnt http://kartolo.sby.datautama.net.id/debian/
debootstrap --arch=amd64 --variant=minbase --exclude=systemd-sysv --include=runit-init,runit-helper,apt,sysvinit-utils trixie /mnt http://deb.debian.org/debian/
mkdir -p /mnt/etc
genfstab -U /mnt >/mnt/etc/fstab

echo "=== LANGKAH 4: Mount File System Virtual & Menyalin Berkas Konfigurasi ==="

# Di dalam skrip installer utama sebelum memanggil 'chroot /mnt':
for i in /dev /dev/pts /proc /sys /run; do mount -B $i /mnt$i; done
mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars 2>/dev/null || true

# Buat folder penampung sementara di target mount
mkdir -p /mnt/tmp/installer-data

# Salin folder-folder kustom dari flashdisk
[ -d ./config ] && cp -r ./config /mnt/tmp/installer-data/
[ -d ./custom-scripts ] && cp -r ./custom-scripts /mnt/tmp/installer-data/
[ -d ./app-install-scripts ] && cp -r ./app-install-scripts /mnt/tmp/installer-data/
[ -d ./setup ] && cp -r ./setup /mnt/tmp/installer-data/
[ -d ./home ] && cp -r ./home /mnt/tmp/installer-data/

# for folder in "";do

# Salin & jalankan skrip chroot
echo "=== Memulai Sesi Chroot ==="
cp chroot-install.sh /mnt/tmp/chroot-install.sh
chmod +x /mnt/tmp/chroot-install.sh

chroot /mnt /tmp/chroot-install.sh

# Bersihkan file sementara setelah instalasi selesai
rm -rf /mnt/tmp/installer-data /mnt/tmp/chroot-install.sh /mnt/tmp/pkglist.txt

echo "=== INSTALASI SELESAI ==="
echo "Silakan keluar, unmount, reboot, dan atur BIOS (Linux S3 & Secure Boot: Enabled)."
