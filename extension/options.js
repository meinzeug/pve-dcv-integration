const DEFAULT_TEMPLATE = "https://{ip}:8443/";
const DEFAULT_METADATA_KEYS = "dcv-url,dcv-host,dcv-ip";
const DEFAULT_USB_INSTALLER_URL =
  "https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-thin-client-usb-installer-latest.sh";

function loadOptions() {
  chrome.storage.sync.get(
    {
      urlTemplate: DEFAULT_TEMPLATE,
      fallbackUrl: "",
      metadataKeys: DEFAULT_METADATA_KEYS,
      usbInstallerUrl: DEFAULT_USB_INSTALLER_URL
    },
    (data) => {
      document.getElementById("urlTemplate").value = data.urlTemplate || DEFAULT_TEMPLATE;
      document.getElementById("fallbackUrl").value = data.fallbackUrl || "";
      document.getElementById("metadataKeys").value = data.metadataKeys || DEFAULT_METADATA_KEYS;
      document.getElementById("usbInstallerUrl").value =
        data.usbInstallerUrl || DEFAULT_USB_INSTALLER_URL;
    }
  );
}

function saveOptions() {
  const urlTemplate = document.getElementById("urlTemplate").value.trim() || DEFAULT_TEMPLATE;
  const fallbackUrl = document.getElementById("fallbackUrl").value.trim();
  const metadataKeys = document.getElementById("metadataKeys").value.trim() || DEFAULT_METADATA_KEYS;
  const usbInstallerUrl =
    document.getElementById("usbInstallerUrl").value.trim() || DEFAULT_USB_INSTALLER_URL;

  chrome.storage.sync.set({ urlTemplate, fallbackUrl, metadataKeys, usbInstallerUrl }, () => {
    const status = document.getElementById("status");
    status.textContent = "Saved.";
    setTimeout(() => {
      status.textContent = "";
    }, 1500);
  });
}

document.getElementById("saveBtn").addEventListener("click", saveOptions);
loadOptions();
