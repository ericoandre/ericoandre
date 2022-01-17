#!/bin/bash
# encoding: utf-8

######## Variaveis
LANGUAGE=pt_BR.UTF-8
KEYBOARD_LAYOUT=br-abnt2

HD=/dev/sda

SWAP_SIZE=1024
BOOT_SIZE=512
ROOT_SIZE=0

EXTRA_PKGS="virtualbox-guest-utils exfat-utils iw net-tools neofetch"

######## Variáveis auxiliares. NÃO DEVEM SER ALTERADAS
BOOT_START=1
BOOT_END=$(($BOOT_START+$BOOT_SIZE))

ROOT_START=$BOOT_END
if [[ $ROOT_SIZE -eq 0 ]]; then
  ROOT_END=-0
else
  ROOT_END=$(($ROOT_START+$ROOT_SIZE))
fi

######## functions
arch_chroot() {
  arch-chroot /mnt /bin/bash -c "${1}"
}

Parted() {
  parted --script $HD "${1}"
}

particionar_discos(){
  if [[ -d "/sys/firmware/efi/" ]]; then
    # Configura o tipo da tabela de partições
    Parted "mklabel gpt"
    Parted "mkpart primary fat32 $BOOT_START $BOOT_END"
    Parted "set 1 esp on"
  else
    # Configura o tipo da tabela de partições
    Parted "mklabel msdos"
    Parted "mkpart primary ext2 $BOOT_START $BOOT_END"
    Parted "set 1 bios_grub on"
  fi

  Parted "mkpart primary $ROOT_FS $ROOT_START $ROOT_END"
}

monta_particoes(){
  # Formatando partição root
  mkfs.ext4 /dev/sda2 -L Root
  mount /dev/sda2 /mnt

  if [[ -d "/sys/firmware/efi/" ]]; then
    # Monta partição esp
    mkfs.vfat -F32 -n BOOT /dev/sda1
    mkdir -p /mnt/boot/efi && mount /dev/sda1 /mnt/boot/efi
  else
    # Monta partição boot
    mkfs.ext2 /dev/sda1
    mkdir -p /mnt/boot && mount /dev/sda1 /mnt/boot
  fi

  touch /mnt/swapfile
  dd if=/dev/zero of=/mnt/swapfile bs=1M count=$SWAP_SIZE
  chmod 600 /mnt/swapfile
  mkswap /mnt/swapfile
  swapon /mnt/swapfile
}

conf_repositorio(){
  reflector --verbose --protocol http --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
  # sed -i 's/^#Color/Color\nILoveCandy' /etc/pacman.conf
  if [ "$(uname -m)" = "x86_64" ]; then
    sed -i '/multilib\]/,+1 s/^#//' /etc/pacman.conf
  fi
  pacman -Sy
}

inst_base(){
  KERNEL=$(dialog  --clear --radiolist "Selecione o Kernel" 15 30 4 "linux" "" ON "linux-lts" "" OFF "linux-hardened" "" OFF "linux-zen" "" OFF --stdout)
  # pacstrap /mnt base bash nano vim-minimal vi linux-firmware cryptsetup e2fsprogs findutils gawk inetutils iproute2 jfsutils licenses linux-firmware logrotate lvm2 man-db man-pages mdadm pciutils procps-ng reiserfsprogs sysfsutils xfsprogs usbutils `echo $kernel`
  pacstrap /mnt base base-devel $KERNEL $KERNEL-headers $KERNEL-firmware bash-completion ntfs-3g os-prober grub dhcpcd networkmanager tar rsync nano acpi acpid dbus ufw alsa-plugins alsa-utils alsa-firmware `echo $EXTRA_PKGS`
  genfstab -U -p /mnt >> /mnt/etc/fstab
  echo "/swapfile             none    swap    defaults        0       0" >> /mnt/etc/fstab
  arch_chroot "systemctl enable NetworkManager && mkinitcpio -p $KERNEL"
}

