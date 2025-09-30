VDI ORCHESTRATED RDP THROUGH INTERLEAVED CONTAINERIZED EXECUTION

# Vortice FreeRDP Proxy

`vortice` builds a Fedora based image that compiles FreeRDP with the bundled `vdi_broker.patch`, installs `podman`, and launches `freerdp-proxy /etc/vdi/config.ini`. Clone the repository with `git clone --recurse-submodules` (or run `git submodule update --init --recursive` after cloning) to pull in the `VORTICE-vdi` desktop template.

## Build the image
1. Review `config/config.ini` and `config/vdi_broker.yaml`. The broker defaults to `dockerfile_path: /etc/vdi/VORTICE-vdi/Containerfile`; initialize the `VORTICE-vdi` submodule (`git submodule update --init --recursive`) so the downstream desktop template is baked into the image build context.
2. Populate `keys/` with `cert.pem` / `key.pem` if you already have TLS material. When the directory is missing or empty, the build auto-generates a self-signed pair.
3. Build:
   - `podman build -t vortice .`
   - `docker build -t vortice .`
   - Override the FreeRDP tag if necessary: `podman build --build-arg FREERDP_TAG=stable-3.5 -t vortice .`

## Regenerating `vdi_broker.patch`
`vdi_broker.patch` is curated in https://github.com/marcomartini97/VDI_Broker. This project only builds correctly with patches generated from that fork. To carry your own modifications, fork `marcomartini97/VDI_Broker`, push your commits there, and then follow the steps below to produce a patch against upstream FreeRDP.
1. Work from a FreeRDP checkout that tracks both your fork (`origin`) and the official repository (`upstream`). If you need to add the upstream remote:
   ```bash
   git remote add upstream https://github.com/FreeRDP/FreeRDP.git
   git fetch upstream
   ```
2. Set the FreeRDP release tag you build against (the same value you pass as `FREERDP_TAG`) and ensure your feature branch is checked out:
   ```bash
   export FREERDP_TAG=3.17.2  # example
   git checkout your-feature-branch
   git fetch origin
   git fetch --tags upstream
   ```
   Confirm the tag exists locally before generating the patch: `git show ${FREERDP_TAG}`.
3. Create a patch that captures every commit between the upstream tag and your branch, then place it at the root of this repository:
   ```bash
   git format-patch --stdout "${FREERDP_TAG}"..HEAD > vdi_broker.patch
   ```
   The patch now contains all commits that your fork introduces relative to the official FreeRDP tag.
4. Copy the refreshed `vdi_broker.patch` into this repository and rebuild the image. Regenerate the patch whenever you rebase or add commits so it continues to align with `FREERDP_TAG`.

## Runtime assumptions
- `/etc/vdi` is baked into the image from the `config/` directory and now includes the `VORTICE-vdi` build context sourced from the submodule alongside `config.ini`, `vdi_broker.yaml`, and TLS assets.
- With the container runtime socket (`/run/podman/podman.sock` or `/var/run/docker.sock`) mounted, the broker provisions downstream containers directly. The image ships a sample `/etc/pam.d/vdi-broker` that authenticates against `/etc/shadow`; mount a different PAM stack at `pam_path` only when you need host-specific logic. Override the baked desktop template by binding an alternate build context over `/etc/vdi/VORTICE-vdi` to match the `dockerfile_path` setting.
- The container listens on TCP `3389`.
- The bundled `VORTICE-vdi` desktop image expects the host to passthrough `/etc/passwd`, `/etc/group`, and `/etc/shadow` (see `config/vdi_broker.yaml`). Ensure these mounts expose a `gnome-remote-desktop` user entry (`gnome-remote-desktop:x:960:960:GNOME Remote Desktop:/var/lib/gnome-remote-desktop:/usr/bin/nologin`) until the template adds a more flexible authentication model.

## Podman CLI example
```bash
podman run --rm -it \
  --name vortice \
  -p 3389:3389 \
  -v /run/podman/podman.sock:/run/podman/podman.sock:Z \
  -v ./config/pam.d/vdi-broker:/etc/pam.d/vdi-broker:ro \
  -v ./config/vdi_broker.yaml:/etc/vdi/vdi_broker.yaml:ro,Z \
  -v /path/to/desktop-context:/etc/vdi/VORTICE-vdi:Z \
  vortice
```
Ensure that `/etc/vdi/VORTICE-vdi/Containerfile` matches the `dockerfile_path` set in `vdi_broker.yaml`. For Docker, replace the socket path with `/var/run/docker.sock` and drop the SELinux suffix if unsupported. After cloning this repository, keep the submodule in sync with `git submodule update` when the desktop template changes upstream.

To reuse an existing host-managed PAM stack instead of the bundled example, replace the volume mount in the command above with `-v /etc/pam.d/vdi-broker:/etc/pam.d/vdi-broker:ro` (and adjust the `pam_path` if the service file lives elsewhere).

## docker-compose / podman-compose
```yaml
services:
  vortice:
    image: vortice
    container_name: vortice
    ports:
      - "3389:3389"
    volumes:
      - /run/podman/podman.sock:/run/podman/podman.sock
      - ./config/vdi_broker.yaml:/etc/vdi/vdi_broker.yaml:ro
      - /home:/home
      - /etc/shadow:/etc/shadow
      - /etc/group:/etc/group
      - /etc/passwd:/etc/passwd
      - ./config/pam.d/vdi-broker:/etc/pam.d/vdi-broker:ro
      # - /etc/pam.d/vdi-broker:/etc/pam.d/vdi-broker:ro  # optional host passthrough
      - ./VORTICE-vdi:/etc/vdi/VORTICE-vdi
    restart: unless-stopped
```
Use the same definition with `docker compose` after swapping the socket path to `/var/run/docker.sock` and trimming the SELinux suffix if unsupported. Place any downstream image Dockerfiles or build context under the `VORTICE-vdi` submodule (or update the mount to another directory) so the broker can access them. Mount `./config/vdi_broker.yaml` to override the baked broker configuration without replacing the rest of `/etc/vdi`; mount the whole `./config` directory only when you need to replace additional assets such as `config.ini`.
