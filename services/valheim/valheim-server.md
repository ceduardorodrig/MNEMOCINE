---
tags: [homelab, service, valheim, gaming]
---

# Valheim — Servidor Dedicated

Servidor dedicado Valheim 1.0 (Deep North) com BepInEx e mods QoL.

**Servidor:** kavure
**Portas:** UDP 2456-2458
**Senha:** no store sops (`VALHEIM_SERVER_PASS`)
**Mundo:** `Fimbulvetr`
**IP (Tailscale):** `100.124.146.77`

> **Ativo desde 09/09/2026:** Valheim 1.0.16 / **network version 40** (relato do log: `Console: Valheim l-1.0.16 (network version 40)`) via `mbround18/valheim:3` com BepInEx + 3 mods server-side. Servidor público=false (acesso pela tailnet). Backup automático a cada 30min via container + offbox NFS. Portais em modo casual (ores passam).
>
> ⚠️ A doc registrava **1.0.12**; a versão atual é **1.0.16**, mas o **network version segue 40** — o protocolo não mudou, então os clientes e a nota do bug de `Compression` continuam válidos.

## Stack

| Container | Imagem | Função |
|---|---|---|
| valheim-server | mbround18/valheim:3 | Servidor dedicated + BepInEx + mods |

## Portas

| Porta | Protocolo | Uso |
|---|---|---|
| 2456 | UDP | Jogo (principal) |
| 2457 | UDP | Jogo (backup) |
| 2458 | UDP | Jogo (backup) |

## Dados

| Item | Valor |
|---|---|
| Mundo | `Fimbulvetr` |
| Servidor | `Mnemocine Vikings` |
| Senha | no store sops (`VALHEIM_SERVER_PASS`) |
| Public | `false` (acesso só via tailnet) |
| BepInEx | Sim (`TYPE: BepInEx`) |
| Modifiers | `portals=casual` |
| Auto-update | 03:00 diário (steamcmd) |
| Auto-backup | A cada 30 min → offbox NFS |
| TZ | America/Sao_Paulo |

## Admin — permissions.yaml

> **Canonizado 26/09/2026.** Até aqui a doc afirmava que "comandos são locais / não há admin remoto" — **estava errado**. O Valheim 1.0 tem sistema **nativo** de permissões, e o mod Server Devcommands lê exatamente esse arquivo (`Reloading N permission data` no log = nº de entradas do `permissions.yaml`).

**Fonte de verdade:** `config/bepinex/permissions.yaml` no host → `/home/steam/valheim/BepInEx/config/permissions.yaml` no container.

```yaml
- id: 76561198075365006
  name: AhNo CaM
  admin: yes
- id: 76561198075365006
  name: AhNo CaM
  character: 1571166467
  admin: yes
```

O jogo mantém esse arquivo sozinho: cria a entrada de cada player no primeiro login (é por isso que ele muda sozinho) e o **recarrega a cada entrada de jogador** (ver *Reinício: obrigatório ou atalho*, abaixo). Padrão do jogo = **2 entradas por conta**: uma base (`id` + `name` + `admin`) e uma por personagem (`+ character`, o ZDOID). Manter as duas.

### Players

| Jogador | Nome in-game | SteamID64 | Admin | Desde |
|---|---|---|---|---|
| Carlos (dono) | AhNo CaM | `76561198075365006` | ✅ | 09/09/2026 |
| Titi / Twister / Lira | Lira | `76561198009545651` | ✅ | 26/09/2026 |
| Henrique | BiM | `76561197988953037` | ✅ | 26/09/2026 |

> Admin é por **conta Steam** (`id`), não por personagem — todos os personagens dessa conta (Titi, Twister, Lira) ganham admin de uma vez.

### Caminho legado (espelhado de propósito)

`saves/adminlist.txt` (o container sobe com `-savedir /home/steam/.config/unity3d/IronGate/Valheim`, então esse é o caminho válido) recebe os mesmos IDs, um por linha. É o formato legado e o que o Thunderstore do mod ainda documenta — mantido em sincronia como hedge, já que dá zero custo.

> ⚠️ **Armadilha histórica (resolvida 26/09/2026):** existia um `/srv/data/valheim/config/server/adminlist.txt` que **NÃO era lido** — resíduo de 09/09 20:00, de antes do `-savedir` ser configurado (o jogo passou a gravar no `saves/` às 20:07, 7 min depois). Removido junto com o diretório vazio. Se voltar a aparecer, cheque o `-savedir` no `ps` do container antes de acreditar nele.

### Reinício: obrigatório ou atalho

