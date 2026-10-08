# Preparazione della beta

La prima beta è per Apple Silicon. La build dichiara macOS 14 come minimo;
le prove reali disponibili sono su macOS 27.0.1. Intel e le altre versioni
restano da verificare. Materiali da rivedere: LEGGIMI.txt, RELEASE-NOTES.md e PRIVACY.md.

## Candidato locale

Dal progetto:

```sh
python3 native-app/release/prepare.py candidate --version 0.5.1 --build 4
```

Crea una cartella nuova in `native-app/releases/`, compila con hardened runtime
e firma locale, esegue i sei controlli funzionali e verifica che tutte le librerie
siano di sistema. Crea il DMG con collegamento ad Applications e checksum SHA-256.
Il manifest conserva esiti, versione, architettura e hash. Una cartella già
esistente non viene sovrascritta. Il pacchetto candidato non è quello pubblico.

La prova dell'8 ottobre ha installato il candidato dal DMG in
`/Applications/Mac System Wallpaper.app`, verificando firma e avvio da quel percorso.
Questo non simula Gatekeeper su un download da Internet: per quello serve il
pacchetto finale notarizzato, con la quarantena applicata dal download, su un altro Mac.

## Firma e notarizzazione

Occorre un certificato **Developer ID Application** con relativa chiave privata
nel Keychain. I certificati **Apple Development** presenti non sostituiscono quel
certificato per questo canale di distribuzione. Si crea dall'account Apple Developer
o da Xcode con il ruolo autorizzato. Non esportare la chiave privata nel progetto.

Configurare le credenziali di notarizzazione con `xcrun notarytool store-credentials`
usando la richiesta interattiva sicura; conservare soltanto il nome del profilo.
Password e API key non vanno inserite nella chat, nei file del progetto o negli argomenti
degli script di rilascio.

```sh
python3 native-app/release/prepare.py release --version 0.5.1 --build 4 \
  --identity 'Developer ID Application: NOME (TEAMID)' \
  --notary-profile 'PROFILO_KEYCHAIN'
```

La procedura richiede identità Developer ID, abilita hardened runtime e timestamp,
usa solo l'entitlement AppleEvents necessario a Spotify, verifica tutti i controlli,
notarizza e allega il ticket all'app, crea/firma/notarizza il DMG e verifica Gatekeeper.
Un esito diverso da Accepted ferma la procedura. Conservare preparation.log e manifest.json.
Il manifest resta in attesa della verifica fisica e della revisione dei materiali prima
della pubblicazione; lo script non pubblica automaticamente.

## GitHub e Homebrew

Repository scelto: **[AnielloFalcone/sorayura](https://github.com/AnielloFalcone/sorayura)**.
Nome dell’app e dell’eseguibile: **Sorayura**.
Il certificato Developer ID e il
profilo di notarizzazione sono ancora da predisporre. La parte della procedura
che firma e notarizza con Apple non è stata eseguita sul candidato locale.

Il codice sorgente è pubblico con licenza MIT nel repository indicato. La procedura
di preparazione non pubblica i pacchetti. Dopo revisione dei materiali, pubblicare
una prerelease con tag immutabile, DMG notarizzato, SHA256SUMS e note della beta.
Il DMG include la licenza MIT. Il candidato locale non va caricato come beta pubblica.

```sh
python3 native-app/release/write-cask.py \
  native-app/releases/0.5.1-4-release/manifest.json \
  --repository AnielloFalcone/sorayura --tag v0.5.1-beta.1 \
  --output native-app/releases/sorayura.rb
```

Tap dedicato: `AnielloFalcone/homebrew-sorayura`. La preparazione, la pubblicazione
del Cask e gli aggiornamenti sono descritti in [HOMEBREW.md](HOMEBREW.md).

Il generatore rifiuta candidati locali e artefatti con checksum diverso. Dopo aver
pubblicato il DMG, verificare il Cask nel tap scelto con un'installazione reale.
La disinstallazione ordinaria conserva i dati. Prima di rimuovere l'app, l'utente
disattiva login e collegamenti Claude dall'interfaccia.

Fonti: [Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[notarizzazione Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).
