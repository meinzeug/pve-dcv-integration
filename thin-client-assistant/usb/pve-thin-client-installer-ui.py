#!/usr/bin/env python3
import json
import logging
import os
import shlex
import shutil
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

SCRIPT_DIR = Path(__file__).resolve().parent
LOCAL_INSTALLER = SCRIPT_DIR / "pve-thin-client-local-installer.sh"
FALLBACK_MENU = SCRIPT_DIR / "pve-thin-client-live-menu.sh"
ASSET_DIR = SCRIPT_DIR / "assets"
HOST = "127.0.0.1"
PORT = 37999
LOG_DIR = Path(os.environ.get("PVE_THIN_CLIENT_LOG_DIR", "/tmp/pve-thin-client-logs"))
LOG_FILE = LOG_DIR / "installer-ui.log"


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        filename=LOG_FILE,
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )


setup_logging()

HTML = """<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>PVE Thin Client Installer</title>
  <style>
    :root {
      --bg: #06111b;
      --panel: rgba(9, 23, 34, 0.84);
      --panel-soft: rgba(10, 27, 40, 0.66);
      --border: rgba(255, 255, 255, 0.12);
      --text: #f6efe5;
      --muted: #c8bba8;
      --accent: #ff8f3d;
      --accent-2: #43b7ff;
      --danger: #d1583d;
      --shadow: 0 24px 80px rgba(0, 0, 0, 0.35);
      font-family: "DejaVu Sans", "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--text);
      background:
        linear-gradient(135deg, rgba(4, 15, 24, 0.95), rgba(5, 12, 19, 0.78)),
        url("/assets/grub-background.jpg") center/cover fixed no-repeat;
      min-height: 100vh;
    }
    .shell {
      min-height: 100vh;
      padding: 36px;
      display: grid;
      grid-template-columns: 1.2fr 0.8fr;
      gap: 28px;
      backdrop-filter: blur(10px);
    }
    .hero, .panel {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 28px;
      box-shadow: var(--shadow);
      overflow: hidden;
    }
    .hero {
      display: grid;
      grid-template-rows: 300px auto;
    }
    .hero-top {
      position: relative;
      padding: 36px;
      background:
        linear-gradient(135deg, rgba(5, 14, 20, 0.22), rgba(255, 143, 61, 0.12)),
        url("/assets/grub-background.jpg") center/cover no-repeat;
    }
    .hero-top::after {
      content: "";
      position: absolute;
      inset: 0;
      background: linear-gradient(180deg, rgba(8, 18, 26, 0.12), rgba(8, 18, 26, 0.8));
    }
    .hero-copy {
      position: relative;
      z-index: 1;
      max-width: 720px;
    }
    .eyebrow {
      display: inline-flex;
      padding: 8px 14px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.15);
      text-transform: uppercase;
      letter-spacing: 0.14em;
      font-size: 12px;
      color: #e9ded0;
    }
    h1 {
      font-size: 52px;
      line-height: 0.95;
      margin: 18px 0 14px;
      max-width: 10ch;
    }
    .lead {
      font-size: 18px;
      line-height: 1.55;
      max-width: 58ch;
      color: #f2e7da;
    }
    .hero-bottom {
      padding: 28px 30px 30px;
      display: grid;
      gap: 18px;
      background:
        linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0)),
        var(--panel);
    }
    .meta-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 16px;
    }
    .meta-card {
      padding: 18px 20px;
      border-radius: 20px;
      background: var(--panel-soft);
      border: 1px solid var(--border);
    }
    .meta-card strong {
      display: block;
      font-size: 14px;
      color: var(--muted);
      margin-bottom: 8px;
    }
    .meta-card span {
      display: block;
      font-size: 24px;
      font-weight: 700;
    }
    .panel {
      display: grid;
      grid-template-rows: auto auto 1fr auto;
      padding: 28px;
      gap: 22px;
    }
    .panel h2, .hero-bottom h2 {
      font-size: 22px;
      margin: 0 0 6px;
    }
    .hint {
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
    }
    .mode-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
    }
    .mode-card {
      position: relative;
      min-height: 190px;
      padding: 18px;
      border-radius: 22px;
      border: 1px solid var(--border);
      cursor: pointer;
      overflow: hidden;
      transition: transform 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
      background: var(--panel-soft);
    }
    .mode-card:hover { transform: translateY(-3px); }
    .mode-card.selected {
      border-color: rgba(255, 143, 61, 0.9);
      box-shadow: 0 18px 48px rgba(255, 143, 61, 0.24);
    }
    .mode-card.unavailable {
      opacity: 0.36;
      filter: grayscale(0.8);
      cursor: not-allowed;
    }
    .mode-card::before {
      content: "";
      position: absolute;
      inset: 0;
      background:
        linear-gradient(180deg, rgba(7, 17, 27, 0.08), rgba(7, 17, 27, 0.88)),
        var(--image) center/cover no-repeat;
    }
    .mode-card > * { position: relative; z-index: 1; }
    .mode-card h3 { margin: 72px 0 8px; font-size: 22px; }
    .mode-card p { margin: 0; color: #e4d6c8; line-height: 1.45; }
    .pill {
      display: inline-flex;
      padding: 7px 11px;
      border-radius: 999px;
      background: rgba(255,255,255,0.14);
      border: 1px solid rgba(255,255,255,0.18);
      font-size: 11px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    label {
      display: block;
      font-size: 13px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 10px;
    }
    select {
      width: 100%;
      border-radius: 16px;
      border: 1px solid var(--border);
      background: rgba(0, 0, 0, 0.2);
      color: var(--text);
      padding: 16px 18px;
      font-size: 17px;
      outline: none;
    }
    .actions {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }
    button {
      appearance: none;
      border: 0;
      border-radius: 18px;
      padding: 15px 18px;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      transition: transform 0.16s ease, opacity 0.16s ease;
    }
    button:hover { transform: translateY(-1px); }
    button.primary {
      background: linear-gradient(135deg, var(--accent), #f25a32);
      color: #fff8f0;
    }
    button.secondary {
      background: rgba(255, 255, 255, 0.08);
      color: var(--text);
      border: 1px solid var(--border);
    }
    button.danger {
      background: rgba(209, 88, 61, 0.16);
      color: #ffd2c7;
      border: 1px solid rgba(209, 88, 61, 0.3);
    }
    .status {
      min-height: 26px;
      color: #eedec7;
    }
    .status.error { color: #ffb7a5; }
    footer {
      font-size: 12px;
      color: var(--muted);
      line-height: 1.5;
    }
    footer a {
      color: #9ed4ff;
      text-decoration: none;
    }
    @media (max-width: 1180px) {
      .shell { grid-template-columns: 1fr; }
      .mode-grid, .meta-grid, .actions { grid-template-columns: 1fr; }
      h1 { font-size: 40px; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <section class="hero">
      <div class="hero-top">
        <div class="hero-copy">
          <div class="eyebrow">PVE Thin Client USB</div>
          <h1>Installer media with a real front end.</h1>
          <p class="lead">
            Waehle nur Streaming-Modus und Zielplatte. VM-Zugangsdaten, Endpunkte und Profile kommen direkt aus dem gebuendelten Preset dieses Sticks.
          </p>
        </div>
      </div>
      <div class="hero-bottom">
        <div>
          <h2 id="vm-name">Lade VM-Profil...</h2>
          <p class="hint" id="vm-hint">Der USB-Stick liest gerade sein gebuendeltes Preset und die verfuegbaren Ziele ein.</p>
        </div>
        <div class="meta-grid">
          <div class="meta-card"><strong>Proxmox Host</strong><span id="meta-host">-</span></div>
          <div class="meta-card"><strong>Node / VMID</strong><span id="meta-node">-</span></div>
          <div class="meta-card"><strong>Modi bereit</strong><span id="meta-modes">-</span></div>
        </div>
      </div>
    </section>

    <aside class="panel">
      <div>
        <h2>Installationsziel</h2>
        <p class="hint">Moonlight, SPICE, noVNC oder DCV waehlen und direkt auf eine leere Zielplatte schreiben.</p>
      </div>

      <div class="mode-grid" id="mode-grid"></div>

      <div>
        <label for="disk-select">Zielplatte</label>
        <select id="disk-select"></select>
      </div>

      <div class="actions">
        <button class="primary" id="install-btn">Jetzt installieren</button>
        <button class="secondary" id="shell-btn">Shell</button>
        <button class="secondary" id="reload-btn">Neu laden</button>
        <button class="secondary" id="preset-btn">Preset anzeigen</button>
        <button class="secondary" id="reboot-btn">Neustart</button>
        <button class="danger" id="poweroff-btn">Ausschalten</button>
      </div>

      <div class="status" id="status"></div>

      <footer>
        Bilder fest eingebunden von Unsplash:
        <a href="https://unsplash.com/photos/QFUTkzaijA0" target="_blank" rel="noreferrer">Background</a>,
        <a href="https://unsplash.com/photos/oxwPGUnsfpE" target="_blank" rel="noreferrer">Server</a>,
        <a href="https://unsplash.com/photos/uqFPSwtCXqg" target="_blank" rel="noreferrer">Keyboard</a>.
      </footer>
    </aside>
  </div>

  <script>
    const MODE_META = {
      MOONLIGHT: {
        title: "Moonlight",
        image: "url('/assets/card-server.jpg')",
        description: "Sunshine-Streaming mit H.264, 1080p60 und Auto-Pairing gegen das vorkonfigurierte VM-Ziel."
      },
      SPICE: {
        title: "SPICE",
        image: "url('/assets/card-server.jpg')",
        description: "Direkter Viewer oder Proxmox-Ticket-Flow fuer klassische Remote-Console-Sessions."
      },
      NOVNC: {
        title: "noVNC",
        image: "url('/assets/card-keyboard.jpg')",
        description: "Browserbasierte Konsole fuer Hosts oder Setups ohne nativen Viewer."
      },
      DCV: {
        title: "DCV",
        image: "url('/assets/grub-background.jpg')",
        description: "Low-latency Streaming mit dem bereits vorkonfigurierten DCV-Ziel dieser VM."
      }
    };

    let state = null;
    let selectedMode = null;

    async function api(path, method = "GET", payload = null) {
      const response = await fetch(path, {
        method,
        headers: { "Content-Type": "application/json" },
        body: payload ? JSON.stringify(payload) : null
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || data.ok === false) {
        throw new Error(data.error || `HTTP ${response.status}`);
      }
      return data;
    }

    function setStatus(message, isError = false) {
      const node = document.getElementById("status");
      node.textContent = message || "";
      node.className = isError ? "status error" : "status";
    }

    function renderState() {
      const preset = state.preset || {};
      const debug = state.debug || {};
      const disks = state.disks || [];
      const modes = preset.available_modes || [];

      document.getElementById("vm-name").textContent = preset.vm_name || preset.profile_name || "Generisches Installationsmedium";
      document.getElementById("vm-hint").textContent =
        preset.preset_active
          ? "Dieses Medium ist bereits an eine VM gebunden. Weitere Zugangsdaten sind nicht noetig."
          : `Kein gebuendeltes VM-Preset gefunden. Quelle: ${debug.preset_source || "unbekannt"}, Datei: ${debug.preset_file || "n/a"}, Logs: ${state.log_dir || "/tmp/pve-thin-client-logs"}`;
      document.getElementById("meta-host").textContent = preset.proxmox_host || "n/a";
      document.getElementById("meta-node").textContent =
        preset.proxmox_node && preset.proxmox_vmid ? `${preset.proxmox_node} / ${preset.proxmox_vmid}` : "n/a";
      document.getElementById("meta-modes").textContent = modes.length ? modes.join("  ") : "keine";

      const grid = document.getElementById("mode-grid");
      grid.innerHTML = "";
      ["MOONLIGHT", "SPICE", "NOVNC", "DCV"].forEach((mode) => {
        const meta = MODE_META[mode];
        const available = modes.includes(mode);
        const card = document.createElement("button");
        card.type = "button";
        card.className = `mode-card${available ? "" : " unavailable"}${selectedMode === mode ? " selected" : ""}`;
        card.style.setProperty("--image", meta.image);
        card.innerHTML = `<span class="pill">${available ? "bereit" : "nicht konfiguriert"}</span><h3>${meta.title}</h3><p>${meta.description}</p>`;
        card.addEventListener("click", () => {
          if (!available) return;
          selectedMode = mode;
          renderState();
        });
        grid.appendChild(card);
      });

      if (!selectedMode || !modes.includes(selectedMode)) {
        selectedMode = preset.default_mode && modes.includes(preset.default_mode) ? preset.default_mode : (modes[0] || null);
      }

      const select = document.getElementById("disk-select");
      select.innerHTML = "";
      disks.forEach((disk) => {
        const option = document.createElement("option");
        option.value = disk.device;
        option.textContent = `${disk.device}  ${disk.model || "disk"}  ${disk.size || ""}  ${disk.transport || ""}`;
        select.appendChild(option);
      });
      if (!disks.length) {
        const option = document.createElement("option");
        option.textContent = "Keine Zielplatten gefunden";
        select.appendChild(option);
      }
    }

    async function loadState() {
      setStatus("Lade Installer-Zustand...");
      state = await api("/api/state");
      renderState();
      setStatus("");
    }

    async function postAction(action, payload = {}) {
      try {
        await api(`/api/${action}`, "POST", payload);
        return true;
      } catch (error) {
        setStatus(error.message, true);
        return false;
      }
    }

    document.getElementById("install-btn").addEventListener("click", async () => {
      const disk = document.getElementById("disk-select").value;
      if (!selectedMode) {
        setStatus("Kein Streaming-Modus verfuegbar.", true);
        return;
      }
      if (!disk || disk.startsWith("Keine Zielplatten")) {
        setStatus("Keine Zielplatte ausgewaehlt.", true);
        return;
      }
      setStatus("Installation wird in einem Terminalfenster gestartet...");
      if (await postAction("install", { mode: selectedMode, disk })) {
        setStatus(`Installationslauf fuer ${selectedMode} auf ${disk} wurde gestartet.`);
      }
    });

    document.getElementById("shell-btn").addEventListener("click", () => postAction("shell"));
    document.getElementById("reload-btn").addEventListener("click", () => loadState().catch((error) => setStatus(error.message, true)));
    document.getElementById("preset-btn").addEventListener("click", () => {
      const preset = state?.preset || {};
      const debug = state?.debug || {};
      const lines = [
        `VM: ${preset.vm_name || preset.profile_name || "n/a"}`,
        `Host: ${preset.proxmox_host || "n/a"}`,
        `Node: ${preset.proxmox_node || "n/a"}`,
        `VMID: ${preset.proxmox_vmid || "n/a"}`,
        `Modi: ${(preset.available_modes || []).join(" ") || "keine"}`,
        `Default: ${preset.default_mode || "n/a"}`,
        `Moonlight Host: ${preset.moonlight_host || "n/a"}`,
        `Moonlight App: ${preset.moonlight_app || "n/a"}`,
        `Preset Quelle: ${debug.preset_source || "n/a"}`,
        `Preset Datei: ${debug.preset_file || "n/a"}`,
        `Cache Datei: ${debug.cached_preset_file || "n/a"}`,
        `Logs: ${state?.log_dir || "/tmp/pve-thin-client-logs"}`
      ];
      window.alert(lines.join("\\n"));
    });
    document.getElementById("reboot-btn").addEventListener("click", () => postAction("reboot"));
    document.getElementById("poweroff-btn").addEventListener("click", () => postAction("poweroff"));

    loadState().catch((error) => setStatus(error.message, true));
  </script>
</body>
</html>
"""


