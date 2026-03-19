(() => {
  const MENU_TEXT = "Konsole";
  const THIN_CLIENT_LABEL = "Thin Client";
  const BUTTON_MARKER = "data-pve-dcv-integration";
  const DEFAULT_TEMPLATE = "https://{ip}:8443/";
  const DEFAULT_METADATA_KEYS = ["dcv-url", "dcv-host", "dcv-ip", "dcv-user", "dcv-password", "dcv-auth-token", "dcv-session", "dcv-auto-submit"];

  function defaultUsbInstallerUrl() {
    return "https://{host}:8443/pve-dcv-downloads/pve-thin-client-usb-installer-vm-{vmid}.sh";
  }

  function defaultDownloadsStatusUrl() {
    return `https://${window.location.hostname}:8443/pve-dcv-downloads/pve-dcv-downloads-status.json`;
  }

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

  function setInputValue(input, value) {
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
    if (setter) {
      setter.call(input, value);
    } else {
      input.value = value;
    }
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function cleanupAutoLoginParams() {
    const url = new URL(window.location.href);
    let changed = false;

    ["pveDcvUser", "pveDcvPassword", "pveDcvAutoSubmit"].forEach((key) => {
      if (!url.searchParams.has(key)) return;
      url.searchParams.delete(key);
      changed = true;
    });

    if (changed) {
      window.history.replaceState({}, document.title, url.toString());
    }
  }

  function startDcvAutoLogin() {
    const url = new URL(window.location.href);
    const username = url.searchParams.get("pveDcvUser") || "";
    const password = url.searchParams.get("pveDcvPassword") || "";
    const autoSubmit = url.searchParams.get("pveDcvAutoSubmit") !== "0";

    if (!username && !password) return;

    cleanupAutoLoginParams();

    let attempts = 0;
    const timer = window.setInterval(() => {
      attempts += 1;

      const inputs = Array.from(document.querySelectorAll("input"));
      const userInput =
        inputs.find((input) => /user/i.test(String(input.name || input.id || input.placeholder || ""))) ||
        inputs.find((input) => input.type === "text" || input.type === "email" || !input.type);
      const passwordInput = inputs.find((input) => input.type === "password");

      if (userInput && username && userInput.value !== username) {
        setInputValue(userInput, username);
      }

      if (passwordInput && password && passwordInput.value !== password) {
        setInputValue(passwordInput, password);
      }

      if (autoSubmit && userInput && passwordInput && (!username || userInput.value === username) && (!password || passwordInput.value === password)) {
        const button = Array.from(document.querySelectorAll("button, input[type='submit'], [role='button']")).find((node) =>
          /sign in|login|anmelden/i.test(String(node.textContent || node.value || ""))
        );
        if (button) {
          button.click();
          window.clearInterval(timer);
          return;
        }
      }

      if (attempts >= 60) {
        window.clearInterval(timer);
      }
    }, 500);
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
          usbInstallerUrl: defaultUsbInstallerUrl(),
          downloadsStatusUrl: defaultDownloadsStatusUrl()
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
    const output = {
      dcvUrl: null,
      dcvHost: null,
      dcvIp: null,
      dcvUser: null,
      dcvPassword: null,
      dcvAuthToken: null,
      dcvSession: null,
      dcvAutoSubmit: true
    };
    const text = String(description || "").replace(/\\r\\n/g, "\n").replace(/\\n/g, "\n");
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
      if (key === "dcv-user" && !output.dcvUser) output.dcvUser = value;
      if (key === "dcv-password" && !output.dcvPassword) output.dcvPassword = value;
      if (key === "dcv-auth-token" && !output.dcvAuthToken) output.dcvAuthToken = value;
      if (key === "dcv-session" && !output.dcvSession) output.dcvSession = value;
      if (key === "dcv-auto-submit") output.dcvAutoSubmit = !/^(0|false|no)$/i.test(value);
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

  function resolveUsbInstallerUrl(ctx, template) {
    return fillTemplate(String(template || defaultUsbInstallerUrl()).trim(), {
      ip: "",
      node: ctx?.node || "",
      vmid: ctx?.vmid || "",
      host: window.location.hostname
    });
  }

  function applyDcvLaunchMetadata(rawUrl, meta) {
    let url;

    try {
      url = new URL(rawUrl, window.location.origin);
    } catch {
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

  async function resolveLaunchState(ctx) {
    const options = await getOptions();
    const host = window.location.hostname;
    const metadataKeys = String(options.metadataKeys || "")
      .split(",")
      .map((key) => key.trim())
      .filter(Boolean);

    let ip = null;
    let meta = {
      dcvUrl: null,
      dcvHost: null,
      dcvIp: null,
      dcvUser: null,
      dcvPassword: null,
      dcvAuthToken: null,
      dcvSession: null,
      dcvAutoSubmit: true
    };

    try {
      ip = await getVmIpViaAgent(ctx.node, ctx.vmid);
    } catch {
      // continue with config fallback
    }

    try {
      const cfg = await getVmConfig(ctx.node, ctx.vmid);
      meta = parseDescriptionMeta(cfg.description || "", metadataKeys);
    } catch {
      // keep fallbacks empty
    }

    let baseUrl = meta.dcvUrl;
    let source = "metadata:dcv-url";
    if (!ip && meta.dcvIp) ip = meta.dcvIp;
    if (!ip && meta.dcvHost) ip = meta.dcvHost;

    if (!baseUrl && ip) {
      source = meta.dcvIp ? "metadata:dcv-ip" : (meta.dcvHost ? "metadata:dcv-host" : "agent-or-template");
      baseUrl = fillTemplate(options.urlTemplate || DEFAULT_TEMPLATE, {
        ip,
        node: ctx.node,
        vmid: ctx.vmid,
        host
      });
    }

    if (!baseUrl && options.fallbackUrl) {
      source = "fallback-url";
      baseUrl = options.fallbackUrl;
    }

    return {
      launchUrl: baseUrl ? applyDcvLaunchMetadata(baseUrl, meta) : null,
      baseUrl,
      ip,
      source: baseUrl ? source : "unresolved",
      meta,
      downloadsStatusUrl: String(options.downloadsStatusUrl || defaultDownloadsStatusUrl()).trim(),
      usbInstallerUrl: String(options.usbInstallerUrl || defaultUsbInstallerUrl()).trim()
    };
  }

  async function buildLaunchUrl(ctx) {
    const state = await resolveLaunchState(ctx);
    return state.launchUrl;
  }

  async function copyText(text, successMessage) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const input = document.createElement("textarea");
    input.value = text;
    document.body.appendChild(input);
    input.select();
    try {
      document.execCommand("copy");
    } finally {
      document.body.removeChild(input);
    }
    if (successMessage) {
      console.info(successMessage);
    }
  }

  async function downloadUsbInstaller() {
    const ctx = await parseVmContext();
    if (!ctx) {
      alert("USB Installer: Keine VM-Ansicht erkannt.");
      return;
    }

    const options = await getOptions();
    const url = resolveUsbInstallerUrl(ctx, options.usbInstallerUrl || defaultUsbInstallerUrl());
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

    const existingThinClient = toolbar.querySelector(`[${BUTTON_MARKER}="${THIN_CLIENT_LABEL}"]`);
    if (!existingThinClient) {
      const thinClientButton = createToolbarButton(THIN_CLIENT_LABEL, downloadUsbInstaller);
      thinClientButton.title = "Laedt den vorkonfigurierten Thin-Client-USB-Installer fuer diese VM herunter.";
      toolbar.appendChild(thinClientButton);
    }
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
    item.style.padding = "4px 24px 4px 24px";
    item.style.cursor = "pointer";
    item.textContent = label;
    item.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      onClick();
    });
    return item;
  }

  function ensureThinClientMenuItem() {
    if (!isVmView()) return;
    const menu = getVisibleMenu();
    if (!menu) return;

    const hasConsoleItems = Array.from(menu.querySelectorAll("*")).some((node) => {
      const text = String(node.textContent || "").trim();
      return text === "noVNC" || text === "SPICE";
    });

    if (!hasConsoleItems) return;
    if (!menuAlreadyHasLabel(menu, THIN_CLIENT_LABEL)) menu.appendChild(createMenuItem(THIN_CLIENT_LABEL, downloadUsbInstaller));
  }

  async function boot() {
    startDcvAutoLogin();

    for (let i = 0; i < 12; i += 1) {
      ensureToolbarButtons();
      ensureThinClientMenuItem();
      await sleep(500);
    }

    window.addEventListener("hashchange", () => {
      ensureToolbarButtons();
      ensureThinClientMenuItem();
    });

    document.addEventListener(
      "click",
      () => {
        window.setTimeout(() => {
          ensureToolbarButtons();
          ensureThinClientMenuItem();
        }, 50);
      },
      true
    );

    const observer = new MutationObserver(() => {
      ensureToolbarButtons();
      ensureThinClientMenuItem();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  boot();
})();
