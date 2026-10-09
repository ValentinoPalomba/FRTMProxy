# Implementazione e validazione

Perimetro UI aggiornato il 6 ottobre 2026: rimosse Workspace e Acquisizione mirata da menu, palette e destinazioni; mantenuti formati e servizi di compatibilità. I profili chiamata/host/app sono dentro Manage. Add Field si apre dal menu slider finale della tabella. Le sezioni workspace/focus/noise e le prove precedenti restano come cronologia tecnica, non come funzionalità attualmente esposte.

Prima tranche della roadmap Rockxy, implementata autonomamente sul progetto FRTMProxy. Nessun sorgente Rockxy copiato e nessuna nuova dipendenza applicativa aggiunta. `project.yml` resta la sorgente del progetto Xcode.

## Funzionalità implementate

- Readiness del bridge correlata alla singola esecuzione, timeout di avvio, verifica TLS upstream attiva e cattura localhost.
- Arresto del solo processo posseduto; journal su disco prima delle modifiche al proxy macOS, rollback e restore condizionati all'ownership. Recupero dopo la scomparsa del processo app attraverso il bridge e modalità `--recover-proxy`.
- Script JavaScriptCore prima del forward request/response, worker separato per hook, massimo quattro worker contemporanei, timeout di due secondi. Un errore lascia proseguire il traffico e produce una diagnostica.
- Eventi headers/stream/complete/error sullo stesso flow per SSE e NDJSON; byte inoltrati senza modifiche. Le regole che richiedono il body completo impongono buffering con avviso.
- Header ripetuti, protocollo e timestamp effettivi; preview di massimo 2 MiB, body originali cifrati AES-GCM su disco con chiave Keychain. Esportazione dei byte originali dall'inspector.
- HAR dei flow caricati o dell’intera sessione chiusa (export paginato e sostituzione atomica): esportazione redatta senza body predefinita, esportazione completa esplicita, header ripetuti e durata registrata. I tempi DNS/connect/TLS non misurati restano sconosciuti.
- Profili nominati per chiamate, host e app che filtrano soltanto la vista; riconoscimento SSE, NDJSON, JSON-RPC, forme comuni di API AI e indizi x402.
- MCP `query_flows` e `analyze_flows`: filtro/paginazione della cache live e analisi locale con evidenze redatte. `list_sessions`, `query_session_flows` e `get_session_flow` raggiungono anche lo storico cifrato fuori dalla cache live, con redazione identica e senza body/note predefiniti. Nessun provider LLM remoto.
- CI macOS con test Swift/Python, fixture end-to-end, verifica SHA-256 del motore e revisione CodeMirror fissata.

## Riproduzione

```sh
make gen
make verify-engine
make test-bridge
xcodebuild -project FRTMProxy.xcodeproj -scheme FRTMProxy \
  -destination 'platform=macOS' -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' test
make test-integration
```

Verifiche locali del 2 ottobre 2026 su macOS arm64, Xcode 27.1: 163 test Swift Testing e 15 XCTest, 10 test Python (bridge e integrità runtime) e 12 test end-to-end. I test end-to-end con `--worker` usano il bridge e il motore effettivamente inclusi nell’app compilata. Le fixture non cambiano le impostazioni proxy di sistema né installano una CA nel sistema; il restore macOS è verificato con un runner `networksetup` simulato. Non sono benchmark comparativi con Rockxy. CI configurata ma non eseguita su GitHub in questa sessione.

## Limiti da considerare prima del rilascio

