(() => {
  const PRODUCT_LABEL = "Beagle OS";
  const MENU_TEXT = "Konsole";
  const BUTTON_MARKER = "data-beagle-integration";
  const STYLE_ID = "beagle-os-extension-style";
  const OVERLAY_ID = "beagle-os-extension-overlay";

  function defaultUsbInstallerUrl() {
    return "https://{host}:8443/beagle-downloads/pve-thin-client-usb-installer-vm-{vmid}.sh";
  }

  function defaultControlPlaneHealthUrl() {
    return "https://{host}:8443/beagle-api/api/v1/health";
  }

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function decodeHash() {
    try {
      return decodeURIComponent(window.location.hash || "");
    } catch {
      return window.location.hash || "";
    }
  }

  function isVmView() {
    return /qemu\/(\d+)/i.test(decodeHash());
  }

  async function parseVmContext() {
    const hash = decodeHash();
    const vmidMatch = hash.match(/qemu\/(\d+)/i);
    let nodeMatch = hash.match(/[?&]node=([a-zA-Z0-9._-]+)/i);

    const vmid = vmidMatch ? Number(vmidMatch[1]) : null;
    let node = nodeMatch ? nodeMatch[1] : null;

    if (!vmid) return null;

    if (!node) {
      try {
        const res = await fetch("/api2/json/cluster/resources?type=vm", { credentials: "same-origin" });
        if (res.ok) {
          const payload = await res.json();
          const vm = (payload?.data || []).find((item) => item.vmid === vmid && item.type === "qemu");
          if (vm?.node) node = vm.node;
        }
      } catch {
        // best effort
      }
    }

    if (!node) {
      const guessed = hash.match(/node[:=]([a-zA-Z0-9._-]+)/i);
      if (guessed) node = guessed[1];
    }

    if (!node) return null;
    return { node, vmid };
  }

  async function getOptions() {
    return new Promise((resolve) => {
      chrome.storage.sync.get(
        {
          usbInstallerUrl: defaultUsbInstallerUrl(),
          controlPlaneHealthUrl: defaultControlPlaneHealthUrl()
        },
        (data) => resolve(data)
      );
    });
  }

  function fillTemplate(template, values) {
    return String(template || "")
      .replaceAll("{node}", values.node || "")
      .replaceAll("{vmid}", String(values.vmid || ""))
      .replaceAll("{host}", values.host || "");
  }

  async function resolveUsbInstallerUrl(ctx) {
    const options = await getOptions();
    return fillTemplate(options.usbInstallerUrl || defaultUsbInstallerUrl(), {
      node: ctx?.node || "",
      vmid: ctx?.vmid || "",
      host: window.location.hostname
    });
  }

  async function resolveControlPlaneHealthUrl() {
    const options = await getOptions();
    return fillTemplate(options.controlPlaneHealthUrl || defaultControlPlaneHealthUrl(), {
      host: window.location.hostname
    });
  }

  function managerUrlFromHealthUrl(healthUrl) {
    return String(healthUrl || "").replace(/\/api\/v1\/health\/?$/, "");
  }

  function ensureStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #${OVERLAY_ID} { position: fixed; inset: 0; background: rgba(15, 23, 42, 0.58); z-index: 2147483647; display: flex; align-items: center; justify-content: center; padding: 24px; }
      #${OVERLAY_ID} .beagle-modal { width: min(980px, 100%); max-height: calc(100vh - 48px); overflow: auto; background: linear-gradient(180deg, #fff8ef 0%, #ffffff 100%); border: 1px solid #fed7aa; border-radius: 22px; box-shadow: 0 30px 70px rgba(15, 23, 42, 0.25); color: #111827; }
      #${OVERLAY_ID} .beagle-header { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; padding: 24px 28px 18px; background: radial-gradient(circle at top right, rgba(59,130,246,0.12), transparent 30%), radial-gradient(circle at top left, rgba(249,115,22,0.18), transparent 36%); border-bottom: 1px solid #fdba74; }
      #${OVERLAY_ID} .beagle-title { font: 700 28px/1.1 'Trebuchet MS', 'Segoe UI', sans-serif; margin: 0 0 6px; }
      #${OVERLAY_ID} .beagle-subtitle { margin: 0; color: #7c2d12; font-size: 14px; }
      #${OVERLAY_ID} .beagle-close { border: 0; background: #111827; color: #fff; border-radius: 999px; width: 36px; height: 36px; cursor: pointer; font-size: 20px; line-height: 36px; }
      #${OVERLAY_ID} .beagle-body { padding: 22px 28px 28px; display: grid; gap: 18px; }
      #${OVERLAY_ID} .beagle-banner { padding: 12px 14px; border-radius: 14px; font-weight: 600; }
      #${OVERLAY_ID} .beagle-banner.info { background: #eff6ff; color: #1d4ed8; border: 1px solid #bfdbfe; }
      #${OVERLAY_ID} .beagle-banner.warn { background: #fff7ed; color: #9a3412; border: 1px solid #fdba74; }
      #${OVERLAY_ID} .beagle-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; }
      #${OVERLAY_ID} .beagle-card { background: rgba(255,255,255,0.88); border: 1px solid #e5e7eb; border-radius: 16px; padding: 16px; }
      #${OVERLAY_ID} .beagle-card h3 { margin: 0 0 12px; font: 700 15px/1.2 'Trebuchet MS', 'Segoe UI', sans-serif; color: #111827; }
      #${OVERLAY_ID} .beagle-kv { display: grid; gap: 8px; }
      #${OVERLAY_ID} .beagle-kv-row { display: grid; gap: 4px; }
      #${OVERLAY_ID} .beagle-kv-row strong { color: #9a3412; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
      #${OVERLAY_ID} .beagle-kv-row span { word-break: break-word; }
      #${OVERLAY_ID} .beagle-actions { display: flex; flex-wrap: wrap; gap: 10px; }
      #${OVERLAY_ID} .beagle-btn { border: 0; border-radius: 999px; padding: 10px 16px; font-weight: 700; cursor: pointer; }
      #${OVERLAY_ID} .beagle-btn.primary { background: linear-gradient(135deg, #f97316, #0ea5e9); color: #fff; }
      #${OVERLAY_ID} .beagle-btn.secondary { background: #fff; color: #111827; border: 1px solid #d1d5db; }
      #${OVERLAY_ID} .beagle-code { width: 100%; min-height: 180px; resize: vertical; border-radius: 14px; border: 1px solid #d1d5db; padding: 12px; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #0f172a; color: #e2e8f0; }
      #${OVERLAY_ID} .beagle-notes { margin: 0; padding-left: 18px; }
      #${OVERLAY_ID} .beagle-muted { color: #6b7280; }
    `;
    document.head.appendChild(style);
  }

  function removeOverlay() {
    document.getElementById(OVERLAY_ID)?.remove();
  }

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function maskSecret(value) {
    if (!value) return "nicht gesetzt";
    if (value.length <= 4) return "****";
    return `${value.slice(0, 2)}***${value.slice(-2)}`;
  }

  async function copyText(text, message) {
    const value = String(text || "");
    if (!value) return;
    try {
      await navigator.clipboard.writeText(value);
      window.alert(message || "In die Zwischenablage kopiert.");
    } catch {
      const textarea = document.createElement("textarea");
      textarea.value = value;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.focus();
      textarea.select();
      document.execCommand("copy");
      textarea.remove();
      window.alert(message || "In die Zwischenablage kopiert.");
    }
  }

  function parseDescriptionMeta(description) {
    const meta = {};
    String(description || "")
      .replace(/\\r\\n/g, "\n")
      .replace(/\\n/g, "\n")
      .split("\n")
      .forEach((rawLine) => {
        const line = rawLine.trim();
        const index = line.indexOf(":");
        if (index <= 0) return;
        const key = line.slice(0, index).trim().toLowerCase();
        const value = line.slice(index + 1).trim();
        if (key && !(key in meta)) meta[key] = value;
      });
    return meta;
  }

  async function apiGetJson(path) {
    const response = await fetch(path, { credentials: "same-origin" });
    if (!response.ok) {
      throw new Error(`API request failed: ${response.status} ${response.statusText}`);
    }
    const payload = await response.json();
    return payload?.data ?? payload;
  }

  function firstGuestIpv4(interfaces) {
    for (const iface of Array.isArray(interfaces) ? interfaces : []) {
      for (const address of Array.isArray(iface?.["ip-addresses"]) ? iface["ip-addresses"] : []) {
        const ip = address?.["ip-address"] || "";
        if (address?.["ip-address-type"] !== "ipv4") continue;
        if (!ip || /^127\./.test(ip) || /^169\.254\./.test(ip)) continue;
        return ip;
      }
    }
    return "";
  }

  function buildEndpointEnv(profile) {
    const endpointProfileName = profile.expectedProfileName || `vm-${profile.vmid}`;
    return [
      'PVE_THIN_CLIENT_MODE="MOONLIGHT"',
      `PVE_THIN_CLIENT_PROFILE_NAME="${endpointProfileName}"`,
      'PVE_THIN_CLIENT_AUTOSTART="1"',
      `PVE_THIN_CLIENT_PROXMOX_HOST="${profile.proxmoxHost || window.location.hostname}"`,
      'PVE_THIN_CLIENT_PROXMOX_PORT="8006"',
      `PVE_THIN_CLIENT_PROXMOX_NODE="${profile.node || ""}"`,
      `PVE_THIN_CLIENT_PROXMOX_VMID="${String(profile.vmid || "")}"`,
      `PVE_THIN_CLIENT_BEAGLE_MANAGER_URL="${profile.managerUrl || ""}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_HOST="${profile.streamHost || ""}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_APP="${profile.app || "Desktop"}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_RESOLUTION="${profile.resolution || "auto"}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_FPS="${profile.fps || "60"}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_BITRATE="${profile.bitrate || "20000"}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_VIDEO_CODEC="${profile.codec || "H.264"}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_VIDEO_DECODER="${profile.decoder || "auto"}"`,
      `PVE_THIN_CLIENT_MOONLIGHT_AUDIO_CONFIG="${profile.audio || "stereo"}"`,
      `PVE_THIN_CLIENT_SUNSHINE_API_URL="${profile.sunshineApiUrl || ""}"`,
      `PVE_THIN_CLIENT_SUNSHINE_USERNAME="${profile.sunshineUsername || ""}"`,
      `PVE_THIN_CLIENT_SUNSHINE_PASSWORD="${profile.sunshinePassword || ""}"`,
      `PVE_THIN_CLIENT_SUNSHINE_PIN="${profile.sunshinePin || ""}"`
    ].join("\n") + "\n";
  }

  function buildNotes(profile) {
    const notes = [];
    if (!profile.streamHost) notes.push("Kein Moonlight-/Sunshine-Ziel in der VM-Metadatenbeschreibung gefunden.");
    if (!profile.sunshineApiUrl) notes.push("Keine Sunshine API URL gesetzt. Pairing und Healthchecks koennen nicht vorab validiert werden.");
    if (!profile.sunshinePassword) notes.push("Kein Sunshine-Passwort hinterlegt. Fuer direkte API-Aktionen ist dann ein vorregistriertes Zertifikat oder manuelles Pairing noetig.");
    if (!profile.guestIp) notes.push("Keine Guest-Agent-IPv4 erkannt. Beagle kann dann nur mit Metadaten arbeiten.");
    if (!notes.length) notes.push("VM-Profil ist vollstaendig genug fuer einen vorkonfigurierten Beagle-Endpoint mit Moonlight-Autostart.");
    if (profile.assignedTarget) notes.push(`Endpoint ist auf Ziel-VM ${profile.assignedTarget.name} (#${profile.assignedTarget.vmid}) zugewiesen.`);
    if (profile.appliedPolicy?.name) notes.push(`Manager-Policy aktiv: ${profile.appliedPolicy.name}.`);
    if (profile.compliance?.status === "drifted") notes.push(`Endpoint driftet vom gewuenschten Profil ab (${String(profile.compliance.drift_count || 0)} Abweichungen).`);
    if (profile.compliance?.status === "degraded") notes.push(`Endpoint ist konfigurationsgleich, aber betrieblich degradiert (${String(profile.compliance.alert_count || 0)} Warnungen).`);
    if (Number(profile.pendingActionCount || 0) > 0) notes.push(`Fuer diesen Endpoint warten ${String(profile.pendingActionCount)} Beagle-Aktion(en) auf Ausfuehrung.`);
    if (profile.lastAction?.action) notes.push(`Letzte Endpoint-Aktion: ${profile.lastAction.action} (${formatActionState(profile.lastAction.ok)}).`);
    if (profile.lastAction?.stored_artifact_path) notes.push("Diagnoseartefakt ist zentral auf dem Beagle-Manager gespeichert.");
    return notes;
  }

  function formatActionState(ok) {
    if (ok === true) return "ok";
    if (ok === false) return "error";
    return "pending";
  }

  async function resolveVmProfile(ctx) {
    const [config, resources, guestInterfaces, installerUrl, controlPlaneHealthUrl, endpointPayload] = await Promise.all([
      apiGetJson(`/api2/json/nodes/${encodeURIComponent(ctx.node)}/qemu/${encodeURIComponent(ctx.vmid)}/config`),
      apiGetJson("/api2/json/cluster/resources?type=vm").catch(() => []),
      apiGetJson(`/api2/json/nodes/${encodeURIComponent(ctx.node)}/qemu/${encodeURIComponent(ctx.vmid)}/agent/network-get-interfaces`).catch(() => []),
      resolveUsbInstallerUrl(ctx),
      resolveControlPlaneHealthUrl(),
      fetch(`/beagle-api/api/v1/public/vms/${encodeURIComponent(ctx.vmid)}/state`, { credentials: "same-origin" })
        .then((response) => (response.ok ? response.json() : null))
        .catch(() => null)
    ]);

    const resource = (Array.isArray(resources) ? resources : []).find(
      (item) => item && item.type === "qemu" && Number(item.vmid) === Number(ctx.vmid)
    ) || {};
    const meta = parseDescriptionMeta(config?.description || "");
    const guestIp = firstGuestIpv4(guestInterfaces);
    const controlPlaneProfile = endpointPayload?.profile || null;
    const streamHost = controlPlaneProfile?.stream_host || meta["moonlight-host"] || meta["sunshine-ip"] || meta["sunshine-host"] || guestIp || "";
    const sunshineApiUrl = controlPlaneProfile?.sunshine_api_url || meta["sunshine-api-url"] || (streamHost ? `https://${streamHost}:47990` : "");
    const profile = {
      vmid: Number(ctx.vmid),
      node: ctx.node,
      name: config?.name || resource?.name || `vm-${ctx.vmid}`,
      status: resource?.status || "unknown",
      guestIp,
      streamHost,
      sunshineApiUrl,
      sunshineUsername: controlPlaneProfile?.sunshine_username || meta["sunshine-user"] || "",
      sunshinePassword: meta["sunshine-password"] || "",
      sunshinePin: meta["sunshine-pin"] || String(ctx.vmid % 10000).padStart(4, "0"),
      app: controlPlaneProfile?.moonlight_app || meta["moonlight-app"] || meta["sunshine-app"] || "Desktop",
      resolution: controlPlaneProfile?.moonlight_resolution || meta["moonlight-resolution"] || "auto",
      fps: controlPlaneProfile?.moonlight_fps || meta["moonlight-fps"] || "60",
      bitrate: controlPlaneProfile?.moonlight_bitrate || meta["moonlight-bitrate"] || "20000",
      codec: controlPlaneProfile?.moonlight_video_codec || meta["moonlight-video-codec"] || "H.264",
      decoder: controlPlaneProfile?.moonlight_video_decoder || meta["moonlight-video-decoder"] || "auto",
      audio: controlPlaneProfile?.moonlight_audio_config || meta["moonlight-audio-config"] || "stereo",
      proxmoxHost: meta["proxmox-host"] || window.location.hostname,
      installerUrl,
      controlPlaneHealthUrl,
      managerUrl: managerUrlFromHealthUrl(controlPlaneHealthUrl),
      endpointSummary: endpointPayload?.endpoint || null,
      compliance: endpointPayload?.compliance || null,
      lastAction: endpointPayload?.last_action || null,
      pendingActionCount: endpointPayload?.pending_action_count || 0,
      assignedTarget: controlPlaneProfile?.assigned_target || null,
      assignmentSource: controlPlaneProfile?.assignment_source || "",
      appliedPolicy: controlPlaneProfile?.applied_policy || null,
      expectedProfileName: controlPlaneProfile?.expected_profile_name || ""
    };
    profile.notes = buildNotes(profile);
    if (!profile.endpointSummary) profile.notes.push("Endpoint hat noch keinen Check-in an die Beagle Control Plane geliefert.");
    profile.endpointEnv = buildEndpointEnv(profile);
    return profile;
  }

  function kvRow(label, value) {
    return `<div class="beagle-kv-row"><strong>${label}</strong><span>${value || '<span class="beagle-muted">nicht gesetzt</span>'}</span></div>`;
  }

  function renderProfileModal(profile) {
    const overlay = document.createElement("div");
    const notesHtml = profile.notes.map((note) => `<li>${escapeHtml(note)}</li>`).join("");
    const profileJson = JSON.stringify(
      {
        vmid: profile.vmid,
        node: profile.node,
        name: profile.name,
        status: profile.status,
        stream_host: profile.streamHost,
        sunshine_api_url: profile.sunshineApiUrl,
        sunshine_username: profile.sunshineUsername,
        sunshine_password_configured: Boolean(profile.sunshinePassword),
        sunshine_pin: profile.sunshinePin,
        moonlight_app: profile.app,
        moonlight_resolution: profile.resolution,
        moonlight_fps: profile.fps,
        moonlight_bitrate: profile.bitrate,
        moonlight_video_codec: profile.codec,
        moonlight_video_decoder: profile.decoder,
        moonlight_audio_config: profile.audio,
        manager_url: profile.managerUrl,
        installer_url: profile.installerUrl,
        control_plane_health_url: profile.controlPlaneHealthUrl,
        assigned_target: profile.assignedTarget,
        assignment_source: profile.assignmentSource,
        applied_policy: profile.appliedPolicy,
        expected_profile_name: profile.expectedProfileName,
        endpoint_summary: profile.endpointSummary,
        compliance: profile.compliance,
        last_action: profile.lastAction,
        pending_action_count: profile.pendingActionCount
      },
      null,
      2
    );

    overlay.id = OVERLAY_ID;
    overlay.innerHTML = `
      <div class="beagle-modal" role="dialog" aria-modal="true" aria-label="Beagle OS Profil">
        <div class="beagle-header">
          <div>
            <h2 class="beagle-title">Beagle Profil fuer VM ${escapeHtml(profile.name)} (#${String(profile.vmid)})</h2>
            <p class="beagle-subtitle">Moonlight-Endpunkt, Sunshine-Ziel und Proxmox-Bereitstellung in einer Sicht.</p>
          </div>
          <button type="button" class="beagle-close" aria-label="Schliessen">×</button>
        </div>
        <div class="beagle-body">
          <div class="beagle-banner ${profile.streamHost ? "info" : "warn"}">${escapeHtml(profile.streamHost ? `Streaming-Ziel erkannt: ${profile.streamHost}` : "Streaming-Ziel fehlt in den VM-Metadaten.")}</div>
          <div class="beagle-actions">
            <button type="button" class="beagle-btn primary" data-beagle-action="download">USB Installer</button>
            <button type="button" class="beagle-btn secondary" data-beagle-action="copy-json">Profil JSON kopieren</button>
            <button type="button" class="beagle-btn secondary" data-beagle-action="copy-env">Endpoint Env kopieren</button>
            <button type="button" class="beagle-btn secondary" data-beagle-action="open-sunshine">Sunshine Web UI</button>
            <button type="button" class="beagle-btn secondary" data-beagle-action="open-health">Control Plane Status</button>
          </div>
          <div class="beagle-grid">
            <section class="beagle-card"><h3>VM</h3><div class="beagle-kv">
              ${kvRow("Name", escapeHtml(profile.name))}
              ${kvRow("VMID", escapeHtml(String(profile.vmid)))}
              ${kvRow("Node", escapeHtml(profile.node))}
              ${kvRow("Status", escapeHtml(profile.status))}
              ${kvRow("Guest IP", escapeHtml(profile.guestIp || ""))}
            </div></section>
            <section class="beagle-card"><h3>Streaming</h3><div class="beagle-kv">
              ${kvRow("Stream Host", escapeHtml(profile.streamHost || ""))}
              ${kvRow("Sunshine API", escapeHtml(profile.sunshineApiUrl || ""))}
              ${kvRow("App", escapeHtml(profile.app))}
              ${kvRow("Manager", escapeHtml(profile.managerUrl || ""))}
              ${kvRow("Assigned Target", escapeHtml(profile.assignedTarget ? `${profile.assignedTarget.name} (#${profile.assignedTarget.vmid})` : ""))}
              ${kvRow("Assignment Source", escapeHtml(profile.assignmentSource || ""))}
              ${kvRow("Applied Policy", escapeHtml(profile.appliedPolicy?.name || ""))}
              ${kvRow("Installer", escapeHtml(profile.installerUrl))}
              ${kvRow("Health", escapeHtml(profile.controlPlaneHealthUrl))}
            </div></section>
            <section class="beagle-card"><h3>Endpoint Defaults</h3><div class="beagle-kv">
              ${kvRow("Resolution", escapeHtml(profile.resolution))}
              ${kvRow("FPS", escapeHtml(profile.fps))}
              ${kvRow("Bitrate", escapeHtml(profile.bitrate))}
              ${kvRow("Codec", escapeHtml(profile.codec))}
              ${kvRow("Decoder", escapeHtml(profile.decoder))}
              ${kvRow("Audio", escapeHtml(profile.audio))}
            </div></section>
            <section class="beagle-card"><h3>Pairing</h3><div class="beagle-kv">
              ${kvRow("Sunshine User", escapeHtml(profile.sunshineUsername || ""))}
              ${kvRow("Sunshine Password", escapeHtml(maskSecret(profile.sunshinePassword)))}
              ${kvRow("Pairing PIN", escapeHtml(profile.sunshinePin || ""))}
            </div></section>
            <section class="beagle-card"><h3>Endpoint State</h3><div class="beagle-kv">
              ${kvRow("Compliance", escapeHtml(profile.compliance?.status || ""))}
              ${kvRow("Drift Count", escapeHtml(String(profile.compliance?.drift_count || 0)))}
              ${kvRow("Alert Count", escapeHtml(String(profile.compliance?.alert_count || 0)))}
              ${kvRow("Pending Actions", escapeHtml(String(profile.pendingActionCount || 0)))}
              ${kvRow("Last Seen", escapeHtml(profile.endpointSummary?.reported_at || ""))}
              ${kvRow("Target Reachable", escapeHtml(profile.endpointSummary?.moonlight_target_reachable || ""))}
              ${kvRow("Sunshine Reachable", escapeHtml(profile.endpointSummary?.sunshine_api_reachable || ""))}
              ${kvRow("Prepare", escapeHtml(profile.endpointSummary?.prepare_state || ""))}
              ${kvRow("Last Launch", escapeHtml(profile.endpointSummary?.last_launch_mode || ""))}
              ${kvRow("Launch Target", escapeHtml(profile.endpointSummary?.last_launch_target || ""))}
              ${kvRow("Last Action", escapeHtml(profile.lastAction?.action || ""))}
              ${kvRow("Action Result", escapeHtml(formatActionState(profile.lastAction?.ok)))}
              ${kvRow("Action Time", escapeHtml(profile.lastAction?.completed_at || ""))}
              ${kvRow("Action Message", escapeHtml(profile.lastAction?.message || ""))}
              ${kvRow("Stored Artifact", escapeHtml(profile.lastAction?.stored_artifact_path || ""))}
              ${kvRow("Artifact Size", escapeHtml(String(profile.lastAction?.stored_artifact_size || 0)))}
            </div></section>
          </div>
          <section class="beagle-card"><h3>Operator Notes</h3><ul class="beagle-notes">${notesHtml}</ul></section>
          <section class="beagle-card"><h3>Beagle Endpoint Env</h3><textarea class="beagle-code" readonly>${escapeHtml(profile.endpointEnv)}</textarea></section>
          <section class="beagle-card"><h3>Profile JSON</h3><textarea class="beagle-code" readonly>${escapeHtml(profileJson)}</textarea></section>
        </div>
      </div>
    `;

    overlay.addEventListener("click", async (event) => {
      if (event.target === overlay || event.target.closest(".beagle-close")) {
        removeOverlay();
        return;
      }
      if (!(event.target instanceof HTMLElement)) return;
      switch (event.target.getAttribute("data-beagle-action")) {
        case "download":
          window.open(profile.installerUrl, "_blank", "noopener,noreferrer");
          break;
        case "copy-json":
          await copyText(profileJson, "Beagle Profil als JSON kopiert.");
          break;
        case "copy-env":
          await copyText(profile.endpointEnv, "Beagle Endpoint-Umgebung kopiert.");
          break;
        case "open-sunshine":
          if (profile.sunshineApiUrl) {
            window.open(profile.sunshineApiUrl, "_blank", "noopener,noreferrer");
          }
          break;
        case "open-health":
          window.open(profile.controlPlaneHealthUrl, "_blank", "noopener,noreferrer");
          break;
        default:
          break;
      }
    });

    document.body.appendChild(overlay);
  }

  async function showProfileModal() {
    const ctx = await parseVmContext();
    if (!ctx) {
      window.alert("Beagle OS: Keine VM-Ansicht erkannt.");
      return;
    }

    ensureStyles();
    removeOverlay();

    const overlay = document.createElement("div");
    overlay.id = OVERLAY_ID;
    overlay.innerHTML = `<div class="beagle-modal"><div class="beagle-header"><div><h2 class="beagle-title">Beagle Profil wird geladen</h2><p class="beagle-subtitle">VM ${String(ctx.vmid)} auf Node ${escapeHtml(ctx.node || "")}</p></div><button type="button" class="beagle-close" aria-label="Schliessen">×</button></div><div class="beagle-body"><div class="beagle-banner info">Proxmox-Konfiguration, Guest-Agent-Daten und Beagle-Metadaten werden aufgeloest.</div></div></div>`;
    overlay.addEventListener("click", (event) => {
      if (event.target === overlay || event.target.closest(".beagle-close")) {
        removeOverlay();
      }
    });
    document.body.appendChild(overlay);

    try {
      const profile = await resolveVmProfile(ctx);
      removeOverlay();
      renderProfileModal(profile);
    } catch (error) {
      removeOverlay();
      window.alert(`Beagle OS: ${error.message}`);
    }
  }

  async function downloadUsbInstaller() {
    const ctx = await parseVmContext();
    if (!ctx) {
      window.alert("Beagle OS: Keine VM-Ansicht erkannt.");
      return;
    }
    const url = await resolveUsbInstallerUrl(ctx);
    window.open(url, "_blank", "noopener,noreferrer");
  }

  function createToolbarButton(label, onClick) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.setAttribute(BUTTON_MARKER, label);
    button.className = "x-btn-text";
    button.style.marginLeft = "6px";
    button.style.padding = "4px 10px";
    button.style.border = "1px solid #b5b8c8";
    button.style.background = "#f5f5f5";
    button.style.borderRadius = "3px";
    button.style.cursor = "pointer";
    button.style.lineHeight = "20px";
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      onClick();
    });
    return button;
  }

  function isConsoleMenuTrigger(element) {
    const text = String(element.textContent || "").trim();
    return text === MENU_TEXT || text.includes(MENU_TEXT);
  }

  function findToolbarRow() {
    const buttons = Array.from(document.querySelectorAll("button, a, div, span"));
    for (const element of buttons) {
      if (!isConsoleMenuTrigger(element)) continue;
      const row =
        element.closest(".x-toolbar") ||
        element.closest(".x-box-inner") ||
        element.closest(".x-panel-header") ||
        element.parentElement;
      if (row) return row;
    }
    return null;
  }

  function ensureToolbarButtons() {
    document.querySelectorAll(`[${BUTTON_MARKER}]`).forEach((node) => {
      if (!isVmView()) node.remove();
    });

    if (!isVmView()) return;

    const toolbar = findToolbarRow();
    if (!toolbar) return;

    const existingButton = toolbar.querySelector(`[${BUTTON_MARKER}="${PRODUCT_LABEL}"]`);
    if (existingButton) return;

    const profileButton = createToolbarButton(PRODUCT_LABEL, showProfileModal);
    profileButton.title = "Zeigt das aufgeloeste Beagle-Profil fuer diese VM und bietet Download-, Export- und Health-Aktionen.";
    toolbar.appendChild(profileButton);
  }

  function getVisibleMenu() {
    const menus = Array.from(document.querySelectorAll(".x-menu, [role='menu']"));
    return menus.find((menu) => menu.offsetParent !== null) || null;
  }

  function menuAlreadyHasLabel(menu, label) {
    return Array.from(menu.querySelectorAll("*")).some((node) => String(node.textContent || "").trim() === label);
  }

  function createMenuItem(label, onClick) {
    const item = document.createElement("a");
    item.href = "#";
    item.setAttribute(BUTTON_MARKER, label);
    item.className = "x-menu-item";
    item.style.display = "block";
    item.style.padding = "4px 24px";
    item.style.cursor = "pointer";
    item.textContent = label;
    item.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      onClick();
    });
    return item;
  }

  function ensureMenuItems() {
    if (!isVmView()) return;
    const menu = getVisibleMenu();
    if (!menu) return;

    const hasConsoleItems = Array.from(menu.querySelectorAll("*")).some((node) => {
      const text = String(node.textContent || "").trim();
      return text === "noVNC" || text === "SPICE" || text === "xterm.js";
    });

    if (!hasConsoleItems) return;
    if (!menuAlreadyHasLabel(menu, `${PRODUCT_LABEL} Profil`)) {
      menu.appendChild(createMenuItem(`${PRODUCT_LABEL} Profil`, showProfileModal));
    }
    if (!menuAlreadyHasLabel(menu, `${PRODUCT_LABEL} Installer`)) {
      menu.appendChild(createMenuItem(`${PRODUCT_LABEL} Installer`, downloadUsbInstaller));
    }
  }

  async function boot() {
    for (let i = 0; i < 12; i += 1) {
      ensureToolbarButtons();
      ensureMenuItems();
      await sleep(500);
    }

    window.addEventListener("hashchange", () => {
      ensureToolbarButtons();
      ensureMenuItems();
    });

    document.addEventListener(
      "click",
      () => {
        window.setTimeout(() => {
          ensureToolbarButtons();
          ensureMenuItems();
        }, 50);
      },
      true
    );

    const observer = new MutationObserver(() => {
      ensureToolbarButtons();
      ensureMenuItems();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  boot();
})();
