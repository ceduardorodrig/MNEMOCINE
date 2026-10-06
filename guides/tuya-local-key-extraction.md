---
tags: [homelab, service, home-assistant, automation]
---

# Tuya Local Key Extraction & Offline Migration Runbook

Comprehensive guide and runbook for extracting Tuya device encryption keys (`local_key`), discovering local device IPs, and migrating Tuya Wi-Fi devices from the cloud integration to 100% offline local control using **Tuya Local** (`make-all/tuya-local`).

## 1. Problem Statement

Consumer IoT devices running Tuya firmware (e.g., smart bulbs, plugs, relays) are typically bound to the Smart Life or Tuya Smart mobile applications. While Home Assistant offers an official cloud integration (`tuya`), it relies on remote Tuya cloud servers, causing:
1. High command latency (often 500ms – 2s).
2. Complete automation failure if internet access is interrupted.
3. Dependence on external API quotas and Tuya developer subscription expiration.

Extracting the 16-character AES encryption key (`local_key`) allows Home Assistant to speak directly to the device on the local network (port TCP 6668 / protocol v3.3/v3.5) with sub-10ms response times and zero internet dependency.

## 2. Zero-Portal Key Extraction Method

Traditional extraction requires logging into the Tuya Developer Platform (`platform.tuya.com`), creating a cloud development project, and linking the mobile app. 

When Home Assistant already has the official **Tuya (Cloud)** integration configured, the container already possesses an active OAuth session token in `/config/.storage/core.config_entries`. We can use Home Assistant's internal `tuya_sharing` module to retrieve the `local_key` of every paired device directly from the API session without visiting any web portal.

### Python Extraction Script

Run inside the `homeassistant` container (or via SSH on the host):

```python
import json
from tuya_sharing import Manager
from homeassistant.components.tuya.const import TUYA_CLIENT_ID

# 1. Read existing Tuya cloud session data
with open("/config/.storage/core.config_entries") as f:
    entries = json.load(f)["data"]["entries"]

tuya_entry = [e for e in entries if e["domain"] == "tuya"][0]
data = tuya_entry["data"]

# 2. Initialize Tuya sharing manager
manager = Manager(
    TUYA_CLIENT_ID,
    data["user_code"],
    data["terminal_id"],
    data["endpoint"],
    data["token_info"],
)

# 3. Pull device metadata and local keys from session cache
manager.update_device_cache()
for dev_id, dev in manager.device_map.items():
    print(f"Device: {dev.name} | ID: {dev_id} | LocalKey: {dev.local_key} | ProductID: {dev.product_id}")
```

This immediately outputs the Device ID, Product ID, and AES `local_key` for every device in the account.

## 3. Local IP & Protocol Discovery

Once the `device_id` and `local_key` are known:

1. **Locate Device MAC & IP via ARP / Subnet Router:**
   Tuya devices commonly use Espressif/Tuya MAC OUIs (`50:8B:B9`, `18:69:D8`, `D8:C8:0C`, etc.).
   ```bash
   ip neigh show | grep -E "50:8b:b9|d8:c8:0c"
   ```

2. **Probe Local Port & Protocol (via `tinytuya`):**
   ```python
   import tinytuya

   d = tinytuya.BulbDevice(dev_id, ip, local_key)
   d.set_version(3.5)  # Test 3.5, 3.4, or 3.3
   status = d.status()
   print(status)
   ```

## 4. Setting Up Tuya Local in Home Assistant

1. **Install Component:**
   Clone or extract `custom_components/tuya_local` into `/srv/data/homeassistant/config/custom_components/tuya_local`.
2. **Register Device Product ID (if required):**
   Add the hardware `product_id` (e.g. `xtsnfp5zitrmrvcm` for Pera NEO 10W) under the `products:` block of the matching device template in `custom_components/tuya_local/devices/`.
3. **Add Devices via UI:**
   In *Settings > Devices & Services > Add Integration > Tuya Local*:
   - Select **Manually provide device connection information**.
   - Input Name, IP (`Host`), Device ID, and Local Key.
   - Select Protocol Version (e.g. `3.5`).
4. **Seamless Entity Swap (Preserving Automations & Adaptive Lighting):**
   If existing automations reference old cloud entity IDs (e.g. `light.desk_lamp`):
   - Disable the old cloud light entity in the Entity Registry.
   - Rename the new local entity (initially created as `light.desk_lamp_2`) to `light.desk_lamp`.
   - Automations and Adaptive Lighting immediately switch to controlling the local device seamlessly.

## 5. Security & Backup

All extracted Tuya local keys must be stored in the homelab's central secret repository:
- Master plaintext (0600): `/mnt/NVME_PCI/secrets/secrets.env`
- Encrypted repository mirror: `mnemocine/secrets.enc.env` (via `sops --encrypt --age`)