- Motore aggiornato a mitmproxy 12.2.3 arm64 (Python 3.14.4/OpenSSL 3.5.5), bundle upstream integro e firmato. `make engine` ripristina l’archivio ufficiale fissato e verifica checksum archivio, firma e hash dell’intero bundle. Intel e HTTP/3 non sono stati verificati.
- Original body: massimo 64 MiB per body e quota 1 GiB. Superare una quota o incontrare un errore disco rende indisponibile l'originale. Schema SQLite 2: riferimenti condivisi preservati, cancellazione/retention delle sessioni elimina i file tramite coda persistente recuperata al riavvio. Migrazione e backfill dei payload precedenti verificati. I body orfani vengono raccolti dopo 24 ore solo se non referenziati da alcuna sessione. Un lock condiviso detenuto dal bridge impedisce la raccolta durante qualsiasi cattura; la pulizia richiede il lock esclusivo e non segue link simbolici.
- Preview e finestra live sono limitate; non esiste ancora un budget globale RAM misurato sotto carico. Il motore può bufferizzare body ordinari o body richiesti dalle regole. Gli stream compressi conservano byte originali ma la preview non viene decodificata progressivamente.
- Massimo 256 breakpoint in pausa, rilascio automatico dopo cinque minuti e su disconnessione del client. Servono prove di stress e crash ripetute prima di dichiarare robustezza di produzione.
- Il marker `X-FRTMProxy-Internal: pairing` esclude solo i client che lo inviano. Il semplice hostname localhost non esclude più il traffico.
- HAR esporta anche l’intera sessione chiusa, paginata, includendo richieste prive di risposta con status 0. Corruzione o conteggio incoerente interrompono l’export senza sostituire il file di destinazione. Le timeline WebSocket non sono ancora esportate. Il replay tramite collection conserva i limiti del modello corrente (header a dizionario e request body testuali).
- Rilevamento AI/x402 euristico: non verifica provider, firme, pagamenti o settlement. `analyze_flows` non sostituisce un assistente AI.
- PAC, autenticazione upstream avanzata, workspace completi, packaging/notarizzazione e benchmark del piano restano aperti. Nessuna firma, pubblicazione o push effettuato.

La parità va dichiarata soltanto dopo aver eseguito la stessa matrice di workflow su FRTMProxy e Rockxy.


## Aggiornamento motore

Il runtime generato è ignorato da Git; un checkout pulito richiede `make bootstrap` o `make gen` prima di aprire Xcode. Il primo ripristino scarica circa 52 MiB; i successivi verificano il bundle locale. Non viene installato software nel sistema. Il manifest contiene URL/versione/hash e commit del cask usato per corroborare il checksum. Il verificatore non esegue i binari; l’installer verifica la firma prima di installare la cartella locale. Il bundle upstream è mantenuto integro, comprese le dipendenze necessarie.


## MCP: consultare lo storico

`list_sessions` accetta `offset`/`limit` e restituisce metadati delle sessioni (ID, nome, date, stato e numero di flow). `get_session_flow` richiede `sessionID` e `id`: non legge la finestra live e applica la redazione standard.

`query_session_flows` richiede `sessionID`, con `query` opzionale nello stesso linguaggio dei filtri UI, `limit` (1–500) e `cursor` opaco restituito dalla pagina precedente. Il limite riguarda i flow **esaminati**, non il numero di match. Una pagina vuota può avere `nextCursor`: continuare finché diventa `null`. `scannedReadableFlows` e `corruptFlowCount` distinguono pagine senza match da payload non leggibili. La memoria è limitata a una pagina e non vengono create colonne SQLite contenenti header/body in chiaro.

Usare sessioni chiuse per una scansione coerente. Durante una cattura attiva i flow cambiano posizione quando arriva la risposta: le pagine riflettono i dati al momento della lettura, senza promettere uno snapshot immutabile. Le query redatte sono state provate su 501 flow con cache live vuota, compresa una prima pagina senza match e una successiva con il risultato cercato. Cursori e tipi JSON errati sono rifiutati.


## Ricerca locale nell’inspector

Il pannello body offre `Search JSON Preview` con due modalità: selezione JSONPath oppure ricerca di chiavi/valori. La selezione supporta `$`, `.field`, `[index]`, `[*]`, `.*` e `["quoted key"]` con escape JSON. Non supporta recursive descent, filtri, slice, indici negativi o apici singoli: le espressioni non supportate sono rifiutate, senza approssimarle. Numeri interi oltre 2^53, booleani e null mantengono la rappresentazione JSON del parser Foundation. La ricerca key/value restituisce percorsi e valori, con confronto localizzato.

