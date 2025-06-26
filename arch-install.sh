
#/bin/bash

loadkeys be-latin1

set -e # Arrêt du script en cas d'erreur

DISK="/dev/sda"

# Vérification si le système est bien en UEFI 64 bits
if [ "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)" != "64" ]; then
	echo "Erreur: Le système n'est pas démarré en mode UEFI 64 bits."
	exit 1
fi


# Vérification de la connexion Internet
if ! ping -c 1 archlinux.org &>/dev/null; then
	echo "Erreur: Pas d'accès Internet, vérifiez votre connexion réseau."
	exit 1
fi


# Vérification si le disque est vide, sinon le formater.
if lsblk "$DISK" -no NAME | grep -q "${DISK##*/}[0-9]"; then
	echo "Le disque contient des partitions. Suppression en cours..."
	wipefs -a "$DISK"
	sgdisk --zap-all "$DISK"
else
	echo "Le disque est vide."
fi

echo "Création de la table GPT et des partitions..."

# Création de la table GPT et des partitions EFI, SWAP et Linux filesystem
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary linux-swap 513MiB 2561MiB
parted -s "$DISK" mkpart primary ext4 2561MiB 100%

echo "Partitions du disque créées."
echo "Partition EFI: 512Mo."
echo "SWAP: 2Go."
echo "Partition /: le reste du disque."
echo "Formatage des partitions..."

# Formatage des partitions
mkfs.fat -F32 "${DISK}1"
mkswap "${DISK}2"
mkfs.ext4 "${DISK}3"

echo "Partitions formatées."

echo "Montage de la partition /..."
mount "${DISK}3" /mnt

echo "Montage de la partition /boot..."
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

swapon "${DISK}2"

echo "Installation des paquets de base..."
pacstrap -K /mnt base linux linux-firmware networkmanager nano sudo grub efibootmgr --noconfirm
echo "Paquets de base installés avec succès."

echo "Génération du fichier fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Chroot dans le nouveau système pour configuration..."

arch-chroot /mnt /bin/bash <<EOF

#Configuration locale
echo "fr_BE.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=fr_BE.UTF-8" > /etc/locale.conf
echo "KEYMAP=be-latin1" > /etc/vconsole.conf

ln -sf /usr/share/zoneinfo/Europe/Brussels /etc/localtime
hwclock --systohc

echo "archlinux" > /etc/hostname

systemctl enable NetworkManager

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

useradd -m -G wheel arch
echo "root:123" | chpasswd
echo "arch:123" | chpasswd

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

EOF

echo "Configuration chroot terminée."
echo "Démontage des disques..."
swapoff "${DISK}2"
umount -R /mnt

echo "Redémarrage sur le nouveau système..."
sleep 3

reboot

