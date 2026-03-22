#!/usr/bin/env python3
import argparse
import json
import os
import re
import shlex
import ssl
import sys
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, build_opener, HTTPSHandler

DEFAULT_BEAGLE_MANAGER_URL = os.environ.get("PVE_DCV_BEAGLE_MANAGER_URL", "")
DEFAULT_BEAGLE_ENDPOINT_TOKEN = os.environ.get("BEAGLE_ENDPOINT_SHARED_TOKEN", "")


def parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


@dataclass
class Endpoint:
    scheme: str
    host: str
    port: int


def normalize_endpoint(raw_host: str, raw_scheme: str, raw_port: int) -> Endpoint:
    text = (raw_host or "").strip()
    if not text:
        raise SystemExit("missing Proxmox API host")

    scheme = raw_scheme
    host = text
    port = raw_port

    if "://" in text:
        parsed = urlparse(text)
        if parsed.scheme:
            scheme = parsed.scheme
        if parsed.hostname:
            host = parsed.hostname
        if parsed.port:
            port = parsed.port
    elif text.count(":") == 1 and not text.startswith("["):
        host_part, port_part = text.rsplit(":", 1)
        if port_part.isdigit():
            host = host_part
            port = int(port_part)

    host = host.strip()
    if not host:
        raise SystemExit("invalid Proxmox API host")

    return Endpoint(scheme=scheme, host=host, port=port)


def split_login(login: str) -> tuple[str, str]:
    raw = (login or "").strip()
    if not raw:
        raise SystemExit("missing Proxmox username")
    if "@" in raw:
        username, realm = raw.rsplit("@", 1)
    else:
        username, realm = raw, "pve"
    if not username or not realm:
        raise SystemExit("invalid Proxmox username, expected user@realm")
    return username, realm


def parse_description_meta(description: str) -> dict[str, str]:
    meta: dict[str, str] = {}
    text = str(description or "").replace("\\r\\n", "\n").replace("\\n", "\n")
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip().lower()
        value = value.strip()
        if key and key not in meta:
            meta[key] = value
    return meta


def safe_hostname(name: str, vmid: int) -> str:
    cleaned = re.sub(r"[^a-z0-9-]+", "-", str(name or "").strip().lower()).strip("-")
    if not cleaned:
        cleaned = f"pve-tc-{vmid}"
    cleaned = cleaned[:63].strip("-")
    return cleaned or f"pve-tc-{vmid}"


def shell_line(key: str, value: str) -> str:
    return f"{key}={shlex.quote(str(value))}\n"


def available_modes_from_preset(preset: dict[str, str]) -> list[str]:
    return ["MOONLIGHT"] if preset["PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST"] else []