inst_boot_load(){
  proc=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')
  if [ "$proc" = "GenuineIntel" ]; then
    pacstrap /mnt intel-ucode
  elif [ "$proc" = "AuthenticAMD" ]; then
    pacstrap /mnt amd-ucode
  fi

  if [[ -d "/sys/firmware/efi/" ]]; then
    arch_chroot "pacman -S --noconfirm efibootmgr dosfstools mtools"
    arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub_uefi --recheck"
    mkdir /mnt/boot/efi/EFI/boot && mkdir /mnt/boot/grub/locale
    cp /mnt/boot/efi/EFI/grub_uefi/grubx64.efi /mnt/boot/efi/EFI/boot/bootx64.efi
  else
    arch_chroot "grub-install --target=i386-pc --recheck $HD"
  fi
  cp /mnt/usr/share/locale/en@quot/LC_MESSAGES/grub.mo /mnt/boot/grub/locale/en.mo
  arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
}

inst_intefacegrafica(){
dialog --title "INTEFACE GRAFICA" --clear --yesno "Deseja Instalar Windows Manager ?" 10 30
if [[ $? -eq 0 ]]; then
  arch_chroot "pacman -S --noconfirm xf86-video-intel vulkan-intel lib32-vulkan-intel xf86-input-synaptics xorg xorg-xinit xorg-server xorg-twm xorg-xclock xorg-xinit xterm ttf-liberation xorg-fonts-100dpi xorg-fonts-75dpi ttf-dejavu"
  DM=$(dialog  --clear --menu "Selecione o Kernel" 15 30 4  1 "gnome" 2 "cinnamon" 3 "plasma" 4 "mate" 5 "Xfce" 6 "deepin" 7 "i3" --stdout)
  if [[ $DM -eq 1 ]]; then
    #arch_chroot "pacman -S --noconfirm gnome gnome-tweaks file-roller gdm"
    arch_chroot "pacman -S --noconfirm gdm gnome-shell gnome-backgrounds gnome-control-center gnome-screenshot gnome-system-monitor gnome-terminal gnome-tweak-tool nautilus gedit gnome-calculator gnome-disk-utility eog evince"
    arch_chroot "systemctl enable gdm.service"
  elif [[ $DM -eq 2 ]]; then
    arch_chroot "pacman -S --noconfirm cinnamon sakura gnome-disk-utility nemo-fileroller gdm"
    arch_chroot "systemctl enable gdm.service"
  elif [[ $DM -eq 3 ]]; then
    arch_chroot "pacman -S --noconfirm plasma file-roller sddm"
    arch_chroot "echo -e '[Theme]\nCurrent=breeze' >> /usr/lib/sddm/sddm.conf.d/default.conf"
    arch_chroot "systemctl enable sddm.service"
  elif [[ $DM -eq 4 ]]; then
    arch_chroot "pacman -S --noconfirm mate mate-extra gnome-disk-utility lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings"
    arch_chroot "systemctl enable lightdm.service"
  elif [[ $DM -eq 5 ]]; then
    arch_chroot "pacman -S --noconfirm xfce4 xfce4-goodies file-roller network-manager-applet lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings"
    arch_chroot "systemctl enable lightdm.service"
  elif [[ $DM -eq 6 ]]; then
    arch_chroot "pacman -S --noconfirm deepin deepin-extra ark gnome-disk-utility lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings"
    arch_chroot "systemctl enable lightdm.service"
  elif [[ $DM -eq 7 ]]; then
    arch_chroot "pacmanpacman -S --noconfirm --needed --asdeps lightdm lightdm-gtk-greeter i3 feh gnome-disk-utility lightdm-gtk-greeter-settings"
    arch_chroot "systemctl enable lightdm.service"
  fi
  arch_chroot "pacman -S --noconfirm mesa mesa-libgl lib32-mesa lib32-mesa-libgl vlc papirus-icon-theme faenza-icon-theme jre8-openjdk jre8-openjdk-headless tilix eog xdg-user-dirs-gtk firefox xpdf mousepad"
fi
}