La ricerca usa esclusivamente la preview locale (2 MiB massimi) e dichiara la troncatura del body; non legge automaticamente gli originali dal disco. Limiti: query 1 KiB, 64 passi, 256 selezioni per passo/risultati, 50.000 nodi visitati e 256 KiB di output. Un limite produce un errore, senza un campione presentato come risultato completo. Debounce e worker cancellabile fuori dal MainActor evitano parsing sul thread UI e risultati di query precedenti. Il pannello header filtra nome/valore mantenendo le occorrenze duplicate.

`ProxyServiceProtocol` e `ProxyViewModel` ora sono MainActor: lo stato UI e il servizio seguono lo stesso contratto di isolamento. I callback di stderr/log e notifiche di terminazione effettuano il passaggio esplicito al MainActor. Questo non equivale a una certificazione generale di compatibilità Swift 6; il progetto resta in modalità Swift 5.


## Composer: cronologia, variabili e invio

Aprendo una richiesta catturata, il composer carica i byte originali cifrati fuori dal MainActor, con limite di lettura di 2 MiB. Body compressi o non UTF-8 sono rappresentati come Base64; body UTF-8 non compressi restano editabili come testo. Se l’originale referenziato manca, la lettura fallisce senza reinvio di una preview. Senza riferimento, sono rifiutate preview troncate, compresse o con conteggio byte incompatibile; gli import legacy senza metadati non garantiscono la fedeltà dei byte. Un errore svuota la URL per impedire un reinvio accidentale della richiesta incompleta.

Il composer mantiene fino a 50 richieste in cronologia (8 MiB massimi per stato), ripristinabili senza invio automatico. Cronologia e variabili sono cifrate AES-GCM con chiave Keychain, autenticazione del payload e file privato. Un errore di lettura conserva il file e impedisce autosalvataggi che lo sovrascriverebbero; il reset esplicito conserva una copia cifrata. Non salva body di risposta nella cronologia.

Le variabili locali usano `{{NAME}}` in URL, header e body, con una sola sostituzione: variabili mancanti/duplicate e sintassi non supportata impediscono l’invio. I valori non vengono automaticamente codificati per URL o JSON. Sono consentiti HTTP/HTTPS senza credenziali nella URL, URL fino a 8 KiB, 128 header/variabili, 64 KiB complessivi di header e body fino a 2 MiB di byte decodificati. CR/LF/NUL nei valori degli header sono rifiutati. Body consentito anche per GET/HEAD quando presente. Il toggle Base64 invia i byte decodificati e rifiuta Base64 invalido. Gli header di richiesta mantengono ordine e duplicati; Content-Length e Transfer-Encoding sono rimossi e ricalcolati dal trasporto. Questo non replica il framing/protocollo originale, ma il payload e le occorrenze degli header applicativi.

L’invio riusa `/usr/bin/curl`, senza shell e senza caricare configurazioni curl personali. Globbing e normalizzazione dei segmenti del percorso sono disabilitati; la URL originale viene passata come argomento separato. Proxy e CA sono espliciti; un proxy irraggiungibile produce errore senza fallback diretto. In modalità diretta vengono disabilitati i proxy ambientali. Timeout connessione 10 secondi, totale 60 secondi; annullamento termina il solo processo posseduto. Redirect restituiti come risposte 3xx, senza reinvio automatico ad altre destinazioni. Header e body usano pipe separate; preview risposta di 2 MiB con byte totali e avviso di troncatura, header fino a 128 KiB con errore esplicito oltre il limite. Risposte binarie mostrate come data URL. Header di risposta ripetuti restano distinti nella vista.

Le fixture del client effettivo verificano localhost attraverso il proxy, righe vuote nel body, header duplicati, conteggio oltre preview, annullamento di una richiesta lenta, proxy irraggiungibile, risposta redirect e rifiuto TLS upstream/diretto. Il probe stdin è compilato esclusivamente in Debug. Verificati anche reinvio di byte non UTF-8/NUL, ordine e duplicati degli header request, valore vuoto, framing ricalcolato, segmenti `..` e parentesi nella query.


## Confronto strutturale e byte

