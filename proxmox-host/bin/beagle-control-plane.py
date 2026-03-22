#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import hashlib
from dataclasses import dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

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


def actions_dir() -> Path:
    path = EFFECTIVE_DATA_DIR / "actions"
    path.mkdir(parents=True, exist_ok=True)
    return path


def support_bundles_dir() -> Path:
    path = EFFECTIVE_DATA_DIR / "support-bundles"
    path.mkdir(parents=True, exist_ok=True)
    return path


def policies_dir() -> Path:
    path = EFFECTIVE_DATA_DIR / "policies"
    path.mkdir(parents=True, exist_ok=True)
    return path


def safe_slug(value: str, default: str = "item") -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value or "")).strip("-")
    return cleaned or default


def action_queue_path(node: str, vmid: int) -> Path:
    safe_node = safe_slug(node, "unknown")
    return actions_dir() / f"{safe_node}-{int(vmid)}-queue.json"


def action_result_path(node: str, vmid: int) -> Path:
    safe_node = safe_slug(node, "unknown")
    return actions_dir() / f"{safe_node}-{int(vmid)}-last-result.json"


def support_bundle_metadata_path(bundle_id: str) -> Path:
    return support_bundles_dir() / f"{safe_slug(bundle_id, 'bundle')}.json"


def support_bundle_archive_path(bundle_id: str, filename: str) -> Path:
    suffix = Path(filename or "support-bundle.tar.gz").suffixes
    extension = "".join(suffix) if suffix else ".bin"
    return support_bundles_dir() / f"{safe_slug(bundle_id, 'bundle')}{extension}"


def policy_path(name: str) -> Path:
    return policies_dir() / f"{safe_slug(name, 'policy')}.json"


def load_action_queue(node: str, vmid: int) -> list[dict[str, Any]]:
    payload = load_json_file(action_queue_path(node, vmid), [])
    return payload if isinstance(payload, list) else []


def save_action_queue(node: str, vmid: int, queue: list[dict[str, Any]]) -> None:
    action_queue_path(node, vmid).write_text(json.dumps(queue, indent=2) + "\n", encoding="utf-8")


def load_action_result(node: str, vmid: int) -> dict[str, Any] | None:
    payload = load_json_file(action_result_path(node, vmid), None)
    return payload if isinstance(payload, dict) else None


def store_action_result(node: str, vmid: int, payload: dict[str, Any]) -> None:
    action_result_path(node, vmid).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def queue_vm_action(vm: VmSummary, action_name: str, requested_by: str) -> dict[str, Any]:
    queue = load_action_queue(vm.node, vm.vmid)
    action_id = f"{vm.node}-{vm.vmid}-{int(datetime.now(timezone.utc).timestamp())}-{len(queue) + 1}"
    payload = {
        "action_id": action_id,
        "action": action_name,
        "vmid": vm.vmid,
        "node": vm.node,
        "requested_at": utcnow(),
        "requested_by": requested_by,
    }
    queue.append(payload)
    save_action_queue(vm.node, vm.vmid, queue)
    return payload


def dequeue_vm_actions(node: str, vmid: int) -> list[dict[str, Any]]:
    queue = load_action_queue(node, vmid)
    save_action_queue(node, vmid, [])
    return queue