######## Script

pacman -Syy && pacman -S --noconfirm reflector dialog

loadkeys br-abnt2
timedatectl set-ntp true

HNAME=$(dialog  --clear --inputbox "Digite o nome do Computador" 10 25 --stdout)

ZONE=$(dialog  --clear --menu "Select Sua country/zone." 20 35 15 $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud | sort | awk '{ printf "\0"$0"\0"  " . " }') --stdout)
SUBZONE=$(dialog  --clear --menu "Select Sua country/zone." 20 35 15 $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "$ZONE/" | sed "s/$ZONE\///g" | sort -ud | sort | awk '{ printf "\0"$0"\0"  " . " }') --stdout)

LANGUAGE=$(dialog  --clear --radiolist "Escolha idioma do sistema:" 15 30 4 $(cat /etc/locale.gen | grep -v "#  " | sed 's/#//g' | sed 's/ UTF-8//g' | grep .UTF-8 | sort | awk '{ print $0 "\"\"  OFF " }') --stdout)
CLOCK=$(dialog  --clear --radiolist "Configurcao do relojo" 10 30 4 "utc" "" ON "localtime" "" OFF --stdout)

ROOT_PASSWD=$(dialog --clear --inputbox "Digite a senha de root" 10 25 --stdout)

USER=$(dialog  --clear --inputbox "Digite o nome do novo Usuario" 10 25 --stdout)
USER_PASSWD=$(dialog --clear --inputbox "Digite a senha  de $USER" 10 25 --stdout)

#### Particionamento
particionar_discos
monta_particoes

#### Configuracao e Instalcao
conf_repositorio
inst_base
inst_boot_load

#### Configuracao 
arch_chroot "loadkeys br-abnt2"
arch_chroot "timedatectl set-ntp true"
arch_chroot "sed -i 's/^#Color/Color\nILoveCandy' /etc/pacman.conf && sed -i '/multilib\]/,+1 s/^#//' /etc/pacman.conf"
arch_chroot "pacman -Sy"


echo "setting hostname"
arch_chroot "echo $HNAME > /etc/hostname"
arch_chroot "echo -e '127.0.0.1    localhost.localdomain    localhost\n::1        localhost.localdomain    localhost\n127.0.1.1    $HNAME.localdomain    $HNAME' >> /etc/hosts"

echo "setting locale pt_BR.UTF-8 UTF-8"
arch_chroot "sed -i 's/^#'$LANGUAGE'/'$LANGUAGE/ /etc/locale.gen"
arch_chroot "echo -e LANG=$LANGUAGE\nLC_MESSAGES=$LANGUAGE > /etc/locale.conf"
arch_chroot "locale-gen"
arch_chroot "export LANG=$LANGUAGE"

echo "Vconsole"
arch_chroot "echo -e KEYMAP=$KEYBOARD_LAYOUT\nFONT=lat0-16\nFONT_MAP= > /etc/vconsole.conf"

echo "Setting timezone"
arch_chroot "ln -s /usr/share/zoneinfo/$ZONE/$SUBZONE /etc/localtime"

echo "Setting hw CLOCK"
arch_chroot "hwclock --systohc --$CLOCK"

echo "root password"
arch_chroot "echo -e $ROOT_PASSWD'\n'$ROOT_PASSWD | passwd"

echo "criar usuario"
arch_chroot "useradd -m -g users -G adm,lp,wheel,power,audio,video -s /bin/bash $USER"

echo "Definir senha do usuário"
arch_chroot "echo -e $USER_PASSWD'\n'$USER_PASSWD | passwd `echo $USER`"

inst_intefacegrafica

exit
umount -R /mnt
poweroff
