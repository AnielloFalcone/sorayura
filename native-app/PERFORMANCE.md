# Prestazioni e verifiche

Le prove locali sono state eseguite su un Mac Apple Silicon con macOS 27.0.1 e tre monitor. Non costituiscono una garanzia per altre configurazioni.

Nell’ultima osservazione di dieci minuti della build 0.5.1 (2), il processo è rimasto attivo con configurazione invariata. Negli ultimi tre minuti: CPU mediana 14,3% di un core, physical footprint mediano 367 MiB, RSS mediano 197,5 MiB. I renderer hanno mantenuto circa 29–30 fps sui tre monitor. I tempi GPU registrati riguardano soltanto i comandi dell’app e non misurano energia, WindowServer o consumo GPU complessivo.

Le precedenti prove di un’ora hanno osservato memoria stabile nell’intervallo registrato; oscillazioni e cache non dimostrano né escludono un leak. Visibilità e blocco dello schermo non erano monitorati per tutta la durata, quindi i valori CPU non vanno attribuiti interamente alle ottimizzazioni.

L’utente ha verificato Mission Control, scollegamento e ricollegamento di un monitor e Stop/risveglio, con ritorno corretto di widget, posizioni e animazione. Queste prove precedono la rinomina Sorayura.

La preparazione del pacchetto esegue sei controlli: M1, M2, osservazione, risorse, campionamento e prestazioni della lettura agenti. Le integrazioni che richiedono consenso o dati di applicazioni esterne, l’avvio al login e l’installazione di un download notarizzato su un altro Mac richiedono verifica reale.

I dati grezzi delle prove sono locali e non fanno parte del repository pubblico.
