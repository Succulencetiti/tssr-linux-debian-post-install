#!/bin/bash

# === VARIABLES ===
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"
CONFIG_DIR="./config"
PACKAGE_LIST="./lists/packages.txt"
USERNAME=$(logname)
USER_HOME="/home/$USERNAME"

# === FUNCTIONS ===
# Affichage de la date et l'heure au moment de l'execution au format AAAA-MM-JJ HH:MM:SS | tee -a ajouter la date au fichier au lieu de remplacer tout en l'affichant
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Installation des paquets
check_and_install() {
  local pkg=$1
  # Si le paquet est déjà installé, output  "is already installed."
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."
  # Sinon installation du paquet
  else
    log "Installing $pkg..."
    apt install -y "$pkg" &>>"$LOG_FILE"

    # Si le paquet est installé avec succès, output "successfully installed"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed."
    # Sinon, Failed to install
    else
      log "Failed to install $pkg."
    fi
  fi
}

ask_yes_no() {
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}

# === INITIAL SETUP ===
# création dossier ./logs et fichier $LOG_DIR/postinstall_$TIMESTAMP.log
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
log "Starting post-installation script. Logged user: $USERNAME"

# Vérification si script est lancé en root
if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  exit 1
fi

# === 1. SYSTEM UPDATE ===
# Mise à jour et actualisation du fichier .log
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE"

# === 2. PACKAGE INSTALLATION ===

# Installation des paquets sur la liste du fichier packages.txt
# Si packages.txt, out "Reading package list from" et loop pour lire chaque ligne de la liste, ignore des lignes vides et ceux avec #. vérifie si installé et install si c'est pas installé

if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi

# === 3. UPDATE MOTD ===
# Modification du Message of the day à /etc/motd. Si .txt pas trouvé, output motd.txt not found.

if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi

# === 4. CUSTOM .bashrc ===
# Application du fichier bashrc pour configuration
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi

# === 5. CUSTOM .nanorc ===
# Configuration de l'éditeur "nano"
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi

# === 6. ADD SSH PUBLIC KEY ===
# Vérificatio, saisis de la clé, creation du réportoire .ssh, ajout de la clé, permissions et enregistrement, message de confirmation

if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi

# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
# configuration serveur ssh et désactivation de l'authentification par mot de passe, vérification de l'existence du fichier sshd_config et redémarrage du service ssh

if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi

log "Post-installation script completed."

exit 0