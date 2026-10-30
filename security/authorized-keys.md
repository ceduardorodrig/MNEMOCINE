---
tags: [homelab, security, ssh, audit, canon]
---

# Canonical SSH Authorized Keys Matrix (Mnemocine)

Single source of truth for authorized SSH public keys across all nodes in the homelab fleet.
Monitored by the security audit sentinel. Any key detected on a host outside this inventory triggers an immediate alert.

## Authorized Keys Inventory

### 1. Primary Operator (Carlos Eduardo / Psicopompo)
- **Key Type:** `ssh-ed25519`
- **Comment:** `edu@psicopompo`
- **Hosts Deployed:** `kuaray`, `kavure`
- **Public Key:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXJTSYAoRuUGfKmafqAlRh+88mwomFVi3AjhOhLWSac edu@psicopompo`

- **Key Type:** `ssh-ed25519`
- **Comment:** `edu@Psicopompo` (legacy desktop)
- **Hosts Deployed:** `kuaray`
- **Public Key:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHSEOzrRCPpzgH3C/UHseEym/ijhE1PKFUvu08FAVBe7 edu@Psicopompo`

### 2. Infrastructure Backup Node (Kavure → Psicopompo)
- **Key Type:** `ssh-ed25519`
- **Comment:** `kavure`
- **Hosts Deployed:** `psicopompo` (for automated backup pulls)
- **Public Key:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMf/QaXdHsw7izutxZ1uXtiUEC+ki4toC1RwItQxZw5 kavure`

### 3. Oracle Cloud Infrastructure (OCI Free Tier Bastion/Provisioning)
- **Host:** `ybytu`
- **Key Type:** `ssh-rsa`
- **Comment:** `ssh-key-2026-05-23`
- **Restrictions (Root):** `no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="echo 'Please login as the user \"ubuntu\"...'"`
- **Public Key:** `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDAMmPhFi2OLCsR5a1W7cEbHoBVZwn/8h2RQavSlV2v0cVBIfA3WARDS6jxKsjiLaoW93DSh9f7ghTxZKRk/kbffWfad0Yz2Nmf7lGLoQl1K2n0PqV0CLeGlwZtv9wMPDm+hY/qVT7Ly7kQtlmBMU1T8kf7yM8BaSVEeQHxfYjxvNAI4vc/68QOGaTdfTFLdqUOMB64/TPwutXumcMonWPdk50SZjkis44KL59uT8U5SD3rqfstFX3WKDVTthtorTC9Z3M6sDS6XgGFPSpjHw5Fnqf9oF/peWlMECdVR+Uz0SYR8nrfdcKCniXHDIDmN2oyYGlt//FqpJU/ixLlG4Wj ssh-key-2026-05-23`

- **Host:** `ybyra`
- **Key Type:** `ssh-rsa`
- **Comment:** `ssh-key-2026-06-05`
- **Restrictions (Root):** `no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="echo 'Please login as the user \"ubuntu\"...'"`
- **Public Key:** `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBS3p6CyRFM+kc3g45KLfw8drG0qdxMGDQp5K06uRcbfLJbH/FLzcCuzqrhEGTAG58FVetz0kvgfLyeilCXDCF6Tc/WX3wQ2oztizjkz6pEV3HU+rKWc14PvTFFnYQxp4KWuAAZ/s93pfm6U2orbiHeuHUO60JgPyNluxAFYroXx0tM5MVote8pKJrNto5zqZsryY91EgqqWI2cNG4GGpTkxwXLLye1oZbdkSCOEt6bPGYhaCeyaGEAKmAoeTgAcUd2gI6K6C+CWVyz3JToo8oZS5S6nkQ1bLE/LNAdxSOFwrQqqHasSJTrsmNYndjHCmRoutR0hRWPqBndT8FJWqh ssh-key-2026-06-05`
