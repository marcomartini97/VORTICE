#!/usr/bin/env bash
set -euo pipefail

launcher="${VORTICE_LAUNCHER:-vdi-redirector}"
config_path="${FREERDP_PROXY_CONFIG:-/etc/vdi/config.ini}"
cert_path="${VORTICE_CERTIFICATE:-/etc/vdi/cert.pem}"
key_path="${VORTICE_PRIVATE_KEY:-/etc/vdi/key.pem}"
bind_address="${VORTICE_BIND_ADDRESS:-}"
listen_port="${VORTICE_PORT:-}"
redirector_config="${VORTICE_REDIRECTOR_CONFIG:-/etc/vdi/vdi_broker.yaml}"
routing_token="${VORTICE_ROUTING_TOKEN:-}"

case "${launcher}" in
	freerdp-proxy)
		args=("$@")
		if [ "${#args[@]}" -eq 0 ]; then
			args=("${config_path}")
		fi
		exec /usr/local/bin/freerdp-proxy "${args[@]}"
		;;
	vdi-redirector)
		if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
			echo "Missing certificate (${cert_path}) or private key (${key_path}) required for vdi-redirector." >&2
			exit 1
		fi
		redirector_args=("/usr/local/bin/vdi-redirector")
		if [ -n "${bind_address}" ]; then
			redirector_args+=("--bind" "${bind_address}")
		fi
		if [ -n "${listen_port}" ]; then
			redirector_args+=("--port" "${listen_port}")
		fi
		if [ -n "${redirector_config}" ]; then
			redirector_args+=("--config" "${redirector_config}")
		fi
		redirector_args+=("--certificate" "${cert_path}" "--private-key" "${key_path}")
		if [ -n "${routing_token}" ] && [[ "${routing_token}" =~ ^([Tt]rue|[Yy]es|1)$ ]]; then
			redirector_args+=("--routing-token")
		fi
		redirector_args+=("$@")
		exec "${redirector_args[@]}"
		;;
	*)
		echo "Unsupported VORTICE_LAUNCHER '${launcher}'. Valid options: freerdp-proxy, vdi-redirector." >&2
		exit 1
		;;
esac
