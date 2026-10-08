# Sorayura 0.5.1 — beta

Widget e animazioni native per il desktop macOS, controllati dalla barra dei menu.

- Layout per monitor, griglia regolabile, trascinamento e ridimensionamento.
- Widget di sistema con grafici e storico; memoria compatta o estesa.
- Quattro animazioni con livelli e colori collegati alle risorse del Mac.
- Preset e backup del layout; integrazioni facoltative con Codex, Claude e Spotify.
- Rendering coordinato fra monitor e buffer Metal riutilizzati. Il confronto breve
  su tre schermi ha misurato circa il 30% in meno di CPU a frequenza dei frame simile.
  Il risultato varia con configurazione, visibilità e attività del Mac.

## Limiti della beta

Pacchetto Apple Silicon. Compilazione per macOS 14+, prova reale su macOS 27.0.1;
altre versioni e altri Mac devono ancora essere verificati. Liquid Glass da macOS
26, materiali nativi sulle versioni precedenti. Non sono inclusi aggiornamenti automatici.

Mission Control mostra lo sfondo statico sincronizzato; animazioni e widget sono
finestre del desktop. Gli Space non ancora visitati possono mantenere lo sfondo precedente.
I dati memoria sono stime dai contatori del sistema. I limiti degli agenti dipendono
dalle fonti disponibili e dalla loro data di aggiornamento; dati mancanti non equivalgono a zero.

Installazione dal DMG locale in Applications verificata l'8 ottobre. L'utente ha
confermato il ritorno corretto di widget, posizioni e animazione dopo Mission Control,
riconnessione di un monitor e Stop/risveglio. La diagnostica conferma il ritorno dei
tre schermi; non ha registrato notifiche di Stop, quindi non verifica la pausa del
renderer durante la sospensione. Il primo avvio del download firmato e notarizzato
su un altro Mac resta da verificare.
