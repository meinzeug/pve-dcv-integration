(function() {
  "use strict";

  var PRODUCT_LABEL = "Beagle OS";
  var STYLE_ID = "beagle-os-modal-style";
  var OVERLAY_ID = "beagle-os-overlay";

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
      controlPlaneHealthUrl: runtimeConfig.controlPlaneHealthUrl || defaultControlPlaneHealthUrl()
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
      "#" + OVERLAY_ID + " .beagle-code { width: 100%; min-height: 180px; resize: vertical; border-radius: 14px; border: 1px solid #d1d5db; padding: 12px; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #0f172a; color: #e2e8f0; }",
      "#" + OVERLAY_ID + " .beagle-notes { margin: 0; padding-left: 18px; }",
      "#" + OVERLAY_ID + " .beagle-muted { color: #6b7280; }"
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
    var lines = [
      "PVE_THIN_CLIENT_MODE=\"MOONLIGHT\"",
      "PVE_THIN_CLIENT_PROFILE_NAME=\"vm-" + profile.vmid + "\"",
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
    return notes;
  }

  function resolveVmProfile(ctx) {
    return Promise.all([
      apiGetJson("/api2/json/nodes/" + encodeURIComponent(ctx.node) + "/qemu/" + encodeURIComponent(ctx.vmid) + "/config"),
      apiGetJson("/api2/json/cluster/resources?type=vm").catch(function() { return []; }),
      apiGetJson("/api2/json/nodes/" + encodeURIComponent(ctx.node) + "/qemu/" + encodeURIComponent(ctx.vmid) + "/agent/network-get-interfaces").catch(function() { return []; }),
      fetch("/beagle-api/api/v1/public/vms/" + encodeURIComponent(ctx.vmid) + "/endpoint", { credentials: "same-origin" }).then(function(response) {
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
      var resource = resources.find(function(item) {
        return item && item.type === "qemu" && Number(item.vmid) === Number(ctx.vmid);
      }) || {};
      var meta = parseDescriptionMeta(config.description || "");
      var guestIp = firstGuestIpv4(guestInterfaces);
      var streamHost = meta["moonlight-host"] || meta["sunshine-host"] || meta["sunshine-ip"] || guestIp || "";
      var sunshineApiUrl = meta["sunshine-api-url"] || (streamHost ? "https://" + streamHost + ":47990" : "");
      var profile = {
        vmid: Number(ctx.vmid),
        node: ctx.node,
        name: config.name || resource.name || ("vm-" + ctx.vmid),
        status: resource.status || "unknown",
        guestIp: guestIp,
        streamHost: streamHost,
        sunshineApiUrl: sunshineApiUrl,
        sunshineUsername: meta["sunshine-user"] || "",
        sunshinePassword: meta["sunshine-password"] || "",
        sunshinePin: meta["sunshine-pin"] || String(ctx.vmid % 10000).padStart(4, "0"),
        app: meta["moonlight-app"] || meta["sunshine-app"] || "Desktop",
        resolution: meta["moonlight-resolution"] || "auto",
        fps: meta["moonlight-fps"] || "60",
        bitrate: meta["moonlight-bitrate"] || "20000",
        codec: meta["moonlight-video-codec"] || "H.264",
        decoder: meta["moonlight-video-decoder"] || "auto",
        audio: meta["moonlight-audio-config"] || "stereo",
        proxmoxHost: meta["proxmox-host"] || window.location.hostname,
        installerUrl: resolveUsbInstallerUrl(ctx),
        controlPlaneHealthUrl: resolveControlPlaneHealthUrl(),
        managerUrl: managerUrlFromHealthUrl(resolveControlPlaneHealthUrl()),
        endpointSummary: endpointPayload && endpointPayload.endpoint ? endpointPayload.endpoint : null,
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
      endpoint_summary: profile.endpointSummary
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
                kvRow('Last Seen', escapeHtml(profile.endpointSummary && profile.endpointSummary.reported_at || '')) +
                kvRow('Target Reachable', escapeHtml(profile.endpointSummary && profile.endpointSummary.moonlight_target_reachable || '')) +
                kvRow('Sunshine Reachable', escapeHtml(profile.endpointSummary && profile.endpointSummary.sunshine_api_reachable || '')) +
                kvRow('Prepare', escapeHtml(profile.endpointSummary && profile.endpointSummary.prepare_state || '')) +
                kvRow('Last Launch', escapeHtml(profile.endpointSummary && profile.endpointSummary.last_launch_mode || '')) +
                kvRow('Launch Target', escapeHtml(profile.endpointSummary && profile.endpointSummary.last_launch_target || '')) +
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

  function integrate() {
    if (!(window.Ext && Ext.ComponentQuery)) {
      return;
    }

    Ext.ComponentQuery.query("pveConsoleButton").forEach(ensureConsoleButtonIntegration);
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
