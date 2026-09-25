---
tags: [homelab, network, storage, todo]
---

Designing the ideal setup for the new house and forecasting the impact of that migration is an excellent planning exercise. Since your network today is mature — running critical services such as **StênioBOT**, optimized Minecraft servers in Docker, home automation with Home Assistant via MQTT, and the Tailscale ecosystem — your focus should be **layer isolation**.

Below is the ideal network design for your profile, and the size of the effort this change involves.

## The Ideal Scenario: What I Would Do on the New Network

The biggest mistake in homelabs is letting the ISP modem manage the local network. For full control and stability, I would adopt the concept of **Bridge Mode Modem + Own Router**.

```
[Mundo Externo (Fibra)] 
          │
          ▼
[Modem da Operadora] ──(Modo Bridge)──> [Seu Roteador Próprio]
                                                │
       ┌────────────────────────────────────────┴────────────────────────────────────────┐
       ▼                                        ▼                                        ▼
[Rede IoT / Automação]                  [Rede Cabeada Física]                    [Rede Wi-Fi Principal]
(Lâmpadas, MQTT, HA)                     (Psicopompo, Linux)                      (Celulares, S10 FE+, PS5)
```

### 1. Centralize Control in Your Own Router

I would buy a robust router compatible with open-source systems like **OpenWrt** (if you want to get your hands dirty) or advanced off-the-shelf solutions (such as an ASUS router from the RT line, or a mini-PC running **pfSense/OPNsense** if you want to go corporate).

- **Action:** Put the ISP modem in **Bridge Mode** (where it becomes just an internet "pipe" and turns Wi-Fi off) and connect your own router behind it.
    
- **Benefit:** Your own router becomes the brain of the network. If you ever change ISP again in the future, you just plug the new modem into it in Bridge mode and **absolutely nothing** in your house needs reconfiguring.
    

### 2. Segmentation with VLANs (Security for Home Assistant)

Smart home automation devices (Wi-Fi bulbs, sensors) tend to run vulnerable Chinese firmwares.

- **Action:** On your new router, I would create a **VLAN** (an isolated virtual network) just for the IoT devices and the Mosquitto/MQTT broker.
    
- **Benefit:** Your bulbs can talk to Home Assistant, but if one of them is compromised, the intruder cannot see your _Psicopompo_ sleeper or your personal data.
    

### 3. Native IPv6 with Failover to the Tailnet

When you sign up with the new ISP (try to find one that delivers native IPv6, like the big fiber providers), you will configure your own router to receive that IPv6 block.

- **Action:** In the Tailscale panel, you can re-enable IPv6 without worry, because now your physical network knows where to route that traffic. Windows (`Psicopompo`) will never hit the little-planet bug again, Google Drive will sync instantly, and you will have real open ports to the world without relying on proxies if you do not want to.
    

## Work Estimate: How Big the Migration "Bill" Is

The good news is that using **Docker** and **Tailscale** in your current setup will drastically reduce your workload. You will not need to reconfigure servers from scratch. The work splits into three difficulty levels:

### Easy Level: Your Services and Containers (Effort: 5%)

Thanks to Docker, migrating your Linux server is practically a "copy and paste".

- Your Minecraft servers, the Home Assistant database and StênioBOT will come up identical in the new house as soon as you plug the Linux server in.
    
- Tailscale will find the machines on the internet and re-establish the tunnels 100% transparently, regardless of the new IP your provider gives you.
    

### Medium Level: Physical and Wi-Fi Infrastructure (Effort: 40%)

Here is the manual reconnection work:

- Run the network cables to _Psicopompo_ and to the Linux server in the new office.
    
- **The golden trick:** If you configure the Wi-Fi on your new router with **exactly the same SSID (network name) and the same password** as the current setup, all your smart bulbs, the Galaxy Tab S10 FE+ and the PS5 will connect on their own on the new network, without you having to reset them one by one.
    

### Hard Level: Static IP and DNS Adjustments (Effort: 55%)

This is the annoying part that will take care not to break the flow:

- The new modem will probably come with a different subnet (e.g. changing from `192.168.3.x` to `192.168.1.x`).
    
- You will have to redefine the static IPs of your Linux server and _Psicopompo_ for the new range.
    
- You will need to update the DNS mapping on the new modem to point at your Pi-hole's updated local IP, ensuring ad blocking keeps working for whoever is on the Wi-Fi.
    

### Verdict summary:

This will be **one weekend** of work. The first day spent running cables, mounting routers and bringing up the Wi-Fi; the second day focused on aligning the static IPs, adjusting Pi-hole on the new subnet, and testing the Home Assistant automations. In the end, with your own router in hand, you will have an infinitely more robust, future-proof network.