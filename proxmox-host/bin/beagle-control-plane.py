#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

VERSION = "dev"
ROOT_DIR = Path(__file__).resolve().parents[2]
VERSION_FILE = ROOT_DIR / "VERSION"
if VERSION_FILE.exists():
    VERSION = VERSION_FILE.read_text(encoding="utf-8").strip() or VERSION

LISTEN_HOST = os.environ.get("BEAGLE_MANAGER_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("BEAGLE_MANAGER_LISTEN_PORT", "9088"))
DATA_DIR = Path(os.environ.get("BEAGLE_MANAGER_DATA_DIR", "/var/lib/beagle/beagle-manager"))
EFFECTIVE_DATA_DIR = DATA_DIR
API_TOKEN = os.environ.get("BEAGLE_MANAGER_API_TOKEN", "").strip()
ENDPOINT_SHARED_TOKEN = os.environ.get("BEAGLE_ENDPOINT_SHARED_TOKEN", "").strip()
ALLOW_LOCALHOST_NOAUTH = os.environ.get("BEAGLE_MANAGER_ALLOW_LOCALHOST_NOAUTH", "0").strip().lower() in {"1", "true", "yes", "on"}
DOWNLOADS_STATUS_FILE = ROOT_DIR / "dist" / "beagle-downloads-status.json"
VM_INSTALLERS_FILE = ROOT_DIR / "dist" / "beagle-vm-installers.json"


@dataclass
class VmSummary:
    vmid: int
    node: str
    name: str
    status: str
    tags: str


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json_file(path: Path, fallback: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return fallback
    except json.JSONDecodeError:
        return fallback


def ensure_data_dir() -> Path:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        return DATA_DIR
    except PermissionError:
        fallback = Path("/tmp/beagle-control-plane")
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


def run_json(command: list[str]) -> Any:
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        return None


def run_text(command: list[str]) -> str:
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return ""
    return result.stdout


def endpoints_dir() -> Path:
    path = EFFECTIVE_DATA_DIR / "endpoints"
    path.mkdir(parents=True, exist_ok=True)
    return path


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
        cleaned = f"beagle-{vmid}"
    return cleaned[:63].strip("-") or f"beagle-{vmid}"


def first_guest_ipv4(vmid: int) -> str:
    payload = run_json(["qm", "guest", "cmd", str(vmid), "network-get-interfaces"])
    if not isinstance(payload, list):
        return ""
    for iface in payload:
        for address in iface.get("ip-addresses", []):
            ip = str(address.get("ip-address", ""))
            if address.get("ip-address-type") != "ipv4":
                continue
            if not ip or ip.startswith("127.") or ip.startswith("169.254."):
                continue
            return ip
    return ""


def list_vms() -> list[VmSummary]:
    resources = run_json(["pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"])
    vms: list[VmSummary] = []
    if not isinstance(resources, list):
        return vms
    for item in resources:
        if item.get("type") != "qemu" or item.get("vmid") is None or not item.get("node"):
            continue
        vms.append(
            VmSummary(
                vmid=int(item["vmid"]),
                node=str(item["node"]),
                name=str(item.get("name") or f"vm-{item['vmid']}"),
                status=str(item.get("status") or "unknown"),
                tags=str(item.get("tags") or ""),
            )
        )
    return sorted(vms, key=lambda vm: vm.vmid)


def get_vm_config(node: str, vmid: int) -> dict[str, Any]:
    payload = run_json(["pvesh", "get", f"/nodes/{node}/qemu/{vmid}/config", "--output-format", "json"])
    if isinstance(payload, dict):
        return payload
    return {}


def build_profile(vm: VmSummary) -> dict[str, Any]:
    config = get_vm_config(vm.node, vm.vmid)
    meta = parse_description_meta(config.get("description", ""))
    guest_ip = first_guest_ipv4(vm.vmid)
    stream_host = meta.get("moonlight-host") or meta.get("sunshine-host") or meta.get("sunshine-ip") or guest_ip
    sunshine_api_url = meta.get("sunshine-api-url") or (f"https://{stream_host}:47990" if stream_host else "")
    installer_url = f"/beagle-downloads/pve-thin-client-usb-installer-vm-{vm.vmid}.sh"
    has_sunshine_password = bool(meta.get("sunshine-password"))

    return {
        "vmid": vm.vmid,
        "node": vm.node,
        "name": config.get("name") or vm.name,
        "status": vm.status,
        "tags": vm.tags,
        "guest_ip": guest_ip,
        "stream_host": stream_host,
        "sunshine_api_url": sunshine_api_url,
        "sunshine_username": meta.get("sunshine-user", ""),
        "sunshine_password_configured": has_sunshine_password,
        "sunshine_pin": meta.get("sunshine-pin", f"{vm.vmid % 10000:04d}"),
        "moonlight_app": meta.get("moonlight-app", meta.get("sunshine-app", "Desktop")),
        "moonlight_resolution": meta.get("moonlight-resolution", "auto"),
        "moonlight_fps": meta.get("moonlight-fps", "60"),
        "moonlight_bitrate": meta.get("moonlight-bitrate", "20000"),
        "moonlight_video_codec": meta.get("moonlight-video-codec", "H.264"),
        "moonlight_video_decoder": meta.get("moonlight-video-decoder", "auto"),
        "moonlight_audio_config": meta.get("moonlight-audio-config", "stereo"),
        "default_mode": "MOONLIGHT" if stream_host else "",
        "beagle_hostname": safe_hostname(config.get("name") or vm.name, vm.vmid),
        "installer_url": installer_url,
        "metadata_keys": sorted(meta.keys()),
        "config_digest": {
            "memory": config.get("memory"),
            "cores": config.get("cores"),
            "sockets": config.get("sockets"),
            "machine": config.get("machine"),
            "ostype": config.get("ostype"),
            "agent": config.get("agent"),
            "vga": config.get("vga"),
        },
    }


def build_health_payload() -> dict[str, Any]:
    downloads_status = load_json_file(DOWNLOADS_STATUS_FILE, {})
    vm_installers = load_json_file(VM_INSTALLERS_FILE, [])
    endpoint_reports = list_endpoint_reports()
    return {
        "service": "beagle-control-plane",
        "ok": True,
        "version": VERSION,
        "generated_at": utcnow(),
        "downloads_status_present": DOWNLOADS_STATUS_FILE.exists(),
        "downloads_status": downloads_status,
        "vm_installer_inventory_present": VM_INSTALLERS_FILE.exists(),
        "vm_installer_count": len(vm_installers) if isinstance(vm_installers, list) else 0,
        "endpoint_count": len(endpoint_reports),
        "data_dir": str(EFFECTIVE_DATA_DIR),
    }


def summarize_endpoint_report(payload: dict[str, Any]) -> dict[str, Any]:
    health = payload.get("health", {}) if isinstance(payload.get("health"), dict) else {}
    session = payload.get("session", {}) if isinstance(payload.get("session"), dict) else {}
    runtime = payload.get("runtime", {}) if isinstance(payload.get("runtime"), dict) else {}
    return {
        "endpoint_id": payload.get("endpoint_id", ""),
        "hostname": payload.get("hostname", ""),
        "profile_name": payload.get("profile_name", ""),
        "vmid": payload.get("vmid"),
        "node": payload.get("node", ""),
        "reported_at": payload.get("reported_at", ""),
        "stream_host": payload.get("stream_host", ""),
        "moonlight_app": payload.get("moonlight_app", ""),
        "network_mode": payload.get("network_mode", ""),
        "ip_summary": health.get("ip_summary", ""),
        "networkmanager_state": health.get("networkmanager_state", ""),
        "autologin_state": health.get("autologin_state", ""),
        "prepare_state": health.get("prepare_state", ""),
        "guest_agent_state": health.get("guest_agent_state", ""),
        "moonlight_target_reachable": health.get("moonlight_target_reachable", ""),
        "sunshine_api_reachable": health.get("sunshine_api_reachable", ""),
        "runtime_binary": runtime.get("required_binary", ""),
        "runtime_binary_available": runtime.get("binary_available", ""),
        "last_launch_mode": session.get("mode", ""),
        "last_launch_target": session.get("target", ""),
        "last_launch_time": session.get("timestamp", ""),
    }


def endpoint_report_path(node: str, vmid: int) -> Path:
    safe_node = re.sub(r"[^A-Za-z0-9._-]+", "-", str(node or "unknown")).strip("-") or "unknown"
    return endpoints_dir() / f"{safe_node}-{int(vmid)}.json"


def load_endpoint_report(node: str, vmid: int) -> dict[str, Any] | None:
    payload = load_json_file(endpoint_report_path(node, vmid), None)
    return payload if isinstance(payload, dict) else None


def list_endpoint_reports() -> list[dict[str, Any]]:
    reports = []
    for path in sorted(endpoints_dir().glob("*.json")):
        payload = load_json_file(path, None)
        if not isinstance(payload, dict):
            continue
        payload["_path"] = str(path)
        reports.append(payload)
    reports.sort(key=lambda item: (str(item.get("node", "")), int(item.get("vmid", 0))))
    return reports


def build_vm_inventory() -> dict[str, Any]:
    inventory = []
    installers = load_json_file(VM_INSTALLERS_FILE, [])
    installers_by_vmid = {
        int(item.get("vmid")): item for item in installers if isinstance(item, dict) and item.get("vmid") is not None
    }
    for vm in list_vms():
        profile = build_profile(vm)
        installer = installers_by_vmid.get(vm.vmid, {})
        inventory.append(
            {
                "vmid": vm.vmid,
                "node": vm.node,
                "name": vm.name,
                "status": vm.status,
                "stream_host": profile["stream_host"],
                "sunshine_api_url": profile["sunshine_api_url"],
                "moonlight_app": profile["moonlight_app"],
                "default_mode": "MOONLIGHT" if profile["stream_host"] else "",
                "installer_url": installer.get("installer_url") or profile["installer_url"],
                "available_modes": installer.get("available_modes") or (["MOONLIGHT"] if profile["stream_host"] else []),
                "endpoint": summarize_endpoint_report(load_endpoint_report(vm.node, vm.vmid) or {}),
            }
        )
    return {
        "service": "beagle-control-plane",
        "version": VERSION,
        "generated_at": utcnow(),
        "vms": inventory,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = f"BeagleControlPlane/{VERSION}"

    def _is_authenticated(self) -> bool:
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path in {"/healthz", "/api/v1/health"}:
            return True
        if ALLOW_LOCALHOST_NOAUTH and self.client_address[0] in {"127.0.0.1", "::1"}:
            return True
        if not API_TOKEN:
            return False
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer ") and header[7:].strip() == API_TOKEN:
            return True
        if self.headers.get("X-Beagle-Api-Token", "").strip() == API_TOKEN:
            return True
        return False

    def _is_endpoint_authenticated(self) -> bool:
        if ALLOW_LOCALHOST_NOAUTH and self.client_address[0] in {"127.0.0.1", "::1"}:
            return True
        if not ENDPOINT_SHARED_TOKEN:
            return False
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer ") and header[7:].strip() == ENDPOINT_SHARED_TOKEN:
            return True
        if self.headers.get("X-Beagle-Endpoint-Token", "").strip() == ENDPOINT_SHARED_TOKEN:
            return True
        return False

    def _write_json(self, status: HTTPStatus, payload: Any) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8") + b"\n"
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > 256 * 1024:
            raise ValueError("invalid content length")
        body = self.rfile.read(length)
        payload = json.loads(body.decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("invalid payload")
        return payload

    def _endpoint_summary_for_vmid(self, vmid: int) -> dict[str, Any] | None:
        for vm in list_vms():
            if vm.vmid == vmid:
                report = load_endpoint_report(vm.node, vm.vmid)
                if report is None:
                    return None
                return summarize_endpoint_report(report)
        return None

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Beagle-Api-Token, X-Beagle-Endpoint-Token")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path.startswith("/api/v1/public/vms/") and path.endswith("/endpoint"):
            vmid_text = path.split("/")[-2]
            if not vmid_text.isdigit():
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                return
            summary = self._endpoint_summary_for_vmid(int(vmid_text))
            if summary is None:
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "endpoint not found"})
                return
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "endpoint": summary,
                },
            )
            return

        if not self._is_authenticated():
            self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
            return

        if path == "/healthz":
            self._write_json(HTTPStatus.OK, {"ok": True, "service": "beagle-control-plane", "version": VERSION})
            return
        if path == "/api/v1/health":
            self._write_json(HTTPStatus.OK, build_health_payload())
            return
        if path == "/api/v1/vms":
            self._write_json(HTTPStatus.OK, build_vm_inventory())
            return
        if path == "/api/v1/endpoints":
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "endpoints": [summarize_endpoint_report(item) for item in list_endpoint_reports()],
                },
            )
            return
        if path.startswith("/api/v1/vms/"):
            if path.endswith("/endpoint"):
                vmid_text = path.split("/")[-2]
                if not vmid_text.isdigit():
                    self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                    return
                summary = self._endpoint_summary_for_vmid(int(vmid_text))
                if summary is None:
                    self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "endpoint not found"})
                    return
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "service": "beagle-control-plane",
                        "version": VERSION,
                        "generated_at": utcnow(),
                        "endpoint": summary,
                    },
                )
                return
            vmid_text = path.rsplit("/", 1)[-1]
            if not vmid_text.isdigit():
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                return
            vmid = int(vmid_text)
            vm = next((candidate for candidate in list_vms() if candidate.vmid == vmid), None)
            if vm is None:
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                return
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "profile": build_profile(vm),
                },
            )
            return

        self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path != "/api/v1/endpoints/check-in":
            self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
            return
        if not self._is_endpoint_authenticated():
            self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
            return

        try:
            payload = self._read_json_body()
            vmid = int(payload.get("vmid"))
            node = str(payload.get("node", "")).strip()
            if not node:
                raise ValueError("missing node")
        except Exception as exc:
            self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"invalid payload: {exc}"})
            return

        payload["vmid"] = vmid
        payload["node"] = node
        payload["received_at"] = utcnow()
        payload["remote_addr"] = self.client_address[0]

        path_obj = endpoint_report_path(node, vmid)
        path_obj.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        self._write_json(
            HTTPStatus.OK,
            {
                "ok": True,
                "service": "beagle-control-plane",
                "version": VERSION,
                "stored_at": str(path_obj),
                "endpoint": summarize_endpoint_report(payload),
            },
        )

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[{utcnow()}] {self.address_string()} {fmt % args}", flush=True)


def main() -> int:
    global EFFECTIVE_DATA_DIR
    EFFECTIVE_DATA_DIR = ensure_data_dir()
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(
        json.dumps(
            {
                "service": "beagle-control-plane",
                "version": VERSION,
                "listen_host": LISTEN_HOST,
                "listen_port": LISTEN_PORT,
                "allow_localhost_noauth": ALLOW_LOCALHOST_NOAUTH,
                "data_dir": str(EFFECTIVE_DATA_DIR),
            }
        ),
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
