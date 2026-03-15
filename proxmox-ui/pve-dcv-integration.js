(function() {
  "use strict";

  var DEFAULTS = {
    urlTemplate: "https://{ip}:8443/",
    fallbackUrl: "",
    metadataKeys: ["dcv-url", "dcv-host", "dcv-ip", "dcv-user", "dcv-password", "dcv-auth-token", "dcv-session", "dcv-auto-submit"],
    usbInstallerUrl: "https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-thin-client-usb-installer-latest.sh"
  };

  function getConfig() {
    var runtimeConfig = window.PVEDCVIntegrationConfig || {};
    return {
      urlTemplate: runtimeConfig.urlTemplate || DEFAULTS.urlTemplate,
      fallbackUrl: runtimeConfig.fallbackUrl || DEFAULTS.fallbackUrl,
      metadataKeys: Array.isArray(runtimeConfig.metadataKeys) ? runtimeConfig.metadataKeys : DEFAULTS.metadataKeys,
      usbInstallerUrl: runtimeConfig.usbInstallerUrl || DEFAULTS.usbInstallerUrl
    };
  }

  function firstUsefulIp(ifaces) {
    for (var i = 0; i < (ifaces || []).length; i += 1) {
      var iface = ifaces[i];
      var addresses = iface["ip-addresses"] || [];
      for (var j = 0; j < addresses.length; j += 1) {
        var addr = addresses[j];
        var ip = addr["ip-address"] || "";
        if (addr["ip-address-type"] !== "ipv4") continue;
        if (!ip || ip.indexOf("127.") === 0 || ip.indexOf("169.254.") === 0) continue;
        return ip;
      }
    }
    return null;
  }

  function parseDescriptionMeta(description, metadataKeys) {
    var text = String(description || "");
    var result = {
      dcvUrl: null,
      dcvHost: null,
      dcvIp: null,
      dcvUser: null,
      dcvPassword: null,
      dcvAuthToken: null,
      dcvSession: null,
      dcvAutoSubmit: true
    };
    var keys = Array.from(new Set(DEFAULTS.metadataKeys.concat(metadataKeys || [])));

    keys.forEach(function(key) {
      var match = text.match(new RegExp(key + "\\s*:\\s*([^\\n\\r]+)", "i"));
      if (!match) return;
      var value = String(match[1] || "").trim();
      if (key === "dcv-url" && /^https?:\/\//i.test(value)) result.dcvUrl = value;
      if (key === "dcv-host" && !result.dcvHost) result.dcvHost = value;
      if (key === "dcv-ip" && !result.dcvIp && /^\d{1,3}(\.\d{1,3}){3}$/.test(value)) result.dcvIp = value;
      if (key === "dcv-user" && !result.dcvUser) result.dcvUser = value;
      if (key === "dcv-password" && !result.dcvPassword) result.dcvPassword = value;
      if (key === "dcv-auth-token" && !result.dcvAuthToken) result.dcvAuthToken = value;
      if (key === "dcv-session" && !result.dcvSession) result.dcvSession = value;
      if (key === "dcv-auto-submit") result.dcvAutoSubmit = !/^(0|false|no)$/i.test(value);
    });

    return result;
  }

  function applyDcvLaunchMetadata(rawUrl, meta) {
    var url;

    try {
      url = new URL(rawUrl, window.location.origin);
    } catch (error) {
      return rawUrl;
    }

    if (meta.dcvAuthToken && !url.searchParams.get("authToken")) {
      url.searchParams.set("authToken", meta.dcvAuthToken);
    }

    if (meta.dcvSession && !url.hash) {
      url.hash = meta.dcvSession;
    }

    if (!meta.dcvAuthToken) {
      if (meta.dcvUser) url.searchParams.set("pveDcvUser", meta.dcvUser);
      if (meta.dcvPassword) url.searchParams.set("pveDcvPassword", meta.dcvPassword);
      url.searchParams.set("pveDcvAutoSubmit", meta.dcvAutoSubmit ? "1" : "0");
    }

    return url.toString();
  }

  function fillTemplate(template, values) {
    return template
      .replaceAll("{ip}", values.ip || "")
      .replaceAll("{node}", values.node || "")
      .replaceAll("{vmid}", String(values.vmid || ""))
      .replaceAll("{host}", values.host || "");
  }

  function buildLaunchUrl(ctx) {
    var config = getConfig();
    var host = window.location.hostname;
    var ip = null;
    var meta = {
      dcvUrl: null,
      dcvHost: null,
      dcvIp: null,
      dcvUser: null,
      dcvPassword: null,
      dcvAuthToken: null,
      dcvSession: null,
      dcvAutoSubmit: true
    };

    function loadConfig() {
      return fetch("/api2/json/nodes/" + encodeURIComponent(ctx.node) + "/qemu/" + ctx.vmid + "/config", {
        credentials: "same-origin"
      })
        .then(function(res) {
          return res.ok ? res.json() : { data: {} };
        })
        .then(function(payload) {
          meta = parseDescriptionMeta(payload.data && payload.data.description, config.metadataKeys);
        });
    }

    function loadAgent() {
      return fetch("/api2/json/nodes/" + encodeURIComponent(ctx.node) + "/qemu/" + ctx.vmid + "/agent/network-get-interfaces", {
        credentials: "same-origin"
      })
        .then(function(res) {
          if (!res.ok) return null;
          return res.json();
        })
        .then(function(payload) {
          if (payload && payload.data && payload.data.result) {
            ip = firstUsefulIp(payload.data.result);
          }
        })
        .catch(function() {
          return null;
        });
    }

    return loadAgent()
      .then(loadConfig)
      .then(function() {
        var baseUrl = meta.dcvUrl;
        if (!ip && meta.dcvIp) ip = meta.dcvIp;
        if (!ip && meta.dcvHost) ip = meta.dcvHost;
        if (ip) {
          baseUrl = fillTemplate(config.urlTemplate, {
            ip: ip,
            node: ctx.node,
            vmid: ctx.vmid,
            host: host
          });
        }
        if (!baseUrl) baseUrl = config.fallbackUrl || null;
        return baseUrl ? applyDcvLaunchMetadata(baseUrl, meta) : null;
      });
  }

  function showError(message) {
    if (window.Ext && Ext.Msg && Ext.Msg.alert) {
      Ext.Msg.alert("PVE DCV Integration", message);
    } else {
      window.alert(message);
    }
  }

  function openDcvForContext(ctx) {
    buildLaunchUrl(ctx).then(function(url) {
      if (!url) {
        showError("DCV URL konnte nicht ermittelt werden. Pruefe Guest Agent oder VM-Beschreibung.");
        return;
      }
      window.open(url, "_blank", "noopener,noreferrer");
    });
  }

  function openUsbInstaller() {
    window.open(getConfig().usbInstallerUrl, "_blank", "noopener,noreferrer");
  }

  function ensureConsoleButtonIntegration(button) {
    if (!button || !button.vmid || button.consoleType !== "kvm" || button.__pveDcvIntegrated) {
      return;
    }

    var menu = button.getMenu ? button.getMenu() : button.menu;
    if (menu && !menu.down("#pveDcvMenuItem")) {
      menu.add({
        itemId: "pveDcvMenuItem",
        text: "DCV",
        iconCls: "fa fa-desktop",
        handler: function() {
          openDcvForContext({ node: button.nodename, vmid: button.vmid });
        }
      });
    }

    var toolbar = button.up && button.up("toolbar");
    if (toolbar && !toolbar.down("#pveUsbInstallerButton")) {
      var index = toolbar.items.indexOf(button);
      toolbar.insert(index + 1, {
        xtype: "button",
        itemId: "pveUsbInstallerButton",
        text: "USB Installer",
        iconCls: "fa fa-download",
        handler: openUsbInstaller
      });
    }

    button.__pveDcvIntegrated = true;
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
