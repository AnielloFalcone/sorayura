# Dati e integrazioni

L'app conserva preferenze, preset, sfondi e riepiloghi locali nella cartella
`~/Library/Application Support/dev.aniello.macsystemwallpaper/`. I widget leggono
contatori di sistema come CPU, memoria, batteria, disco, rete e stato termico.
Non è presente un servizio di telemetria dell'autore o un sistema di account dell'app.

Quando attivi gli agenti AI, l'app legge i registri locali di Codex/Claude e ne ricava
consumi, modelli, progetti e attività. I registri originali possono contenere anche
contenuti delle conversazioni: vengono elaborati localmente. Il collegamento account
Codex, se abilitato, avvia il CLI scelto dall'utente usando l'autenticazione già presente;
il CLI può contattare i servizi OpenAI per ottenere i limiti. L'app non richiede
l'inserimento della password o di una chiave API nelle proprie impostazioni.

La lettura dei limiti Claude desktop usa dati locali disponibili dell'app Claude.
I collegamenti Claude facoltativi modificano la configurazione locale di Claude
per ricevere eventi/stato; conservano una copia della configurazione per il ripristino.

Spotify usa AppleEvents dopo il consenso macOS. Titolo, artista e riproduzione sono
letti dall'app Spotify; le copertine vengono scaricate via HTTPS dai domini CDN
Spotify consentiti. Queste richieste espongono al fornitore i normali dati di rete,
come l'indirizzo IP. I permessi sono revocabili nelle impostazioni di macOS.

I backup esportati includono layout e immagine dello sfondo: condividili consapevolmente.
La disinstallazione conserva i dati locali. Per rimuoverli occorre cancellare
esplicitamente la cartella dei dati, dopo aver disattivato login e collegamenti Claude.

La diagnostica di sviluppo è attiva solo con opzioni esplicite di avvio, scrive
localmente contatori delle risorse/renderer e identificativi dei monitor e ha durata
limitata. Non viene inviata automaticamente all'autore.
