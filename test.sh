#!/usr/bin/env bash

ARCH=$(uname -m)
DOCKER_BINARY=/usr/bin/docker
DOCKER_REPO=homeassistant
DOCKER_SERVICE=docker.service
URL_VERSION="https://version.home-assistant.io/stable.json"
URL_HA="https://raw.githubusercontent.com/home-assistant/supervised-installer/files/ha"
URL_BIN_HASSIO="https://raw.githubusercontent.com/home-assistant/supervised-installer/files/hassio-supervisor"
URL_BIN_APPARMOR="https://raw.githubusercontent.com/home-assistant/supervised-installer/files/hassio-apparmor"
URL_SERVICE_HASSIO="https://raw.githubusercontent.com/home-assistant/supervised-installer/files/hassio-supervisor.service"
URL_SERVICE_APPARMOR="https://raw.githubusercontent.com/home-assistant/supervised-installer/files/hassio-apparmor.service"
URL_APPARMOR_PROFILE="https://version.home-assistant.io/apparmor.txt"


# Check if Modem Manager is enabled
if systemctl list-unit-files ModemManager.service | grep enabled; then
    warn "ModemManager service is enabled. This might cause issue when using serial devices."
fi

# Detect if running on snapped docker
if snap list docker >/dev/null 2>&1; then
    DOCKER_BINARY=/snap/bin/docker
    DATA_SHARE=/root/snap/docker/common/hassio
    CONFIG=$DATA_SHARE/hassio.json
    DOCKER_SERVICE="snap.docker.dockerd.service"
fi

# Parse command line parameters
while [[ $# -gt 0 ]]; do
    arg="$1"

    case $arg in
        -m|--machine)
            MACHINE=$2
            shift
            ;;
        -d|--data-share)
            DATA_SHARE=$2
            shift
            ;;
        -p|--prefix)
            PREFIX=$2
            shift
            ;;
        -s|--sysconfdir)
            SYSCONFDIR=$2
            shift
            ;;
        *)
            error "Unrecognized option $1"
            ;;
    esac
    shift
done

PREFIX=${PREFIX:-/usr}
SYSCONFDIR=${SYSCONFDIR:-/etc}
DATA_SHARE=${DATA_SHARE:-/home/pi/smarthome/hassio}
CONFIG=$SYSCONFDIR/hassio.json

### Main

# Init folders
if [ ! -d "$DATA_SHARE" ]; then
    mkdir -p "$DATA_SHARE"
fi

# Read infos from web
HASSIO_VERSION=$(curl -s $URL_VERSION | jq -e -r '.supervisor')

##
# Write configuration
cat > "$CONFIG" <<- EOF
{
    "supervisor": "${HASSIO_DOCKER}",
    "homeassistant": "${HOMEASSISTANT_DOCKER}",
    "data": "${DATA_SHARE}"
}
EOF

##
# Pull supervisor image
echo "[Info] Install supervisor Docker container"
docker pull "$HASSIO_DOCKER:$HASSIO_VERSION" > /dev/null
docker tag "$HASSIO_DOCKER:$HASSIO_VERSION" "$HASSIO_DOCKER:latest" > /dev/null

##
# Install Hass.io Supervisor
echo "[Info] Install supervisor startup scripts"
curl -sL ${URL_BIN_HASSIO} > "${PREFIX}/sbin/hassio-supervisor"
curl -sL ${URL_SERVICE_HASSIO} > "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}"/sbin/hassio-supervisor
sed -i -e "s,%%DOCKER_BINARY%%,${DOCKER_BINARY},g" \
       -e "s,%%DOCKER_SERVICE%%,${DOCKER_SERVICE},g" \
       -e "s,%%HASSIO_BINARY%%,${PREFIX}/sbin/hassio-supervisor,g" \
       "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

chmod a+x "${PREFIX}/sbin/hassio-supervisor"
systemctl enable hassio-supervisor.service

#
# Install Hass.io AppArmor
if command -v apparmor_parser > /dev/null 2>&1; then
    echo "[Info] Install AppArmor scripts"
    mkdir -p "${DATA_SHARE}/apparmor"
    curl -sL ${URL_BIN_APPARMOR} > "${PREFIX}/sbin/hassio-apparmor"
    curl -sL ${URL_SERVICE_APPARMOR} > "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"
    curl -sL ${URL_APPARMOR_PROFILE} > "${DATA_SHARE}/apparmor/hassio-supervisor"

    sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}/sbin/hassio-apparmor"
    sed -i -e "s,%%DOCKER_SERVICE%%,${DOCKER_SERVICE},g" \
	   -e "s,%%HASSIO_APPARMOR_BINARY%%,${PREFIX}/sbin/hassio-apparmor,g" \
	   "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"

    chmod a+x "${PREFIX}/sbin/hassio-apparmor"
    systemctl enable hassio-apparmor.service
    systemctl start hassio-apparmor.service
fi

##
# Init system
echo "[Info] Run Hass.io"
systemctl start hassio-supervisor.service

##
# Setup CLI
echo "[Info] Install cli 'ha'"
curl -sL ${URL_HA} > "${PREFIX}/bin/ha"
chmod a+x "${PREFIX}/bin/ha"
