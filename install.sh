#!/usr/bin/env bash
set -e

# Fungsi untuk unmount otomatis saat skrip selesai/gagal
cleanup() {
    echo "=== MEMBERSIHKAN MOUNT POINT, BIND MOUNT & SWAP ==="
    umount -l /mnt/sys/firmware/efi/efivars 2>/dev/null || true
    umount -l /mnt/sys 2>/dev/null || true
    umount -l /mnt/proc 2>/dev/null || true
    umount -l /mnt/dev 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true
}
trap cleanup EXIT

echo "=== PERSIAPAN PERKAKAS AWAL ==="
apt update && apt install -y debootstrap btrfs-progs parted arch-install-scripts debian-archive-keyring smenu dialog curl

# Memastikan modul skrip dapat dieksekusi
chmod +x 01-setup-disk.sh 02-setup-repo.sh

echo "=== MEMANGGIL MODUL PARTISI ==="
bash ./01-setup-disk.sh

echo "=== MEMANGGIL MODUL REPOSITORI ==="
bash ./02-setup-repo.sh
# Membaca hasil pilihan dari berkas sementara
SELECTED_MIRROR=$(cat /tmp/selected_mirror.tmp)

echo "=== DEBOOTSTRAP (Memasang Sistem Dasar) ==="
# Menggunakan mirror yang telah dipilih dari modul repositori
debootstrap --arch=amd64 --variant=minbase --exclude=systemd-sysv --include=runit-init,runit-helper,apt,sysvinit-utils trixie /mnt "$SELECTED_MIRROR" | dialog --title "Menjalankan Debootstrap..." --programbox 20 80
clear

echo "=== MOUNT VIRTUAL FILESYSTEM & PENYALINAN DATA ==="
for i in /dev /dev/pts /proc /sys /run; do mount -B $i /mnt$i; done
mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars 2>/dev/null || true

# Buat folder penampung sementara di target mount
TMP="/mnt/tmp/installer-data"
mkdir -p "$TMP"

# Menyimpan mirror yang dipilih agar bisa dibaca oleh chroot-install.sh
echo "$SELECTED_MIRROR" >$TMP/selected_mirror.txt

# Salin folder-folder kustom (Pastikan direktori proyek siap)
[ -d ./config ] && cp -r ./config "$TMP/"
[ -d ./custom-scripts ] && cp -r ./custom-scripts "$TMP/"
[ -d ./app-install-scripts ] && cp -r ./app-install-scripts "$TMP/"
[ -d ./setup ] && cp -r ./setup "$TMP/"
[ -d ./home ] && cp -r ./home "$TMP/"

# Salin & jalankan skrip chroot
echo "=== MEMULAI SESI CHROOT ==="
cp chroot-install.sh /mnt/tmp/chroot-install.sh
chmod +x /mnt/tmp/chroot-install.sh

chroot /mnt /tmp/chroot-install.sh

# Bersihkan file sementara setelah instalasi di dalam chroot selesai
rm -rf /mnt/tmp/installer-data /mnt/tmp/chroot-install.sh /tmp/selected_mirror.tmp

echo "=== INSTALASI SELESAI ==="
echo "Silakan keluar, unmount, reboot, dan atur BIOS (Linux S3 & Secure Boot: Enabled)."
