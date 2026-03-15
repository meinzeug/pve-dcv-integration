(() => {
  const MENU_TEXT = "Konsole";
  const DCV_MENU_LABEL = "DCV";
  const USB_BUTTON_LABEL = "USB Installer";
  const BUTTON_MARKER = "data-pve-dcv-integration";
  const DEFAULT_TEMPLATE = "https://{ip}:8443/";
  const DEFAULT_METADATA_KEYS = ["dcv-url", "dcv-host", "dcv-ip"];
  const DEFAULT_USB_INSTALLER_URL =
    "https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-thin-client-usb-installer-latest.sh";

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
          urlTemplate: DEFAULT_TEMPLATE,
          fallbackUrl: "",
          metadataKeys: DEFAULT_METADATA_KEYS.join(","),
          usbInstallerUrl: DEFAULT_USB_INSTALLER_URL
        },
        (data) => resolve(data)
      );
    });
  }

  function firstUsefulIp(ifaces) {
    for (const iface of ifaces || []) {
      for (const addr of iface["ip-addresses"] || []) {
        if (addr["ip-address-type"] !== "ipv4") continue;
        const ip = addr["ip-address"] || "";
        if (!ip || ip.startsWith("127.") || ip.startsWith("169.254.")) continue;
        return ip;
      }
    }
    return null;
  }

  function pickCandidateIp(value) {
    const text = String(value || "").trim();
    if (!text) return null;
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(text)) return text;
    return null;
  }

  async function getVmIpViaAgent(node, vmid) {
    const endpoint = `/api2/json/nodes/${encodeURIComponent(node)}/qemu/${vmid}/agent/network-get-interfaces`;
    const res = await fetch(endpoint, { credentials: "same-origin" });
    if (!res.ok) {
      throw new Error(`agent endpoint failed: ${res.status}`);
    }
    const payload = await res.json();
    return firstUsefulIp(payload?.data?.result || []);
  }

  function parseDescriptionMeta(description, metadataKeys) {
    const output = { dcvUrl: null, dcvHost: null, dcvIp: null };
    const text = String(description || "");
    const keys = Array.from(
      new Set(
        [...DEFAULT_METADATA_KEYS, ...(metadataKeys || []).map((key) => key.trim()).filter(Boolean)]
      )
    );

    for (const key of keys) {
      const pattern = new RegExp(`${key}\\s*:\\s*([^\\n\\r]+)`, "i");
      const match = text.match(pattern);
      if (!match) continue;

      const value = match[1].trim();
      if (key === "dcv-url" && /^https?:\/\//i.test(value)) output.dcvUrl = value;
      if (key === "dcv-host" && !output.dcvHost) output.dcvHost = value;
      if (key === "dcv-ip" && !output.dcvIp) output.dcvIp = pickCandidateIp(value);
    }

    return output;
  }

  async function getVmConfig(node, vmid) {
    const endpoint = `/api2/json/nodes/${encodeURIComponent(node)}/qemu/${vmid}/config`;
    const res = await fetch(endpoint, { credentials: "same-origin" });
    if (!res.ok) {
      throw new Error(`config endpoint failed: ${res.status}`);
    }
    const payload = await res.json();
    return payload?.data || {};
  }

  function fillTemplate(template, values) {
    return template
      .replaceAll("{ip}", values.ip || "")
      .replaceAll("{node}", values.node || "")
      .replaceAll("{vmid}", String(values.vmid || ""))
      .replaceAll("{host}", values.host || "");
  }

  async function buildLaunchUrl(ctx) {
    const options = await getOptions();
    const host = window.location.hostname;
    const metadataKeys = String(options.metadataKeys || "")
      .split(",")
      .map((key) => key.trim())
      .filter(Boolean);

    let ip = null;
    let dcvUrl = null;
    let dcvHost = null;
    let dcvIp = null;

    try {
      ip = await getVmIpViaAgent(ctx.node, ctx.vmid);
    } catch {
      // continue with config fallback
    }

    try {
      const cfg = await getVmConfig(ctx.node, ctx.vmid);
      const meta = parseDescriptionMeta(cfg.description || "", metadataKeys);
      dcvUrl = meta.dcvUrl;
      dcvHost = meta.dcvHost;
      dcvIp = meta.dcvIp;
    } catch {
      // keep fallbacks empty
    }

    if (dcvUrl) return dcvUrl;
    if (!ip && dcvIp) ip = dcvIp;
    if (!ip && dcvHost) ip = dcvHost;

    if (ip) {
      const url = fillTemplate(options.urlTemplate || DEFAULT_TEMPLATE, {
        ip,
        node: ctx.node,
        vmid: ctx.vmid,
        host
      });
      if (url.startsWith("http://") || url.startsWith("https://")) {
        return url;
      }
    }

    if (options.fallbackUrl) return options.fallbackUrl;
    return null;
  }

  async function openDcv() {
    const ctx = await parseVmContext();
    if (!ctx) {
      alert("DCV: Keine VM-Ansicht erkannt.");
      return;
    }

    const launchUrl = await buildLaunchUrl(ctx);
    if (!launchUrl) {
      alert(
        "DCV URL konnte nicht ermittelt werden.\n" +
          "Pruefe QEMU Guest Agent oder setze dcv-url/dcv-host in die VM-Beschreibung."
      );
      return;
    }

    window.open(launchUrl, "_blank", "noopener,noreferrer");
  }

  async function downloadUsbInstaller() {
    const options = await getOptions();
    const url = String(options.usbInstallerUrl || DEFAULT_USB_INSTALLER_URL).trim();
    if (!url) {
      alert("USB Installer URL ist nicht konfiguriert.");
      return;
    }
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

    const existingUsb = toolbar.querySelector(`[${BUTTON_MARKER}="${USB_BUTTON_LABEL}"]`);
    if (!existingUsb) {
      const usbButton = createToolbarButton(USB_BUTTON_LABEL, downloadUsbInstaller);
      toolbar.appendChild(usbButton);
    }
  }

  function getVisibleMenu() {
    const menus = Array.from(document.querySelectorAll(".x-menu, [role='menu']"));
    return menus.find((menu) => menu.offsetParent !== null) || null;
  }

  function menuAlreadyHasDcv(menu) {
    return Array.from(menu.querySelectorAll("*")).some((node) => String(node.textContent || "").trim() === DCV_MENU_LABEL);
  }

  function createDcvMenuItem() {
    const item = document.createElement("a");
    item.href = "#";
    item.setAttribute(BUTTON_MARKER, DCV_MENU_LABEL);
    item.className = "x-menu-item";
    item.style.display = "block";
    item.style.padding = "4px 24px 4px 24px";
    item.style.cursor = "pointer";
    item.textContent = DCV_MENU_LABEL;
    item.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      openDcv();
    });
    return item;
  }

  function ensureDcvMenuItem() {
    if (!isVmView()) return;
    const menu = getVisibleMenu();
    if (!menu) return;

    const hasConsoleItems = Array.from(menu.querySelectorAll("*")).some((node) => {
      const text = String(node.textContent || "").trim();
      return text === "noVNC" || text === "SPICE";
    });

    if (!hasConsoleItems || menuAlreadyHasDcv(menu)) return;
    menu.appendChild(createDcvMenuItem());
  }

  async function boot() {
    for (let i = 0; i < 12; i += 1) {
      ensureToolbarButtons();
      ensureDcvMenuItem();
      await sleep(500);
    }

    window.addEventListener("hashchange", () => {
      ensureToolbarButtons();
      ensureDcvMenuItem();
    });

    document.addEventListener(
      "click",
      () => {
        window.setTimeout(() => {
          ensureToolbarButtons();
          ensureDcvMenuItem();
        }, 50);
      },
      true
    );

    const observer = new MutationObserver(() => {
      ensureToolbarButtons();
      ensureDcvMenuItem();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  boot();
})();