def run_json_command(*args):
    command = list(args)
    if command and Path(command[0]) == LOCAL_INSTALLER and os.geteuid() != 0 and shutil.which("sudo"):
        command = [
            "sudo",
            "-n",
            "env",
            f"PVE_THIN_CLIENT_LOG_DIR={LOG_DIR}",
            f"PVE_THIN_CLIENT_LOG_SESSION_ID={os.environ.get('PVE_THIN_CLIENT_LOG_SESSION_ID', LOG_DIR.name)}",
            *command,
        ]
    logging.info("run_json_command: %s", " ".join(shlex.quote(part) for part in command))
    result = subprocess.run(command, capture_output=True, text=True)
    logging.info(
        "command result rc=%s stdout=%s stderr=%s",
        result.returncode,
        (result.stdout or "").strip(),
        (result.stderr or "").strip(),
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "command failed")
    return json.loads(result.stdout or "{}")


def build_state():
    preset = {}
    debug = {}
    for attempt in range(1, 16):
        try:
            if shutil.which("sudo") and os.geteuid() != 0:
                subprocess.run(
                    [
                        "sudo",
                        "-n",
                        "env",
                        f"PVE_THIN_CLIENT_LOG_DIR={LOG_DIR}",
                        f"PVE_THIN_CLIENT_LOG_SESSION_ID={os.environ.get('PVE_THIN_CLIENT_LOG_SESSION_ID', LOG_DIR.name)}",
                        str(LOCAL_INSTALLER),
                        "--cache-bundled-preset",
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
        except Exception as exc:
            logging.warning("cache-bundled-preset warmup failed on attempt %s: %s", attempt, exc)
        preset = run_json_command(str(LOCAL_INSTALLER), "--print-preset-json")
        debug = run_json_command(str(LOCAL_INSTALLER), "--print-debug-json")
        if preset.get("preset_active"):
            logging.info("preset active after attempt %s: %s", attempt, preset)
            break
        logging.warning("preset missing on attempt %s: %s", attempt, debug)
        if attempt < 15:
            time.sleep(1)
    disks = run_json_command(str(LOCAL_INSTALLER), "--list-targets-json")
    state = {"ok": True, "preset": preset, "debug": debug, "disks": disks, "log_dir": str(LOG_DIR)}
    logging.info("build_state: %s", state)
    return state


def spawn_terminal(command, title):
    xterm = shutil.which("xterm")
    if not xterm:
        raise RuntimeError("xterm is not installed in the live environment")

    wrapped = " ".join(shlex.quote(part) for part in command)
    shell_cmd = f"{wrapped}; code=$?; printf '\\n\\nExit code: %s\\nPress ENTER to close.' \"$code\"; read _"
    subprocess.Popen(
        [
            xterm,
            "-title",
            title,
            "-fa",
            "DejaVu Sans Mono",
            "-fs",
            "11",
            "-bg",
            "#07111b",
            "-fg",
            "#f5eadf",
            "-geometry",
            "136x40",
            "-e",
            "bash",
            "-lc",
            shell_cmd,
        ]
    )
    logging.info("spawned terminal %s with command %s", title, command)


def install_target(mode, disk):
    if mode not in {"MOONLIGHT", "SPICE", "NOVNC", "DCV"}:
        raise RuntimeError(f"unsupported mode: {mode}")
    if not disk.startswith("/dev/"):
        raise RuntimeError(f"invalid disk: {disk}")

    spawn_terminal(
        [
            "sudo",
            str(LOCAL_INSTALLER),
            "--mode",
            mode,
            "--target-disk",
            disk,
            "--yes",
        ],
        f"PVE Thin Client Install {mode}",
    )
    logging.info("requested install mode=%s disk=%s", mode, disk)


def launch_shell():
    spawn_terminal(["bash", "--login"], "PVE Thin Client Shell")
    logging.info("requested shell")


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, payload, status=HTTPStatus.OK):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path):
        if not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content_type = "image/jpeg"
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/":
            body = HTML.encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if parsed.path == "/api/state":
            try:
                self._send_json(build_state())
            except Exception as exc:  # noqa: BLE001
                logging.exception("failed to build UI state")
                self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        if parsed.path.startswith("/assets/"):
            asset_name = unquote(parsed.path.removeprefix("/assets/"))
            self._send_file(ASSET_DIR / asset_name)
            return

        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        payload = json.loads(raw.decode("utf-8") or "{}")

        try:
            if parsed.path == "/api/install":
                install_target(str(payload.get("mode", "")).upper(), str(payload.get("disk", "")))
                self._send_json({"ok": True})
                return
            if parsed.path == "/api/shell":
                launch_shell()
                self._send_json({"ok": True})
                return
            if parsed.path == "/api/reboot":
                subprocess.Popen(["sudo", "reboot"])
                self._send_json({"ok": True})
                return
            if parsed.path == "/api/poweroff":
                subprocess.Popen(["sudo", "poweroff"])
                self._send_json({"ok": True})
                return
            self.send_error(HTTPStatus.NOT_FOUND)
        except Exception as exc:  # noqa: BLE001
            logging.exception("POST handler failed for %s", parsed.path)
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)

    def log_message(self, _format, *_args):
        return


def fallback_to_tui():
    logging.warning("falling back to TUI menu")
    os.execv(str(FALLBACK_MENU), [str(FALLBACK_MENU)])


def main():
    if not LOCAL_INSTALLER.is_file() or not FALLBACK_MENU.is_file():
        raise SystemExit("Installer UI dependencies are missing.")

    logging.info("starting installer UI display=%s", os.environ.get("DISPLAY", ""))
    browser = shutil.which("chromium") or shutil.which("chromium-browser")
    if not browser or not os.environ.get("DISPLAY"):
        fallback_to_tui()

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    try:
        subprocess.run(
            [
                browser,
                f"--app=http://{HOST}:{PORT}/",
                "--incognito",
                "--no-first-run",
                "--disable-session-crashed-bubble",
                "--disable-infobars",
                "--check-for-update-interval=31536000",
                "--window-size=1440,900",
            ],
            check=False,
        )
    finally:
        logging.info("shutting down installer UI")
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
