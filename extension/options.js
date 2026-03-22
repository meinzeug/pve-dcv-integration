function defaultUsbInstallerUrl() {
  return "https://{host}:8443/beagle-downloads/pve-thin-client-usb-installer-vm-{vmid}.sh";
}

function defaultControlPlaneHealthUrl() {
  return "https://{host}:8443/beagle-api/api/v1/health";
}

function loadOptions() {
  chrome.storage.sync.get(
    {
      usbInstallerUrl: defaultUsbInstallerUrl(),
      controlPlaneHealthUrl: defaultControlPlaneHealthUrl()
    },
    (data) => {
      document.getElementById("usbInstallerUrl").value =
        data.usbInstallerUrl || defaultUsbInstallerUrl();
      document.getElementById("controlPlaneHealthUrl").value =
        data.controlPlaneHealthUrl || defaultControlPlaneHealthUrl();
    }
  );
}

function saveOptions() {
  const usbInstallerUrl =
    document.getElementById("usbInstallerUrl").value.trim() || defaultUsbInstallerUrl();
  const controlPlaneHealthUrl =
    document.getElementById("controlPlaneHealthUrl").value.trim() || defaultControlPlaneHealthUrl();

  chrome.storage.sync.set({ usbInstallerUrl, controlPlaneHealthUrl }, () => {
    const status = document.getElementById("status");
    status.textContent = "Saved.";
    setTimeout(() => {
      status.textContent = "";
    }, 1500);
  });
}

document.getElementById("saveBtn").addEventListener("click", saveOptions);
loadOptions();