`Compare flows` confronta request/response body e header. La modalità Structure confronta i valori JSON per percorso, ignorando l’ordine delle chiavi degli oggetti ma preservando indici array, tipi, interi del parser Foundation, null e contenitori vuoti. I path usano chiavi tra parentesi con escape JSON; assenza, stringa vuota e null sono distinti. Il testo non JSON usa `CollectionDifference` dopo aver escluso prefisso/suffisso comuni, così un’inserzione non cambia tutte le righe successive.

Gli header sono confrontati per nome case-insensitive e numero di occorrenza; valori e ordine delle occorrenze dello stesso nome rimangono significativi. Gli import legacy a dizionario mostrano un avviso perché i duplicati non sono recuperabili. La modalità Bytes confronta blocchi da 16 byte con offset decimale e valori esadecimali, caricando gli originali cifrati quando referenziati. Originali mancanti o troppo grandi causano errore senza fallback silenzioso; in assenza di riferimenti l’avviso dichiara che si confrontano preview, che possono contenere testo decodificato. Preview troncate non provano uguaglianza degli originali.

Il calcolo avviene una sola volta fuori dal MainActor, è cancellabile e scarta risultati di selezioni precedenti. La tabella nativa mostra solo cambiamenti. Limiti: 2 MiB per body/originale, 50.000 nodi/righe, profondità JSON 64, 8 MiB di percorsi pendenti o valori preparati per lato, 4.000 cambiamenti, 256 KiB di output, un milione di celle nella ricerca delle modifiche al testo residuo. Superare un limite produce errore invece di un campione presentato come confronto completo. L’algoritmo LCS quadratico precedente e le viste duplicate inutilizzate sono stati rimossi.


## Colonne header personalizzate

`Header Columns` nella lista traffico aggiunge fino a otto colonne request/response, anche senza traffico. Nome HTTP valido fino a 128 byte, distinzione case-insensitive, duplicati di configurazione rifiutati per fase. L’editor consente ricerca dei nomi configurati, rimozione e riordino; Save rende persistenti nomi/fasi/ordine su questo Mac. I valori catturati non vengono copiati nelle preferenze. Configurazione illeggibile preservata fino a reset e salvataggio espliciti.

Le celle preservano le occorrenze dello stesso header in ordine; valori assenti e vuoti sono distinti. Tooltip e accessibilità includono una preview limitata a otto occorrenze, 256 caratteri ciascuna, con troncatura visibile. Il valore completo resta nell’inspector. Il click sull’intestazione ordina per questa preview con confronto localizzato numerico, tie-break stabile per flow ID e assenti prima/dopo secondo la direzione; colonna e direzione sono persistenti. La tabella scorre orizzontalmente per mantenere accessibili tutte le colonne. Le configurazioni vengono decodificate al cambio, senza decoding per ciascuna riga. Gli import legacy a dizionario conservano i loro limiti sui duplicati.

Verificati round-trip configurazione, nomi invalidi/duplicati, limite di colonne e dimensione configurazione (32 KiB), separazione request/response, header case-insensitive, valori ripetuti/assenti/vuoti, ordinamento numerico e preview limitata. Le colonne sono incluse nel workspace esportato come preferenze opzionali, descritte sotto.


## Workspace: preferenze dell’inspector

Il manifest schema 1 ora può contenere `inspectorPreferences`: definizioni delle colonne header (nomi, fasi, ID, ordine), ID della colonna di ordinamento e direzione. È un’estensione opzionale: i workspace precedenti restano importabili e non modificano le preferenze locali. Un array vuoto esplicito rimuove le colonne; un campo assente le conserva. Le versioni precedenti dell’app possono ignorare questo campo. Non sono esportati valori degli header, cronologia/variabili del composer o chiavi.

La preview mostra le colonne e dichiara la sostituzione delle preferenze prima dell’applicazione; un workspace contenente solo preferenze è applicabile. Il risultato segnala separatamente l’applicazione delle preferenze. Validazione del manifest rifiuta colonne duplicate/invalide e riferimenti di ordinamento a colonne assenti prima di cambiare le risorse. Configurazione locale illeggibile impedisce l’export con diagnostica, senza sostituirla con un array vuoto.