def summarize_action_result(payload: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {
            "action_id": "",
            "action": "",
            "ok": None,
            "message": "",
            "artifact_path": "",
            "stored_artifact_path": "",
            "stored_artifact_bundle_id": "",
            "stored_artifact_download_path": "",
            "stored_artifact_size": 0,
            "requested_at": "",
            "completed_at": "",
        }
    return {
        "action_id": payload.get("action_id", ""),
        "action": payload.get("action", ""),
        "ok": payload.get("ok"),
        "message": payload.get("message", ""),
        "artifact_path": payload.get("artifact_path", ""),
        "stored_artifact_path": payload.get("stored_artifact_path", ""),
        "stored_artifact_bundle_id": payload.get("stored_artifact_bundle_id", ""),
        "stored_artifact_download_path": payload.get("stored_artifact_download_path", ""),
        "stored_artifact_size": payload.get("stored_artifact_size", 0),
        "requested_at": payload.get("requested_at", ""),
        "completed_at": payload.get("completed_at", ""),
    }


def list_support_bundle_metadata(*, node: str | None = None, vmid: int | None = None) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for path in sorted(support_bundles_dir().glob("*.json")):
        payload = load_json_file(path, None)
        if not isinstance(payload, dict):
            continue
        if node is not None and str(payload.get("node", "")).strip() != str(node).strip():
            continue
        if vmid is not None and int(payload.get("vmid", -1)) != int(vmid):
            continue
        items.append(payload)
    items.sort(key=lambda item: str(item.get("uploaded_at", "")), reverse=True)
    return items


def find_support_bundle_metadata(bundle_id: str) -> dict[str, Any] | None:
    payload = load_json_file(support_bundle_metadata_path(bundle_id), None)
    return payload if isinstance(payload, dict) else None


def store_support_bundle(node: str, vmid: int, action_id: str, filename: str, content: bytes) -> dict[str, Any]:
    safe_node = safe_slug(node, "unknown")
    safe_name = safe_slug(filename, "support-bundle.tar.gz")
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    bundle_id = f"{safe_node}-{int(vmid)}-{timestamp}-{safe_slug(action_id, 'action')}"
    archive_path = support_bundle_archive_path(bundle_id, safe_name)
    archive_path.write_bytes(content)
    sha256 = hashlib.sha256(content).hexdigest()
    payload = {
        "bundle_id": bundle_id,
        "node": node,
        "vmid": int(vmid),
        "action_id": action_id,
        "filename": filename,
        "stored_filename": archive_path.name,
        "stored_path": str(archive_path),
        "size": len(content),
        "sha256": sha256,
        "uploaded_at": utcnow(),
        "download_path": f"/api/v1/support-bundles/{bundle_id}/download",
    }
    support_bundle_metadata_path(bundle_id).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def normalize_policy_payload(payload: dict[str, Any], *, policy_name: str | None = None) -> dict[str, Any]:
    name = str(policy_name or payload.get("name", "")).strip()
    if not name:
        raise ValueError("missing policy name")
    selector = payload.get("selector", {})
    if selector is None:
        selector = {}
    if not isinstance(selector, dict):
        raise ValueError("selector must be an object")
    profile = payload.get("profile", {})
    if profile is None:
        profile = {}
    if not isinstance(profile, dict):
        raise ValueError("profile must be an object")
    priority = int(payload.get("priority", 100))
    enabled = bool(payload.get("enabled", True))
    normalized = {
        "name": name,
        "enabled": enabled,
        "priority": priority,
        "selector": {
            "vmid": int(selector["vmid"]) if str(selector.get("vmid", "")).strip() else None,
            "node": str(selector.get("node", "")).strip(),
            "role": str(selector.get("role", "")).strip(),
            "tags_any": [str(item).strip() for item in selector.get("tags_any", []) if str(item).strip()],
            "tags_all": [str(item).strip() for item in selector.get("tags_all", []) if str(item).strip()],
        },
        "profile": {
            "expected_profile_name": str(profile.get("expected_profile_name", "")).strip(),
            "network_mode": str(profile.get("network_mode", "")).strip(),
            "moonlight_app": str(profile.get("moonlight_app", "")).strip(),
            "stream_host": str(profile.get("stream_host", "")).strip(),
            "sunshine_api_url": str(profile.get("sunshine_api_url", "")).strip(),
            "moonlight_resolution": str(profile.get("moonlight_resolution", "")).strip(),
            "moonlight_fps": str(profile.get("moonlight_fps", "")).strip(),
            "moonlight_bitrate": str(profile.get("moonlight_bitrate", "")).strip(),
            "moonlight_video_codec": str(profile.get("moonlight_video_codec", "")).strip(),
            "moonlight_video_decoder": str(profile.get("moonlight_video_decoder", "")).strip(),
            "moonlight_audio_config": str(profile.get("moonlight_audio_config", "")).strip(),
            "beagle_role": str(profile.get("beagle_role", "")).strip(),
            "assigned_target": {
                "vmid": int(profile.get("assigned_target", {}).get("vmid")) if str(profile.get("assigned_target", {}).get("vmid", "")).strip() else None,
                "node": str(profile.get("assigned_target", {}).get("node", "")).strip(),
            } if isinstance(profile.get("assigned_target"), dict) else None,
        },
        "updated_at": utcnow(),
    }
    return normalized


def save_policy(payload: dict[str, Any], *, policy_name: str | None = None) -> dict[str, Any]:
    normalized = normalize_policy_payload(payload, policy_name=policy_name)
    policy_path(normalized["name"]).write_text(json.dumps(normalized, indent=2) + "\n", encoding="utf-8")
    return normalized


def load_policy(name: str) -> dict[str, Any] | None:
    payload = load_json_file(policy_path(name), None)
    return payload if isinstance(payload, dict) else None


def delete_policy(name: str) -> bool:
    path = policy_path(name)
    if not path.exists():
        return False
    path.unlink()
    return True


def list_policies() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for path in sorted(policies_dir().glob("*.json")):
        payload = load_json_file(path, None)
        if not isinstance(payload, dict):
            continue
        items.append(payload)
    items.sort(key=lambda item: (-int(item.get("priority", 0)), str(item.get("name", ""))))
    return items


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


def find_vm(vmid: int) -> VmSummary | None:
    return next((candidate for candidate in list_vms() if candidate.vmid == vmid), None)


def resolve_assigned_target(target_vmid: int, target_node: str, *, allow_assignment: bool) -> dict[str, Any] | None:
    target_vm = find_vm(target_vmid)
    if target_vm is None:
        return None
    if target_node and target_node != target_vm.node:
        return None
    target_profile = build_profile(target_vm, allow_assignment=False)
    return {
        "vmid": target_vm.vmid,
        "node": target_vm.node,
        "name": target_vm.name,
        "stream_host": target_profile["stream_host"],
        "sunshine_api_url": target_profile["sunshine_api_url"],
        "moonlight_app": target_profile["moonlight_app"],
    }


def resolve_policy_for_vm(vm: VmSummary, meta: dict[str, str]) -> dict[str, Any] | None:
    tags = {item.strip() for item in str(vm.tags or "").split(";") if item.strip()}
    role = meta.get("beagle-role", "desktop" if meta.get("moonlight-host") or meta.get("sunshine-ip") or meta.get("sunshine-host") else "")
    for policy in list_policies():
        if not policy.get("enabled", True):
            continue
        selector = policy.get("selector", {}) if isinstance(policy.get("selector"), dict) else {}
        selector_vmid = selector.get("vmid")
        if selector_vmid is not None and int(selector_vmid) != vm.vmid:
            continue
        if selector.get("node") and str(selector.get("node")).strip() != vm.node:
            continue
        if selector.get("role") and str(selector.get("role")).strip() != role:
            continue
        tags_any = {item for item in selector.get("tags_any", []) if item}
        if tags_any and not tags.intersection(tags_any):
            continue
        tags_all = {item for item in selector.get("tags_all", []) if item}
        if tags_all and not tags_all.issubset(tags):
            continue
        return policy
    return None


def build_profile(vm: VmSummary, *, allow_assignment: bool = True) -> dict[str, Any]:
    config = get_vm_config(vm.node, vm.vmid)
    meta = parse_description_meta(config.get("description", ""))
    matched_policy = resolve_policy_for_vm(vm, meta) if allow_assignment else None
    policy_profile = matched_policy.get("profile", {}) if isinstance(matched_policy, dict) and isinstance(matched_policy.get("profile"), dict) else {}
    guest_ip = first_guest_ipv4(vm.vmid)
    stream_host = policy_profile.get("stream_host") or meta.get("moonlight-host") or meta.get("sunshine-ip") or meta.get("sunshine-host") or guest_ip
    sunshine_api_url = policy_profile.get("sunshine_api_url") or meta.get("sunshine-api-url") or (f"https://{stream_host}:47990" if stream_host else "")
    installer_url = f"/beagle-downloads/pve-thin-client-usb-installer-vm-{vm.vmid}.sh"
    has_sunshine_password = bool(meta.get("sunshine-password"))
    expected_profile_name = policy_profile.get("expected_profile_name") or meta.get("beagle-profile-name", "")
    moonlight_app = policy_profile.get("moonlight_app") or meta.get("moonlight-app", meta.get("sunshine-app", "Desktop"))
    profile = {
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
        "moonlight_app": moonlight_app,
        "moonlight_resolution": policy_profile.get("moonlight_resolution") or meta.get("moonlight-resolution", "auto"),
        "moonlight_fps": policy_profile.get("moonlight_fps") or meta.get("moonlight-fps", "60"),
        "moonlight_bitrate": policy_profile.get("moonlight_bitrate") or meta.get("moonlight-bitrate", "20000"),
        "moonlight_video_codec": policy_profile.get("moonlight_video_codec") or meta.get("moonlight-video-codec", "H.264"),
        "moonlight_video_decoder": policy_profile.get("moonlight_video_decoder") or meta.get("moonlight-video-decoder", "auto"),
        "moonlight_audio_config": policy_profile.get("moonlight_audio_config") or meta.get("moonlight-audio-config", "stereo"),
        "network_mode": policy_profile.get("network_mode") or meta.get("thinclient-network-mode", "dhcp"),
        "default_mode": "MOONLIGHT" if stream_host else "",
        "beagle_hostname": safe_hostname(config.get("name") or vm.name, vm.vmid),
        "beagle_role": policy_profile.get("beagle_role") or meta.get("beagle-role", "desktop" if stream_host else ""),
        "expected_profile_name": expected_profile_name,
        "installer_url": installer_url,
        "metadata_keys": sorted(meta.keys()),
        "applied_policy": {
            "name": matched_policy.get("name", ""),
            "priority": matched_policy.get("priority", 0),
        } if matched_policy else None,
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
    if allow_assignment:
        target_vmid = None
        target_node = ""
        assignment_source = ""
        policy_target = policy_profile.get("assigned_target") if isinstance(policy_profile.get("assigned_target"), dict) else None
        if policy_target and policy_target.get("vmid") is not None:
            target_vmid = int(policy_target["vmid"])
            target_node = str(policy_target.get("node", "")).strip()
            assignment_source = "manager-policy"
        else:
            assigned_vmid = meta.get("beagle-target-vmid", "").strip()
            if assigned_vmid.isdigit():
                target_vmid = int(assigned_vmid)
                target_node = meta.get("beagle-target-node", "").strip()
                assignment_source = "vm-metadata"
        if target_vmid is not None:
            assigned_target = resolve_assigned_target(target_vmid, target_node, allow_assignment=False)
            if assigned_target is not None:
                profile["assigned_target"] = assigned_target
                profile["assignment_source"] = assignment_source
                profile["beagle_role"] = "endpoint"
                if (assignment_source == "manager-policy" or not meta.get("moonlight-host")) and assigned_target["stream_host"]:
                    profile["stream_host"] = assigned_target["stream_host"]
                if (assignment_source == "manager-policy" or not meta.get("sunshine-api-url")) and assigned_target["sunshine_api_url"]:
                    profile["sunshine_api_url"] = assigned_target["sunshine_api_url"]
                if (assignment_source == "manager-policy" or not meta.get("moonlight-app")) and assigned_target["moonlight_app"]:
                    profile["moonlight_app"] = assigned_target["moonlight_app"]
                if not expected_profile_name:
                    profile["expected_profile_name"] = f"vm-{target_vmid}"
                profile["default_mode"] = "MOONLIGHT" if profile["stream_host"] else ""
    return profile


def evaluate_endpoint_compliance(profile: dict[str, Any], report: dict[str, Any] | None) -> dict[str, Any]:
    managed = bool(profile.get("stream_host") or profile.get("assigned_target") or profile.get("expected_profile_name"))
    desired = {
        "stream_host": profile.get("stream_host", ""),
        "moonlight_app": profile.get("moonlight_app", ""),
        "network_mode": profile.get("network_mode", ""),
        "profile_name": profile.get("expected_profile_name", ""),
        "assigned_target": profile.get("assigned_target"),
    }
    if not isinstance(report, dict):
        return {
            "managed": managed,
            "endpoint_seen": False,
            "status": "pending" if managed else "unmanaged",
            "compliant": False,
            "drift_count": 0,
            "alert_count": 0,
            "drift": [],
            "alerts": [],
            "desired": desired,
        }

    summary = summarize_endpoint_report(report)
    drift: list[dict[str, Any]] = []
    alerts: list[dict[str, Any]] = []

    def compare(field: str, expected: str, actual: str, label: str) -> None:
        if not expected:
            return
        if str(expected).strip() == str(actual).strip():
            return
        drift.append({"field": field, "label": label, "expected": expected, "actual": actual})

    compare("stream_host", str(profile.get("stream_host", "")), str(summary.get("stream_host", "")), "Stream Host")
    compare("moonlight_app", str(profile.get("moonlight_app", "")), str(summary.get("moonlight_app", "")), "Moonlight App")
    compare("network_mode", str(profile.get("network_mode", "")), str(summary.get("network_mode", "")), "Network Mode")
    compare("profile_name", str(profile.get("expected_profile_name", "")), str(summary.get("profile_name", "")), "Profile Name")

    def alert(field: str, label: str, actual: str, expected: str = "1") -> None:
        if str(actual).strip() == str(expected).strip():
            return
        alerts.append({"field": field, "label": label, "expected": expected, "actual": actual})

    alert("moonlight_target_reachable", "Target Reachable", str(summary.get("moonlight_target_reachable", "")))
    alert("sunshine_api_reachable", "Sunshine API Reachable", str(summary.get("sunshine_api_reachable", "")))
    alert("runtime_binary_available", "Moonlight Runtime", str(summary.get("runtime_binary_available", "")))

    autologin_state = str(summary.get("autologin_state", "")).strip()
    if autologin_state and autologin_state != "active":
        alerts.append({"field": "autologin_state", "label": "Autologin", "expected": "active", "actual": autologin_state})

    status = "healthy"
    if drift:
        status = "drifted"
    elif alerts:
        status = "degraded"

    return {
        "managed": managed,
        "endpoint_seen": True,
        "status": status,
        "compliant": not drift,
        "drift_count": len(drift),
        "alert_count": len(alerts),
        "drift": drift,
        "alerts": alerts,
        "desired": desired,
    }


def build_vm_state(vm: VmSummary) -> dict[str, Any]:
    profile = build_profile(vm)
    report = load_endpoint_report(vm.node, vm.vmid)
    endpoint = summarize_endpoint_report(report or {})
    compliance = evaluate_endpoint_compliance(profile, report)
    last_action = summarize_action_result(load_action_result(vm.node, vm.vmid))
    pending_actions = load_action_queue(vm.node, vm.vmid)
    return {
        "profile": profile,
        "endpoint": endpoint,
        "compliance": compliance,
        "last_action": last_action,
        "pending_action_count": len(pending_actions),
    }


def build_health_payload() -> dict[str, Any]:
    downloads_status = load_json_file(DOWNLOADS_STATUS_FILE, {})
    vm_installers = load_json_file(VM_INSTALLERS_FILE, [])
    endpoint_reports = list_endpoint_reports()
    policies = list_policies()
    status_counts = {"healthy": 0, "degraded": 0, "drifted": 0, "pending": 0, "unmanaged": 0}
    for vm in list_vms():
        compliance = build_vm_state(vm)["compliance"]
        status = str(compliance.get("status", "unmanaged"))
        status_counts[status] = status_counts.get(status, 0) + 1
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
        "policy_count": len(policies),
        "endpoint_status_counts": status_counts,
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
        state = build_vm_state(vm)
        profile = state["profile"]
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
                "assigned_target": profile.get("assigned_target"),
                "applied_policy": profile.get("applied_policy"),
                "endpoint": state["endpoint"],
                "compliance": state["compliance"],
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

    def _read_binary_body(self, *, max_bytes: int) -> bytes:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > max_bytes:
            raise ValueError("invalid content length")
        return self.rfile.read(length)

    def _write_bytes(self, status: HTTPStatus, body: bytes, *, content_type: str, filename: str | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        if filename:
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _endpoint_summary_for_vmid(self, vmid: int) -> dict[str, Any] | None:
        for vm in list_vms():
            if vm.vmid == vmid:
                report = load_endpoint_report(vm.node, vm.vmid)
                if report is None:
                    return None
                return summarize_endpoint_report(report)
        return None

    def _vm_state_for_vmid(self, vmid: int) -> dict[str, Any] | None:
        vm = find_vm(vmid)
        if vm is None:
            return None
        return build_vm_state(vm)

    def _requester_identity(self) -> str:
        if self.client_address and self.client_address[0]:
            return self.client_address[0]
        return "unknown"

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

        if path.startswith("/api/v1/public/vms/") and path.endswith("/state"):
            vmid_text = path.split("/")[-2]
            if not vmid_text.isdigit():
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                return
            state = self._vm_state_for_vmid(int(vmid_text))
            if state is None:
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                return
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    **state,
                },
            )
            return

        if path.startswith("/api/v1/public/vms/") and path.endswith("/endpoint"):
            vmid_text = path.split("/")[-2]
            if not vmid_text.isdigit():
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                return
            state = self._vm_state_for_vmid(int(vmid_text))
            if state is None or not state["endpoint"].get("reported_at"):
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "endpoint not found"})
                return
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    **state,
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
        if path == "/api/v1/policies":
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "policies": list_policies(),
                },
            )
            return
        if path.startswith("/api/v1/policies/"):
            policy_name = path.rsplit("/", 1)[-1]
            policy = load_policy(policy_name)
            if policy is None:
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "policy not found"})
                return
            self._write_json(
                HTTPStatus.OK,
                {
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "policy": policy,
                },
            )
            return
        if path.startswith("/api/v1/support-bundles/") and path.endswith("/download"):
            bundle_id = path.split("/")[-2]
            metadata = find_support_bundle_metadata(bundle_id)
            if metadata is None:
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "support bundle not found"})
                return
            archive_path = Path(str(metadata.get("stored_path", "")))
            if not archive_path.is_file():
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "support bundle payload missing"})
                return
            self._write_bytes(
                HTTPStatus.OK,
                archive_path.read_bytes(),
                content_type="application/gzip",
                filename=str(metadata.get("stored_filename") or archive_path.name),
            )
            return
        if path.startswith("/api/v1/vms/"):
            if path.endswith("/policy"):
                vmid_text = path.split("/")[-2]
                if not vmid_text.isdigit():
                    self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                    return
                vm = find_vm(int(vmid_text))
                if vm is None:
                    self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                    return
                profile = build_profile(vm)
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "service": "beagle-control-plane",
                        "version": VERSION,
                        "generated_at": utcnow(),
                        "applied_policy": profile.get("applied_policy"),
                        "assignment_source": profile.get("assignment_source", ""),
                    },
                )
                return
            if path.endswith("/support-bundles"):
                vmid_text = path.split("/")[-2]
                if not vmid_text.isdigit():
                    self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                    return
                vm = find_vm(int(vmid_text))
                if vm is None:
                    self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                    return
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "service": "beagle-control-plane",
                        "version": VERSION,
                        "generated_at": utcnow(),
                        "support_bundles": list_support_bundle_metadata(node=vm.node, vmid=vm.vmid),
                    },
                )
                return
            if path.endswith("/state"):
                vmid_text = path.split("/")[-2]
                if not vmid_text.isdigit():
                    self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                    return
                state = self._vm_state_for_vmid(int(vmid_text))
                if state is None:
                    self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                    return
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "service": "beagle-control-plane",
                        "version": VERSION,
                        "generated_at": utcnow(),
                        **state,
                    },
                )
                return
            if path.endswith("/actions"):
                vmid_text = path.split("/")[-2]
                if not vmid_text.isdigit():
                    self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                    return
                vmid = int(vmid_text)
                state = self._vm_state_for_vmid(vmid)
                if state is None:
                    self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                    return
                vm = find_vm(vmid)
                assert vm is not None
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "service": "beagle-control-plane",
                        "version": VERSION,
                        "generated_at": utcnow(),
                        "pending_actions": load_action_queue(vm.node, vm.vmid),
                        "last_action": state["last_action"],
                    },
                )
                return
            if path.endswith("/endpoint"):
                vmid_text = path.split("/")[-2]
                if not vmid_text.isdigit():
                    self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                    return
                state = self._vm_state_for_vmid(int(vmid_text))
                if state is None or not state["endpoint"].get("reported_at"):
                    self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "endpoint not found"})
                    return
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "service": "beagle-control-plane",
                        "version": VERSION,
                        "generated_at": utcnow(),
                        **state,
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
        query = parse_qs(parsed.query or "")

        if path == "/api/v1/endpoints/actions/pull":
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
            actions = dequeue_vm_actions(node, vmid)
            self._write_json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "actions": actions,
                },
            )
            return

        if path == "/api/v1/endpoints/actions/result":
            if not self._is_endpoint_authenticated():
                self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
                return
            try:
                payload = self._read_json_body()
                vmid = int(payload.get("vmid"))
                node = str(payload.get("node", "")).strip()
                action_name = str(payload.get("action", "")).strip()
                action_id = str(payload.get("action_id", "")).strip()
                if not node or not action_name or not action_id:
                    raise ValueError("missing action result fields")
            except Exception as exc:
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"invalid payload: {exc}"})
                return

            payload["vmid"] = vmid
            payload["node"] = node
            payload["received_at"] = utcnow()
            store_action_result(node, vmid, payload)
            self._write_json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "last_action": summarize_action_result(payload),
                },
            )
            return

        if path == "/api/v1/policies":
            if not self._is_authenticated():
                self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
                return
            try:
                payload = self._read_json_body()
                policy = save_policy(payload)
            except Exception as exc:
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"invalid policy: {exc}"})
                return
            self._write_json(
                HTTPStatus.CREATED,
                {
                    "ok": True,
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "policy": policy,
                },
            )
            return

        if path == "/api/v1/endpoints/support-bundles/upload":
            if not self._is_endpoint_authenticated():
                self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
                return
            try:
                vmid_values = query.get("vmid", [])
                node_values = query.get("node", [])
                action_values = query.get("action_id", [])
                filename_values = query.get("filename", [])
                vmid = int(vmid_values[0])
                node = str(node_values[0]).strip()
                action_id = str(action_values[0]).strip()
                filename = str(filename_values[0]).strip() or "support-bundle.tar.gz"
                if not node or not action_id:
                    raise ValueError("missing upload fields")
                payload = self._read_binary_body(max_bytes=128 * 1024 * 1024)
            except Exception as exc:
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"invalid upload: {exc}"})
                return
            bundle = store_support_bundle(node, vmid, action_id, filename, payload)
            self._write_json(
                HTTPStatus.CREATED,
                {
                    "ok": True,
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "support_bundle": bundle,
                },
            )
            return

        if path.startswith("/api/v1/vms/") and path.endswith("/actions"):
            if not self._is_authenticated():
                self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
                return
            vmid_text = path.split("/")[-2]
            if not vmid_text.isdigit():
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "invalid vmid"})
                return
            vm = find_vm(int(vmid_text))
            if vm is None:
                self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "vm not found"})
                return
            try:
                payload = self._read_json_body()
                action_name = str(payload.get("action", "")).strip().lower()
                if action_name not in {"healthcheck", "recheckin", "restart-session", "restart-runtime", "support-bundle"}:
                    raise ValueError("unsupported action")
            except Exception as exc:
                self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"invalid payload: {exc}"})
                return
            queued = queue_vm_action(vm, action_name, self._requester_identity())
            self._write_json(
                HTTPStatus.ACCEPTED,
                {
                    "ok": True,
                    "service": "beagle-control-plane",
                    "version": VERSION,
                    "generated_at": utcnow(),
                    "queued_action": queued,
                },
            )
            return

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

    def do_PUT(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if not path.startswith("/api/v1/policies/"):
            self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
            return
        if not self._is_authenticated():
            self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
            return
        policy_name = path.rsplit("/", 1)[-1]
        try:
            payload = self._read_json_body()
            policy = save_policy(payload, policy_name=policy_name)
        except Exception as exc:
            self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"invalid policy: {exc}"})
            return
        self._write_json(
            HTTPStatus.OK,
            {
                "ok": True,
                "service": "beagle-control-plane",
                "version": VERSION,
                "generated_at": utcnow(),
                "policy": policy,
            },
        )

    def do_DELETE(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if not path.startswith("/api/v1/policies/"):
            self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
            return
        if not self._is_authenticated():
            self._write_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "unauthorized"})
            return
        policy_name = path.rsplit("/", 1)[-1]
        if not delete_policy(policy_name):
            self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "policy not found"})
            return
        self._write_json(
            HTTPStatus.OK,
            {
                "ok": True,
                "service": "beagle-control-plane",
                "version": VERSION,
                "generated_at": utcnow(),
                "deleted": policy_name,
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
