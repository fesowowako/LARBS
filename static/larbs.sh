#!/bin/sh

# Luke's Auto Rice Bootstrapping Script (LARBS)
# by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

dotfilesrepo="https://github.com/fesowowako/dotfiles.git"
progsfile="https://raw.githubusercontent.com/fesowowako/LARBS/master/static/progs.csv"
aurhelper="paru"
repobranch="master"
export TERM=ansi

### FUNCTIONS ###

installpkg() {
  pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

error() {
  # Log to stderr and exit with failure
  printf "%s\n" "$1" >&2
  exit 1
}

welcomemsg() {
  whiptail --title "Welcome!" \
    --msgbox "Welcome to Luke's Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Linux desktop, which I use as my main machine.\\n\\n-Luke" 10 60

  whiptail --title "Important Note!" --yes-button "All ready!" \
    --no-button "Return..." \
    --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

getuserandpass() {
  # Prompts user for new username and password
  name=$(whiptail --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
  while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
    name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
  done
  pass1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
  pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
  while ! [ "$pass1" = "$pass2" ]; do
    unset pass2
    pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
  done
}

usercheck() {
  ! { id -u "$name" >/dev/null 2>&1; } ||
    whiptail --title "WARNING" --yes-button "CONTINUE" \
      --no-button "No wait..." \
      --yesno "The user \`$name\` already exists on this system. LARBS can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\nLARBS will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that LARBS will change $name's password to the one you just gave." 14 70
}

preinstallmsg() {
  whiptail --title "Let's get this party started!" --yes-button "Let's go!" \
    --no-button "No, nevermind!" \
    --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || {
    clear
    exit 1
  }
}

adduserandpass() {
  # Adds user `$name` with password $pass1
  whiptail --infobox "Adding user \"$name\"..." 7 50
  useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
  export repodir="/home/$name/.local/src"
  mkdir -p "$repodir"
  chown -R "$name":wheel "$(dirname "$repodir")"
  echo "$name:$pass1" | chpasswd
  unset pass1 pass2
}

refreshkeys() {
  case "$(readlink -f /sbin/init)" in
  *systemd*)
    whiptail --infobox "Refreshing Arch Keyring..." 7 40
    pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
    ;;
  *)
    whiptail --infobox "Enabling Arch Repositories for more a more extensive software collection..." 7 40
    pacman --noconfirm --needed -S \
      artix-keyring artix-archlinux-support >/dev/null 2>&1
    grep -q "^\[extra\]" /etc/pacman.conf ||
      echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
    pacman -Sy --noconfirm >/dev/null 2>&1
    pacman-key --populate archlinux >/dev/null 2>&1
    ;;
  esac
}

chaoticaur() {
  whiptail --title "Chaotic AUR Installation" --infobox "Adding the Chaotic AUR repository to your system..." 8 60
  # Import Chaotic AUR key
  pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com >/dev/null 2>&1
  pacman-key --lsign-key 3056513887B78AEB >/dev/null 2>&1
  # Install Chaotic AUR keyring and mirrorlist packages
  yes | pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' >/dev/null 2>&1
  yes | pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' >/dev/null 2>&1
  # Add Chaotic AUR repository to pacman configuration if not already present
  grep -qxF "[chaotic-aur]" /etc/pacman.conf ||
    {
      echo "[chaotic-aur]"
      echo "Include = /etc/pacman.d/chaotic-mirrorlist"
    } >>/etc/pacman.conf
  # Update package database and install the AUR helper
  whiptail --title "Installing AUR Helper from Chaotic AUR" --infobox "Installing $aurhelper binary from Chaotic AUR..." 8 60
  pacman -Sy --noconfirm --needed $aurhelper >/dev/null 2>&1
}

maininstall() {
  # Installs all needed programs from main repo
  whiptail --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 9 70
  installpkg "$1"
}

gitmakeinstall() {
  progname="${1##*/}"
  progname="${progname%.git}"
  dir="$repodir/$progname"
  whiptail --title "LARBS Installation" \
    --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
  sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
    --no-tags -q "$1" "$dir" ||
    {
      cd "$dir" || return 1
      sudo -u "$name" git pull --force origin master
    }
  cd "$dir" || exit 1
  make >/dev/null 2>&1
  make install >/dev/null 2>&1
  cd /tmp || return 1
}

aurinstall() {
  whiptail --title "LARBS Installation" \
    --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 9 70
  echo "$aurinstalled" | grep -q "^$1$" && return 1
  sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
  whiptail --title "LARBS Installation" \
    --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 9 70
  [ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
  yes | pip install "$1"
}

installationloop() {
  ([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
    curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
  total=$(wc -l </tmp/progs.csv)
  aurinstalled=$(pacman -Qqm)
  while IFS=, read -r tag program comment; do
    n=$((n + 1))
    echo "$comment" | grep -q "^\".*\"$" &&
      comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
    case "$tag" in
    "A") aurinstall "$program" "$comment" ;;
    "G") gitmakeinstall "$program" "$comment" ;;
    "P") pipinstall "$program" "$comment" ;;
    *) maininstall "$program" "$comment" ;;
    esac
  done </tmp/progs.csv
}

