# Sorayura — M2 nativa

Implementazione Swift, AppKit, SwiftUI e Metal. Vedi il [README principale](../README.md) per le funzionalità e le impostazioni.

## Compilazione

```sh
./build-native.sh
```

Apri `build/Sorayura.app`. Il pacchetto viene firmato localmente per mantenere una struttura valida; non è una distribuzione notarizzata.

## Controlli

```sh
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-m1
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-m2
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-observation
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-resources
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-sampling
```

Le verifiche che richiedono l'interazione con il Mac sono elencate in [PERFORMANCE.md](PERFORMANCE.md).

Il controllo Observation usa un modello isolato: verifica che un campione CPU non notifichi impostazioni, agenti, Spotify o metriche invariate; verifica inoltre storici, avvisi e binding dei controlli. Non avvia i lettori delle integrazioni e non scrive le preferenze dell'utente.

Il controllo Resources crea finestre delle impostazioni non mostrate e piccoli buffer di prova: verifica rilascio della vista, riapertura con sezione e geometria conservate, massimo di tre frame in volo, riuso/crescita dei buffer, completamento GPU e geometrie dei quattro stili. Non avvia il wallpaper né modifica le preferenze.

Verifica anche pausa/ripresa e collegamento/distacco della vista Metal, vertici di riferimento della release precedente, pixel GPU identici fra disegni separati/raggruppati e ripristino delle fasi diagnostiche. Sampling usa letture disco simulate per verificare scadenza della cache, gestione degli errori e aggiornamento immediato dopo reset. CPU/memoria/rete continuano a campionare ogni secondo; lo spazio disco viene letto ogni 30 secondi e dopo wake/reset.

Resources verifica inoltre il clock comune con renderer a frequenze diverse e un batch di tre passaggi GPU: slot conservati fino al completamento, restituzione se il batch viene abbandonato e pixel indipendenti corretti. Pausa su sleep/sessione inattiva e occlusione di tutte le finestre è verificata con stati simulati; queste fixture non certificano le transizioni fisiche del Mac.

## Rendering su più monitor

Il lancio normale coordina i renderer con un clock comune e invia i passaggi dovuti nello stesso tick in un command buffer Metal. Ogni monitor conserva il proprio limite FPS e i propri buffer. Nessuna riduzione automatica della qualità o modifica delle preferenze per questa ottimizzazione.

`--independent-frames` è un flag di confronto interno che ripristina i clock automatici distinti di MTKView nello stesso binario. È un'opzione di avvio, non un'impostazione dell'interfaccia: per confrontare le modalità occorre chiudere normalmente l'istanza esistente prima di avviare il pacchetto esatto con il flag. È possibile eseguire il controllo Resources anche con `--independent-frames --check-resources`, senza avviare il desktop.

Nel rendering condiviso `MTKView.isPaused` è sempre true perché il disegno è esplicito. Gli snapshot distinguono `automatic_mtk_paused` dalla pausa logica `paused`, e aggiungono `frame_clock`, tick e invii condivisi. Usare i contatori di frame inviati per verificare che l'animazione sia attiva. Sleep/sessione inattiva o tutte le finestre wallpaper attive occluse sospendono il clock; la verifica fisica della ripresa resta elencata in PERFORMANCE.md.

## Diagnostica dei componenti

`--benchmark-sampling` confronta pochi campioni seriali del lettore con query disco ripetute e conservate. `--benchmark-geometry` misura piccole fixture CPU delle quattro geometrie. Nessuna finestra del wallpaper, lettura degli agenti o scrittura delle preferenze; non sono confronti dell'app completa o misure GPU/energia.

Il lancio con `--profile-components /percorso/assoluto/cartella` attiva una prova visiva esplicita di circa nove minuti: sei fasi da 90 secondi (normale, Metal sospeso, Glass sostituito, widget nascosti, widget nascosti + Metal sospeso, normale). Registra i confini in component-profile.json. Non salva modifiche alle preferenze, mantiene la vista Metal e la sua timeline e ripristina automaticamente la presentazione normale. Interrompe/ripristina su modifica del layout/preferenze, cambio di schermi/Space o wake. Va usato con Mac sbloccato e visibilità controllata, dopo aver concordato la temporanea variazione dello sfondo. Raccogliere contemporaneamente CPU/RSS/footprint del PID; escludere i campioni di transizione e distinguere il costo del processo da quello GPU/WindowServer. Un'istanza già aperta non avvia una seconda prova da sola.

`--render-diagnostics /percorso/assoluto/file.json` abilita per circa dieci minuti uno snapshot passivo ogni dieci secondi dei contatori draw/fotogrammi inviati e dello stato delle viste Metal sui monitor. Nessuna modifica al desktop o alle preferenze. Zero fotogrammi, occlusione e pausa vanno controllati prima di interpretare una diminuzione CPU come risparmio del renderer; i contatori non misurano costo GPU/energia o visibilità dei pixel. Il normale lancio non abilita questa raccolta.

Da 0.5.1 gli snapshot includono anche i tempi GPU dei command buffer di questa app,
errori di completamento, finestre/schermi e gli ultimi 64 eventi di cambio Space,
monitor e sospensione. `--render-diagnostics-seconds 1800` estende la durata fino
a un massimo di un'ora. I tempi GPU non sono utilizzo percentuale dell'intera GPU
né consumo energetico. Le statistiche dei tempi recenti conservano al massimo
240 campioni e non raccolgono contenuti delle finestre.

Per una prova dei componenti autorizzata, il monitor `performance/measure-footprint.py` accetta `--render-health <file.json>` e conserva gli snapshot nuovi in render-snapshots.jsonl. Dopo il ripristino del profilo, `python3 performance/analyze-components.py <cartella-prova>` calcola CPU/RSS/footprint per fase, esclude i primi 30 e gli ultimi cinque secondi e controlla presenza, pausa e invio dei fotogrammi su ogni monitor. Interpretare una sequenza breve con cache/ordine delle fasi e confronto completa iniziale/finale; non misura costo GPU o energia.

Per due raccolte di tre minuti `independent/` e `shared/` con metadata e snapshot, `python3 performance/analyze-renderer.py <cartella-prova>` confronta CPU/RSS/footprint nel segmento 60–175 s, includendo soltanto intervalli CPU interamente nel segmento. Controlla identità/configurazione, renderer attivi, dimensioni e FPS equivalenti (rapporto 0,95–1,05). Confronto e limiti dell'8 ottobre in PERFORMANCE.md: calo CPU osservato circa 30%, nessun risparmio RAM dimostrato; da confermare nel tempo.

Novità M2 e limiti dei dati: [M2.md](M2.md).
