VDI ORCHESTRATED RDP THROUGH INTERLEAVED CONTAINERIZED EXECUTION

# Vortice FreeRDP Proxy

`vortice` builds a Fedora based image that compiles FreeRDP from the bundled `VDI_Broker` submodule, installs `podman`, and launches `vdi-redirector` by default. Switch the launcher with the `VORTICE_LAUNCHER` environment variable when you need the legacy `freerdp-proxy /etc/vdi/config.ini` behaviour. Clone the repository with `git clone --recurse-submodules` (or run `git submodule update --init --recursive` after cloning) to pull in both the FreeRDP fork and the `VORTICE-vdi` desktop template.

## Build the image
1. Review `config/config.ini` and `config/vdi_broker.yaml`. The broker defaults to `dockerfile_path: /etc/vdi/VORTICE-vdi/Containerfile`; initialize the `VORTICE-vdi` submodule (`git submodule update --init --recursive`) so the downstream desktop template is baked into the image build context.
2. Populate `keys/` with `cert.pem` / `key.pem` if you already have TLS material. When the directory is missing or empty, the build auto-generates a self-signed pair.
3. Build:
   - `podman build -t vortice .`
   - `docker build -t vortice .`
   The build always uses the `VDI_Broker` submodule (https://github.com/marcomartini97/VDI_Broker), which is a FreeRDP fork carrying the `vdi-broker` proxy module and supporting patches. Keep the submodule up to date with `git submodule update --remote` if you need newer changes.

## Updating `VDI_Broker`
The FreeRDP fork that provides the proxy module lives in the `VDI_Broker` submodule at the repository root.
1. Pull the latest commits from the fork:
   ```bash
   git submodule update --remote VDI_Broker
   ```
2. Inspect and commit the updated submodule reference alongside any local changes. If you maintain your own fork, update the submodule URL and point it at the desired commit before rebuilding the image.

## Runtime assumptions
- `/etc/vdi` is baked into the image from the `config/` directory and now includes the `VORTICE-vdi` build context sourced from the submodule alongside `config.ini`, `vdi_broker.yaml`, and TLS assets.
- With the container runtime socket (`/run/podman/podman.sock` or `/var/run/docker.sock`) mounted, the broker provisions downstream containers directly. The image ships a sample `/etc/pam.d/vdi-broker` that authenticates against `/etc/shadow`; mount a different PAM stack at `pam_path` only when you need host-specific logic. Override the baked desktop template by binding an alternate build context over `/etc/vdi/VORTICE-vdi` to match the `dockerfile_path` setting.
- The container listens on TCP `3389`.
- The bundled `VORTICE-vdi` desktop image expects the host to passthrough `/etc/passwd`, `/etc/group`, and `/etc/shadow` (see `config/vdi_broker.yaml`). Ensure these mounts expose a `gnome-remote-desktop` user entry (`gnome-remote-desktop:x:960:960:GNOME Remote Desktop:/var/lib/gnome-remote-desktop:/usr/bin/nologin`) until the template adds a more flexible authentication model.

## Runtime launchers
- `VORTICE_LAUNCHER=vdi-redirector` is the default. Its launch flags can be controlled with the following environment variables (they have no effect on `freerdp-proxy`):
  - `VORTICE_BIND_ADDRESS` → `--bind` (defaults to `0.0.0.0` when unset)
  - `VORTICE_PORT` → `--port` (defaults to `3389` when unset)
  - `VORTICE_REDIRECTOR_CONFIG` → `--config` (defaults to `/etc/vdi/vdi_broker.yaml`)
  - `VORTICE_CERTIFICATE` / `VORTICE_PRIVATE_KEY` → `--certificate` / `--private-key` (default to `/etc/vdi/cert.pem` and `/etc/vdi/key.pem`)
  - `VORTICE_ROUTING_TOKEN` (`true`, `yes`, or `1`) → `--routing-token`
- Override them with `podman run -e VORTICE_BIND_ADDRESS=10.0.0.10 -e VORTICE_CERTIFICATE=/path/cert.pem ... vortice` (or the equivalent `docker run` invocation).
- `VORTICE_LAUNCHER=freerdp-proxy` reverts to the proxy. When using the proxy adjust `/etc/vdi/config.ini` (or mount a replacement and optionally point `FREERDP_PROXY_CONFIG` at it) to reflect the desired bind address, port, certificates, and other settings because the redirector-specific environment variables are ignored.
- When running in redirector mode ensure the broker configuration (`vdi_broker.yaml`) pins the desktop network to either `macvlan` or `bridge-unmanaged` and supplies a valid `parent` interface so the downstream sessions land on the correct network.

## Broker networking modes
The `network` block in `config/vdi_broker.yaml` controls how the broker wires newly created desktop containers onto your host network:
- Leave `type` unset (default) to let Podman manage a private bridge called `vortice-network`. The broker provisions and tears down the bridge automatically and assigns container addresses from Podman's internal subnet.
- Set `type: bridge-unmanaged` when you already created and configure your own bridge. Podman still attaches containers to the named `network.name`, but it does not try to manage the bridge lifecycle. Use this when another service (e.g., NetworkManager or systemd-networkd) owns the bridge. Wireless interfaces generally cannot back this bridge; choose a wired uplink.
- Set `type: macvlan` to give each VDI session its own MAC address on the upstream network. This blocks direct host-to-guest communication by design, so plan management access accordingly. Populate `network.parent` with the physical or bridge interface that should carry the traffic (again, wireless adapters are not viable) and ensure the upstream switch allows multiple MACs.

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
      - ./logs:/var/log/vdi-broker
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