putgitrepo() {
  # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
  whiptail --infobox "Downloading and installing config files..." 7 60
  [ -z "$3" ] && branch="master" || branch="$repobranch"
  dir=$(mktemp -d)
  [ ! -d "$2" ] && mkdir -p "$2"
  chown "$name":wheel "$dir" "$2"
  sudo -u "$name" git -C "$repodir" clone --depth 1 \
    --single-branch --no-tags -q --recursive -b "$branch" \
    --recurse-submodules "$1" "$dir"
  sudo -u "$name" cp -rfT "$dir" "$2"
}

finalize() {
  whiptail --title "All done!" \
    --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t Luke" 13 80
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order

# Check if user is root on Arch distro. Install whiptail
pacman --noconfirm --needed -Sy libnewt ||
  error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user and pick dotfiles
welcomemsg || error "User exited."

# Get and verify username and password
getuserandpass || error "User exited."

# Give warning if user already exists
usercheck || error "User exited."

# Last chance for user to back out before install
preinstallmsg || error "User exited."

### The rest of the script requires no user input

# Refresh Arch keyrings
refreshkeys ||
  error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates ccache base-devel git ntp zsh dash; do
  whiptail --title "LARBS Installation" \
    --infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
  installpkg "$x"
done

# Add Chaotic AUR repository to the system
chaoticaur || error "Error installing Chaotic AUR."

whiptail --title "LARBS Installation" \
  --infobox "Synchronizing system time to ensure successful and secure installation of software..." 8 70
ntpd -q -g >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR
trap 'rm -f /etc/sudoers.d/larbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel,root runcwd=*" >/etc/sudoers.d/larbs-temp

# Enable parallel downloads, uncomment VerbosePkgLists and Color, and add ILoveCandy for pacman
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;s/^#(VerbosePkgLists)$/\1/;/^#Color$/s/#//" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/^VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Add custom build settings
echo 'CFLAGS="-march=native -O2 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,-z,pack-relative-relocs,-fuse-ld=mold"
RUSTFLAGS="-C force-frame-pointers=yes -C opt-level=3 -C target-cpu=native -C link-arg=-fuse-ld=mold"
MAKEFLAGS="-j$(nproc)"
BUILDENV=(!distcc color ccache check !sign)
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)
COMPRESSGZ=(pigz -c -f -n)
COMPRESSBZ2=(pbzip2 -c -f)
COMPRESSZST=(zstd -c -T0 --auto-threads=logical -)' | tee /etc/makepkg.conf.d/makepkgd.conf >/dev/null

# Make sure .*-git AUR packages get updated automatically
$aurhelper -Y --save --devel

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed
installationloop

# Install the dotfiles in the user's home directory, but remove .git dir and
# other unnecessary files
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md"

# Most important command! Get rid of the beep!
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Make zsh the default shell for the user
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Make dash the default #!/bin/sh symlink.
ln -sfT /bin/dash /bin/sh >/dev/null 2>&1

# dbus UUID must be generated for Artix runit
dbus-uuidgen >/var/lib/dbus/machine-id

# Use system notifications for Brave on Artix
# Only do it when systemd is not present
[ "$(readlink -f /sbin/init)" != "/usr/lib/systemd/systemd" ] && echo "export \$(dbus-launch)" >/etc/profile.d/dbus.sh

# Enable tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

# Allow wheel users to sudo with password and allow several system commands
# (like `shutdown` to run without password)
echo '%wheel ALL=(ALL:ALL) ALL
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --
Defaults editor=/usr/bin/nvim' | tee /etc/sudoers.d/sudoersd >/dev/null
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" >/etc/sysctl.d/dmesg.conf

# Cleanup
rm -f /etc/sudoers.d/larbs-temp

# Last message! Install complete!
finalize