Verificati export/import reale su filesystem, piano di importazione senza risorse, codec legacy, preferenze invalide senza mutazioni, round-trip e applicazione tramite il view model con un dominio UserDefaults isolato. Focus salvati e noise control sono ora inclusi come campi opzionali; i tab persistenti restano da completare.


## Focus e noise control nei workspace

`inspectorPreferences` può ora contenere `focusSets` e `noiseControl`. Focus conservano ID, nome e tutto il `FlowFilter` (query, host, app, client IP, mapped/errors). Noise conserva query e stato di abilitazione; filtra solo la vista e non arresta la cattura. Il manifest/preview mostra i filtri che verranno applicati. Campi assenti mantengono le preferenze locali, array vuoto esplicito rimuove i focus, booleano false disabilita il noise. I workspace precedenti contenenti soltanto colonne non sovrascrivono scope/noise.

Limiti: 50 focus, ID distinti, nomi non vuoti fino a 128 byte, query fino a 4 KiB, 128 valori per ciascun insieme host/app/IP con 1 KiB per valore, payload focus massimo 256 KiB. Le nuove creazioni rifiutano nomi già usati; i nomi duplicati legacy restano leggibili e sono disambiguati nel menu tramite ID. Gli errori di salvataggio non eliminano lo stato precedente. Dati illeggibili disabilitano salvataggio/cancellazione fino al reset esplicito, che conserva l’ultima copia locale dei dati originali.

Il menu osserva i cambiamenti delle preferenze e rilegge i focus dopo importazione. Noise usa una bozza nella sheet: Save applica soltanto query entro il limite, Cancel conserva lo stato precedente. L’export rifiuta preferenze focus illeggibili invece di esportare un array vuoto. Le query dei filtri sono metadati esportati in chiaro e visibili nella preview.

Verificati round-trip su filesystem e UserDefaults isolati, applicazione tramite view model, conservazione dei campi assenti, reset tramite array vuoto, rifiuto di input invalido prima delle mutazioni, limiti e compatibilità dei nomi legacy. Non è ancora implementata la persistenza di tab multipli.


## Stress del motore: cache e memoria

Runner riproducibile `make test-stress` (app già compilata in `DERIVED`): client HTTP locali, concorrenza 20, rate target 100/s, 3.000 risposte da 1 KiB e 256 da 2 MiB + 7 byte. Confronta tutti i byte restituiti, ID/eventi terminali e duplicati; campiona RSS del solo processo motore. Interrompe il carico se supera 500 MiB. Report in `artifacts/proxy-stress.json`; CI esegue una prova da 1.000 + 256 richieste e conserva il report anche quando passa. Non modifica proxy/CA di sistema.

La prima prova ha superato il budget a 583,41 MiB, completando 1.217 richieste prima dell’interruzione; i 1.217 terminal events corrispondevano ai client. Il limite di soli 1.000 flow non limitava i body trattenuti. Il bridge ora elimina i più vecchi dalla cache anche oltre 64 MiB complessivi di body/preview. I breakpoint hanno lo stesso budget di body: oltre il limite inoltrano il flow con diagnostica. Gli originali già cifrati rimangono sul disco. Lookup/retry di un flow evinto richiede lo storico/composer e non è più garantito nella cache del bridge.

