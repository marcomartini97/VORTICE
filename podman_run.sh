#!/bin/bash
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
podman run --rm -it \
  --name vortice \
  -p 3389:3389 \
  -e VORTICE_BIND_ADDRESS=0.0.0.0 \
  -e VORTICE_PORT=3389 \
  -e VORTICE_REDIRECTOR_CONFIG=/etc/vdi/vdi_broker.yaml \
  -e VORTICE_CERTIFICATE=/etc/vdi/cert.pem \
  -e VORTICE_PRIVATE_KEY=/etc/vdi/key.pem \
  -v /run/podman/podman.sock:/run/podman/podman.sock \
  -v /home:/home \
  -v /etc/shadow:/etc/shadow \
  -v /etc/group:/etc/group \
  -v /etc/passwd:/etc/passwd \
  -v $SCRIPTPATH/config/pam.d/vdi-broker:/etc/pam.d/vdi-broker:ro \
  -v $SCRIPTPATH/config/vdi_broker.yaml:/etc/vdi/vdi_broker.yaml \
  -v $SCRIPTPATH/logs:/var/log/vdi-broker \
  -v $SCRIPTPATH/VORTICE-vdi:/etc/vdi/VORTICE-vdi \
  vortice