---
tags: [homelab, cold-storage, docker, tutorial]
---

# Cold Storage de Serviços (homelab)

**Metodologia** para **congelar** um serviço do homelab: ele deixa de rodar, mas continua
existindo como artefato recuperável — **não sobe sem querer**, **fica nos backups** e tem
**rollback testado**. Diferente do cold storage de *projetos* do vault
(`governance/cold-storage.md`, que compacta em `.tar.gz`), aqui o artefato é um
**serviço Docker nativo** que precisa ser reativável em minutos.

> Criado em **08/10/2026** com o caso do `dnscrypt-proxy` (kavure), substituído pelo
> [`unbound`](../services/unbound.md) recursivo nativo.

## Definição de "congelado"

Um serviço está em cold storage quando **todas** as condições valem:

1. **Perfil `cold` no compose** — o `docker compose up -d` (rotina, watchtower, humano
   no automático) **ignora** serviços sem perfil ativo;
2. **`restart: "no"`** no compose **e** `docker update --restart=no` no container
   existente (a policy é gravada no container, não só no YAML);
3. **Container parado** (`exited`);
4. **Fail-closed provado** — se subir por engano, ele **não consegue operar** (ver abaixo);
5. **Backup verificado** — o diretório do serviço está no espelho do NAS;
6. **Doc marcada ⛔** — a página do serviço diz que está congelado + como reativar.

## Checklist de congelamento

```bash
# 1. Backup do compose ANTES de mexer
cp compose.yml compose.yml.bak-AAAAMMDD-cold

# 2. Editar compose: adicionar no serviço:
#      profiles: ["cold"]
#      restart: "no"
#    Validar que a rotina nem enxerga o serviço:
docker compose config --services                # NÃO deve listar o serviço
docker compose --profile cold config --services # DEVE listar

# 3. Congelar o container existente (policy mora no container, não só no YAML)
docker update --restart=no <container>
docker stop <container>
docker inspect -f '{{.HostConfig.RestartPolicy.Name}} {{.State.Status}}' <container>
# esperado: no exited

# 4. PROVAR o fail-closed (não presumir!):
docker start <container>                         # provocar de propósito
#  → verificar que o serviço alvo continua de pé (ex.: ss -ulnp | grep 5053 = unbound)
#  → verificar log do container com erro de bind/autenticação
#  → verificar estado exited e SEM crash-loop (restart=no)
docker stop <container>                          # volta ao estado congelado

# 5. PROVAR o backup:
systemctl start hl-config-backup.service         # roda a rotina na hora
ls /mnt/BACKUP/configs-homelab/<host>/data/<serviço>/

# 6. Documentar (a própria página do serviço + catálogo abaixo)
```

**Fail-closed** = a segunda camada de defesa: mesmo que as camadas 1–3 falhem, o serviço
congelado não pode operar. No caso do `dnscrypt-proxy` a prova é forte: ele precisa da
porta `5053` e o **unbound a segura** (loopback + tailnet) → `[FATAL] ... bind: address
already in use`, exit 255, sem loop. Para outros serviços, definir explicitamente qual é
a trava (porta ocupada, credencial removida, rede inexistente).

## Rollback (reativação)

```bash
# 1. Parar o que assumiu o lugar (se aplicável) — ex.: unbound:
systemctl stop unbound

# 2. Reverter watchdog/units que apontam para o sucessor (se aplicável)
#    ex.: hl-dns-watchdog.service → --container <container> em vez de --service unbound

# 3. Reativar com perfil explícito (o guard é o próprio perfil)
cd /srv/data/<serviço> && docker compose --profile cold up -d

# 4. Reverter a policy de restart se quiser o comportamento antigo
docker update --restart=unless-stopped <container>
```

Após testar, **re-congelar** seguindo o checklist (volta ao `profiles: ["cold"]`).

## Rotinas que cobrem serviços congelados

| Rotina | Cobre como |
|---|---|
| `hl-config-backup.timer` (05:00) | `SRC_DIRS` espelha o **diretório inteiro** do serviço (compose, `.bak`s e config) para `/mnt/BACKUP/configs-homelab/` — ver [`../backups/config-backup.md`](../backups/config-backup.md) |
| restic + snapper | o espelho NAS é versionado (anti-ransomware/anti-deleção) |
| Watchtower | **não toca**: padrão não inclui containers parados + perfil esconde o serviço do `compose up` |
| Autoheal | **não toca**: monitora apenas containers em execução |

## Catálogo de serviços em cold storage

| Serviço | Host | Desde | Sucessor | Rollback | Doc |
|---|---|---|---|---|---|
| `dnscrypt-proxy` | kavure | 08/10/2026 | `unbound` nativo (`:5053`) | `docker compose --profile cold up -d` (ver doc do serviço) | [`../services/dnscrypt-proxy.md`](../services/dnscrypt-proxy.md) |

## Ver também

- [`../services/dnscrypt-proxy.md`](../services/dnscrypt-proxy.md) — caso de referência
- [`../services/unbound.md`](../services/unbound.md) — sucessor
- [`docker-healthchecks.md`](docker-healthchecks.md) — watchdog Rust e cobertura de health
- [`../backups/config-backup.md`](../backups/config-backup.md) — espelho de configs