O fluxo garantido é **parar → editar → subir** (ver [[ssh-runbook#Dar admin a um jogador]]). Mas desde 26/09/2026 ficou confirmado em produção que dá pra editar **com o servidor no ar**:

- `permissions.yaml` é **recarregado a cada entrada de jogador** → o mod loga `Reloading <N> permission data` de novo (N = nº de entradas do YAML). Grant novo vale a partir do **próximo join**.
- O jogo **lê do disco e mescla** — não sobrescreve do zero: entrada hand-editada (a "base", sem `character`) sobreviveu a um join real. As entradas que ele cria sozinho são as de `character` (o ZDOID do personagem).
- Por isso, escrita **atômica** é obrigatória (`install` = tmp + `rename`): o jogo reescreve o arquivo a cada join, e o rename garante que ele leia o arquivo antigo inteiro ou o novo inteiro — nunca um pela metade.
- O jogador que recebeu o grant precisa **reconectar** (sair e entrar) — a recarga acontece no evento de join, não em tempo real.
- O `adminlist.txt` legado é lido **só no boot** — quem escreve nele espera o próximo restart (o timer diário das 05:00 serve).

| Método | Garantia | Custo |
|---|---|---|
| Parar → editar → subir | ✅ total, validado ponta a ponta | derruba quem está jogando + ~3 min de boot (roda steamcmd) |
| Editar no ar | ✅ pro `permissions.yaml` (validado 26/09 com 3 jogadores online) | só o legado espera o restart |

## World Modifiers

| Modifier | Valor | Efeito |
|---|---|---|
| portals | `casual` | Ores/minérios passam por portais |

## Módulos SmoothServer desabilitados

| Módulo | Config | Motivo |
|---|---|---|
| `[Compression] Enabled` | `false` | Incompatível com o Valheim 1.0 (frame tag `0x48`, mundo vazio). Fix em 12/09/2026; **segue desligado no 1.0.16** porque o network version não mudou (40). |
| `[Map] Enabled` | `false` | Compartilhamento de mapa desabilitado a pedido (20/09/2026). Cada jogador vê só o que explorou + pins locais. |

> Ambos persistem entre restarts porque `Profile = Custom` está ativo (sem sobrescrita automática de defaults).

## SmoothServer — ajustes de 27/09/2026 (diagnóstico de conexão)

Investigação de "dificuldades de conexão" (piorava com mais jogadores, variava por jogador). **Método:** telemetria do próprio mod (`config/bepinex/smoothserver/stats/{stats,events}-YYYY-MM-DD.jsonl`), `[LagProbe]`, correlação `leave` × `ZRpc timeout` no `docker logs`, e `tailscale status --json` para o caminho de rede.

### O que a medição descartou

| Hipótese | Veredito | Medida |
|---|---|---|
| Saturação de banda / outbound | ❌ **descartada** | ~3,6 kB/s por peer (2762 updates / 216 kB por min) |
| `AdaptiveBudget` estrangulando | ❌ **ruído benigno** | `target = clamp(2 × bps × rtt, 16 KB, 128 KB)` → piso por *design* com tráfego baixo; `budgetCongested=false`, `pendingBytes=0` |
| `SteamRates.SendRateMin` | ❌ **já está correto** | `0` = "leave vanilla" (vanilla fixa 153600 B/s) — a doc oficial manda **não** mexer |
| Servidor sobrecarregado | ❌ **descartada** | load 1,19 · 88% idle · 0% steal · 0% iowait · 1,5 GB de 11 GB |

### O que foi mudado (só o que a doc oficial quantifica)

| Chave | Antes | Depois | Ganho documentado |
|---|---|---|---|
| `[FrameRate] TargetFrameRate` | `0` (vanilla ~30) | **`60`** | *"roughly +4pp of one CPU core for **half the tick latency**"* |
| `[PriorityLane] Enabled` | `false` | **`true`** | *"the residual delay drops from the **80–430 ms** band to roughly **25 ms**… Unmodded clients benefit too"* |
| `[Map] SharePins` | `true` | **`false`** | pedido do dono (trava o flag; módulo já desabilitado) |
| `[Map] ShareExploration` | `true` | **`false`** | idem |

**Resultado medido:** tick `33,36 ms → 16,70 ms`, fps `29,98 → 59,90` (conforme a doc). No boot o summary confirma `FrameRate=applied`, `PriorityLane=applied` e `SendCadence … priority=High`.

> ⚠️ **Ressalva do autor do mod:** `PriorityLane` é *"OFF by default in 0.6.0 (not yet measured with real players)"*. Foi ligado mesmo assim (ganho documentado) e **exige restart** para entrar em vigor.
> **Rollback:** `[PriorityLane] Enabled = false` + `valheim-restart`.
> Backup do cfg: `config/bepinex/Nosferatu.SmoothServer.cfg.bak-20260927-211755`.

### Achados que ficaram abertos (não são config do servidor)

| Achado | Evidência | Por que não foi mexido |
|---|---|---|
| **Quedas do Mr. Bones** (`76561198004062946`) = `ZRpc timeout` (30 s de silêncio RPC) | timeout 23:15:29 → leave 23:15:30; timeout 23:43:21 → leave 23:43:21 (mesmo segundo). **Não** coincide com save nem GC | é o caminho de rede dele, não o servidor: a 1ª queda coincidiu com o nó Tailscale dele caindo (23:15:13) |
| **Todos os clientes jogam sem o mod** | `client-mod=none`; `CombatOwnership … disabled(side)` | `Compression`, `ClientNet`, `CombatOwnership` (~0,5 s por hit em objeto de outro peer) e o `LagProbe` (que mediria perda/jitter de verdade) só existem no **cliente** |
| **Jogadores chegam por nós compartilhados, vários RELAY via DERP São Paulo** (não direto) | `tailscale status --json`: `CurAddr` vazio + `Relay: sao` | relay é decisão de rede (hole punching / roteador), não de config do Valheim |
| RTT por jogador | você `1 ms` · Lira `~20 ms` · **BiM (Europa) `233 ms`** · Mr. Bones `18→282 ms` (instável) | o BiM é intercontinental: física, nenhum knob corrige |
| **Saves congelam o servidor** | `save` stall `94–265 ms` (mediana 127), ~48×/dia | sem knob documentado; `AsyncSave` já ativo (e o `PreSizeClone` é no-op no 1.0) |

> Receita de diagnóstico e consultas prontas em [[ssh-runbook#Diagnóstico de conexão]].

## SmoothServer — ajustes de 29/09/2026 (lag em Plains / "borracha")

> **Contexto.** Sessão 28/09 21:00 → 29/09 00:14 BRT (158 min, 3 players: AhNo CaM, Lira, Mr. Bones), com lag relatado durante exploração de **Plains** e várias mortes. O tipo de lag foi caracterizado pelo dono como **"borracha/desync"** (e não congelamento) → modelou investigação de fila de saída e dono de zona, não de save.
> **Método:** `[StatsLog]` + `[PeerTelemetry]` + `[LagProbe]` correlacionados com os eventos `save`. Janela analisada = `stats-2026-09-29.jsonl` (949 amostras com players online).

### O que a medição mostrou

**Base saudável:** `frameAvg` mediana 16,7–17,8 ms · fps 59,9 · `loss=0%` para **todos** os peers · `budgetCongested=false` sempre · load 0,74–0,96 nos 4 cores do i3-8100.

**① A fila de saída da Lira era a única que saturava.** Todos os peers ficam **presos no piso** do `AdaptiveBudget` (16.384 B), porque `target = clamp(2 × bps × rtt, 16 KB, 128 KB)` e o BDP dos nossos RTTs de ~20 ms é baixo. Como `cong=false` e `pending` é pequeno, **não havia congestionamento real** — era o **piso artificial** segurando o envio.

| Player | fila mediana | p95 do orçamento | **amostras ≥95% do orçamento** | `pendingBytes` máx | RTT |
|---|---|---|---|---|---|
| AhNo CaM | 0 B | 25% | **0,6%** (6/949) | 12.932 B | 1 ms |
| **Lira** | **395 B** | **101%** | **9,2%** (87/941) | **14.205 B** | 19 ms |
| Mr. Bones | 0 B | 54% | 2,2% (14/647) | 5.145 B | 21 ms |

**② Os picos de frame são dois problemas distintos** (11 picos `frameWorst > 140 ms` na janela):

| Causa | Ocorrências | Faixa | Padrão |
|---|---|---|---|
| **save** (clona os 552.476 ZDOs no shutdown/save) | ~6 | 180–252 ms | `HH:01:3x` e `HH:31:3x` (a cada 30 min) |
| **churn de combate** | ~5 | 140–212 ms | `recv` 497–900 ZDO/s, aleatório |

> ⚠️ **Hipótese testada e DESCARTADA:** a saturação da fila **não** explica os picos de frame — nos 5 picos de combate a fila da Lira estava em **mediana 7%** do orçamento. São **dois problemas separados**; corrigir um não corrige o outro.

**③ Na medição, não foi possível confirmar nem descartar o dono de zona.** O `[LagProbe]` só emite linha de cliente para `AhNo CaM`:

```
cfps 80–141 (med 106) · loss 0% em 61 amostras · RTT med 18 ms / máx 101 ms · clientFrame med 9,7 / máx 24,1 ms
```

Lira e Mr. Bones **não têm nenhuma linha** → sem `cfps` deles, a hipótese de "quem entra primeiro na zona simula o combate" ficou **indeterminada na medição**.

> **Desfecho (mesmo dia): encerrado pelo dono — ver [Dono de zona — encerrado](#dono-de-zona--encerrado-29092026).** O servidor sonda todos os peers, mas só o `AhNo CaM` responde; é client-side de terceiros, fora do nosso controle. O SmoothServer fica.

### O que foi mudado

| Chave / local | Antes | Depois | Justificativa (só o que a doc do mod quantifica) |
|---|---|---|---|
| `[AdaptiveBudget] FloorBytes` | `16384` | **`32768`** | ataca a saturação da fila da Lira; 32768 é o valor do perfil **FastLink do próprio autor**. Folga real: `CeilingBytes=131072`, `SteamRates.SendRateMax=1048576` |
| `[LowLatency] NagleMicros` | `5000` | **`0`** | doc do mod: *"−5 ms per direction"*; `5000` é o default → o módulo estava **no-op** (não estava fazendo nada) |
| `[CreateBudget] MaxCreatedPerFrame` | `10` | **`20`** | valor do perfil FastLink do autor (`raise it to test`) |
| `[StatsLog] IntervalSec` | `10` | **`3`** | resolução p/ diagnóstico; **hot-reload** (validado: `delta=3,0s` entre amostras) |
| `[SendCadence] SendHz` | `20` | **`30`** | varredura da fila 30×/s em vez de 20× → a espera máxima na fila cai de **50 ms para 33,3 ms** (ver *Por que `SendHz` importa*) |
| `docker-compose.yml` → `cpu_shares` | *(default)* | **`2048`** | peso relativo de CPU do container — ver nota sobre `SYS_NICE` abaixo |

**Validação no boot (todos os pontos verificados):**

```
[Profiles] Custom (startup): no overrides applied, every value in the cfg file stands
SmoothServer 0.6.1 loaded, 25 modules
Chainloader startup complete (3 loaded, 0 skipped, 0 failed)
Reloading 7 permission data
[Profiles] Profile=Custom -> AdaptiveBudget.FloorBytes=32768 ... LowLatency.NagleMicros=0 ... CreateBudget.MaxCreatedPerFrame=20
Console: Valheim l-1.0.16 (network version 40)
```
`docker inspect` → `HostConfig.CpuShares = 2048` · `CapAdd=[CAP_SYS_NICE]` · mundo recarregado com `ZDOMan.LoadChunks - Starting to load 552,476 zdos from 63 Chu`.

O `SendHz` foi aplicado **depois**, já com o servidor no ar, e pegou por **hot-reload — sem restart, sem derrubar ninguém**:

```text
[SendCadence] SendHz -> 30.0 (interval 33.3ms)
[Profiles] Custom (cfg reload): no overrides applied, every value in the cfg file stands
[Config] reloaded: [SendCadence] SendHz 20 -> 30
```

E **sobreviveu a um restart limpo** (29/09 01:31 BRT) — provando que é persistente, não só hot-reload:

```text
[Profiles] Profile=Custom -> SendCadence.SendHz=30 AdaptiveBudget.CeilingBytes=131072 AdaptiveBudget.FloorBytes=32768 ... LowLatency.NagleMicros=0 ... CreateBudget.MaxCreatedPerFrame=20
SendCadence [Server] = applied
SmoothServer 0.6.1 (server half)  EnforceClientMod=False  configLocked=False  sourceOfTruth=True
ZDOMan.LoadChunks done [2,549ms]
Game server connected
```

> `docker inspect` após o restart → `CpuShares = 2048`. **Restart preserva o container** (`docker compose restart`); só um recreate alteraria resources — por isso reverter `cpu_shares` exige `up -d --force-recreate`.

> **Por que o `SYS_NICE` nunca tinha sido usado:** `cap_add: [SYS_NICE]` é só a **capacidade** Linux de mudar scheduling — é uma permissão, não uma ação. Varredura feita em 29/09/2026 em `/home/steam/scripts/` + `/entrypoint.sh` por `nice|renice|setpriority|sched_setscheduler|sched_setattr` → **um único match**, e ele é só um `log`:
> ```bash
> start_valheim.sh:110: log "Auto Backup Nice Level: ${AUTO_BACKUP_NICE_LEVEL}"
> ```
> Ou seja: `AUTO_BACKUP_NICE_LEVEL` existe e é **impressa no log, mas nunca é aplicada** — nem para o backup nem para o jogo. **Nenhuma linha do boot invoca a capacidade.** Resultado: `valheim_server` ficava `nice=0 pri=19 cls=TS`, disputando CPU **em igualdade** com os outros ~40 containers no i3-8100.
> `cpu_shares` é a forma Docker-nativa de dar peso — config-as-code no compose, sobrevive a recreate, não exige capacidade nenhuma.
> ⚠️ **`SYS_NICE` permanece no compose** (inofensivo, e caso alguma versão futura da imagem passe a usar `AUTO_BACKUP_NICE_LEVEL` de verdade ele será necessário).

> ⚠️ **`-saveinterval` não é viável nesta imagem:** o parâmetro oficial da Iron Gate existe (`-saveinterval 1800`, *"Change how often the world will save in seconds"*), mas `grep -c saveinterval` = **0** em `start_valheim.sh`, `entrypoint.sh`, `env.sh`, `utils.sh`, `steam_bashrc.sh`. A imagem não o expõe → exigiria sobrescrever o `command` do compose. **Descartado:** os ~6 picos de save a cada 2,6 h são o menor dos problemas e o trade-off (mais perda em crash) não compensa.

### Rollback

```bash
cd /srv/data/valheim
sudo cp -a config/bepinex/Nosferatu.SmoothServer.cfg.bak-20260929-005016 \
           config/bepinex/Nosferatu.SmoothServer.cfg
sudo cp -a docker-compose.yml.bak-20260929-005016 docker-compose.yml
sudo docker compose up -d --force-recreate
```

> ⚠️ **`valheim-restart` NÃO serve para reverter o compose** — ele usa `docker compose restart`, que **não recria** o container e portanto **não aplica** `cpu_shares`. Mudança de resource exige `up -d --force-recreate`.
> Backups criados nesta janela: `Nosferatu.SmoothServer.cfg.bak-20260929-005016` e `docker-compose.yml.bak-20260929-005016`.

### Por que `SendHz` importa

O `[SendCadence]` substitui o rodízio do vanilla — *"one-peer-per-frame"* — por uma **varredura de todos os peers a taxa fixa**. No vanilla, a 60 fps com 3 online, cada jogador só era atendido 1× a cada 3 frames ≈ **6,7 Hz**. O mod entrega a taxa cheia **por jogador**, independente de quantos estejam online.

O número que interessa é a **espera máxima de um ZDO na fila** = `1 / SendHz`:

| `SendHz` | Espera máx. na fila |
|---|---|
| vanilla (3 players) | ~150 ms |
| 20 (antes) | 50 ms |
| **30 (atual)** | **33,3 ms** |
| 40 (teto sugerido) | 25 ms |

Com RTT de 1–21 ms, **essa espera de fila domina o atraso total** — cortar de 50 → 33,3 ms vale mais que qualquer ajuste de banda. Custo: mais varreduras/s (CPU leve) e mais pacotes pequenos; sem custo relevante de banda.

> **Não passar de 40:** os clientes não renderizam todos a 60 fps (o do dono mede ~106, mas não é a regra), então acima de 40 vira pacote sem informação nova. `SendHz` é clampado em 1–60 pelo próprio mod.

### Dono de zona — encerrado (29/09/2026)

**Decisão do dono: não perseguir.** O SmoothServer fica.

O assunto foi **fechado com dado**, não por desistência:

- O `[LagProbe]` é **server-driven e sincronizado**: `PingIntervalSec = 5` → *"One tiny routed RPC each way per player per interval"*. O servidor sonda **todos** os peers, com ou sem mod.
- **Mas só o `AhNo CaM` respondeu** em toda a história do log: 61 sondagens, `loss=0% (12/12 answered)`, 118 amostras de `cfps` (80–141).
- **Lira e Mr. Bones: zero linhas.** `SS_Ping` é RPC do mod — quem não tem o client half ativo não responde.
- Contexto: a Lira **já teve** o mod (ela via o mapa compartilhado — feature do client half — antes de 20/09), mas desde então não responde a sondagem. Ou caiu, ou ficou em versão antiga (o "both-ends" só existe a partir da **0.5.0**).

→ **Fora do nosso controle** (é client-side de terceiros). **Sem `EnforceClientMod`** — decisão do dono: não vale derrubar quem não tem.

### Teto do `FloorBytes` — 65536, **não** o máximo

Subir o `FloorBytes` até o `CeilingBytes` (`131072`) foi considerado e **recusado**:

1. **Mataria o módulo.** O `AdaptiveBudget` deriva o alvo do RTT + throughput de cada peer. Com `Floor = Ceiling` o alvo vira constante — é o mesmo que fixar `[SendBudget] HighWaterBytes = 131072` e desligar o adaptativo.
2. **Bufferbloat.** O próprio cfg avisa: *"Never budget a peer above this many bytes. **Steam's own send queue starts erroring well above this; 128KB is a deliberate safety margin.**"* Fila maior = dado esperando = entrega **atrasada** = o peer vê estado **mais velho**. Ajuda rajada, atrapalha link lento. E o recuo (`PendingBackoffBytes = 8192`) só olha o pendente **no Steam** — *"in-flight/unacked bytes **deliberately do NOT** trigger a back-off"* → fila local grande pode crescer sem gatilho.
3. **32768 já é o fim do testado** — é o valor do perfil **FastLink do próprio autor**, o preset mais agressivo que ele publica.

**Teto acordado: `65536`** — igual ao `[SendBudget] HighWaterBytes = 65536`, o high-water "levantado" que o **próprio autor** escolheu para quem não usa o caminho adaptativo. Acima disso ficaríamos mais agressivos que o preset do autor.

**Gatilho para subir:** só se a fila da Lira **ainda** saturar (≥95% de `queuedBytes / budgetTargetBytes`) numa medição futura.

### Próximos passos — quando o dono quiser

- **Medir a próxima Plains.** `[StatsLog] IntervalSec` fica em **3 s** de propósito (aprovado pelo dono): a última lag foi **espontânea**, não combinada — se repetir sem aviso, os dados finos já estão lá. Custo: ~20 MB/dia (disco com ~71 GB livres). **Reverter para 10 s** só se o dono quiser — a 10 s o arquivo é 3,3× menor.
- Se a fila ainda saturar → `FloorBytes` `32768` → **`65536`** (teto).

### Descartado (consolidado em 29/09/2026)

| Item | Motivo |
|---|---|
| Qualquer coisa no **mundo** (drops, mobs, estruturas, itens, terraformação) | **proibido pelo dono** — reiterado em 29/09/2026 |
| **Servidor dono de todas as zonas** | decisão do dono (29/09): **o SmoothServer já é bom o bastante**. Não perseguir |
| **FiresGhettoNetworking** (server-side simulation) | **é** mantido (v1.4.31, atualizado p/ Valheim 1.0) e **seria** o único caminho real pro servidor donar as zonas — mas: (a) o próprio autor avisa *"if you also run ... another networking mod — **disable one**; running two networking mods at once will produce **conflicting patches**"* → exigiria **remover** o SmoothServer; (b) joga a simulação do mundo pro servidor, inverso do desenho do vanilla, num i3-8100 com ~40 containers |
| `Serverside Simulations` (ddormer) | descontinuado desde 2026 (último patch p/ 0.220.5) + *"dramatically increases server resource usage"* |
| `EnforceClientMod = true` | recusado pelo dono — derrubaria quem não tem o mod no cliente |
| **`FloorBytes` até o máximo (`131072`)** | bufferbloat + mataria o módulo adaptativo (ver *Teto do `FloorBytes`*). **Teto é `65536`** |
| Reativar `Compression` | network version segue **40** = mesmo protocolo do bug `frame tag 0x48`; causou "mundo vazio" antes |
| Mexer no **`n8n`** por CPU | recusado pelo dono — está em Docker, tem `cpu_shares` próprio, e foi rajada pontual |
| `Better Networking` | redundante com `SteamRates`/`SendCadence` já ativos (`SendRateMax=1048576`, `SendHz=30`) |
| `-saveinterval` | não exposto pela imagem (ver acima) |
| `Map` (`SharePins`/`ShareExploration`) | seguem `false` — pedido do dono |

## Mods (3 ativos — server-side)

| Mod | Versão | Função |
|---|---|---|
| Server_devcommands | 1.115 | Devcommands + admin tools |
| FuelEternal | 1.2.1 | Fogo nunca apaga |
| NoodlesMcDoodles | **1.0.12** | Simulação de zonas e criaturas no servidor (anti-desync/anti-rubberbanding) |

**Todos os mods são server-side** — clientes vanilla conectam sem problema.

> **NoodlesMcDoodles (04/10/2026):** Adicionado `Wubarrk-NoodlesMcDoodles-*` no compose. Transfere a responsabilidade da simulação de zonas (monstros, criaturas, plantações, forjas, portas) para o servidor dedicado, evitando que o primeiro jogador a entrar na zona atue como "host" local para os demais. Com a desinstalação do SmoothServer em 05/10/2026, o Noodles assumiu 100% dos hooks com `forced-off features: none`, operando em modo `FarOrShared` com autoridade total do servidor. Admins podem usar comandos no console in-game (`F5`): `noodles status`, `noodles disable`, `noodles enable`.
> - **Ajustes de Estabilidade (05/10/2026 via hot-reload):** `T9_PingInflationMs = 100` (evita throttles prematuros em oscilações normais de Wi-Fi/relay), `T1_GlobalRateBps = 524288` (teto dobrado para 512 KB/s por jogador) e `T9_LossThreshold = 0.95` (tolerância a variações de rede).

### Mods client-side (instalar no cliente, não no servidor)

| Mod | Versão | Função |
|---|---|---|
| Gizmo (ComfyMods) | 1.16.0 | Rotação de construção (Ctrl+scroll) |
| CameraTweaks (Searica) | 1.3.1 | Zoom e FOV customizável |

### Mods removidos do servidor

| Mod | Motivo |
|---|---|
| SmoothServer (Nosferatu) | Removido em 05/10/2026 após desyncs e anomalias em lutas de boss (Yagluth) e conflitos de interpolação; NoodlesMcDoodles assumiu o controle unificado com `forced-off features: none` |
| Gizmo (ComfyMods) | Client-side only — removido do servidor em 16/09/2026; cada jogador instala no cliente |
| CameraTweaks (Searica) | Client-side only — removido do servidor em 16/09/2026; cada jogador instala no cliente |
| BuildCamera (Azumatt) | Kickava clientes vanilla (`EnforceClientMod: true`); sem demanda |
| AAA_Crafting | `Inventory.AddItem` mudou assinatura (incompatível com 1.0) |
| aruberuto/AreaRepair | Harmony patch crash em `Awake` (incompatível com 1.0) |
| Azumatt/AzuAreaRepair | Harmony patch crash em `Awake` (incompatível com 1.0) |

## Dados no disco

```
/srv/data/valheim/
├── docker-compose.yml    ← compose (MODS, MODIFIERS: portals=casual)
├── .env                  ← VALHEIM_SERVER_PASS
├── config/               ← BepInEx + configurações
│   └── bepinex/          ← configs dos mods (persistidas entre restarts)
│       └── permissions.yaml  ← ADMINS — fonte de verdade (ver [[valheim-server#Admin — permissions.yaml]])
├── data/                 ← binário do servidor (volume → /home/steam/valheim)
├── saves/                ← MUNDO + auto-backups do jogo (volume → /home/steam/.config/unity3d/IronGate/Valheim)
│   ├── adminlist.txt     ← lista de admins legada (espelho de permissions.yaml)
│   ├── player.list       ← histórico de jogadores (id/ZDOID/nome/última vez)
│   └── worlds_local/     ← Fimbulvetr (mundo ativo) + Fimbulvetr_backup_auto-* (auto-backups nativos do jogo)
├── backups/              ← AUTO_BACKUP do container (Odin) → /home/steam/backups (persistido desde 13/09)
└── offbox/               ← mount NFS → psicopompo (backup off-box)
```

## Backup

> **Corrigido (13/09/2026):** o backup off-box estava **quebrado** — o script `valheim-backup` apontava para `/srv/data/valheim/config/backups/` (padrão de outra imagem), pasta que **não existe** neste setup. O mundo real vive em `saves/worlds_local/`. Corrigido o script (fonte → `saves/worlds_local/`) + adicionado mount `./backups:/home/steam/backups` no compose para o AUTO_BACKUP do Odin não perder backup no recreate.

- **Off-box (principal):** o **auto-backup nativo do jogo** grava em `saves/worlds_local/Fimbulvetr_backup_auto-*` → espelhado por `valheim-backup` (rsync) para NFS psicopompo (`/mnt/BACKUP/valheim-server-kavure/daily/worlds_local/`). Cobre o mundo ativo + backups.
- **AUTO_BACKUP do container (Odin):** a cada 30 min → `/home/steam/backups` (`./backups`, persistido desde 13/09). Retenção `AUTO_BACKUP_DAYS_TO_LIVE=7`.
- **Schedule:** systemd timer `hl-valheim-backup.timer` (05:30, `Persistent=true`) → health file `/srv/health/valheim-backup-last-ok` (alerta `BackupNotRun` cobre).

## Agendamentos (systemd timers)

```ini
# hl-valheim-restart.timer — 05:00 diário (Persistent=true)
# hl-valheim-backup.timer  — 05:30 diário (Persistent=true)
```

- **watchtower** (container da stack `ops`, **03:00 BRT**): atualiza `valheim-server` — recria container com stop-timeout 30s; `AUTO_BACKUP_ON_UPDATE=1` salva antes.

## Acesso

```bash
tailscale ssh kavure@kavure
valheim-status    # status completo
```

## Troubleshooting

### SmoothServer Compression incompatível com Valheim 1.0.12 (mundo vazio)

**Sintomas:** mundo carrega vazio (terreno OK, sem árvores/construções), erro `unknown frame tag 0x48` nos logs, `zdosSent/s=0` (servidor não envia ZDOs pro client).

**Causa raiz (diagnóstico final 12/09/2026):** o módulo `[Compression]` do SmoothServer 0.6.0 é **incompatível com o Valheim 1.0** (protocolo de rede mudou, frame tag `0x48`). **Não** é DLL corrompido — mesmo reinstalado limpo, o problema voltava.

> ⚠️ **Ainda vale no 1.0.16 (verificado 29/09/2026):** o patch 1.0.12 → 1.0.16 **não mudou o network version** (segue **40**), então o protocolo é o mesmo e o bug persiste. **Não** reativar `Compression` sem antes confirmar que o network version subiu.

**O detalhe que impediu o fix antes:** com `Profile = Default`, o SmoothServer 0.6.0 **força os valores default de volta** no config a cada boot — qualquer edição em `Compression.Enabled` era sobrescrita silenciosamente.

**Fix (confirmado):**
1. Editar `[Profiles] Profile = Default` → `Profile = Custom` (para o plugin não sobrescrever nada)
2. Editar `[Compression] Enabled = true` → `Enabled = false`
3. Restart container

**Como editar o config (importante):** editar via **`docker exec`** dentro do container, com aspas aninhadas corretas. Editar via `echo senha | sudo -S sed` no host não persiste.

```bash
ssh kavure@kavure
echo 'SENHA' | sudo -S docker exec valheim-server bash -c \
  'sed -i "281s/Profile = Default/Profile = Custom/; 90s/Enabled = true/Enabled = false/" \
  /home/steam/valheim/BepInEx/config/Nosferatu.SmoothServer.cfg'
```

> **Nunca** delete arquivos de `saves/` ou `worlds_local/` — eles contêm o mundo.

### Erros de edição no config via host não persistem

O arquivo do config do SmoothServer é montado de `./config/bepinex` no host para `/home/steam/valheim/BepInEx/config` no container. Edições feitas no host com `echo senha | sudo -S sed ...` **não aplicam** (problema de stdin/aspas no SSH). Use sempre `docker exec` no container.

### Jogador sem chat/ping e placas com caracteres estranhos (client-side)

**Sintomas:** mensagens de chat de um jogador invisíveis, pings dele invisíveis, e placas escritas por ele aparecendo com caracteres estranhos / `TEXT HIDDEN DUE UGC SETTINGS` — **só para um jogador específico** (quem bloqueou).

**Causa raiz (confirmada 29/09/2026 — caso Lira):** lista de bloqueio do Valheim, sincronizada pelo **Steam Cloud**. O arquivo é criado no primeiro `mute` pela **lista de jogadores da sessão** — basta um clique; o do dono é de **19/06/2024**, dois anos antes e anterior ao servidor.

#### ⚠️ Primeiro: este cliente roda via PROTON, não nativo

O dono joga o Valheim por **Proton** (`WINEDLLOVERRIDES="winhttp,version=n,b"` + `PROTON_ENABLE_WAYLAND=1` — o `winhttp` é o BepInEx), instalado em `/mnt/NVME_PCI/SteamLibrary`.

| Caminho | Papel | Vale? |
|---|---|---|
| `~/.local/share/Steam/userdata/115099278/892970/remote/blocked_players` | **Connected Storage** — é **este** que o jogo lê e a Steam sincroniza | ✅ **é o que importa** |
| `/mnt/NVME_PCI/SteamLibrary/steamapps/compatdata/892970/pfx/.../IronGate/Valheim/` | config local do jogo (prefixo Proton) | contém `Player.log` mas **não** tem `blocked_players` |
| `~/.config/unity3d/IronGate/Valheim/` | Valheim **nativo** — `Player.log` parado em 13/09 | ❌ **inerte** aqui (editar não adianta) |

> Evidência nos logs do cliente: `Player-prev.log` (28/09 23:38, **antes**) diz `blocked_players (24)`; `Player.log` (29/09 02:50, **depois**) diz `blocked_players (0)` + `Failed to read from blocked_players : Connected Storage file missing`.

#### 🔴 Por que o bloqueio "voltava sempre" — bug do Steam, não do Valheim

```
1. Valheim limpa a lista → grava blocked_players VAZIO (0 bytes)   ← estado correto do jogo
2. Steam tenta subir pra nuvem                                     ← RECUSA
3. A nuvem mantém a cópia antiga de 24 bytes                       ← o bloqueio volta
```

O passo 2 falha **de forma determinística** — repetiu em 02:50:59 e 13:48:31, sempre igual:

```
HTTP Upload for file 'blocked_players' (offset=0, length=0) → failed with error 'Forbidden' (403)
```

No **mesmo instante**, outros arquivos subiam OK (`Upload OK for file characters/ahno cam.fch`). Não é instabilidade nem quota: **é o tamanho zero**. É o *"Persistent block bug"* reportado pela comunidade.

> E o caminho "oficial" (desmutar pela UI) **não escapa**: a comunidade reporta que não gruda — *"Can't unmute players permanently"*. Mesmo que grudasse, o resultado seria de novo 0 bytes → mesmo 403.

#### Fix — degrau 1 resolveu (confirmado 29/09/2026)

Tudo no **PC do cliente**. O arquivo que importa é o **espelho da nuvem**; o nativo é opcional (só para os dois ficarem iguais).

| Degrau | Ação | Status |
|---|---|---|
| **1** | `printf '\n' > .../remote/blocked_players` (**1 byte**) | ✅ **funcionou de primeira** |
| **2** | se o log acusasse `403` → deletar o arquivo | não precisou |
| **3** | gerenciador de Cloud da Steam | não precisou |

**Por que 1 byte e não 0:** com **0 bytes** o upload falha (`length=0` → `403`); com **1 byte** passa. E o jogo **também lê melhor** — com 0 bytes ele logava `blocked_players (0)` + `Failed to read … Connected Storage file missing`; com 1 byte loga `blocked_players (1)` **sem aviso nenhum**. O Valheim lê uma linha em branco como "nenhuma entrada".

#### Resultado confirmado (29/09/2026)

| Verificação | Antes | Depois |
|---|---|---|
| Upload pra nuvem | `(length=0)` → **403 Forbidden** → `Upload Failure` | `(length=1)` → **success** → **`Upload OK`** |
| Log do jogo | `(24)` → `(0)` + `Failed to read` | **`blocked_players (1)`**, sem aviso |
| Prática | placas da Lira ilegíveis | ✅ **o dono passou a ler as placas da Lira** |

Sequência no `cloud_log.txt` (14:29:14–17):

```text
(ValidateCache) File '.../remote/blocked_players' SHA mismatch with cache - setting local changes
Need to upload file blocked_players
HTTP upload for file 'blocked_players' (offset=0, length=1) ... - success
Upload OK for file blocked_players
```

> ⚠️ **Isto é um remendo, não uma cura.** Se o Valheim **reescrever** o arquivo (qualquer mute/desmute pela lista de jogadores), ele grava no formato dele — e com a lista vazia isso significa **0 bytes** → o `403` volta. A receita acima resolve em minutos.
> **Escopo:** é **por conta Steam** e o sintoma é **unilateral** — quem mutou perde a visão do outro, não o contrário. Se **outro jogador** reclamar de não ver chat/placas de alguém, é o mesmo arquivo **na máquina dele**.
> **Artefato:** o backup do conteúdo original (`Steam_76561198009545651`) foi removido em 29/09 após a confirmação. Ele **nunca chegou à nuvem** (o `cloud_log.txt` não o menciona e o `remotecache.vdf` só rastreia `blocked_players`) — era apenas um arquivo local a mais no diretório de saves, que o **jogo** enumerava. O conteúdo está preservado nesta nota.

#### Como verificar (objetivo, sem achismo)

```bash
# 1. a nuvem aceitou? deve dizer "Upload OK" (e o 403 tem que sumir)
rg -N "blocked_players" ~/.local/share/Steam/logs/cloud_log.txt | tail -5

# 2. o jogo leu limpo? (Player.log do prefixo Proton, NÃO o nativo)
rg -N "blocked_players" /mnt/NVME_PCI/SteamLibrary/steamapps/compatdata/892970/pfx/drive_c/users/steamuser/AppData/LocalLow/IronGate/Valheim/Player.log
```

**Confirmação final:** com a Lira online, ver chat / ping / placas. *Chat e ping ainda pendentes de validação em 29/09 — só as placas foram confirmadas.*

> **Não é** problema de encoding, nem do servidor, nem do `permissions.yaml` (ali ela é admin). É 100% client-side, e a raiz é **um mute antigo + um bug de sincronização da Steam Cloud**.

## See also

- [[onboarding]] — Guia para jogadores
- [[ssh-runbook]] — Operação via SSH
- [[kavure]] — Servidor de destino
- [[project-zomboid]] — Servidor Zomboid (padrão de referência)
