(() => {
  const BUTTON_ID = "pve-dcv-open-btn";
  const DEFAULT_TEMPLATE = "https://{ip}:8443/";
  const DEFAULT_METADATA_KEYS = ["dcv-url", "dcv-host", "dcv-ip"];

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  function decodeHash() {
    try {
      return decodeURIComponent(window.location.hash || "");
    } catch {
      return window.location.hash || "";
    }
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
        // fallback below
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
        { urlTemplate: DEFAULT_TEMPLATE, fallbackUrl: "", metadataKeys: DEFAULT_METADATA_KEYS.join(",") },
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
    const output = { dcvUrl: null, dcvHost: null, dcvIp: null, raw: {} };
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
      output.raw[key] = value;

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

  async function onDcvClick() {
    const ctx = await parseVmContext();
    if (!ctx) {
      alert("DCV: Keine VM-Ansicht erkannt.");
      return;
    }

    const launchUrl = await buildLaunchUrl(ctx);
    if (!launchUrl) {
      alert(
        "DCV URL konnte nicht ermittelt werden.\\n" +
          "Pruefe QEMU Guest Agent oder setze dcv-url/dcv-host in die VM-Beschreibung."
      );
      return;
    }

    window.open(launchUrl, "_blank", "noopener,noreferrer");
  }

  function ensureButton() {
    const ctxHash = decodeHash();
    const looksLikeVm = /qemu\/(\d+)/i.test(ctxHash);

    const existing = document.getElementById(BUTTON_ID);
    if (!looksLikeVm) {
      if (existing) existing.remove();
      return;
    }

    if (existing) return;

    const btn = document.createElement("button");
    btn.id = BUTTON_ID;
    btn.textContent = "DCV";
    btn.type = "button";
    btn.style.position = "fixed";
    btn.style.right = "16px";
    btn.style.bottom = "16px";
    btn.style.zIndex = "99999";
    btn.style.padding = "10px 14px";
    btn.style.border = "0";
    btn.style.borderRadius = "10px";
    btn.style.cursor = "pointer";
    btn.style.fontWeight = "700";
    btn.style.background = "#0f62fe";
    btn.style.color = "#fff";
    btn.style.boxShadow = "0 8px 24px rgba(0,0,0,0.25)";
    btn.title = "Open NICE DCV";
    btn.addEventListener("click", onDcvClick);

    document.body.appendChild(btn);
  }

  async function boot() {
    for (let i = 0; i < 5; i += 1) {
      ensureButton();
      await sleep(500);
    }

    window.addEventListener("hashchange", ensureButton);
    const observer = new MutationObserver(() => ensureButton());
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  boot();
})();
