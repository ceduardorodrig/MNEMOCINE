---
tags: [homelab, oracle, oci, cloud, tutorial, sops]
---

# Oracle Cloud Infrastructure (OCI) — CLI/API Management

> **Standard established 2026-10-08:** Homelab cloud instances (**ybytu**, **ybyra**) are managed programmatically via **OCI CLI directly from the terminal** on **psicopompo**. Covers: instance inventories, lifecycle management, boot/block volumes, virtual networking (subnets/VNICs), images, and the **Always Free ARM VM automated capture pipeline**. Eliminates reliance on the Oracle web console.

## Architecture

```
psicopompo (terminal)   ──RSA API Key (request signing)──►   OCI · sa-saopaulo-1
  ~/.oci/config + private key                               tenancy ceduardorodrig
  (hydrated from SOPS vault)                                ├── ybytu  (VM.Standard.E2.1.Micro)
                                                            └── ybyra  (VM.Standard.E2.1.Micro)
```

- **Authentication:** **RSA API Key** (cryptographic request signing). The key pair is generated and persisted on psicopompo; only the public key was uploaded to OCI.
- **Credentials:** Securely managed within the **SOPS encrypted vault** (`OCI_*` in `secrets.enc.env`).
- **Region:** `sa-saopaulo-1` (the tenancy home region — Always Free tier resources are strictly restricted to home regions).

## Secrets Storage (SOPS Vault)

| Variable | Description |
|---|---|
| `OCI_USER_ID` | User OCID (`ceduardorodrig@gmail.com`) |
| `OCI_TENANCY_ID` | Tenancy root OCID |
| `OCI_FINGERPRINT` | API key fingerprint (`46:b4:f0:…`) |
| `OCI_REGION` | Home region identifier (`sa-saopaulo-1`) |
| `OCI_PRIVATE_KEY_B64` | Base64-encoded RSA private key PEM (retaining Oracle security markers) |

**Restore Command** (materializes `~/.oci/config` and the private key on psicopompo):

```bash
/mnt/NVME_PCI/secrets/oci-restore.sh
```

## CLI Installation & Execution Environment

The Oracle CLI is a Python package. It is installed in an isolated environment via `uv`, pinned strictly to **Python 3.11** to prevent upstream regex escape syntax warnings present in Python 3.12:

```bash
uv tool install oci-cli --python 3.11
# Binary location: ~/.local/bin/oci
```

## Essential CLI Commands

```bash
# Load tenancy context
export T="$(/mnt/NVME_PCI/secrets/sops-decrypt.sh OCI_TENANCY_ID)"

# Query instance states
oci compute instance list --compartment-id "$T" --output table \
  --query 'data[].{nome:"display-name", estado:"lifecycle-state", shape:shape, ad:"availability-domain"}'

# Query boot and block volumes
oci bv boot-volume list --compartment-id "$T" --output table

# Check compute quota availability (standard A1 ARM cores)
oci limits resource-availability get --service-name compute \
  --limit-name standard-a1-core-count --compartment-id "$T" \
  --availability-domain 'WdCV:SA-SAOPAULO-1-AD-1'
```

## Free Tier Quotas & Constraints (Measured 2026-10-08)

| Metric | Account Value | Operational Constraint |
|---|---|---|
| Block Storage Quota | **200 GB** | ybytu (50 GB) + ybyra (150 GB) = 200 GB (100% capacity). Shrinking ybyra required to release space for ARM. |
| `custom-image-count` | **0** | Custom image creation is disallowed; instances must be re-provisioned from platform base images. |
| ARM A1 Compute Quota | 2 OCPU / 12 GB (`available: 2`) | Account quota exists; bottleneck is physical data center host capacity. |
| Availability Domains | 1 (`WdCV:SA-SAOPAULO-1-AD-1`) | Single AD data center region. |

## Rationale: Automating ARM VM Capture

The Always Free ARM allowance (`VM.Standard.A1.Flex`) grants up to **2 OCPU / 12 GB RAM**. Account verification confirms quota availability (`available: 2`), but Oracle returns frequent `Out of host capacity` errors when launch requests hit capacity limits. The OCI CLI enables automated background polling (`arm-hunt`) to claim instances immediately as compute slots open.

## Security Controls

- The private signing key exists exclusively on psicopompo (permissions `0600`) and inside the encrypted SOPS store.
- Revocation: Deleting the public key from the OCI IAM console immediately invalidates the API credential.

## See Also

- [`guides/secrets-centralizados.md`](secrets-centralizados.md) — SOPS vault architecture
- [`guides/oracle-arm-capture.md`](oracle-arm-capture.md) — Automated `arm-hunt` polling loop
- [`guides/oci-shrink-boot-volume.md`](oci-shrink-boot-volume.md) — Storage reallocation runbook
