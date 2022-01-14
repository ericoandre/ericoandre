#!/bin/bash
# encoding: utf-8
##################################################
#                   Variaveis                    #
##################################################
ZONE=America
SUBZONE=Recife
LOCALE=pt_BR.UTF-8
CLOCK=utc
KEYBOARD_LAYOUT=br-abnt2
# Nome do Computador
HNAME=Arch-VM
ROOT_PASSWD=toorrico
#
USER=erico
USER_PASSWD=toor
#
HD=/dev/sda
# File System das partições
ROOT_FS=ext4
BOOT_FS=ext2
#
SWAP_SIZE=1024
GRUB_SIZE=256
ROOT_SIZE=117
EXTRA_PKGS="networkmanager"
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
particionar_discos(){
    ERR=0
    if [[ -d "/sys/firmware/efi/" ]]; then
        # Configura o tipo da tabela de partições
        Parted "mklabel gpt" 1>/dev/null || ERR=1
        # Cria partição esp
        Parted "mkpart primary fat32 $BOOT_START $BOOT_END" 1>/dev/null || ERR=1
        Parted "set 1 esp on" 1>/dev/null || ERR=1
    else
        # Configura o tipo da tabela de partições
        Parted "mklabel msdos" 1>/dev/null || ERR=1
        Parted "mkpart primary $BOOT_FS $BOOT_START $BOOT_END" 1>/dev/null || ERR=1
        Parted "set 1 bios_grub on" 1>/dev/null || ERR=1
    fi
    Parted "mkpart primary $ROOT_FS $ROOT_START $ROOT_END" 1>/dev/null || ERR=1
    if [ $ERR -eq 1 ]; then
        echo "Erro durante o particionamento"
        exit 1
    fi
}
formata_particoes(){
    ERR=0
    if [[ -d "/sys/firmware/efi/" ]]; then
        echo "Formatando partição esp"
        mkfs.vfat -F32 -n BOOT /dev/sda1 1>/dev/null || ERR=1
    else
        mkfs.$BOOT_FS /dev/sda1 -L Boot 1>/dev/null || ERR=1
    fi
    echo "Formatando partição root"
    mkfs.$ROOT_FS /dev/sda2 -L Root 1>/dev/null || ERR=1
    
    if [ $ERR -eq 1 ]; then
        echo "Erro ao criar File Systems"
        exit 1
    fi
}
monta_particoes(){
    ERR=0
    echo "Monta partição root"
    mount /dev/sda2 /mnt 1>/dev/null || ERR=1
    touch /mnt/swapfile
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$SWAP_SIZE
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
    if [[ -d "/sys/firmware/efi/" ]]; then
        # Monta partição esp
        mkdir -p /mnt/boot/EFI 1>/dev/null || ERR=1
        mount /dev/sda1 /mnt/boot/EFI 1>/dev/null || ERR=1
    else
        mount /dev/sda1 /mnt/boot 1>/dev/null || ERR=1
    fi
    if [ $ERR -eq 1 ]; then
        echo "Erro ao Montar particoes"
        exit 1
    fi
}
conf_repositorio(){
    echo "Configurando pacman"
    if [ "$(uname -m)" = "x86_64" ]; then
        cp /etc/pacman.conf /etc/pacman.conf.bkp
        sed '/^#\[multilib\]/{s/^#//;n;s/^#//;n;s/^#//}' /etc/pacman.conf > /tmp/pacman
        mv /tmp/pacman /etc/pacman.conf
        echo ILoveCandy >> /etc/pacman.conf
    fi
}
inst_base(){
    ERR=0
    pacstrap /mnt base base-devel linux linux-headers linux-firmware `echo $EXTRA_PKGS`
    genfstab -U /mnt >> /mnt/etc/fstab 1>/dev/null || ERR=1
    
    echo "/swapfile		none	swap	defaults	0	0" >> /mnt/etc/fstab
    if [ $ERR -eq 1 ]; then
        echo "Erro ao instalar sistema"
        exit 1
    fi
}
boot_load(){
    ERR=0
    arch_chroot "pacman -Syy && pacman -S --noconfirm grub"
    arch_chroot "pacman -S --noconfirm intel-ucode"
    if [[ -d "/sys/firmware/efi/" ]]; then
        # installing bootloader
        arch_chroot "pacman -S --noconfirm efibootmgr dosfstools mtools"
        arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub_uefi --recheck" 1>/dev/null || ERR=1
        mkdir /mnt/boot/efi/EFI/boot
        mkdir /mnt/boot/grub/locale
        cp /mnt/boot/efi/EFI/grub_uefi/grubx64.efi /mnt/boot/efi/EFI/boot/bootx64.efi 1>/dev/null || ERR=1
    else
        arch_chroot "grub-install --target=i386-pc --recheck /dev/sda1" 1>/dev/null || ERR=1
    fi
    cp /mnt/usr/share/locale/en@quot/LC_MESSAGES/grub.mo /mnt/boot/grub/locale/en.mo 1>/dev/null || ERR=1
    arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 1>/dev/null || ERR=1
    if [ $ERR -eq 1 ]; then
        echo "Erro ao instalar boot load"
        exit 1
    fi
}
##################################################
#                   Script                       #
##################################################
sudo pacman -Syy
sudo pacman -S --noconfirm reflector dialog
loadkeys br-abnt2
timedatectl set-ntp true
#echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
echo "nameserver 200.17.137.34" >> /etc/resolv.conf
echo "nameserver 200.17.137.37" >> /etc/resolv.conf
echo "MirrorList"
reflector --country Brazil --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
echo "Particionamento"
#### Particionamento
particionar_discos
formata_particoes
monta_particoes
#### Configuracao e Instalcao
conf_repositorio
inst_base
# Setting hostname
echo "# Setting Hostname..."
arch_chroot "echo $HNAME > /etc/hostname"
# Host
echo "HostFile"
arch_chroot "echo -e '127.0.0.1    localhost.localdomain    localhost\n::1    localhost.localdomain    localhost\n127.0.1.1    $HNAME.localdomain    $HNAME' >> /etc/hosts"
#setting locale pt_BR.UTF-8 UTF-8
echo "# Generating Locale..."
arch_chroot "echo ${LOCALE} UTF-8 > /etc/locale.gen"
arch_chroot 'echo -e LANG="${LOCALE}\nLC_MESSAGES="${LOCALE}"> /etc/locale.conf'
arch_chroot "locale-gen"
arch_chroot "export LANG=${LOCALE}"
#setting keymap
arch_chroot "echo -e KEYMAP=$KEYBOARD_LAYOUT\nFONT=lat0–16\nFONT_MAP= > /etc/vconsole.conf"
# Setting timezone
echo "# Setting Timezone..."
arch_chroot "rm /etc/localtime"
arch_chroot "ln -s /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime"
# Setting hw CLOCK
echo "# Setting System Clock..."
arch_chroot "hwclock --systohc --$CLOCK"
# root password
arch_chroot "echo -e $ROOT_PASSWD'\n'$ROOT_PASSWD | passwd"
# Adding user
echo "# Making new user..."
arch_chroot "useradd -m -g users -G power,storage,wheel -s /bin/bash `echo $USER`"
arch_chroot "echo -e $USER_PASSWD'\n'$USER_PASSWD | passwd `echo $USER`"
arch_chroot "echo %wheel ALL=(ALL) ALL >> /etc/sudoers"
echo "# Installing Bootloader..."
boot_load
arch_chroot "Systemctl enable NetworkManager"
# Configura ambiente ramdisk inicial
arch_chroot "mkinitcpio -p linux"
# #cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
# arch_chroot "pacman -S --noconfirm xf86-video-intel xorg xorg-server xorg-server-xwayland"
# arch_chroot "pacman -S --noconfirm gnome gnome-tweaks gdm"
# arch_chroot "pacman -R --noconfirm gnome-terminal"
# arch_chroot "pacman -S --noconfirm eog chromium tilix git docker docker-compose nodejs npm"
# arch_chroot "systemctl enable docker"
# arch_chroot "sudo usermod -aG docker `echo $USER`"
umount -a
