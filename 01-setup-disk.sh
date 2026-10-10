#!/usr/bin/env bash
set -e

echo "=== LANGKAH 1: Pemilihan Disk Target ==="
# Menangkap input dinamis menggunakan lsblk dan smenu (vertikal 1 kolom)
DISK_RAW=$(lsblk -dno NAME,SIZE | smenu -c 1 -m "Gunakan panah untuk memilih disk instalasi, lalu tekan Enter:")

if [ -z "$DISK_RAW" ]; then
    echo "Instalasi dibatalkan: Tidak ada disk yang dipilih."
    exit 1
fi

DISK="/dev/$(echo "$DISK_RAW" | awk '{print $1}')"

dialog --title "Peringatan Format Disk" --yesno "PERHATIAN!\n\nSeluruh data pada disk $DISK akan DIHAPUS PERMANEN.\n\nApakah Anda yakin ingin melanjutkan proses format dan instalasi?" 10 60
if [ $? -ne 0 ]; then
    clear
    echo "Instalasi dibatalkan oleh pengguna."
    exit 1
fi
clear

echo "=== LANGKAH 2: Konfigurasi Swap ==="
dialog --title "Partisi Swap" --yesno "Apakah Anda ingin membuat partisi Swap sebesar 4GB?\n\n(Direkomendasikan untuk sistem dengan RAM di bawah 8GB)" 10 60
CREATE_SWAP=$?
clear

echo "=== LANGKAH 3: Partisi & Subvolume Btrfs pada $DISK ==="
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on

if [ $CREATE_SWAP -eq 0 ]; then
    echo "Membuat skema partisi DENGAN Swap (4GB)..."
    parted -s "$DISK" mkpart primary linux-swap 513MiB 4609MiB
    parted -s "$DISK" mkpart primary btrfs 4609MiB 100%
    
    if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
        PART_EFI="${DISK}p1"
        PART_SWAP="${DISK}p2"
        PART_ROOT="${DISK}p3"
    else
        PART_EFI="${DISK}1"
        PART_SWAP="${DISK}2"
        PART_ROOT="${DISK}3"
    fi
    
    mkswap "$PART_SWAP"
    swapon "$PART_SWAP" # Diaktifkan agar genfstab bisa merekam Swap otomatis
else
    echo "Membuat skema partisi TANPA Swap..."
    parted -s "$DISK" mkpart primary btrfs 513MiB 100%
    
    if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
        PART_EFI="${DISK}p1"
        PART_ROOT="${DISK}p2"
    else
        PART_EFI="${DISK}1"
        PART_ROOT="${DISK}2"
    fi
fi

mkfs.vfat -F 32 "$PART_EFI"
mkfs.btrfs -f "$PART_ROOT"

# Mount sementara untuk subvolume
mount "$PART_ROOT" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Mount subvolume akhir
mount -o noatime,compress=zstd,ssd,discard=async,subvol=@ "$PART_ROOT" /mnt
mkdir -p /mnt/home /mnt/.snapshots /mnt/boot/efi
mount -o noatime,compress=zstd,ssd,discard=async,subvol=@home "$PART_ROOT" /mnt/home
mount -o noatime,compress=zstd,ssd,discard=async,subvol=@snapshots "$PART_ROOT" /mnt/.snapshots
mount "$PART_EFI" /mnt/boot/efi

echo "=== LANGKAH 4: Generate fstab ==="
mkdir -p /mnt/etc
genfstab -U /mnt > /mnt/etc/fstab
echo "Partisi, subvolume, dan fstab berhasil dikonfigurasi."