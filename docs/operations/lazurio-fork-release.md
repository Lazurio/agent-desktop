# Lazurio distribuce agent-desktop

`Lazurio/agent-desktop` je veřejný distribuční fork
[vercel-labs/agent-desktop](https://github.com/vercel-labs/agent-desktop)
(Apache-2.0). Lazurio z něj bere engine, kterým agenti z Prostředí ovládají
aplikace na počítači člověka přes rozhraní přístupnosti systému. Desktopové
aplikace Lazuria ho přibalují jako pomocný proces: dnes utilita Lazurio Agent
Desktop ([Lazurio/lazurio-agent-desktop](https://github.com/Lazurio/lazurio-agent-desktop)),
později pomocník Lazurio App (rozhodnutí 0240, 0241 a 0248 v rejstříku
`Lazurio/LazurioPlatform:docs/decision-register.md`). Fork nese jen opravy,
které tyto aplikace potřebují dřív, než je vydá upstream. Každou opravu kódu
enginu zároveň nabízí upstreamu pull requestem (oddíl Patche a upstream níž);
patche samotné distribuce (verze, workflow vydání, CI vydávaných cílů, tento
dokument) zůstávají jen tady.

## Model: rolling distribution patch-stack

Stejně jako `Lazurio/t3code`, `Lazurio/OpenMausBot` a `Lazurio/agent-browser`:

- `main` je čitelný snapshot právě publikované distribuce: přesný upstream
  release tag a nad ním jen aktuální, významově oddělené commity Lazuria.
- Historickou a rollback autoritou jsou chráněné neměnné release tagy
  `vX.Y.Z-lazurio.N`, ne `main`. Tag se nikdy nepoužije znovu.
- `main` smí nahradit jen Organization Admin, přesným
  `--force-with-lease=refs/heads/main:<sha starého main>`, po zeleném CI
  kandidáta, se schválením přesného headu kandidáta a až když starý `main`
  drží release tag. Jedinou úlevou je jednorázový bootstrap: první nahrazení
  `main` z upstream commitu `54855b6225aec00da4ac65e2d0362fd41cd9fcb3`
  (upstream `main` při založení forku, bez commitů Lazuria). Release tag ho
  nedrží, ale nic se neztratí: je předkem `v1.3.1`, takže první nahrazení je
  fast-forward a `git log <nový main>..54855b6` je prázdný.

## Vydávané cíle

| Cíl | Soubor vydání | Obsah archivu | Proč |
| --- | --- | --- | --- |
| `aarch64-apple-darwin` | `agent-desktop-vX.Y.Z-lazurio.N-aarch64-apple-darwin.tar.gz` | `agent-desktop`, `agent-desktop-macos-helper` | Macy s Apple silicon |
| `x86_64-apple-darwin` | `agent-desktop-vX.Y.Z-lazurio.N-x86_64-apple-darwin.tar.gz` | `agent-desktop`, `agent-desktop-macos-helper` | Macy s procesorem Intel |
| `x86_64-pc-windows-msvc` | `agent-desktop-vX.Y.Z-lazurio.N-x86_64-pc-windows-msvc.tar.gz` | `agent-desktop.exe` | Windows 11 x64 |

Jsou to přesně cíle, pro které utilita engine přibaluje, a systémy, pro které
rozhodnutí 0248 chystá Lazurio App GEN4. Vedle archivů vydání nese jen
`SHA256SUMS`.

Na macOS hledá engine pomocnou binárku (schránka) jen ve své složce a jen pod
přesným jménem `agent-desktop-macos-helper`; jinou cestu přijme jen absolutní
z proměnné `AGENT_DESKTOP_MACOS_HELPER_PATH`, a to se stejným jménem souboru.
Proto archiv drží binárky vedle sebe pod jmény, která potřebují za běhu. Jsou
to i jména, pod kterými je staví cargo, takže archiv má stejné rozložení jako
`target/<target triple>/release/`. Binárky s příponou cíle vedle sebe by engine
nenašel. Archivy balí a kontroluje `scripts/lazurio-release-archive.sh`:
`check` archiv rozbalí do čisté soukromé složky, ověří verzi a na macOS nechá
rozbalený engine přečíst schránku s prázdným `PATH`. Projde jen tehdy, když
engine pomocnou binárku najde a dosáhne na ni. Negativní kontrola položí
pomocnou binárku pod jméno s příponou cíle a musí skončit chybou nalezení
(`clipboard_helper_invalid`). Kontrolu spouští workflow vydání na každém
archivu před nahráním.

Jediný dnešní konzument, utilita Lazurio Agent Desktop, staví engine ze zdroje
(`scripts/build-engine.sh`) a binárky kopíruje jako sidecary Tauri do
`src-tauri/binaries/<název>-<target triple>`. Tauri při balení příponu cíle
odstraní a obě binárky položí vedle sebe do `Contents/MacOS/`, tedy do
rozložení, které engine potřebuje. Když utilita přejde ze stavby ze zdroje na
vydání, archiv rozbalí a stejnými řádky `cp` jako dnes z `target/<target
triple>/release/` binárky zkopíruje do `src-tauri/binaries/`. Tato změna patří
do jejího repozitáře.

Nevydává se Linux ani Windows ARM64. Prostředí na serveru agent-desktop
neinstalují a desktopovou aplikaci pro Linux ani Windows ARM64 Lazurio zatím
nestaví. Až ji bude stavět, cíl přibude do vydání i do brány CI.

## Aktuální báze a patche

Báze: upstream `v1.3.1` (`b0b7277bea09b770ef9d1fb45aad667bc432cd57`, vydaný
2026-11-13). Je to první báze distribuce; `main` před ní byl upstream commit
`54855b6` bez vlastních commitů.

Patche v pořadí, v jakém leží nad bází:

| Commit | Co dělá | Proč ho nese Lazurio | Kdy zmizí |
| --- | --- | --- | --- |
| `fix(macos): tolerate stable processless AppKit records in complete inventories` | Bridge u záznamu `NSRunningApplication` s `pid <= 0` hlásí v `skipped` i to, co ho ještě identifikuje: `terminated`, jméno, bundle ID, spustitelný soubor a čas spuštění. Takový záznam nedělá inventář neúplným, jen když se jeho identita nezmění mezi dvěma po sobě jdoucími kontrolami úplnosti téže operace (jedna smyčka opakovaného čtení; mimo ni a z jiné operace se nic neporovnává) a když buď je ukončený, nebo nese jméno, bundle ID i spustitelný soubor a žádný z nich na hledanou aplikaci nesedí. S živým záznamem zůstává neúplné hledání aplikace, kterou může znamenat, každé hledání, když záznamu některý z těch tří údajů chybí, i úplný inventář všech aplikací. Bez opravy `launch`, `find` a další příkazy závislé na inventáři opakují pokusy až do `application_inventory_unstable`. | Na skutečném Macu NSWorkspace držel takový záznam pro Preview a engine pak nespustil ani nenašel žádnou aplikaci. Upstream opravu nemá. Stejná změna je odeslaná upstreamu jako vercel-labs/agent-desktop#684 (otevřený, z větve `upstream/macos-stable-processless-records` tohoto forku). vercel-labs/agent-desktop#553 (otevřený, jiný přispěvatel) řeší užší případ: bridge zahodí záznam bez procesu jen s `terminated == YES`. | Až upstream vydá #684 nebo jinou opravu, se kterou takový záznam inventář neblokuje |
| `chore(lazurio): distribution version …` | Verze `X.Y.Z-lazurio.N` všude, kde ji upstream drží (`Cargo.toml`, `Cargo.lock`, `npm/package.json`). Upstreamový `release.yml` (npm a vydání upstreamu) běží jen ve `vercel-labs/agent-desktop`. | Distribuce se vydává tady, ne na npm | Zůstává |
| `chore(lazurio): release workflow and distribution contract` | `.github/workflows/lazurio-release.yml`, `scripts/lazurio-release-archive.sh`, tento dokument, poznámka v README a CI i na větvích `candidate/**` | Vydání s atestací, které aplikace Lazuria pinují | Zůstává |

Tabulku drží commit, který patch přidává nebo mění. Každý nový patch do ní
přibude se svým upstreamovým původem, důvodem a podmínkou odchodu.

## Patche a upstream

1. Oprava enginu leží v kandidátovi jako jeden commit s testy.
2. Stejná změna jde upstreamu jako pull request do
   `vercel-labs/agent-desktop` z větve `upstream/<téma>` tohoto forku. Větev
   stojí na aktuálním upstream `main`, nese jen tu změnu a její popis sleduje
   šablonu upstreamu, bez interních odkazů Lazuria. Odeslání pull requestu
   upstreamu je Publikace a čeká na souhlas.
3. Oprava z review forku nebo upstreamu jde do obou zároveň: do patche
   v kandidátovi i do upstream větve, a popis upstream pull requestu se
   aktualizuje. Tabulka výš uvádí číslo upstream pull requestu a jeho stav.
4. Při refreshi na nové upstream vydání se patch klasifikuje (oddíl Refresh):
   `remove`, když upstream změnu vydal; `migrate` na upstreamovou opravu,
   když upstream vydal jinou; `retain` s důvodem v tabulce, když upstream
   změnu odmítl nebo ji ještě nevydal.

## Verze

`X.Y.Z-lazurio.N`: `X.Y.Z` je upstream release, na kterém `main` stojí, `N`
začíná na 1 a roste s každým vydáním nad stejnou bází; nová báze začíná znovu
od `.1`. `agent-desktop --version` vypíše `agent-desktop X.Y.Z-lazurio.N`
a stejnou verzi engine hlásí v MCP `serverInfo`.

Pozor na SemVer: `1.3.1-lazurio.1` je nižší než `1.3.1`. Aplikace Lazuria
proto engine nevybírají podle rozsahu verzí, ale pinují přesné vydání: commit
release tagu, nebo archiv podle digestu SHA-256.

## Vydání

Brány, které drží repozitář (nastavuje je Organization Admin; schvalovatel je
před schválením přečte zpět):

- prostředí `lazurio-agent-desktop-release` s povinnými reviewery,
  `prevent_self_review: true` (účet, který vydání spustil, ho neschválí)
  a nasazením jen z větve `main`:
  `gh api repos/Lazurio/agent-desktop/environments/lazurio-agent-desktop-release`;
- immutable releases zapnuté:
  `gh api repos/Lazurio/agent-desktop/immutable-releases` → `"enabled": true`
  (token workflow nastavení číst neumí, proto ho workflow dokazuje až na
  publikovaném vydání);
- ruleset „Protect Lazurio release tags“: `refs/tags/v*-lazurio.*` nejde
  přepsat ani smazat;
- ruleset pro `main`: bez smazání a bez force push, s výjimkou jen pro
  Organization Admina, který tak smí `main` nahradit podle modelu výše.

1. `main` je kandidát po review a zeleném CI. Brána CI jsou joby vydávaných
   cílů (oddíl CI níž). Test, který padá kvůli prostředí runneru, dostane
   deterministickou opravu jako patch v tabulce výše; brána se kvůli němu
   nevynechává.
2. Vydání spouští jeden účet a schvaluje jiný, protože prostředí má
   `prevent_self_review`. Kdo je reviewer, určuje nastavení prostředí, které
   schvalovatel přečte zpět. Do issue tohoto repozitáře, ke kterému vydání
   patří, napiš nejdřív spouštějícím účtem komentář, který začíná
   `Release dispatch request:` a obsahuje přesný příkaz s doslovnými
   hodnotami (ne proměnnými shellu), a ten pak beze změny spusť:

   ```text
   Release dispatch request:
   gh workflow run lazurio-release.yml --repo Lazurio/agent-desktop --ref main -f version=<verze shodná s Cargo.toml> -f source_sha=<40 znaků špičky main> -f upstream_tag=<vX.Y.Z> -f upstream_sha=<40 znaků commitu upstream tagu>
   ```
3. Workflow odmítne spuštění, které neběží z `refs/heads/main` přesně na
   `source_sha`, ověří, že zdroj je špička `main`, leží nad upstream tagem jen
   lineárními commity Lazuria a nese verzi, sestaví tři vydávané cíle, zabalí
   pro každý archiv a rozbalený archiv zkontroluje (verze vydání, na macOS
   nalezení pomocné binárky, oddíl Vydávané cíle) a čeká na schválení prostředí
   `lazurio-agent-desktop-release`. Schvalovatel běh schválí, jen když
   workflow je `lazurio-release.yml`, spustil ho účet, který napsal žádost,
   `head_sha` je špička `main`, všechny dokončené úlohy jsou zelené a vstupy
   zalogované úlohou „Verify source and version“ se do jednoho rovnají
   nejnovějšímu komentáři `Release dispatch request:` tohoto účtu, napsanému
   před spuštěním běhu. Rozdíl ve vstupech, jiný commit nebo selhaná úloha
   znamenají odmítnutí s důvodem. Komentář rozhodnutí začíná
   `Run <id> attempt <n>:`. Odmítnutý běh se neopakuje.
4. Po schválení workflow znovu ověří spuštění a špičku `main`, zapíše
   `SHA256SUMS`, atestuje všechny archivy, publikuje release
   `vX.Y.Z-lazurio.N` s tagem na `source_sha` a ověří, že je immutable a tag
   míří na `source_sha`; jinak běh selže.

Ověření archivu:

```sh
gh attestation verify agent-desktop-v1.3.1-lazurio.1-aarch64-apple-darwin.tar.gz \
  --repo Lazurio/agent-desktop \
  --signer-workflow Lazurio/agent-desktop/.github/workflows/lazurio-release.yml \
  --source-digest <source_sha>
```

Aplikace pak pinují commit release tagu (utilita dnes staví engine ze zdroje
na pinnutém commitu), nebo přiložené archivy podle digestu SHA-256; pohyblivý
`main` nepinuje nic. Binárky v aplikaci podepisuje až aplikace svou identitou.

## CI ve forku

- Upstreamové CI běží na pull requestech, na `main` a i na větvích
  `candidate/**`, takže kandidát distribuce je otestovaný dřív, než nahradí
  `main`.
- `Native desktop E2E` (`native-e2e.yml`) běží jen na self-hosted runneru
  s popisky `self-hosted`, `macOS` a `agent-desktop-e2e`. Fork ani Organizace
  takový runner nemají, takže na GitHubu neběží. Upstream před mergem
  vyžaduje headed E2E na macOS proti několika skutečným aplikacím
  (`CONTRIBUTING.md`, `AGENTS.md`). Kandidát s patchem, který mění chování na
  macOS, ho proto potřebuje z vyhrazeného Macu
  (`AGENT_DESKTOP_E2E_EXCLUSIVE=1 bash tests/e2e/run.sh` na přesném headu)
  a výsledek patří do jeho pull requestu.
- Ostatní workflow upstreamu bránou nejsou. `Release Dry Run` (zkouška
  upstreamového vydání pro šest cílů) se spustí na pull requestu, který mění
  jeho cesty, a `CodeQL` se `Supply Chain` mají ve forku stav
  `disabled_fork`.
- GitHub ve forku workflows po čase sám vypíná („Workflows on this fork have
  been disabled“). Bez zapnutých Actions neběží žádná brána; zapíná je
  Organization Admin na stránce Actions repozitáře.

## Refresh na nové upstream vydání

1. Kandidát začíná na přesném upstream release tagu, nikdy na pohyblivém
   upstream `main`, ve větvi `candidate/vX.Y.Z-lazurio.1`.
2. Každý patch se znovu klasifikuje `remove` (upstream ho vydal), `retain`
   nebo `migrate`; starý `main` se do kandidáta nemerguje.
3. Verze `X.Y.Z-lazurio.1` nové báze, pull request kandidáta se schválením
   přesného headu a zeleným CI.
4. Starý `main` musí držet release tag; pak nahrazení `main` přesným
   `--force-with-lease` a samostatné vydání.
