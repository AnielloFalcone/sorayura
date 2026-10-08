# Homebrew per Sorayura

Tap: `AnielloFalcone/homebrew-sorayura`. Pacchetti: release di `AnielloFalcone/sorayura`.
Homebrew riconosce il prefisso `homebrew-`, quindi il comando sarà `brew tap AnielloFalcone/sorayura`.

Il tap nasce con README, licenza e verifica automatica. `Casks/sorayura.rb` verrà
aggiunto dopo la prima release firmata, notarizzata, pubblicata e verificata.
Non contiene URL fittizi o checksum provvisori installabili.

## Prima release

1. Preparare il pacchetto pubblico con `prepare.py release`, come descritto in [README.md](README.md).
2. Completare la verifica del pacchetto finale scaricato su un altro Mac e pubblicarlo nella release GitHub con tag immutabile.
3. Clonare il tap in una cartella locale:

   ```sh
   gh repo clone AnielloFalcone/homebrew-sorayura native-app/releases/homebrew-sorayura
   ```

4. Generare il Cask dal manifest del pacchetto locale definitivo:

   ```sh
   python3 native-app/release/write-cask.py \
     native-app/releases/0.5.1-4-release/manifest.json \
     --repository AnielloFalcone/sorayura --tag v0.5.1-beta.1 \
     --output native-app/releases/homebrew-sorayura/Casks/sorayura.rb
   ruby -c native-app/releases/homebrew-sorayura/Casks/sorayura.rb
   brew style native-app/releases/homebrew-sorayura/Casks/sorayura.rb
   ```

5. Confrontare il checksum del DMG scaricato da GitHub con quello del manifest/Cask. Il generatore verifica il file locale; non certifica il download remoto.
6. Aggiornare il README del tap rimuovendo l’avviso di preparazione; fare commit e push nel tap. Il workflow controlla sintassi Ruby e stile Homebrew senza installare l’app.
7. Verificare su un Mac di prova `brew tap AnielloFalcone/sorayura`, `brew readall --os=sonoma --arch=arm AnielloFalcone/sorayura`, installazione, apertura, aggiornamento e disinstallazione.

Su Homebrew configurato per richiedere fiducia esplicita, il manutentore deve
verificare il contenuto del proprio tap e autorizzarlo con
`brew trust --tap AnielloFalcone/sorayura` prima di `readall`. Per gli utenti
è sufficiente autorizzare il singolo Cask, come indicato nel README del tap.

La validazione preliminare non sostituisce la prova di installazione del download.
L’app manualmente installata su questo Mac resta attiva durante la preparazione del tap.

## Aggiornamenti

Per ogni nuovo pacchetto usare un nuovo numero di build e un nuovo tag; conservare
gli artefatti pubblicati senza sostituirli. Il Cask usa `version "versione,build"`
per rilevare anche due beta con la stessa versione dell’app.

Generare il nuovo Cask in un file temporaneo, verificarlo e sostituire quello del
tap con un commit. Il generatore rifiuta di sovrascrivere un file esistente.
La pubblicazione nel tap è un passaggio esplicito; non richiede token salvati
nel repository o un’automazione che scriva in altri repository.

`uninstall quit:` chiude normalmente l’app anche durante upgrade/reinstall.
Non vengono rimossi automaticamente dati, preset o sfondi. Prima di disinstallare,
l’utente disattiva login e integrazioni Claude dall’app; non è previsto `zap`.

## Verifica del generatore

```sh
python3 native-app/release/test_cask.py
```

I test usano manifest sintetici e file temporanei: provano checksum, formato,
architettura, rifiuto dei candidati, notarizzazione non accettata e sovrascrittura.
I dati sintetici non sono pacchetti firmati e non vanno pubblicati.

Fonti: [creare un tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap),
[Cask Cookbook](https://docs.brew.sh/Cask-Cookbook),
[sicurezza Homebrew](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain).

Verifica della preparazione: otto test del generatore superati, sintassi Ruby e
`brew style` superati; Cask sintetico caricato con `brew info` e `brew readall`
simulando Sonoma/ARM in un tap temporaneo poi rimosso. Nessuna app installata.
Il workflow GitHub del tap è passato sullo scheletro iniziale; la verifica del
primo Cask reale avverrà quando verrà aggiunto.
