# Sorayura — M2 (in sviluppo)

App nativa per macOS, scritta in Swift, AppKit, SwiftUI e Metal. Widget di sistema e animazioni sul desktop, con un controller nella barra dei menu e nessuna icona nel Dock.

## Avvio

Apri **native-app/build/Sorayura.app**. Dalla barra dei menu scegli **Widget e sfondo…** per le impostazioni o **Modifica layout…** per organizzare il desktop.

Per ricompilare servono Xcode Command Line Tools e macOS 14 o successivo:

```sh
cd native-app
./build-native.sh
```

Il progetto contiene soltanto la versione nativa Swift e non richiede Node, Rust o Tauri.

## Funzionalità M1

- Widget: orologio, CPU, memoria, rete, batteria, disco, attività e nome Mac.
- CPU e memoria con barra o grafici degli ultimi 90 secondi; modalità compatta o estesa.
- Memoria estesa con cache, swap, memoria app, vincolata e compressa. Sono stime dai contatori macOS, non una replica esatta di Activity Monitor.
- Click secondario (due dita, se configurato nel trackpad) per il menu del widget. Click mantenuto per 550 ms e trascinamento per spostarlo.
- Modalità modifica con griglia o posizionamento libero, celle regolabili e widget larghi/alti fino alle colonne e righe disponibili; menu Aggiungi per gli elementi nascosti.
- Animazioni Aurora, Impulso, Tracce e Nucleo luminoso; risorse, colori, posizione e dimensione configurabili.
- Warning e critical con soglie e colori configurabili. Rete in bps, Kbps, Mbps o Gbps.
- Contenuti e posizioni indipendenti per monitor; identificazione degli schermi e associazione tramite identità macOS stabile.
- Preset Minimal, Glass, Monitoraggio e Cyber; preset personali; annullamento dell'ultima applicazione.
- Temi widget Minimal, Glass e Cyber. Glass usa Liquid Glass da macOS 26, con materiali nativi sulle versioni precedenti.
- Importazione/esportazione JSON con immagine dello sfondo inclusa, validazione e abbinamento dei monitor.
- Avvio al login opzionale tramite Service Management, attivabile nella sezione Generali.
- Salvataggio automatico e copia di recupero; gestione dei cambi di risoluzione, dei monitor e del risveglio.

## Sfondo e Space

L'app imposta anche il wallpaper statico macOS quando **Usa lo stesso sfondo anche in macOS** è attivo. Mission Control mostra questa immagine, mentre widget e animazioni sono finestre sul desktop.

Al cambio Space e al risveglio l'app riapplica lo sfondo nello Space attivo. Gli Space non visitati possono conservare il wallpaper precedente finché vengono aperti. Puoi usare **Riapplica sfondo** nella sezione Schermi. Non viene impostato un video come wallpaper di sistema.

## Preferenze e backup

I file sono in `~/Library/Application Support/dev.aniello.macsystemwallpaper/`:

- `native-settings.json`: configurazione corrente.
- `native-settings.backup.json`: copia precedente leggibile, usata se il file corrente è danneggiato.
- `presets.json`: preset personali.
- `wallpapers/`: sfondi generati o importati.

La prima apertura recupera le impostazioni della versione Tauri, quando disponibili. Gli identificativi numerici dei monitor vengono migrati mantenendo contenuti e posizioni.

L'export contiene la configurazione corrente e lo sfondo, fino a 25 MB di immagine. I preset personali restano nella loro raccolta locale. I file di importazione possono arrivare a 35 MB. Il toggle di avvio al login è una preferenza di macOS e non viene trasferito dal backup.

## Verifica

Dopo la compilazione:

```sh
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-m1
```

Il controllo copre preset, codifica JSON, abbinamento monitor, compatibilità con le impostazioni precedenti e rifiuto di configurazioni non valide. La verifica di login, sleep/wake e gesture fisiche richiede una sessione reale; vedi [verifiche e prestazioni](native-app/PERFORMANCE.md).

La temperatura in gradi non è disponibile; il widget termico mostra lo stato fornito da macOS.

## Prima versione M2

Dashboard locale Codex/Claude Code, collegamento facoltativo alla status line Claude, widget termico e politica energetica delle animazioni. Dettagli e limiti: [M2](native-app/M2.md).

## Distribuzione beta

Preparazione di DMG, controlli, firma e notarizzazione: [procedura di rilascio](native-app/release/README.md).
Il candidato locale 0.5.1 è distinto dal pacchetto pubblico firmato Developer ID.
Stato delle verifiche: [prestazioni e verifiche](native-app/PERFORMANCE.md).

Il nome del bundle e del processo è **Sorayura**. L’identificatore interno e la cartella dati conservano il nome precedente per mantenere preferenze, layout e permessi. I collegamenti Claude già installati dal percorso precedente vengono aggiornati al primo avvio di Sorayura.

Repository: [AnielloFalcone/sorayura](https://github.com/AnielloFalcone/sorayura).

## Licenza

[MIT](LICENSE) — Copyright © 2026 Aniello Falcone.

Il supporto Homebrew è in preparazione nel [tap Sorayura](https://github.com/AnielloFalcone/homebrew-sorayura); il Cask sarà installabile dopo la prima release firmata e notarizzata. [Procedura Homebrew](native-app/release/HOMEBREW.md).
