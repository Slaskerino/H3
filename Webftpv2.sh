#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "Fejl: Dette script skal køres med sudo eller som root." >&2
  exit 1
fi

# -----------------------------
# VARIABLES
# -----------------------------
DISK="/dev/sdb"
PARTITION="/dev/sdb1"
DATA_ROOT="/data"
WEB_ROOT="$DATA_ROOT/www/html"
MEDIA_DIR="$WEB_ROOT/media"
FTP_ROOT="$DATA_ROOT/ftpuser"

IMAGE_URL="https://i.kym-cdn.com/entries/icons/original/000/035/396/borat.jpg"
VIDEO_URL="https://ia801303.us.archive.org/7/items/rick-astley-never-gonna-give-you-up-assets/rick-roll.gif"

FTP_USER="ftpuser"
FTP_PASS="Password1"

# -----------------------------
# PREPARE DISK
# -----------------------------
echo "[+] Klargør disk..."

# Create partition if it doesn't exist
if ! lsblk | grep -q "sdb1"; then
  echo "[+] Opretter partition..."
  parted -s $DISK mklabel gpt
  parted -s $DISK mkpart primary ext4 0% 100%
fi

# Format partition
mkfs.ext4 -F $PARTITION

# Mount
mkdir -p $DATA_ROOT
mount $PARTITION $DATA_ROOT

# Persist mount
UUID=$(blkid -s UUID -o value $PARTITION)
grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $DATA_ROOT ext4 defaults 0 2" >> /etc/fstab

# Verify mount
if ! mount | grep -q "$DATA_ROOT"; then
  echo "❌ Disk blev ikke mounted korrekt!"
  exit 1
fi

# -----------------------------
# INSTALL PACKAGES
# -----------------------------
echo "[+] Installerer pakker..."
apt update && apt upgrade -y
apt install apache2 vsftpd wget unzip iptables-persistent -y

# -----------------------------
# APACHE SETUP
# -----------------------------
echo "[+] Konfigurerer Apache..."

mkdir -p "$MEDIA_DIR"

# Update ONLY DocumentRoot safely
sed -i "s|DocumentRoot /var/www/html|DocumentRoot $WEB_ROOT|g" /etc/apache2/sites-available/000-default.conf

# Ensure directory permissions config exists
cat <<EOF > /etc/apache2/conf-available/data-root.conf
<Directory $DATA_ROOT>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

a2enconf data-root

systemctl reload apache2

# Remove default index if exists
rm -f "$WEB_ROOT/index.html"

# Download media
echo "[+] Downloader medie filer..."
wget -O "$MEDIA_DIR/background.jpg" "$IMAGE_URL"
wget -O "$MEDIA_DIR/video.gif" "$VIDEO_URL"

# Create index.html
echo "[+] Opretter index.html..."
echo "[+] Opretter index.html..."
cat <<EOF | tee "$WEB_ROOT/index.html" > /dev/null
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>En fe hjemmeside</title>
  <style>
    body, html {
      height: 100%;
      margin: 0;
      overflow: hidden;
      font-family: Arial, sans-serif;
    }
    /* Baggrundsbillede (fylder hele skærmen) */
    img#bgImage {
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      object-fit: cover;
      z-index: -2;
    }

    /* GIF overlay */
    img#gifOverlay {
      position: fixed;
      bottom: 50px;
      right: 50px;
      width: 300px; 
      height: auto;
      z-index: 1;
    }

    /* Tekst indhold */
    .content {
      position: relative;
      z-index: 2;
      height: 100%;
      display: flex;
      justify-content: center;
      align-items: center;
      text-align: center;
    }

    .text-box {
      background-color: rgba(0, 0, 0, 0.6);  /* Semi-transparent sort */
      color: white;
      padding: 30px 40px;
      border-radius: 12px;
      box-shadow: 0 0 20px rgba(0, 0, 0, 0.5);
      max-width: 80%;
    }

  </style>
</head>
<body>
  <!-- Baggrundsbillede -->
  <img src="media/background.jpg" id="bgImage" alt="Background Image">

  <!-- GIF Overlay -->
  <img src="media/video.gif" id="gifOverlay" alt="GIF Animation">


  <!-- Text Content -->
  <div class="content">
    <div class="text-box">
      <h1>Velkommen til Denne ret seje hjemmeside</h1>
      <p>Borat synes du er lækker og Rick er så glad for at se dig, at han ikke kan stoppe med at danse!</p>
      <p>Borat er også glad for at se dig<P>
      <P>Rigtig glad ( ͡° ͜ʖ ͡° )<p>
    </div>
  </div>

</body>
</html>

EOF

# Fix permissions for Apache
chown -R www-data:www-data $DATA_ROOT
chmod -R 755 $DATA_ROOT

systemctl restart apache2

# -----------------------------
# FTP CONFIG
# -----------------------------
echo "[+] Konfigurerer FTP..."

cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

bash -c "cat <<EOF > /etc/vsftpd.conf
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100
user_sub_token=\$USER
local_root=$FTP_ROOT
EOF"

systemctl restart vsftpd

# -----------------------------
# FTP USER
# -----------------------------
echo "[+] Opretter FTP bruger..."

mkdir -p $FTP_ROOT

adduser --home $FTP_ROOT --no-create-home --disabled-password --gecos "" "$FTP_USER"
echo "$FTP_USER:$FTP_PASS" | chpasswd

chown -R "$FTP_USER:$FTP_USER" $FTP_ROOT
chmod -R 777 $FTP_ROOT

# -----------------------------
# DISABLE SSH
# -----------------------------
echo "DenyUsers $FTP_USER" >> /etc/ssh/sshd_config
systemctl restart sshd

# -----------------------------
# FIREWALL
# -----------------------------
echo "[+] Konfigurerer firewall..."

iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 20 -j ACCEPT
iptables -A INPUT -p tcp --dport 21 -j ACCEPT
iptables -A INPUT -p tcp --dport 10000:10100 -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

iptables-save > /etc/iptables/rules.v4

# -----------------------------
# OUTPUT
# -----------------------------
IP=$(hostname -I | awk '{print $1}')

echo "-----------------------------------"
echo "Færdig!"
echo "Web: http://$IP"
echo "FTP user: $FTP_USER"
echo "FTP pass: $FTP_PASS"
echo "Data ligger på: $DATA_ROOT (sdb)"