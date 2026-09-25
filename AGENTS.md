---
tags: [meta, agents, governance, homelab]
---

# AGENTS.md — Mnemocine Homelab Governance Rules

This repository contains the public documentation, architectural manifests, and network topologies of the **Mnemocine Homelab**.

When modifying any file in this repository, follow these mandatory governance rules:

## 🔒 Security Rules & Secret Protection

1. **ABSOLUTE PROHIBITION OF PLAINTEXT SECRETS (`SEC-SECRETS`)** — No file containing private keys, passwords, API tokens, or production credentials may be committed. All examples must use fictional values or environment variable references (`.env.template`).

2. **PROHIBITION OF REAL ENCRYPTED FILES IN PUBLIC** — The `secrets.enc.env` file from the SOPS/Age vault is strictly forbidden in this public repository. Only `.env.template` may be present.

3. **MANDATORY STÊNIOSENTINEL CHECK (RULE 0)** — Before any commit, it is mandatory to run `stenio --scope homelab --path .`. The Quality Gate must approve with zero blocking errors.

4. **LINK AND NAMING INTEGRITY** — All relative markdown links must point to existing documents. Service files must live in `services/`, servers in `servers/`, and guides in `guides/`.

5. **STANDARD DISCLAIMER IN THE README** — The root `README.md` must keep the standardized human-AI governance disclaimer:
   ```markdown
   <div align="center">

   > **Yes... This is a Vibe Coded project**
   >
   > Governed by 🤖 **StenioSentinel** (our Rust-based AI Governance Sentinel) with **Carlos Eduardo Rodrigues** ([@ceduardorodrig](https://github.com/ceduardorodrig)).

   </div>
   ```
