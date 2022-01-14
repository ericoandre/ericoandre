#!/usr/bin/env bash
# encoding: utf-8
##################################################
#                   Variaveis                    #
##################################################
KEYBOARD_LAYOUT=br-abnt2
# File System das partições
ROOT_FS=ext4
BOOT_FS=ext2
SWAP_SIZE=1024
GRUB_SIZE=256
ROOT_SIZE=117
######## Variáveis auxiliares. NÃO DEVEM SER ALTERADAS
BOOT_START=1
BOOT_END=$(($BOOT_START+$GRUB_SIZE))
ROOT_START=$BOOT_END
ROOT_END=$(($ROOT_START+$ROOT_SIZE))
##################################################
#                   functions                    #
##################################################
arch_chroot(){
    arch-chroot /mnt /bin/bash -c "${1}"
}
Parted() {
    parted --script $HD "${1}"
}
##################################################
#                   Script                       #
##################################################
# ILoveCandy
loadkeys $KEYBOARD_LAYOUT
timedatectl set-ntp true
if [ "$(uname -m)" = "x86_64" ]; then
    sed -i '/multilib\]/,+1 s/^#//' /etc/pacman.conf
    echo ILoveCandy >> /etc/pacman.conf
fi
pacman -Syu && pacman -S --noconfirm reflector dialog
reflector --verbose --protocol http --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
# reflector --country Brazil --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
if [[ -d "/sys/firmware/efi/" ]]; then
    Parted "mklabel gpt"
    Parted "mkpart primary fat32 $BOOT_START $BOOT_END"
    Parted "set 1 esp on"
    mkfs.vfat -F32 -n BOOT /dev/sda1
else
    Parted "mklabel msdos
    Parted "mkpart primary $BOOT_START $BOOT_END"
    Parted "set 1 bios_grub on"
    Parted "name 1 boot"
    mkfs.$BOOT_FS /dev/sda1
fi
Parted "mkpart primary $ROOT_FS $ROOT_START $ROOT_END"
Parted "name 2 arch_linux"
mkfs.$ROOT_FS /dev/sda2 -L Root && mount /dev/sda2 /mnt
if [[ -d "/sys/firmware/efi/" ]]; then
    mkdir -p /mnt/boot/efi && mount /dev/sda1 /mnt/boot/efi
else
    mkdir /mnt/boot && mount /dev/sda1 /mnt/boot
fi
touch /mnt/swapfile
dd if=/dev/zero of=/mnt/swapfile bs=1M count=$SWAP_SIZE
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile
pacstrap /mnt base base-devel linux linux-firmware linux-headers bash-completion git reflector ntfs-3g neofetch htop os-prober grub wget 
genfstab -U -p /mnt >> /mnt/etc/fstab
# echo "/swapfile       none    swap    defaults    0   0" >> /mnt/etc/fstab
#setting hostname
HNAME=$(dialog --inputbox "Digite Nome para Maquina: " 10 25 --stdout)
arch_chroot "echo $HNAME > /etc/hostname"
arch_chroot "echo -e '127.0.0.1    localhost.localdomain    localhost
::1        localhost.localdomain    localhost
127.0.1.1    $HNAME.localdomain    $HNAME' >> /etc/hosts"
#setting locale pt_BR.UTF-8 UTF-8
LANGUAGE=$(dialog --title "$TITLE" --radiolist "Escolha o Idioma:" 15 30 4 $locales --stdout)
sed 's/^#'$LANGUAGE'/'$LANGUAGE/ /mnt/etc/locale.gen > /tmp/locale && mv /tmp/locale /mnt/etc/locale.gen
arch_chroot 'echo -e LANG="${LANGUAGE}
LC_MESSAGES="${LANGUAGE}"> /etc/locale.conf'
arch_chroot "locale-gen"
arch_chroot "export LANG=${LANGUAGE}"
# Vconsole
arch_chroot "echo -e KEYMAP=$KEYBOARD_LAYOUT
FONT=lat0–16
FONT_MAP= > /etc/vconsole.conf"
# Setting timezone
ZONE=$(dialog  --clear --menu "Select Sua country/zone." 20 35 15 $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud | sort | awk '{ printf " "$0" "  " . " }') --stdout)
SUBZONE=$(dialog  --clear --menu "Select Sua country/zone." 20 35 15 $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "$ZONE/" | sed "s/$ZONE\///g" | sort -ud | sort | awk '{ printf " "$0" "  " . " }') --stdout)
arch_chroot "rm /etc/localtime"
arch_chroot "ln -s /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime"
# Setting hw CLOCK
CLOCK=$(dialog  --clear --radiolist "Configurcao do relojo" 10 30 4 "utc" "" ON "localtime" "" OFF --stdout)
arch_chroot "hwclock --systohc --$CLOCK"
# root password
ROOT_PASSWD=$(dialog --inputbox "Digite o root PASSWD" 10 25 --stdout)
arch_chroot "echo -e $ROOT_PASSWD'
'$ROOT_PASSWD | passwd"
#criar usuario
USER=$(dialog --inputbox "Digite seu nome" 10 25 --stdout)
arch_chroot "useradd -m -g users -G adm,lp,wheel,power,audio,video -s /bin/bash $USER"
#Definir senha do usuário 
USER_PASSWD=$(dialog --inputbox "Digite seu PASSWD" 10 25 --stdout)
arch_chroot "echo -e $USER_PASSWD"
"$USER_PASSWD | passwd `echo $USER`"
# arch_chroot "echo %wheel ALL=(ALL) ALL >> /etc/sudoers"
arch_chroot "mkinitcpio -p linux"
if [[ -d "/sys/firmware/efi/" ]]; then
    arch_chroot "pacman -S --noconfirm intel-ucode  efibootmgr dosfstools mtools"
    arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub_uefi --recheck"
    mkdir /mnt/boot/efi/EFI/boot && mkdir /mnt/boot/grub/locale
    cp /mnt/boot/efi/EFI/grub_uefi/grubx64.efi /mnt/boot/efi/EFI/boot/bootx64.efi
else
    arch_chroot "grub-install --target=i386-pc --recheck $HD"
fi
cp /mnt/usr/share/locale/en@quot/LC_MESSAGES/grub.mo /mnt/boot/grub/locale/en.mo
arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
arch_chroot "pacman -S --noconfirm xf86-video-intel xorg xorg-server"
