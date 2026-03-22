(function() {
  "use strict";

  var PRODUCT_LABEL = "Beagle OS";
  var STYLE_ID = "beagle-os-modal-style";
  var OVERLAY_ID = "beagle-os-overlay";
  var FLEET_LAUNCHER_ID = "beagle-os-fleet-launcher";

  function defaultUsbInstallerUrl() {
    return "https://{host}:8443/beagle-downloads/pve-thin-client-usb-installer-vm-{vmid}.sh";
  }

  function defaultControlPlaneHealthUrl() {
    return "https://{host}:8443/beagle-api/api/v1/health";
  }

  function getConfig() {
    var runtimeConfig = window.BeagleIntegrationConfig || {};
    return {
      usbInstallerUrl: runtimeConfig.usbInstallerUrl || defaultUsbInstallerUrl(),
      controlPlaneHealthUrl: runtimeConfig.controlPlaneHealthUrl || defaultControlPlaneHealthUrl(),
      apiToken: runtimeConfig.apiToken || ""
    };
  }

  function fillTemplate(template, values) {
    return String(template || "")
      .replaceAll("{node}", values.node || "")
      .replaceAll("{vmid}", String(values.vmid || ""))
      .replaceAll("{host}", values.host || "");
  }

  function resolveUsbInstallerUrl(ctx) {
    return fillTemplate(getConfig().usbInstallerUrl, {
      node: ctx && ctx.node,
      vmid: ctx && ctx.vmid,
      host: window.location.hostname
    });
  }

  function resolveControlPlaneHealthUrl() {
    return fillTemplate(getConfig().controlPlaneHealthUrl, {
      host: window.location.hostname
    });
  }

  function managerUrlFromHealthUrl(healthUrl) {
    return String(healthUrl || "").replace(/\/api\/v1\/health\/?$/, "");
  }

  function showError(message) {
    if (window.Ext && Ext.Msg && Ext.Msg.alert) {
      Ext.Msg.alert(PRODUCT_LABEL, message);
    } else {
      window.alert(message);
    }
  }

  function showToast(message) {
    if (window.Ext && Ext.toast) {
      Ext.toast({ html: message, title: PRODUCT_LABEL, align: "t" });
      return;
    }
    window.alert(message);
  }

  function openUrl(url) {
    if (!url) {
      showError("URL konnte nicht ermittelt werden.");
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  }

  function openUsbInstaller(ctx) {
    openUrl(resolveUsbInstallerUrl(ctx || {}));
  }

  function ensureStyles() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }

    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = [
      "#" + OVERLAY_ID + " { position: fixed; inset: 0; background: rgba(15, 23, 42, 0.55); z-index: 100000; display: flex; align-items: center; justify-content: center; padding: 24px; }",
      "#" + OVERLAY_ID + " .beagle-modal { width: min(980px, 100%); max-height: calc(100vh - 48px); overflow: auto; background: linear-gradient(180deg, #fff8ef 0%, #ffffff 100%); border: 1px solid #fed7aa; border-radius: 22px; box-shadow: 0 30px 70px rgba(15, 23, 42, 0.25); color: #111827; }",
      "#" + OVERLAY_ID + " .beagle-header { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; padding: 24px 28px 18px; background: radial-gradient(circle at top right, rgba(59,130,246,0.12), transparent 30%), radial-gradient(circle at top left, rgba(249,115,22,0.18), transparent 36%); border-bottom: 1px solid #fdba74; }",
      "#" + OVERLAY_ID + " .beagle-title { font: 700 28px/1.1 'Trebuchet MS', 'Segoe UI', sans-serif; margin: 0 0 6px; }",
      "#" + OVERLAY_ID + " .beagle-subtitle { margin: 0; color: #7c2d12; font-size: 14px; }",
      "#" + OVERLAY_ID + " .beagle-close { border: 0; background: #111827; color: #fff; border-radius: 999px; width: 36px; height: 36px; cursor: pointer; font-size: 20px; line-height: 36px; }",
      "#" + OVERLAY_ID + " .beagle-body { padding: 22px 28px 28px; display: grid; gap: 18px; }",
      "#" + OVERLAY_ID + " .beagle-banner { padding: 12px 14px; border-radius: 14px; font-weight: 600; }",
      "#" + OVERLAY_ID + " .beagle-banner.info { background: #eff6ff; color: #1d4ed8; border: 1px solid #bfdbfe; }",
      "#" + OVERLAY_ID + " .beagle-banner.warn { background: #fff7ed; color: #9a3412; border: 1px solid #fdba74; }",
      "#" + OVERLAY_ID + " .beagle-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; }",
      "#" + OVERLAY_ID + " .beagle-card { background: rgba(255,255,255,0.88); border: 1px solid #e5e7eb; border-radius: 16px; padding: 16px; }",
      "#" + OVERLAY_ID + " .beagle-card h3 { margin: 0 0 12px; font: 700 15px/1.2 'Trebuchet MS', 'Segoe UI', sans-serif; color: #111827; }",
      "#" + OVERLAY_ID + " .beagle-kv { display: grid; gap: 8px; }",
      "#" + OVERLAY_ID + " .beagle-kv-row { display: grid; gap: 4px; }",
      "#" + OVERLAY_ID + " .beagle-kv-row strong { color: #9a3412; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }",
      "#" + OVERLAY_ID + " .beagle-kv-row span { word-break: break-word; }",
      "#" + OVERLAY_ID + " .beagle-actions { display: flex; flex-wrap: wrap; gap: 10px; }",
      "#" + OVERLAY_ID + " .beagle-btn { border: 0; border-radius: 999px; padding: 10px 16px; font-weight: 700; cursor: pointer; }",
      "#" + OVERLAY_ID + " .beagle-btn.primary { background: linear-gradient(135deg, #f97316, #0ea5e9); color: #fff; }",
      "#" + OVERLAY_ID + " .beagle-btn.secondary { background: #fff; color: #111827; border: 1px solid #d1d5db; }",
      "#" + OVERLAY_ID + " .beagle-btn.muted { background: #f3f4f6; color: #4b5563; border: 1px solid #d1d5db; }",
      "#" + OVERLAY_ID + " .beagle-code { width: 100%; min-height: 180px; resize: vertical; border-radius: 14px; border: 1px solid #d1d5db; padding: 12px; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #0f172a; color: #e2e8f0; }",
      "#" + OVERLAY_ID + " .beagle-notes { margin: 0; padding-left: 18px; }",
      "#" + OVERLAY_ID + " .beagle-muted { color: #6b7280; }",
      "#" + OVERLAY_ID + " .beagle-table-wrap { overflow: auto; border-radius: 16px; border: 1px solid #e5e7eb; background: rgba(255,255,255,0.92); }",
      "#" + OVERLAY_ID + " .beagle-table { width: 100%; border-collapse: collapse; min-width: 880px; }",
      "#" + OVERLAY_ID + " .beagle-table th, #" + OVERLAY_ID + " .beagle-table td { padding: 12px 14px; text-align: left; border-bottom: 1px solid #e5e7eb; vertical-align: top; }",
      "#" + OVERLAY_ID + " .beagle-table th { font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: #9a3412; background: #fff7ed; position: sticky; top: 0; }",
      "#" + OVERLAY_ID + " .beagle-badge { display: inline-flex; align-items: center; gap: 6px; border-radius: 999px; padding: 4px 10px; font-size: 12px; font-weight: 700; }",
      "#" + OVERLAY_ID + " .beagle-badge.healthy { background: #ecfdf5; color: #047857; }",
      "#" + OVERLAY_ID + " .beagle-badge.degraded { background: #fffbeb; color: #b45309; }",
      "#" + OVERLAY_ID + " .beagle-badge.drifted { background: #fef2f2; color: #b91c1c; }",
      "#" + OVERLAY_ID + " .beagle-badge.pending, #" + OVERLAY_ID + " .beagle-badge.unmanaged { background: #eff6ff; color: #1d4ed8; }",
      "#" + OVERLAY_ID + " .beagle-inline-actions { display: flex; flex-wrap: wrap; gap: 8px; }",
      "#" + OVERLAY_ID + " .beagle-mini-btn { border: 1px solid #d1d5db; background: #fff; border-radius: 999px; padding: 6px 10px; font-size: 12px; font-weight: 700; cursor: pointer; }",
      "#" + FLEET_LAUNCHER_ID + " { position: fixed; right: 22px; bottom: 22px; z-index: 99999; border: 0; border-radius: 999px; padding: 12px 18px; font: 700 14px/1 'Trebuchet MS', 'Segoe UI', sans-serif; color: #fff; background: linear-gradient(135deg, #f97316, #0ea5e9); box-shadow: 0 18px 40px rgba(15, 23, 42, 0.28); cursor: pointer; }"
    ].join("\n");
    document.head.appendChild(style);
  }

  function removeOverlay() {
    var existing = document.getElementById(OVERLAY_ID);
    if (existing) {
      existing.remove();
    }
  }

  function copyText(text, successMessage) {
    var value = String(text || "");
    if (!value) {
      showError("Keine Daten zum Kopieren vorhanden.");
      return;
    }

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(value).then(function() {
        showToast(successMessage || "In die Zwischenablage kopiert.");
      }).catch(function() {
        fallbackCopyText(value, successMessage);
      });
      return;
    }

    fallbackCopyText(value, successMessage);
  }

  function fallbackCopyText(text, successMessage) {
    var textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    try {
      document.execCommand("copy");
      showToast(successMessage || "In die Zwischenablage kopiert.");
    } catch (error) {
      showError("Kopieren fehlgeschlagen.");
    } finally {
      textarea.remove();
    }
  }

  function parseDescriptionMeta(description) {
    var meta = {};
    String(description || "")
      .replace(/\\r\\n/g, "\n")
      .replace(/\\n/g, "\n")
      .split("\n")
      .forEach(function(rawLine) {
        var line = rawLine.trim();
        var index = line.indexOf(":");
        var key;
        var value;
        if (index <= 0) {
          return;
        }
        key = line.slice(0, index).trim().toLowerCase();
        value = line.slice(index + 1).trim();
        if (key && !(key in meta)) {
          meta[key] = value;
        }
      });
    return meta;
  }

  function maskSecret(value) {
    if (!value) {
      return "nicht gesetzt";
    }
    if (value.length <= 4) {
      return "****";
    }
    return value.slice(0, 2) + "***" + value.slice(-2);
  }

  function apiGetJson(path) {
    return fetch(path, { credentials: "same-origin" }).then(function(response) {
      if (!response.ok) {
        throw new Error("API request failed: " + response.status + " " + response.statusText);
      }
      return response.json();
    }).then(function(payload) {
      return payload && payload.data ? payload.data : payload;
    });
  }

  function getApiToken() {
    return String(getConfig().apiToken || "").trim();
  }

  function buildBeagleRequestHeaders(extraHeaders) {
    var headers = Object.assign({}, extraHeaders || {});
    var token = getApiToken();
    if (token) {
      headers.Authorization = "Bearer " + token;
    }
    return headers;
  }

  function apiBeagleJson(path, options) {
    return fetch(path, Object.assign({ credentials: "same-origin" }, options || {})).then(function(response) {
      if (!response.ok) {
        throw new Error("Beagle API request failed: " + response.status + " " + response.statusText);
      }
      return response.json();
    });
  }

  function apiGetBeagleJson(path) {
    return apiBeagleJson(path, { headers: buildBeagleRequestHeaders() });
  }

  function apiPostBeagleJson(path, payload) {
    return apiBeagleJson(path, {
      method: "POST",
      headers: buildBeagleRequestHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify(payload || {})
    });
  }

  function apiDeleteBeagle(path) {
    return apiBeagleJson(path, {
      method: "DELETE",
      headers: buildBeagleRequestHeaders()
    });
  }

  function downloadProtectedFile(path, filename) {
    return fetch(path, {
      credentials: "same-origin",
      headers: buildBeagleRequestHeaders()
    }).then(function(response) {
      if (!response.ok) {
        throw new Error("Download failed: " + response.status + " " + response.statusText);
      }
      return response.blob();
    }).then(function(blob) {
      var objectUrl = URL.createObjectURL(blob);
      var anchor = document.createElement("a");
      anchor.href = objectUrl;
      anchor.download = filename || "beagle-artifact.bin";
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      window.setTimeout(function() {
        URL.revokeObjectURL(objectUrl);
      }, 1000);
    });
  }

  function firstGuestIpv4(interfaces) {
    var list = Array.isArray(interfaces) ? interfaces : [];
    var iface;
    var addresses;
    var i;
    var j;
    var address;
    for (i = 0; i < list.length; i += 1) {
      iface = list[i] || {};
      addresses = Array.isArray(iface["ip-addresses"]) ? iface["ip-addresses"] : [];
      for (j = 0; j < addresses.length; j += 1) {
        address = addresses[j] || {};
        if (address["ip-address-type"] !== "ipv4") {
          continue;
        }
        if (!address["ip-address"] || /^127\./.test(address["ip-address"]) || /^169\.254\./.test(address["ip-address"])) {
          continue;
        }
        return address["ip-address"];
      }
    }
    return "";
  }

  function buildEndpointEnv(profile) {
    var endpointProfileName = profile.expectedProfileName || ("vm-" + profile.vmid);
    var lines = [
      "PVE_THIN_CLIENT_MODE=\"MOONLIGHT\"",
      "PVE_THIN_CLIENT_PROFILE_NAME=\"" + endpointProfileName + "\"",
      "PVE_THIN_CLIENT_AUTOSTART=\"1\"",
      "PVE_THIN_CLIENT_PROXMOX_HOST=\"" + (profile.proxmoxHost || window.location.hostname) + "\"",
      "PVE_THIN_CLIENT_PROXMOX_PORT=\"8006\"",
      "PVE_THIN_CLIENT_PROXMOX_NODE=\"" + (profile.node || "") + "\"",
      "PVE_THIN_CLIENT_PROXMOX_VMID=\"" + String(profile.vmid || "") + "\"",
      "PVE_THIN_CLIENT_BEAGLE_MANAGER_URL=\"" + (profile.managerUrl || "") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_HOST=\"" + (profile.streamHost || "") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_APP=\"" + (profile.app || "Desktop") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_RESOLUTION=\"" + (profile.resolution || "auto") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_FPS=\"" + (profile.fps || "60") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_BITRATE=\"" + (profile.bitrate || "20000") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_VIDEO_CODEC=\"" + (profile.codec || "H.264") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_VIDEO_DECODER=\"" + (profile.decoder || "auto") + "\"",
      "PVE_THIN_CLIENT_MOONLIGHT_AUDIO_CONFIG=\"" + (profile.audio || "stereo") + "\"",
      "PVE_THIN_CLIENT_SUNSHINE_API_URL=\"" + (profile.sunshineApiUrl || "") + "\"",
      "PVE_THIN_CLIENT_SUNSHINE_USERNAME=\"" + (profile.sunshineUsername || "") + "\"",
      "PVE_THIN_CLIENT_SUNSHINE_PASSWORD=\"" + (profile.sunshinePassword || "") + "\"",
      "PVE_THIN_CLIENT_SUNSHINE_PIN=\"" + (profile.sunshinePin || "") + "\""
    ];
    return lines.join("\n") + "\n";
  }

  function buildNotes(profile) {
    var notes = [];
    if (!profile.streamHost) {
      notes.push("Kein Moonlight-/Sunshine-Ziel in der VM-Metadatenbeschreibung gefunden.");
    }
    if (!profile.sunshineApiUrl) {
      notes.push("Keine Sunshine API URL gesetzt. Pairing und Healthchecks koennen nicht vorab validiert werden.");
    }
    if (!profile.sunshinePassword) {
      notes.push("Kein Sunshine-Passwort hinterlegt. Fuer direkte API-Aktionen ist dann ein vorregistriertes Zertifikat oder manuelles Pairing noetig.");
    }
    if (!profile.guestIp) {
      notes.push("Keine Guest-Agent-IPv4 erkannt. Beagle kann dann nur mit Metadaten arbeiten.");
    }
    if (!notes.length) {
      notes.push("VM-Profil ist vollstaendig genug fuer einen vorkonfigurierten Beagle-Endpoint mit Moonlight-Autostart.");
    }
    if (profile.assignedTarget) {
      notes.push("Endpoint ist auf Ziel-VM " + profile.assignedTarget.name + " (#" + profile.assignedTarget.vmid + ") zugewiesen.");
    }
    if (profile.appliedPolicy && profile.appliedPolicy.name) {
      notes.push("Manager-Policy aktiv: " + profile.appliedPolicy.name + ".");
    }
    if (profile.compliance && profile.compliance.status === "drifted") {
      notes.push("Endpoint driftet vom gewuenschten Profil ab (" + String(profile.compliance.drift_count || 0) + " Abweichungen).");
    }
    if (profile.compliance && profile.compliance.status === "degraded") {
      notes.push("Endpoint ist konfigurationsgleich, aber betrieblich degradiert (" + String(profile.compliance.alert_count || 0) + " Warnungen).");
    }
    if (Number(profile.pendingActionCount || 0) > 0) {
      notes.push("Fuer diesen Endpoint warten " + String(profile.pendingActionCount) + " Beagle-Aktion(en) auf Ausfuehrung.");
    }
    if (profile.lastAction && profile.lastAction.action) {
      notes.push("Letzte Endpoint-Aktion: " + profile.lastAction.action + " (" + formatActionState(profile.lastAction.ok) + ").");
    }
    if (profile.lastAction && profile.lastAction.stored_artifact_path) {
      notes.push("Diagnoseartefakt ist zentral auf dem Beagle-Manager gespeichert.");
    }
    return notes;
  }

  function formatActionState(ok) {
    if (ok === true) {
      return "ok";
    }
    if (ok === false) {
      return "error";
    }
    return "pending";
  }

  function renderStatusBadge(status) {
    var value = String(status || "unknown").toLowerCase();
    return '<span class="beagle-badge ' + escapeHtml(value) + '">' + escapeHtml(value) + '</span>';
  }

  function createPolicyFromInventoryItem(item) {
    var target = item && item.assigned_target ? item.assigned_target : null;
    if (!target || !target.vmid) {
      throw new Error("Kein zugewiesenes Ziel fuer diese VM vorhanden.");
    }
    return {
      name: "vm-" + String(item.vmid) + "-managed",
      enabled: true,
      priority: 700,
      selector: {
        vmid: Number(item.vmid),
        node: item.node || "",
        role: "endpoint"
      },
      profile: {
        beagle_role: "endpoint",
        expected_profile_name: item.expected_profile_name || ("vm-" + String(target.vmid)),
        network_mode: item.network_mode || "dhcp",
        moonlight_app: item.moonlight_app || "Desktop",
        assigned_target: {
          vmid: Number(target.vmid),
          node: target.node || ""
        }
      }
    };
  }

  function renderFleetModal(payload) {
    var overlay = document.createElement("div");
    var vms = payload && Array.isArray(payload.vms) ? payload.vms : [];
    var policies = payload && Array.isArray(payload.policies) ? payload.policies : [];
    var health = payload && payload.health ? payload.health : {};
    var endpointCounts = health.endpoint_status_counts || {};
    var vmRows = vms.map(function(item) {
      var lastAction = item.last_action || {};
      var bundleDownloadPath = lastAction.stored_artifact_download_path || "";
      var policyName = item.applied_policy && item.applied_policy.name || "";
      return '' +
        '<tr>' +
        '  <td><strong>' + escapeHtml(item.name || ("vm-" + item.vmid)) + '</strong><br><span class="beagle-muted">#' + escapeHtml(String(item.vmid || "")) + ' / ' + escapeHtml(item.node || "") + '</span></td>' +
        '  <td>' + renderStatusBadge(item.compliance && item.compliance.status || "unknown") + '<br><span class="beagle-muted">' + escapeHtml(item.assignment_source || "unassigned") + '</span></td>' +
        '  <td>' + escapeHtml(item.assigned_target ? (item.assigned_target.name + " (#" + item.assigned_target.vmid + ")") : "") + '<br><span class="beagle-muted">' + escapeHtml(item.stream_host || "") + '</span></td>' +
        '  <td>' + escapeHtml(policyName || "keine") + '<br><span class="beagle-muted">Bundles: ' + escapeHtml(String(item.support_bundle_count || 0)) + '</span></td>' +
        '  <td>' + escapeHtml(item.endpoint && item.endpoint.reported_at || "") + '<br><span class="beagle-muted">' + escapeHtml(lastAction.action || "") + " " + escapeHtml(formatActionState(lastAction.ok)) + '</span></td>' +
        '  <td><div class="beagle-inline-actions">' +
        '    <button type="button" class="beagle-mini-btn" data-beagle-fleet-action="profile" data-vmid="' + escapeHtml(String(item.vmid || "")) + '" data-node="' + escapeHtml(item.node || "") + '">Profil</button>' +
        '    <button type="button" class="beagle-mini-btn" data-beagle-fleet-action="healthcheck" data-vmid="' + escapeHtml(String(item.vmid || "")) + '">Check</button>' +
        '    <button type="button" class="beagle-mini-btn" data-beagle-fleet-action="support-bundle" data-vmid="' + escapeHtml(String(item.vmid || "")) + '">Bundle</button>' +
        (bundleDownloadPath ? '    <button type="button" class="beagle-mini-btn" data-beagle-fleet-action="download-bundle" data-bundle-path="' + escapeHtml(bundleDownloadPath) + '" data-bundle-name="vm-' + escapeHtml(String(item.vmid || "")) + '-support.tar.gz">Download</button>' : '') +
        (policyName ? '    <button type="button" class="beagle-mini-btn" data-beagle-fleet-action="delete-policy" data-policy-name="' + escapeHtml(policyName) + '">Policy loeschen</button>' : (item.assigned_target ? '    <button type="button" class="beagle-mini-btn" data-beagle-fleet-action="create-policy" data-vmid="' + escapeHtml(String(item.vmid || "")) + '">Zu Policy</button>' : '')) +
        '  </div></td>' +
        '</tr>';
    }).join("");
    var policyRows = policies.map(function(policy) {
      var selector = policy.selector || {};
      var profile = policy.profile || {};
      return '' +
        '<tr>' +
        '  <td><strong>' + escapeHtml(policy.name || "") + '</strong></td>' +
        '  <td>' + escapeHtml(String(policy.priority || 0)) + '</td>' +
        '  <td>' + escapeHtml(selector.vmid ? ("VM " + selector.vmid) : "") + ' ' + escapeHtml(selector.node || "") + ' ' + escapeHtml(selector.role || "") + '</td>' +
        '  <td>' + escapeHtml(profile.expected_profile_name || "") + '<br><span class="beagle-muted">' + escapeHtml(profile.network_mode || "") + '</span></td>' +
        '  <td><button type="button" class="beagle-mini-btn" data-beagle-fleet-action="delete-policy" data-policy-name="' + escapeHtml(policy.name || "") + '">Loeschen</button></td>' +
        '</tr>';
    }).join("");

    overlay.id = OVERLAY_ID;
    overlay.innerHTML = '' +
      '<div class="beagle-modal" role="dialog" aria-modal="true" aria-label="Beagle Fleet">' +
      '  <div class="beagle-header">' +
      '    <div><h2 class="beagle-title">Beagle Fleet</h2><p class="beagle-subtitle">Zentrale Endpunkt-, Policy- und Diagnose-Sicht fuer Proxmox.</p></div>' +
      '    <button type="button" class="beagle-close" aria-label="Schliessen">×</button>' +
      '  </div>' +
      '  <div class="beagle-body">' +
      '    <div class="beagle-actions">' +
      '      <button type="button" class="beagle-btn primary" data-beagle-fleet-action="refresh">Aktualisieren</button>' +
      '      <button type="button" class="beagle-btn secondary" data-beagle-fleet-action="open-health">Health</button>' +
      '      <button type="button" class="beagle-btn secondary" data-beagle-fleet-action="copy-policies">Policies JSON</button>' +
      '    </div>' +
      '    <div class="beagle-grid">' +
      '      <section class="beagle-card"><h3>Fleet</h3><div class="beagle-kv">' +
                kvRow('Endpoints', escapeHtml(String(health.endpoint_count || 0))) +
                kvRow('Policies', escapeHtml(String(health.policy_count || 0))) +
                kvRow('Healthy', escapeHtml(String(endpointCounts.healthy || 0))) +
                kvRow('Pending', escapeHtml(String(endpointCounts.pending || 0))) +
      '      </div></section>' +
      '      <section class="beagle-card"><h3>Compliance</h3><div class="beagle-kv">' +
                kvRow('Degraded', escapeHtml(String(endpointCounts.degraded || 0))) +
                kvRow('Drifted', escapeHtml(String(endpointCounts.drifted || 0))) +
                kvRow('Unmanaged', escapeHtml(String(endpointCounts.unmanaged || 0))) +
                kvRow('Generated', escapeHtml(health.generated_at || '')) +
      '      </div></section>' +
      '    </div>' +
      '    <section class="beagle-card"><h3>Endpoints</h3><div class="beagle-table-wrap"><table class="beagle-table"><thead><tr><th>VM</th><th>Status</th><th>Ziel</th><th>Policy</th><th>Letzter Kontakt</th><th>Aktionen</th></tr></thead><tbody>' + vmRows + '</tbody></table></div></section>' +
      '    <section class="beagle-card"><h3>Policies</h3><div class="beagle-table-wrap"><table class="beagle-table"><thead><tr><th>Name</th><th>Prioritaet</th><th>Selektor</th><th>Profil</th><th>Aktion</th></tr></thead><tbody>' + policyRows + '</tbody></table></div></section>' +
      '  </div>' +
      '</div>';

    overlay.addEventListener('click', function(event) {
      var target;
      var item;
      if (event.target === overlay || event.target.closest('.beagle-close')) {
        removeOverlay();
        return;
      }
      target = event.target instanceof HTMLElement ? event.target.closest('[data-beagle-fleet-action]') : null;
      if (!target) {
        return;
      }
      switch (target.getAttribute('data-beagle-fleet-action')) {
        case 'refresh':
          showFleetModal();
          break;
        case 'open-health':
          openUrl(resolveControlPlaneHealthUrl());
          break;
        case 'copy-policies':
          copyText(JSON.stringify(policies, null, 2), 'Beagle Policies kopiert.');
          break;
        case 'profile':
          showProfileModal({ vmid: Number(target.getAttribute('data-vmid')), node: target.getAttribute('data-node') });
          break;
        case 'healthcheck':
        case 'support-bundle':
          apiPostBeagleJson('/beagle-api/api/v1/vms/' + encodeURIComponent(target.getAttribute('data-vmid')) + '/actions', {
            action: target.getAttribute('data-beagle-fleet-action')
          }).then(function() {
            showToast('Beagle Aktion wurde in die Queue gestellt.');
            showFleetModal();
          }).catch(function(error) {
            showError(error.message);
          });
          break;
        case 'download-bundle':
          downloadProtectedFile('/beagle-api' + target.getAttribute('data-bundle-path'), target.getAttribute('data-bundle-name')).catch(function(error) {
            showError(error.message);
          });
          break;
        case 'create-policy':
          item = vms.find(function(candidate) { return Number(candidate.vmid) === Number(target.getAttribute('data-vmid')); });
          apiPostBeagleJson('/beagle-api/api/v1/policies', createPolicyFromInventoryItem(item)).then(function() {
            showToast('Beagle Policy wurde erzeugt.');
            showFleetModal();
          }).catch(function(error) {
            showError(error.message);
          });
          break;
        case 'delete-policy':
          apiDeleteBeagle('/beagle-api/api/v1/policies/' + encodeURIComponent(target.getAttribute('data-policy-name'))).then(function() {
            showToast('Beagle Policy wurde geloescht.');
            showFleetModal();
          }).catch(function(error) {
            showError(error.message);
          });
          break;
        default:
          break;
      }
    });

    document.body.appendChild(overlay);
  }

  function showFleetModal() {
    ensureStyles();
    removeOverlay();
    if (!getApiToken()) {
      showError('Beagle API Token fehlt in der Proxmox-UI-Konfiguration.');
      return;
    }
    var overlay = document.createElement('div');
    overlay.id = OVERLAY_ID;
    overlay.innerHTML = '<div class="beagle-modal"><div class="beagle-header"><div><h2 class="beagle-title">Beagle Fleet wird geladen</h2><p class="beagle-subtitle">Inventar, Policies und Endpoint-Zustand werden vom Manager geladen.</p></div><button type="button" class="beagle-close" aria-label="Schliessen">×</button></div><div class="beagle-body"><div class="beagle-banner info">Beagle Control Plane wird abgefragt.</div></div></div>';
    overlay.addEventListener('click', function(event) {
      if (event.target === overlay || event.target.closest('.beagle-close')) {
        removeOverlay();
      }
    });
    document.body.appendChild(overlay);
    Promise.all([
      apiGetJson('/beagle-api/api/v1/health'),
      apiGetBeagleJson('/beagle-api/api/v1/vms'),
      apiGetBeagleJson('/beagle-api/api/v1/policies')
    ]).then(function(results) {
      removeOverlay();
      renderFleetModal({
        health: results[0] || {},
        vms: results[1] && results[1].vms || [],
        policies: results[2] && results[2].policies || []
      });
    }).catch(function(error) {
      removeOverlay();
      showError('Beagle Fleet konnte nicht geladen werden: ' + error.message);
    });
  }

  function resolveVmProfile(ctx) {
    return Promise.all([
      apiGetJson("/api2/json/nodes/" + encodeURIComponent(ctx.node) + "/qemu/" + encodeURIComponent(ctx.vmid) + "/config"),
      apiGetJson("/api2/json/cluster/resources?type=vm").catch(function() { return []; }),
      apiGetJson("/api2/json/nodes/" + encodeURIComponent(ctx.node) + "/qemu/" + encodeURIComponent(ctx.vmid) + "/agent/network-get-interfaces").catch(function() { return []; }),
      fetch("/beagle-api/api/v1/public/vms/" + encodeURIComponent(ctx.vmid) + "/state", { credentials: "same-origin" }).then(function(response) {
        if (!response.ok) {
          return null;
        }
        return response.json();
      }).catch(function() { return null; })
    ]).then(function(results) {
      var config = results[0] || {};
      var resources = Array.isArray(results[1]) ? results[1] : [];
      var guestInterfaces = Array.isArray(results[2]) ? results[2] : [];
      var endpointPayload = results[3] || null;
      var controlPlaneProfile = endpointPayload && endpointPayload.profile ? endpointPayload.profile : null;
      var endpointSummary = endpointPayload && endpointPayload.endpoint ? endpointPayload.endpoint : null;
      var compliance = endpointPayload && endpointPayload.compliance ? endpointPayload.compliance : null;
      var lastAction = endpointPayload && endpointPayload.last_action ? endpointPayload.last_action : null;
      var pendingActionCount = endpointPayload && endpointPayload.pending_action_count ? endpointPayload.pending_action_count : 0;
      var resource = resources.find(function(item) {
        return item && item.type === "qemu" && Number(item.vmid) === Number(ctx.vmid);
      }) || {};
      var meta = parseDescriptionMeta(config.description || "");
      var guestIp = firstGuestIpv4(guestInterfaces);
      var streamHost = controlPlaneProfile && controlPlaneProfile.stream_host || meta["moonlight-host"] || meta["sunshine-ip"] || meta["sunshine-host"] || guestIp || "";
      var sunshineApiUrl = controlPlaneProfile && controlPlaneProfile.sunshine_api_url || meta["sunshine-api-url"] || (streamHost ? "https://" + streamHost + ":47990" : "");
      var profile = {
        vmid: Number(ctx.vmid),
        node: ctx.node,
        name: config.name || resource.name || ("vm-" + ctx.vmid),
        status: resource.status || "unknown",
        guestIp: guestIp,
        streamHost: streamHost,
        sunshineApiUrl: sunshineApiUrl,
        sunshineUsername: controlPlaneProfile && controlPlaneProfile.sunshine_username || meta["sunshine-user"] || "",
        sunshinePassword: meta["sunshine-password"] || "",
        sunshinePin: meta["sunshine-pin"] || String(ctx.vmid % 10000).padStart(4, "0"),
        app: controlPlaneProfile && controlPlaneProfile.moonlight_app || meta["moonlight-app"] || meta["sunshine-app"] || "Desktop",
        resolution: controlPlaneProfile && controlPlaneProfile.moonlight_resolution || meta["moonlight-resolution"] || "auto",
        fps: controlPlaneProfile && controlPlaneProfile.moonlight_fps || meta["moonlight-fps"] || "60",
        bitrate: controlPlaneProfile && controlPlaneProfile.moonlight_bitrate || meta["moonlight-bitrate"] || "20000",
        codec: controlPlaneProfile && controlPlaneProfile.moonlight_video_codec || meta["moonlight-video-codec"] || "H.264",
        decoder: controlPlaneProfile && controlPlaneProfile.moonlight_video_decoder || meta["moonlight-video-decoder"] || "auto",
        audio: controlPlaneProfile && controlPlaneProfile.moonlight_audio_config || meta["moonlight-audio-config"] || "stereo",
        proxmoxHost: meta["proxmox-host"] || window.location.hostname,
        installerUrl: resolveUsbInstallerUrl(ctx),
        controlPlaneHealthUrl: resolveControlPlaneHealthUrl(),
        managerUrl: managerUrlFromHealthUrl(resolveControlPlaneHealthUrl()),
        endpointSummary: endpointSummary,
        compliance: compliance,
        lastAction: lastAction,
        pendingActionCount: pendingActionCount,
        assignedTarget: controlPlaneProfile && controlPlaneProfile.assigned_target || null,
        assignmentSource: controlPlaneProfile && controlPlaneProfile.assignment_source || "",
        appliedPolicy: controlPlaneProfile && controlPlaneProfile.applied_policy || null,
        expectedProfileName: controlPlaneProfile && controlPlaneProfile.expected_profile_name || "",
        metadata: meta
      };
      profile.notes = buildNotes(profile);
      if (!profile.endpointSummary) {
        profile.notes.push("Endpoint hat noch keinen Check-in an die Beagle Control Plane geliefert.");
      }
      profile.endpointEnv = buildEndpointEnv(profile);
      return profile;
    });
  }

  function kvRow(label, value) {
    return '<div class="beagle-kv-row"><strong>' + label + '</strong><span>' + (value || '<span class="beagle-muted">nicht gesetzt</span>') + '</span></div>';
  }

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function renderProfileModal(profile) {
    var overlay = document.createElement("div");
    var notesHtml = profile.notes.map(function(note) {
      return "<li>" + escapeHtml(note) + "</li>";
    }).join("");
    var profileJson = JSON.stringify({
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
    }, null, 2);

    overlay.id = OVERLAY_ID;
    overlay.innerHTML = '' +
      '<div class="beagle-modal" role="dialog" aria-modal="true" aria-label="Beagle OS Profil">' +
      '  <div class="beagle-header">' +
      '    <div>' +
      '      <h2 class="beagle-title">Beagle Profil fuer VM ' + escapeHtml(profile.name) + ' (#' + String(profile.vmid) + ')</h2>' +
      '      <p class="beagle-subtitle">Moonlight-Endpunkt, Sunshine-Ziel und Proxmox-Bereitstellung in einer Sicht.</p>' +
      '    </div>' +
      '    <button type="button" class="beagle-close" aria-label="Schliessen">×</button>' +
      '  </div>' +
      '  <div class="beagle-body">' +
      '    <div class="beagle-banner ' + (profile.streamHost ? 'info' : 'warn') + '">' + escapeHtml(profile.streamHost ? 'Streaming-Ziel erkannt: ' + profile.streamHost : 'Streaming-Ziel fehlt in den VM-Metadaten.') + '</div>' +
      '    <div class="beagle-actions">' +
      '      <button type="button" class="beagle-btn primary" data-beagle-action="download">USB Installer</button>' +
      '      <button type="button" class="beagle-btn secondary" data-beagle-action="copy-json">Profil JSON kopieren</button>' +
      '      <button type="button" class="beagle-btn secondary" data-beagle-action="copy-env">Endpoint Env kopieren</button>' +
      '      <button type="button" class="beagle-btn secondary" data-beagle-action="open-sunshine">Sunshine Web UI</button>' +
      '      <button type="button" class="beagle-btn secondary" data-beagle-action="open-health">Control Plane Status</button>' +
      '    </div>' +
      '    <div class="beagle-grid">' +
      '      <section class="beagle-card"><h3>VM</h3><div class="beagle-kv">' +
                kvRow('Name', escapeHtml(profile.name)) +
                kvRow('VMID', escapeHtml(String(profile.vmid))) +
                kvRow('Node', escapeHtml(profile.node)) +
                kvRow('Status', escapeHtml(profile.status)) +
                kvRow('Guest IP', escapeHtml(profile.guestIp || '')) +
      '      </div></section>' +
      '      <section class="beagle-card"><h3>Streaming</h3><div class="beagle-kv">' +
                kvRow('Stream Host', escapeHtml(profile.streamHost || '')) +
                kvRow('Sunshine API', escapeHtml(profile.sunshineApiUrl || '')) +
                kvRow('App', escapeHtml(profile.app)) +
                kvRow('Manager', escapeHtml(profile.managerUrl || '')) +
                kvRow('Assigned Target', escapeHtml(profile.assignedTarget ? (profile.assignedTarget.name + " (#" + profile.assignedTarget.vmid + ")") : '')) +
                kvRow('Assignment Source', escapeHtml(profile.assignmentSource || '')) +
                kvRow('Applied Policy', escapeHtml(profile.appliedPolicy && profile.appliedPolicy.name || '')) +
                kvRow('Installer', escapeHtml(profile.installerUrl)) +
                kvRow('Health', escapeHtml(profile.controlPlaneHealthUrl)) +
      '      </div></section>' +
      '      <section class="beagle-card"><h3>Endpoint Defaults</h3><div class="beagle-kv">' +
                kvRow('Resolution', escapeHtml(profile.resolution)) +
                kvRow('FPS', escapeHtml(profile.fps)) +
                kvRow('Bitrate', escapeHtml(profile.bitrate)) +
                kvRow('Codec', escapeHtml(profile.codec)) +
                kvRow('Decoder', escapeHtml(profile.decoder)) +
                kvRow('Audio', escapeHtml(profile.audio)) +
      '      </div></section>' +
      '      <section class="beagle-card"><h3>Pairing</h3><div class="beagle-kv">' +
                kvRow('Sunshine User', escapeHtml(profile.sunshineUsername || '')) +
                kvRow('Sunshine Password', escapeHtml(maskSecret(profile.sunshinePassword))) +
                kvRow('Pairing PIN', escapeHtml(profile.sunshinePin || '')) +
      '      </div></section>' +
      '      <section class="beagle-card"><h3>Endpoint State</h3><div class="beagle-kv">' +
                kvRow('Compliance', escapeHtml(profile.compliance && profile.compliance.status || '')) +
                kvRow('Drift Count', escapeHtml(profile.compliance ? String(profile.compliance.drift_count || 0) : '')) +
                kvRow('Alert Count', escapeHtml(profile.compliance ? String(profile.compliance.alert_count || 0) : '')) +
                kvRow('Pending Actions', escapeHtml(String(profile.pendingActionCount || 0))) +
                kvRow('Last Seen', escapeHtml(profile.endpointSummary && profile.endpointSummary.reported_at || '')) +
                kvRow('Target Reachable', escapeHtml(profile.endpointSummary && profile.endpointSummary.moonlight_target_reachable || '')) +
                kvRow('Sunshine Reachable', escapeHtml(profile.endpointSummary && profile.endpointSummary.sunshine_api_reachable || '')) +
                kvRow('Prepare', escapeHtml(profile.endpointSummary && profile.endpointSummary.prepare_state || '')) +
                kvRow('Last Launch', escapeHtml(profile.endpointSummary && profile.endpointSummary.last_launch_mode || '')) +
                kvRow('Launch Target', escapeHtml(profile.endpointSummary && profile.endpointSummary.last_launch_target || '')) +
                kvRow('Last Action', escapeHtml(profile.lastAction && profile.lastAction.action || '')) +
                kvRow('Action Result', escapeHtml(formatActionState(profile.lastAction && profile.lastAction.ok))) +
                kvRow('Action Time', escapeHtml(profile.lastAction && profile.lastAction.completed_at || '')) +
                kvRow('Action Message', escapeHtml(profile.lastAction && profile.lastAction.message || '')) +
                kvRow('Stored Artifact', escapeHtml(profile.lastAction && profile.lastAction.stored_artifact_path || '')) +
                kvRow('Artifact Size', escapeHtml(profile.lastAction ? String(profile.lastAction.stored_artifact_size || 0) : '')) +
      '      </div></section>' +
      '    </div>' +
      '    <section class="beagle-card"><h3>Operator Notes</h3><ul class="beagle-notes">' + notesHtml + '</ul></section>' +
      '    <section class="beagle-card"><h3>Beagle Endpoint Env</h3><textarea class="beagle-code" readonly>' + escapeHtml(profile.endpointEnv) + '</textarea></section>' +
      '    <section class="beagle-card"><h3>Profile JSON</h3><textarea class="beagle-code" readonly>' + escapeHtml(profileJson) + '</textarea></section>' +
      '  </div>' +
      '</div>';

    overlay.addEventListener('click', function(event) {
      if (event.target === overlay || event.target.closest('.beagle-close')) {
        removeOverlay();
        return;
      }

      if (!(event.target instanceof HTMLElement)) {
        return;
      }

      switch (event.target.getAttribute('data-beagle-action')) {
        case 'download':
          openUrl(profile.installerUrl);
          break;
        case 'copy-json':
          copyText(profileJson, 'Beagle Profil als JSON kopiert.');
          break;
        case 'copy-env':
          copyText(profile.endpointEnv, 'Beagle Endpoint-Umgebung kopiert.');
          break;
        case 'open-sunshine':
          openUrl(profile.sunshineApiUrl);
          break;
        case 'open-health':
          openUrl(profile.controlPlaneHealthUrl);
          break;
        default:
          break;
      }
    });

    document.body.appendChild(overlay);
  }

  function showProfileModal(ctx) {
    ensureStyles();
    removeOverlay();

    var overlay = document.createElement('div');
    overlay.id = OVERLAY_ID;
    overlay.innerHTML = '<div class="beagle-modal"><div class="beagle-header"><div><h2 class="beagle-title">Beagle Profil wird geladen</h2><p class="beagle-subtitle">VM ' + String(ctx.vmid) + ' auf Node ' + escapeHtml(ctx.node || '') + '</p></div><button type="button" class="beagle-close" aria-label="Schliessen">×</button></div><div class="beagle-body"><div class="beagle-banner info">Proxmox-Konfiguration, Guest-Agent-Daten und Beagle-Metadaten werden aufgeloest.</div></div></div>';
    overlay.addEventListener('click', function(event) {
      if (event.target === overlay || event.target.closest('.beagle-close')) {
        removeOverlay();
      }
    });
    document.body.appendChild(overlay);

    resolveVmProfile(ctx).then(function(profile) {
      removeOverlay();
      renderProfileModal(profile);
    }).catch(function(error) {
      removeOverlay();
      showError('Beagle Profil konnte nicht geladen werden: ' + error.message);
    });
  }

  function ensureConsoleButtonIntegration(button) {
    if (!button || !button.vmid || button.consoleType !== "kvm" || button.__beagleIntegrated) {
      return;
    }

    var menu = button.getMenu ? button.getMenu() : button.menu;
    if (menu && !menu.down("#beagleOsProfileMenuItem")) {
      menu.add({
        itemId: "beagleOsProfileMenuItem",
        text: PRODUCT_LABEL + " Profil",
        iconCls: "fa fa-desktop",
        handler: function() {
          showProfileModal({ node: button.nodename, vmid: button.vmid });
        }
      });
      menu.add({
        itemId: "beagleOsInstallerMenuItem",
        text: PRODUCT_LABEL + " Installer",
        iconCls: "fa fa-usb",
        handler: function() {
          openUsbInstaller({ node: button.nodename, vmid: button.vmid });
        }
      });
    }

    var toolbar = button.up && button.up("toolbar");
    if (toolbar && !toolbar.down("#beagleOsButton")) {
      var index = toolbar.items.indexOf(button);
      toolbar.insert(index + 1, {
        xtype: "button",
        itemId: "beagleOsButton",
        text: PRODUCT_LABEL,
        iconCls: "fa fa-desktop",
        handler: function() {
          showProfileModal({ node: button.nodename, vmid: button.vmid });
        },
        tooltip: "Zeigt das aufgeloeste Beagle-Profil fuer diese VM und bietet Download-, Export- und Health-Aktionen."
      });
    }

    button.__beagleIntegrated = true;
  }

  function ensureFleetLauncher() {
    if (document.getElementById(FLEET_LAUNCHER_ID)) {
      return;
    }
    var button = document.createElement('button');
    button.id = FLEET_LAUNCHER_ID;
    button.type = 'button';
    button.textContent = 'Beagle Fleet';
    button.addEventListener('click', function() {
      showFleetModal();
    });
    document.body.appendChild(button);
  }

  function integrate() {
    if (!(window.Ext && Ext.ComponentQuery)) {
      return;
    }

    Ext.ComponentQuery.query("pveConsoleButton").forEach(ensureConsoleButtonIntegration);
    ensureFleetLauncher();
  }

  function boot() {
    integrate();
    window.setInterval(integrate, 1000);
  }

  if (window.Ext && Ext.onReady) {
    Ext.onReady(boot);
  } else {
    boot();
  }
})();