La sola potatura non bastava: una replica ha raggiunto 530,20 MiB. Il runtime fissato usa Python 3.14.4. La [documentazione Python](https://www.python.org/downloads/release/python-3145/) descrive problemi di pressione di memoria del GC incrementale nelle versioni 3.14.0–3.14.4, corretto dalla 3.14.5. Il bridge richiede una raccolta completa dopo 8 MiB di body evinti, esclusivamente su quelle versioni; il bundle firmato resta integro. I test verificano potatura per byte, flow in pausa e condizione di versione del workaround.

Due repliche da 1.256 richieste hanno completato tutti i client/terminal events, senza warning o duplicati, con picchi RSS campionati di 340,88 e 335,91 MiB. La prova finale da 3.256 richieste completa tutti gli eventi in 33,53 s, con picco RSS campionato 353,75 MiB: latenza assoluta p95 11,85 ms sui body piccoli e 298,37 ms su quelli grandi. Hardware Mac15,6 / Apple M3 Pro, macOS arm64; versioni e campioni sono nel [report](benchmarks/2026-10-02-proxy-stress.json). Non è una misura dell’overhead TLS, né della RAM/UI/writer SQLite dell’app, né un confronto con Rockxy. La prova sostenuta da 180.000 richieste è separata: il primo tentativo è fallito, come descritto sotto.


## Budget dei payload nella cache live Swift

Il servizio limita ora la cache a 500 flow e 64 MiB di payload stimati, contando body, URL, header a dizionario/occorrenze e frame. Il peso viene aggiornato per singolo flow; la potatura ordina per attività recente con tie-break deterministico e preferisce i breakpoint in attesa entro il budget. I messaggi di diagnostica sono limitati a uno ogni cinque secondi. È un limite dei payload trattenuti, non una misura né una garanzia di RSS dell’intera app: restano UI, buffer/eventi in transito, writer SQLite e strutture Swift.

Ogni evento di flow viene pubblicato per la registrazione anche se non entra nella cache live. WebSocket mantiene al massimo 1.000 frame / 4 MiB di contenuto per flow; frame precedenti o singoli frame fuori budget sono esclusi dalla preview con avviso nell’inspector. Gli eventi per lo storico vengono pubblicati prima di questa potatura. Un frame successivo all’evizione ricrea una riga con metadati mancanti dichiarati e continua a pubblicare gli eventi; la sessione può unirli ai metadati precedentemente registrati. Gli avvisi della preview restano transitori e non sono serializzati come errori dello storico. Il writer/session store non ha ancora un budget globale verificato per timeline WebSocket molto grandi.

La riconciliazione dei breakpoint considera soltanto i flow osservati nell’aggiornamento, perché una cache limitata non è la lista completa dei flow in pausa. Evizione e aggiornamenti di altri flow non eliminano le attese; un evento di rilascio elimina la sola attesa corrispondente e l’arresto del proxy svuota la coda. Verificati budget per byte/count, priorità e tie-break, frame sovradimensionati, preservazione del valore completo prima della preview, costo dei duplicati/Unicode e riconciliazione tramite view model.


## Writer: batch e barriere di errore

Il writer suddivide le scritture accorpate in batch fino a 128 flow / 16 MiB stimati. Un singolo record oltre il budget rimane un batch autonomo, senza eliminarne dati: il limite per transazione non è un limite assoluto per quel record. Ordine dei flow, coalescing e aggiornamenti dei contatori delle sessioni sono mantenuti.

Gli errori sono associati ai flow falliti finché il relativo retry non viene salvato. Un batch successivo riuscito, anche della stessa sessione, non cancella l’errore di un batch precedente; la barriera `flush` segnala ancora il fallimento. Verificati 129 flow con primo batch fallito, secondo riuscito e retry completo, suddivisione di 300 record, budget dei byte e conservazione di record singoli sovradimensionati.

Resta aperta la pressione della coda globale: se il disco rimane lento/non scrivibile, i dati accettati e i retry possono accumularsi. La suddivisione limita le transazioni, non garantisce RSS né backpressure dell’intero writer. Non viene dichiarato chiuso questo gate della roadmap.


## Cattura sostenuta: timeout e costo della quota body

Il primo tentativo da 180.000 richieste piccole ha completato 179.600 client e prodotto 180.000 eventi terminali, senza duplicati. È fallito: timeout nel tratto finale e throughput effettivo 64,90/s, inferiore al target 100/s; durata 2.767,39 s, picco RSS campionato 136,22 MiB. Il [report completo precedente alla correzione](benchmarks/2026-10-02-proxy-sustained-before.json) conserva anche i campioni. Le prime 20 diagnostiche sono un campione, non il conteggio totale degli errori.

Nel percorso di append dei body era presente una scansione sincrona con stat di ogni file ogni cinque secondi. Il costo cresce con tutti i body conservati e blocca l’event loop del motore: è una causa plausibile dei timeout, da confermare con la replica. Ora si riusa il contatore delle scritture: scansione iniziale e successivamente solo quando una scrittura rischia di superare la quota, con intervallo minimo di cinque secondi tra tentativi. Le cancellazioni vengono riconosciute su pressione di quota. Controllata la quota anche prima di creare nonce/tag e finalizzare il tag, per non eccederla con molti body vuoti o concorrenti. Nessuna modifica al bundle firmato o alle cifratura/chiavi.

Il test verifica scansione iniziale, mille controlli sotto quota senza riscansione, rifiuto oltre quota, intervallo di retry e recupero dopo cancellazione. Passano 11 test Python e 12 end-to-end sul bundle ricompilato. Resta una scansione sincrona potenzialmente costosa al raggiungimento della quota o all’avvio di una directory molto grande: questo limite non viene dichiarato risolto.

Il runner ora conserva i conteggi degli errori client per tipo e numero di richieste programmate. Il successo richiede anche la durata coerente col rate target (tolleranza 5% più un secondo), oltre a byte/eventi/memoria: un carico rallentato non può superare il gate soltanto perché tutti i client terminano. Il budget globale del writer e la parità con Rockxy restano aperti.


Replica breve dopo la correzione: 3.256 richieste e altrettanti eventi terminali, zero errori/duplicati/warning, durata 33,73 s, throughput 96,53/s entro la tolleranza, picco RSS campionato 365,27 MiB. P95 assoluto 12,38 ms piccoli / 334,98 ms grandi. [Report dopo la correzione](benchmarks/2026-10-02-proxy-quota-after.json). La nuova prova sostenuta da 180.000 richieste è avviata separatamente; finché non termina il gate resta aperto.

## 5 October: recovery and writer capacity

See [UI_RECOVERY_LOG.md](UI_RECOVERY_LOG.md) for the regression inventory and acceptance state. Queue reservations now include pending/in-flight/retry snapshots (4,096 records / 64 MiB estimated payload). Saturation is explicit and stops capture; accepted data is retained for retry. SQLite schema 3 adds a nullable incomplete reason shown in the session list/timeline. This does not promise an RSS bound or crash durability for uncommitted memory. Full-disk persistence of the marker and whole-app stress remain required.

The final native run passes 186 tests; integration passes 13 and Python passes 11. Composer Add/type/send/response and variable Cancel/Save/reopen pass in dark/light at S/M/L. Rule matcher Add/save/reopen passes in dark/light; actual proxied requests verify wildcard and case-sensitive match/nonmatch. Columns/noise have reviewed medium screenshots; their full editing matrix and the remaining search/diff/session/workspace UI workflows remain open.

The sustained HTTP engine run passes: 180,000 expected/completed/terminal IDs, zero duplicates/client errors, 100 req/s for 30 minutes and peak engine RSS 138.375 MiB. See [raw report](benchmarks/2026-10-05-proxy-sustained.json). This measures engine + bridge, not the Swift app/writer or TLS overhead; whole-app performance gates remain open.

## HAR import into captured sessions

Sessions now offers Import HAR with a local preview and an explicit Import action. It accepts HAR 1.2 up to 32 MiB / 10,000 entries. HTTP/HTTPS URLs and headers are validated; repeated headers, binary base64, recorded HTTP version and elapsed timing are preserved. The preview caps each body at 2 MiB; originals are written as authenticated encrypted files and indexed with the imported closed session in one SQLite transaction. A write failure rolls back the session and cleans up files created by that attempt. Cancel before Import does not write capture data or enable mocks.

HAR export preserves fractional timestamps and uses `-1` for an unknown elapsed time. Missing/redacted bodies and unknown DNS/TLS phases are not reconstructed. Unfinished stream entries retain their event and mark the imported session incomplete. Native import tests cover a 3 MiB binary body, repeated/empty headers, timing, original-byte decryption, redacted data, and rollback under a body-write failure. Full file-picker → preview → import UI acceptance remains open.