def build_preset(
    vm: dict[str, Any],
    config: dict[str, Any],
    endpoint: Endpoint,
    login: str,
    password: str,
    verify_tls: bool,
) -> tuple[dict[str, str], list[str]]:
    meta = parse_description_meta(config.get("description", ""))
    vmid = int(vm["vmid"])
    vm_name = config.get("name") or vm.get("name") or f"vm-{vmid}"
    proxmox_user, proxmox_realm = split_login(login)
    proxmox_scheme = meta.get("proxmox-scheme", endpoint.scheme)
    proxmox_host = meta.get("proxmox-host", endpoint.host)
    proxmox_port = meta.get("proxmox-port", str(endpoint.port))
    proxmox_verify_tls = meta.get("proxmox-verify-tls", "1" if verify_tls else "0")

    moonlight_host = meta.get("moonlight-host") or meta.get("sunshine-host") or meta.get("sunshine-ip") or ""
    sunshine_api_url = meta.get("sunshine-api-url") or (f"https://{moonlight_host}:47990" if moonlight_host else "")
    default_mode = "MOONLIGHT" if moonlight_host else ""

    preset = {
        "PVE_THIN_CLIENT_PRESET_PROFILE_NAME": f"vm-{vmid}",
        "PVE_THIN_CLIENT_PRESET_VM_NAME": vm_name,
        "PVE_THIN_CLIENT_PRESET_HOSTNAME_VALUE": safe_hostname(vm_name, vmid),
        "PVE_THIN_CLIENT_PRESET_AUTOSTART": meta.get("thinclient-autostart", "1"),
        "PVE_THIN_CLIENT_PRESET_DEFAULT_MODE": default_mode,
        "PVE_THIN_CLIENT_PRESET_NETWORK_MODE": meta.get("thinclient-network-mode", "dhcp"),
        "PVE_THIN_CLIENT_PRESET_NETWORK_INTERFACE": meta.get("thinclient-network-interface", "eth0"),
        "PVE_THIN_CLIENT_PRESET_PROXMOX_SCHEME": proxmox_scheme,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_HOST": proxmox_host,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_PORT": proxmox_port,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_NODE": str(vm.get("node", "")),
        "PVE_THIN_CLIENT_PRESET_PROXMOX_VMID": str(vmid),
        "PVE_THIN_CLIENT_PRESET_PROXMOX_REALM": proxmox_realm,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_VERIFY_TLS": proxmox_verify_tls,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_USERNAME": proxmox_user,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_PASSWORD": password,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_BEAGLE_MANAGER_URL": DEFAULT_BEAGLE_MANAGER_URL,
        "PVE_THIN_CLIENT_PRESET_BEAGLE_MANAGER_TOKEN": DEFAULT_BEAGLE_ENDPOINT_TOKEN,
        "PVE_THIN_CLIENT_PRESET_SPICE_METHOD": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_URL": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_USERNAME": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_PASSWORD": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_URL": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_USERNAME": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_PASSWORD": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_DCV_URL": "",
        "PVE_THIN_CLIENT_PRESET_DCV_USERNAME": "",
        "PVE_THIN_CLIENT_PRESET_DCV_PASSWORD": "",
        "PVE_THIN_CLIENT_PRESET_DCV_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_DCV_SESSION": "",
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST": moonlight_host,
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_APP": meta.get("moonlight-app", meta.get("sunshine-app", "Desktop")),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_BIN": meta.get("moonlight-bin", "moonlight"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_RESOLUTION": meta.get("moonlight-resolution", "auto"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_FPS": meta.get("moonlight-fps", "60"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_BITRATE": meta.get("moonlight-bitrate", "20000"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_VIDEO_CODEC": meta.get("moonlight-video-codec", "H.264"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_VIDEO_DECODER": meta.get("moonlight-video-decoder", "auto"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_AUDIO_CONFIG": meta.get("moonlight-audio-config", "stereo"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_ABSOLUTE_MOUSE": meta.get("moonlight-absolute-mouse", "1"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_QUIT_AFTER": meta.get("moonlight-quit-after", "0"),
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_API_URL": sunshine_api_url,
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_USERNAME": meta.get("sunshine-user", ""),
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_PASSWORD": meta.get("sunshine-password", ""),
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_PIN": meta.get("sunshine-pin", f"{vmid % 10000:04d}"),
    }

    return preset, available_modes_from_preset(preset)


class ProxmoxApi:
    def __init__(self, endpoint: Endpoint, username: str, password: str, verify_tls: bool):
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.verify_tls = verify_tls
        self.ticket = ""

        context = ssl.create_default_context()
        if not verify_tls:
            context = ssl._create_unverified_context()  # noqa: SLF001
        self.opener = build_opener(HTTPSHandler(context=context))

    def url(self, path: str, query: dict[str, Any] | None = None) -> str:
        base = f"{self.endpoint.scheme}://{self.endpoint.host}:{self.endpoint.port}/api2/json{path}"
        if query:
            return f"{base}?{urlencode(query)}"
        return base

    def request(self, path: str, *, query: dict[str, Any] | None = None, data: dict[str, Any] | None = None) -> Any:
        payload = None
        headers = {"Accept": "application/json"}
        if data is not None:
            payload = urlencode(data).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if self.ticket:
            headers["Cookie"] = f"PVEAuthCookie={self.ticket}"
        request = Request(self.url(path, query=query), data=payload, headers=headers)
        try:
            with self.opener.open(request, timeout=20) as response:
                body = response.read().decode("utf-8")
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace").strip()
            raise SystemExit(f"Proxmox API request failed: {exc.code} {exc.reason}: {detail}") from exc
        except URLError as exc:
            raise SystemExit(f"Unable to reach Proxmox API: {exc.reason}") from exc

        try:
            payload_json = json.loads(body)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON response from Proxmox API: {exc}") from exc

        if "data" not in payload_json:
            raise SystemExit("Unexpected Proxmox API response: missing data field")
        return payload_json["data"]

    def login(self) -> None:
        data = self.request(
            "/access/ticket",
            data={"username": self.username, "password": self.password},
        )
        ticket = data.get("ticket", "")
        if not ticket:
            raise SystemExit("Proxmox login succeeded but no ticket was returned")
        self.ticket = ticket

    def list_nodes(self) -> list[str]:
        data = self.request("/nodes")
        nodes: list[str] = []
        for item in data:
            node = str(item.get("node", "")).strip()
            if node and node not in nodes:
                nodes.append(node)
        return nodes

    def list_vms_on_node(self, node: str) -> list[dict[str, Any]]:
        data = self.request(f"/nodes/{node}/qemu")
        vms = []
        for item in data:
            if item.get("vmid") is None:
                continue
            vms.append(
                {
                    "vmid": int(item["vmid"]),
                    "node": node,
                    "name": item.get("name") or f"vm-{item['vmid']}",
                    "status": item.get("status", "unknown"),
                    "tags": item.get("tags", ""),
                    "template": bool(item.get("template")),
                }
            )
        return vms

    def list_vms(self) -> list[dict[str, Any]]:
        data = self.request("/cluster/resources", query={"type": "vm"})
        vms = []
        for item in data:
            if item.get("type") != "qemu":
                continue
            if item.get("vmid") is None or not item.get("node"):
                continue
            vms.append(
                {
                    "vmid": int(item["vmid"]),
                    "node": item["node"],
                    "name": item.get("name") or f"vm-{item['vmid']}",
                    "status": item.get("status", "unknown"),
                    "tags": item.get("tags", ""),
                    "template": bool(item.get("template")),
                }
            )
        if not vms:
            seen: set[tuple[str, int]] = set()
            for node in self.list_nodes():
                for vm in self.list_vms_on_node(node):
                    key = (vm["node"], vm["vmid"])
                    if key in seen:
                        continue
                    seen.add(key)
                    vms.append(vm)
        vms.sort(key=lambda entry: (entry["name"].lower(), entry["vmid"]))
        return vms

    def resolve_vm(self, vmid: int, node: str | None = None) -> dict[str, Any]:
        for vm in self.list_vms():
            if vm["vmid"] == vmid and (not node or vm["node"] == node):
                return vm
        raise SystemExit(f"VM {vmid} is not visible for the supplied user")

    def fetch_vm_config(self, node: str, vmid: int) -> dict[str, Any]:
        return self.request(f"/nodes/{node}/qemu/{vmid}/config")


def command_list_vms(args: argparse.Namespace) -> int:
    endpoint = normalize_endpoint(args.host, args.scheme, args.port)
    api = ProxmoxApi(endpoint, args.username, args.password, parse_bool(args.verify_tls))
    api.login()
    payload = {
        "endpoint": {"scheme": endpoint.scheme, "host": endpoint.host, "port": endpoint.port},
        "username": args.username,
        "vms": api.list_vms(),
    }
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def command_build_preset_env(args: argparse.Namespace) -> int:
    endpoint = normalize_endpoint(args.host, args.scheme, args.port)
    verify_tls = parse_bool(args.verify_tls)
    api = ProxmoxApi(endpoint, args.username, args.password, verify_tls)
    api.login()
    vm = api.resolve_vm(args.vmid, args.node)
    config = api.fetch_vm_config(vm["node"], vm["vmid"])
    preset, _ = build_preset(vm, config, endpoint, args.username, args.password, verify_tls)
    sys.stdout.write("".join(shell_line(key, value) for key, value in preset.items()))
    return 0


def command_build_preset_json(args: argparse.Namespace) -> int:
    endpoint = normalize_endpoint(args.host, args.scheme, args.port)
    verify_tls = parse_bool(args.verify_tls)
    api = ProxmoxApi(endpoint, args.username, args.password, verify_tls)
    api.login()
    vm = api.resolve_vm(args.vmid, args.node)
    config = api.fetch_vm_config(vm["node"], vm["vmid"])
    preset, available_modes = build_preset(vm, config, endpoint, args.username, args.password, verify_tls)
    payload = {"vm": vm, "preset": preset, "available_modes": available_modes}
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Proxmox API helper for the thin-client installer")
    parser.add_argument("--host", required=True)
    parser.add_argument("--scheme", default="https")
    parser.add_argument("--port", type=int, default=8006)
    parser.add_argument("--verify-tls", default="0")
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list-vms-json")

    preset_env = subparsers.add_parser("build-preset-env")
    preset_env.add_argument("--vmid", type=int, required=True)
    preset_env.add_argument("--node")

    preset_json = subparsers.add_parser("build-preset-json")
    preset_json.add_argument("--vmid", type=int, required=True)
    preset_json.add_argument("--node")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "list-vms-json":
        return command_list_vms(args)
    if args.command == "build-preset-env":
        return command_build_preset_env(args)
    if args.command == "build-preset-json":
        return command_build_preset_json(args)
    parser.error(f"unsupported command: {args.command}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
