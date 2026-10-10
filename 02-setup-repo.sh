#!/usr/bin/env bash
set -e

dialog --infobox "Sedang mengambil daftar mirror resmi Debian dari https://www.debian.org/mirror/list-full..." 5 60

# Mengambil URL persis seperti yang tertulis di dalam atribut href HTML
MIRROR_LIST=$(curl -sL https://www.debian.org/mirror/list-full | grep -A 1 "Packages over HTTP" | grep -Eo 'href="http://[^"]+"' | sed 's/href="//;s/"//' | sort -u)

if [ -z "$MIRROR_LIST" ]; then
    # Fallback apabila tidak ada koneksi internet / curl gagal
    MIRROR_LIST="http://deb.debian.org/debian/\nhttp://kartolo.sby.datautama.net.id/debian/\nhttp://kebo.pens.ac.id/debian/"
fi

# Menampilkan fzf dengan tampilan kustom seperti pop-up dialog
SELECTED_MIRROR=$(echo -e "$MIRROR_LIST" | fzf \
    --height=70% \
    --layout=reverse \
    --border=rounded \
    --margin=2,5 \
    --prompt="Cari/Pilih Mirror ❯ " \
    --pointer="▶" \
    --header=" Ketik kode negara (misal: id, sg) atau nama institusi untuk mencari. Enter untuk memilih. " \
    --info=inline)

if [ -z "$SELECTED_MIRROR" ]; then
    SELECTED_MIRROR="http://deb.debian.org/debian/" # Fallback jika pengguna membatalkan pilihan
fi
clear

# Simpan pilihan ke berkas sementara agar tidak merusak antarmuka TTY saat dibaca oleh skrip utama
echo "$SELECTED_MIRROR" >/tmp/selected_mirror.tmp
