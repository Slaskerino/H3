#!/bin/bash

# Definer forskellige download links som henter indhold til hjemmesiden fra offenligt tilgængeligt indhold

# Tjekker om scriptet bliver kørt som root.
if [[ $EUID -ne 0 ]]; then
  echo "Fejl: Dette script skal køres med sudo eller som root." >&2
  exit 1
fi

IMAGE_URL="https://i.kym-cdn.com/entries/icons/original/000/035/396/borat.jpg"
VIDEO_URL="https://ia801303.us.archive.org/7/items/rick-astley-never-gonna-give-you-up-assets/rick-roll.gif"

FTP_FILE_URLS=(
    "https://fm.dk/media/xraiv33r/finansloven-for-2024.pdf"
    "https://fm.dk/media/mmbgxwah/fl23a.pdf"
)
FTP_USER="ftpuser"
FTP_PASS="Password1"

# -----------------------------
# Updater & installer nødvendige pakker
# -----------------------------
echo "[+] Opdaterer systemet og installerer pakker..."
apt update && apt upgrade -y
apt install apache2 vsftpd wget unzip -y

# -----------------------------
# Konfigurer Apache Web Server
# -----------------------------
echo "[+] Konfigurerer Apache web server..."

WEB_ROOT="/var/www/html"
MEDIA_DIR="$WEB_ROOT/media"

# Opretter mappe til medie filer
mkdir -p "$MEDIA_DIR"

# Fjerner index.html som Apache selv opretter ved installation
rm -f "$WEB_ROOT/index.html"

# Downloader billede og video med et get request
echo "[+] Downloader medie filer..."
wget -O "$MEDIA_DIR/background.jpg" "$IMAGE_URL"
wget -O "$MEDIA_DIR/video.gif" "$VIDEO_URL"

# Opretter ny index.html samt skriver indhold til filen.
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

# -----------------------------
# Konfigurerer vsftpd til at tillade uploads fra brugeren "ftpuser"
# -----------------------------
echo "[+] Konfigurerer FTP server..."

# Laver backup af konfigurations filen
cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

# Skriver ny konfigurations fil. 
bash -c 'cat <<EOF > /etc/vsftpd.conf
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
local_root=/var/ftpuser
EOF'

# Genstart FTP service
systemctl restart vsftpd

# -----------------------------
# Opret vores FTP bruger
# -----------------------------
echo "[+] Opretter FTP bruger..."


# Brugeren får roden af web mappen som hjemmemappe, vi opretter ikke nogen ny mappe til brugeren og 
# vælger --disabled-password for at kunne oprette et password uden output til stout
adduser --home /var/ftpuser --no-create-home --disabled-password --gecos "" "$FTP_USER"

# opretter et password til ftp brugeren
echo "$FTP_USER:$FTP_PASS" | chpasswd

# Definer ejerskab samt rettigheder
# Dette er MEGET åbne rettigheder og skal ikke lukkes ud til resten af verdenen. 
# I den rigtige verden ville man nok løse dette ved at benytte en gruppe til at give adgang, men her går vi med denne løsning.
echo "[+] Definerer ejerskab samt rettigheder til ftp adgang..."
chown -R "$FTP_USER:$FTP_USER" /var/ftpuser
chmod -R 777 /var/ftpuser

# -----------------------------
# Nægt adgang for FTP brugeren at kunne logge på med ssh 
# -----------------------------
echo "[+] Fjerner SSH adgang for FTP bruger..."
echo "DenyUsers $FTP_USER" | tee -a /etc/ssh/sshd_config
systemctl restart sshd

# -----------------------------
# Konfigurerer iptables til at kunne acceptere http, https og FTP trafik
# -----------------------------

echo "[+] Konfigurerer iptables..."

apt install iptables-persistent

# Tillad HTTP og HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Tillad FTP
iptables -A INPUT -p tcp --dport 20 -j ACCEPT
iptables -A INPUT -p tcp --dport 21 -j ACCEPT

# Tillad passive FTP porte
iptables -A INPUT -p tcp --dport 10000:10100 -j ACCEPT

# Tillad etablerede og realateret trafik til FTP
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Tillad intern kommunikation gennem localhost
iptables -A INPUT -i lo -j ACCEPT

# Gemmer nye iptables regler til at være persistent gennem reboots.
iptables-save | tee /etc/iptables/rules.v4 > /dev/null


# finder IP addresser på alle interfaces på hosten
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

IPS=()

for IFACE in $INTERFACES; do
    IP=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -n "$IP" ]]; then
        IPS+=(" $IP")
    fi
done

# Samler streng med addresser til en komma sepereret linje med IFS
IP_STRING=$(IFS=, ; echo "${IPS[*]}")

# -----------------------------
# Færdig
# -----------------------------
echo "Konfiguration af web server samt FTP adgang er færdig!"
echo "Din fede nye hjemmeside/web server kan ses via:$IP_STRING"
echo "FTP login:"
echo "  Username: $FTP_USER"
echo "  Password: $FTP_PASS"