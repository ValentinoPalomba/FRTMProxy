# FRTMProxy: piano per raggiungere la maturità di Rockxy

Aggiornamento di perimetro del 6 ottobre 2026: Workspace e Acquisizione mirata non fanno più parte delle funzionalità esposte. I relativi formati e servizi rimangono per compatibilità dei dati. La UI usa profili nominati per chiamate, host e app dentro Manage, e Add Field nel menu slider finale della tabella; i riferimenti storici a focus/noise/workspace sotto non ampliano questo perimetro.

Data: 1 ottobre 2026. Approccio: Ponytail, livello full.

Obiettivo: raggiungere la potenza del workflow pubblico di Rockxy con meno codice da mantenere. La complessità utile è gestire traffico, errori e sessioni reali; aumentare file, dipendenze o livelli architetturali non è un obiettivo.

## Baseline e perimetro

- FRTMProxy analizzato: `30b678513db1fd27bae7f5bff954c9cbe839c369`, versione nel progetto `1.8.1`.
- Rockxy analizzato: `5bff790764d1371bebfa9fc2a64778747365d0c8`, clone del ramo predefinito; README indica release `0.40.0`.
- Analisi: sorgenti Swift/Python, modelli, test, configurazione progetto e release; grafo strutturale locale di FRTMProxy per orientare le dipendenze. Non è una prova di equivalenza runtime.
- Verifica eseguita: `python3 -m unittest discover -s tests -v`, 4 test passati. Non sono stati eseguiti build Xcode, suite Swift, benchmark o installazioni di certificati.
- Rockxy separa il repository Community dalla distribuzione ufficiale, che include componenti downstream non pubblici. La parità verificabile riguarda il sorgente pubblico; eventuali capacità esclusive del binario richiedono un confronto separato.

Fonti di riferimento: [FRTMProxy](https://github.com/ValentinoPalomba/FRTMProxy/tree/30b678513db1fd27bae7f5bff954c9cbe839c369), [Rockxy](https://github.com/RockxyApp/Rockxy/tree/5bff790764d1371bebfa9fc2a64778747365d0c8), [licenze Rockxy](https://github.com/RockxyApp/Rockxy/blob/5bff790764d1371bebfa9fc2a64778747365d0c8/LICENSING.md), [roadmap Rockxy](https://github.com/RockxyApp/Rockxy/blob/5bff790764d1371bebfa9fc2a64778747365d0c8/ROADMAP.md). Funzioni future della roadmap, come collaborazione cloud e regole più profonde per protocolli specializzati, non sono considerate capacità già rilasciate.

## Decisione tecnica

Conservare SwiftUI/AppKit + mitmproxy + bridge JSONL + SQLite/CryptoKit. mitmproxy è già il motore HTTP/TLS: sfruttarne gli hook e le opzioni prima di costruire un altro proxy. Conservare Sparkle, CodeMirror, i modelli di regole e i servizi esistenti.

Nessuna riscrittura in SwiftNIO per questa roadmap. Valutarla solo se una misura riproducibile dimostra un limite non risolvibile del motore embedded: compatibilità indispensabile, packaging o throughput. Un prototipo deve allora battere la baseline e includere il costo di TLS, certificati, routing e aggiornamenti.

Niente framework di plugin, bus di eventi aggiuntivo, migrazione generale a `@Observable`, servizi cloud o nuovo database. Estrarre una responsabilità dal view model solo quando un intervento concreto lo richiede. Rispettare `project.yml` come sorgente del progetto Xcode.

## Situazione attuale e gap

“Presente” significa individuato nel codice, non certificato in produzione. “Da verificare” richiede un caso riproducibile prima di dichiarare parità.

| Area | Evidenza FRTMProxy | Azione necessaria |
|---|---|---|
| HTTP/HTTPS e selezione host | `MitmproxyService`, impostazioni host | Verificare TLS, HTTP/2 e bypass; mostrare limiti e fallimenti reali |
| Avvio e recupero proxy | Snapshot in `MacOSProxyOverrideManager`; self-healing nelle impostazioni | Ownership dei processi, readiness, rollback e recupero dopo crash |
| Rules, mock, redirect, header, blocco, delay, breakpoint | Pipeline unificata nel bridge, store/versioni/ACK e test | Provare ordine e risultato osservato dal client; completare migrazione legacy |
| JavaScript | `ProxyViewModel+Scripts` esegue dopo l'evento response | Portare gli hook prima dell'inoltro; deadline e isolamento |
| WebSocket | Eventi start/message/end e inspector | Verificare limiti, chiusure, binary frame e persistenza |
| SSE e NDJSON | Inspector SSE; bridge pubblica la risposta nell'hook `response` | Cattura incrementale live e finalizzazione unica della riga |
| Sessioni durabili | SQLite WAL, payload cifrati, Keychain, paginazione, note/bookmark | Retention, ricerca nello storico, grandi body e recupero sotto carico |
| Filtri e scope | Parser `FlowFilter`, host/app/device/protocollo | Scope salvati, esclusioni, tab persistenti e rumore nascosto senza perdere capture |
| Compose/replay/diff | Feature già presenti | Cronologia e ambiente; fedeltà di byte/header e replay deterministico |
| HAR e condivisione | Converter delle Collections, workspace e Git | Export delle transazioni reali, timing/protocollo/binary e redazione uniforme |
| Inspector protocolli | GraphQL, JWT, form/multipart, SSE, gRPC/Protobuf euristico | NDJSON, AI/RPC/x402, JSON search e preview; distinguere euristica da decode completo |
| Setup runtime/device | Mac, Simulator, QR, Android, selective capture | Preset e prova end-to-end per client, container e device |
| Proxy upstream/PAC | Nessuna implementazione individuata nel percorso di avvio esaminato | HTTP/HTTPS upstream, credenziali e PAC; verificare SOCKS separatamente |
| AI e automazione | MCP locale su Unix socket, redazione e replace rules | Espandere strumenti di indagine e aggiungere assistente opzionale |
| Distribuzione e qualità | Script firma/notarizzazione/Sparkle/Homebrew; test Swift | CI automatica, dipendenze fissate e provenienza del motore; `mitmdump` attuale arm64 |

## Rischi prioritari individuati

1. `MitmproxyService.terminateStaleMitmProcesses` usa `pkill -f mitmdump`, `pkill -f mitmproxy` e `killall`: può terminare istanze estranee. Eliminare il cleanup per nome e gestire solo il figlio posseduto, con identità verificata anche nel recupero.
2. `buildArguments` imposta sempre `ssl_insecure=true`: la verifica del certificato del server è disabilitata. Ripristinarla come default, con eccezione esplicita e circoscritta per ambienti di sviluppo.
3. `isRunning` diventa true dopo `Process.run()`, senza prova che il listener sia pronto. Le impostazioni possono applicare il proxy di sistema prima della readiness. Separare starting/ready/failed e applicare override solo dopo verifica.
4. `processScripts` viene chiamato da una subscription UI throttled dopo `response`; invia `mock_response`, che aggiorna le regole mock. Non garantisce la trasformazione della risposta in corso vista dal client. Serve una pausa nel bridge prima del forward, una sola esecuzione e un esito correlato.
5. `serialize_body` tronca a 2 MB, i flow attivi sono limitati a 500 in Swift e i lookup a 1.000 nel bridge. La persistenza riceve eventi separati dalla lista UI: non significa che la sessione abbia soltanto 500 richieste. Però lo storico riceve già il payload serializzato/troncato; conservare il body originale richiede un percorso dedicato.
6. `MitmFlow` usa dizionari per gli header: non rappresenta duplicati e ordine. L'HAR delle Collections usa `HTTP/1.1` e `time: 0`. È un export di mock, non una registrazione fedele del protocollo/timing.
7. `LineBuffer` è sincronizzato ma non impone un massimo al frame incompleto. Aggiungere limiti e segnalazione dell'overflow; controllare anche code di comandi/eventi e retention WS.
8. Il bridge ignora in blocco i target loopback. Distinguere il traffico interno di pairing dal server locale che uno sviluppatore vuole debuggare.

Questi punti sono osservazioni statiche. P0 deve convertirli in test di comportamento, senza attribuire numeri di performance non misurati.

## Roadmap e criteri di uscita

Ogni fase produce PR piccole, una dimostrazione riproducibile e documentazione coerente con il comportamento. I check devono coprire confini Swift↔Python↔client, dove i soli test dei modelli non bastano.

### P0 — Baseline riproducibile e affidabilità minima

Effort indicativo: 1–2 settimane di una persona esperta. Dipendenze: nessuna.

- Aggiungere CI Python + build/test macOS senza credenziali di release; pubblicare `.xcresult` in caso di errore. Usare gli strumenti esistenti, separando la release firmata.
- Fissare CodeMirror a una revisione/versione verificata invece del branch mobile `master`; documentare versione, checksum, licenza e produzione del `mitmdump` embedded.
- Una piccola fixture HTTP/HTTPS/WS/SSE, con ID richieste e output deterministici, e un runner Python stdlib. Riutilizzarla nelle fasi successive; TLS della fixture locale configurato esplicitamente.
- Correggere cleanup dei processi, readiness/porta occupata e default TLS. Riutilizzare il manager di override: snapshot prima di ogni mutazione, ripristino solo dei valori ancora posseduti, recupero dopo fallimenti parziali e crash. Non aggiungere helper privilegiati senza una necessità dimostrata.
- Testare localhost senza catturare il pairing interno. Aggiornare i commenti AGENTS obsoleti: il shaping è già asincrono e le sessioni durabili esistono.

Uscita: CI verde su checkout pulito; un `mitmdump` esterno resta vivo; porta occupata non cambia le impostazioni; certificato upstream invalido rifiutato di default; stop/fallimento ripristina il precedente proxy senza sovrascrivere modifiche esterne. Per un crash completo dell'app verificare anche il periodo prima del riavvio: il recupero al prossimo launch da solo non garantisce connettività immediata. Se serve, introdurre soltanto il minimo watchdog di proprietà con lifespan limitato.

### P1 — Regole, breakpoint e scripting che agiscono sul traffico reale

Effort: 2–3 settimane. Dipendenze: fixture P0.

- Conservare `TrafficRuleDocument` e la pipeline Python. Provare priorità, azioni terminali, redirect, query/body matching, migrazione legacy e ACK con timeout/stato applicato visibile.
- Correggere JS con hook request/response nel bridge: intercettare soltanto i flow che richiedono uno script, inviare ID/fase/revisione, attendere il risultato, applicarlo e riprendere. La UI non deve decidere la modifica dal proprio refresh throttled.
- Riutilizzare JavaScriptCore fuori dal MainActor. Cancellare una Task non interrompe un ciclo infinito JS: usare un limite di esecuzione verificabile; se il runtime non offre una terminazione affidabile, usare un solo worker terminabile. Errori e timeout hanno esito esplicito, senza lasciare richieste appese.
- Garantire rilascio dei breakpoint su stop, disconnect, timeout e errore; evitare eviction dei flow ancora intercettati. Gli script non devono creare mock permanenti incidentalmente.
- Presentare il shaping per ciò che fa: ritardi e fallimenti HTTP simulati. La risposta sintetica 598 non è perdita reale di pacchetti TCP; verificare separatamente shaping per chunk.

Uscita: il client riceve esattamente metodo/header/body/status modificati; ordine deterministico e script eseguito una volta per fase; uno script infinito non blocca UI o tutto il proxy; nessun flow sospeso resta irrecuperabile. La suite copre una pipeline combinata, non solo ciascuna azione isolata.

### P2 — Streaming e catture grandi senza perdita silenziosa

Effort: 2–4 settimane. Dipendenze: P0; coordinare semantica script/breakpoint con P1.

- Estendere JSONL con versione, ID flow/evento e sequenza; distinguere response headers, chunk, complete, error e cancel. Compatibilità dei vecchi payload e limite del frame.
- Usare gli hook di streaming mitmproxy: una riga dagli header, aggiornamenti limitati in frequenza, stesso ID fino alla chiusura. SSE/NDJSON non devono aspettare il body completo.
- Separare anteprima e body originale. Salvare bytes su storage locale protetto/cifrato con riferimento, dimensione, encoding e stato di troncamento; caricare nell'inspector solo su richiesta. Iniziare con limiti chiari e consistenza con SQLite, senza inventare un object store generico.
- Preservare header ripetuti, versione HTTP, encoding, byte count e timestamp disponibili dal motore; non inventare waterfall DNS/TLS quando manca la misura.
- Limitare code, eventi/frame WS e spazio su disco. Coalescing solo degli aggiornamenti UI, non di eventi terminali o dati necessari al replay. Rallentamento o limiti raggiunti devono essere visibili.
- Riutilizzare paginazione SQLite, aggiungere retention configurabile e ricerca nello storico. Prima metadata SQL; ricerca body con scansione cancellabile e budget. FTS in chiaro non va introdotto incidentalmente sui payload cifrati.

Uscita: SSE/NDJSON e WS hanno una sola riga e chiusura corretta anche con cancel; byte finali uguali alla fixture entro i limiti dichiarati; test con Unicode spezzato tra chunk, header duplicati, body binario >2 MB e client lento. Memoria limitata anche quando il client resta connesso a lungo.

### P3 — Workflow quotidiano alla pari

Effort: 2–3 settimane. Dipendenze: P1/P2 per dati fedeli.

- Scope salvati con inclusioni/esclusioni app/domain/path, tab persistenti e noise control, costruiti sopra `FlowFilter` e workspace esistenti. Nascondere traffico non deve impedirne il salvataggio.
- Colonne header personalizzate; ricerca key/value e JSONPath nell'inspector. Iniziare dal sottoinsieme dichiarato di JSONPath, senza promettere lo standard completo.
- Migliorare composer esistente con cronologia e variabili di ambiente locali; replay e diff strutturale di JSON/header/bytes con duplicati preservati.
- Export HAR delle sessioni/transazioni reali distinto dalle Collections mock; import con revisione, binary base64, timing e streaming. Unificare redazione di export/cURL/workspace/MCP sopra la policy esistente e aggiungere preview.
- Setup Hub minimo: snippet verificati per cURL, Node, Python, Java, Go, Rust, browser, Docker e device; il test deve provare passaggio nel proxy e fiducia TLS del client scelto. Separare proxy system-wide da launch selettivo e attribuzione app best-effort.
- Routing upstream HTTP/HTTPS e autenticazione tramite capacità del motore, Keychain per credenziali. PAC con CFNetwork e test di DIRECT/PROXY/HTTPS, timeout e no bypass accidentale; verificare come inoltrare una route per flow a mitmproxy prima di progettare il bridge. SOCKS5 richiede spike e test: non assumere che modalità upstream e listener SOCKS siano la stessa cosa.
- Rotazione/rimozione CA, diagnostica trust e certificati client mTLS se il motore li supporta nel packaging scelto. Preview aggiuntive riusano gli inspector esistenti, senza marketplace di plugin.
- Shortcut, focus/selezione stabile, split view e accessibilità; rispettare `PRODUCT.md`/`DESIGN.md` senza un redesign globale.

Uscita: un utente completa installazione→capture→filter→mock→replay→diff→export/import con tastiera e senza CLI; scope/tab tornano al rilancio; il noise control preserva la cattura; l'HAR conserva le informazioni disponibili e nessun segreto delle fixture compare nell'export redatto. Upstream e PAC hanno test di routing separati da quelli del proxy locale.

### P4 — Ispezione moderna e integrazione AI

Effort: 2–3 settimane. Dipendenze: P2/P3.

- Estendere `ProtocolInspector`: traffico API AI con modello, usage, tool call e stream quando presenti; JSON-RPC singolo/batch/error e indicatori x402. Mostrare “sconosciuto” quando il payload non sostiene l'inferenza.
- Mantenere gRPC/Protobuf come wire inspection euristica finché mancano descriptor/schema; aggiungere decode completo solo con schema fornito e un caso d'uso reale.
- MCP: aggiungere query, dettagli storici, confronto e riepilogo protocolli; paginazione e redazione. Conservare la mutazione atomica delle regole esistente con permessi espliciti e strumenti read-only come default di indagine.
- Assistente iniziale locale: analisi deterministica di errori, timing e differenze, con riferimenti ai flow. Riutilizzare MCP come canale per modelli esterni prima di aggiungere SDK/provider.
- Per parità dell'assistente interno, aggiungere un adapter HTTP per Ollama/provider compatibile e un adapter specifico soltanto dove necessario: preview del contesto redatto, consenso all'invio, budget, cancellazione e risposta streaming. Le azioni proposte restano confermabili; un payload catturato non diventa istruzione eseguibile.
- Export OpenAPI JSON iniziale con esempi redatti e schema dichiarato inferito; YAML/HTML come completamento della parità export. Condivisione Gist opzionale solo su azione esplicita, con preview e credenziali Keychain; nessun servizio cloud proprietario necessario.

Uscita: fixture AI/RPC/payment riconosciute senza falsi dati inventati; assistant/MCP collegano conclusioni ai flow e rispettano i limiti; nessun dato viene inviato automaticamente; spec/export validati e operazioni di sharing intenzionali.

### P5 — Release e dichiarazione di parità

Effort: 1–2 settimane, oltre ai controlli introdotti nelle fasi precedenti.

- Verificare build arm64 e definire il supporto Intel: binary mitmdump separato/universal solo se prodotto e testato. Non chiamare universal l'app mentre il motore embedded è soltanto arm64.
- Release riproducibile con dipendenze fissate, firma di tutti gli eseguibili embedded, notarizzazione, Sparkle, Homebrew e verifica di aggiornamento/rollback compatibile con lo schema dati.
- Allineare README/sito/help alle capacità testate, istruzioni di uninstall/rimozione CA, troubleshooting e issue template con diagnostica redatta.
- Eseguire la matrice di confronto su entrambi i prodotti, sulla stessa macchina e con le stesse fixture. Non valutare la maturità dal numero di test, file o release.

Uscita: installazione pulita e aggiornamento da una versione precedente verificati; nessun blocker aperto nei workflow concordati; report con risultati, hardware, versioni e limiti. FRTMProxy può dichiarare parità per i workflow verificati, senza estendere la promessa ai componenti privati di Rockxy.

## Budget prestazionale proposto

Sono obiettivi da validare e correggere dopo P0, non misure attuali né benchmark pubblici di Rockxy. Registrare hardware, macOS, versione motore e dimensioni dei payload. Distinguere app e processo mitmdump.

| Scenario | Criterio iniziale |
|---|---|
| Capture 30 minuti, 100 req/s, concorrenza 20, body 1 KB | 180.000 ID richieste attesi e confronto con terminal events; nessuna perdita silenziosa |
| Overhead con TLS già caldo, senza regole | p95 latenza aggiunta ≤20 ms rispetto al client diretto, fixture locale |
| UI durante capture | filtro/selezione/scroll p95 ≤100 ms sulla finestra live; nessun blocco >250 ms |
| RAM nello scenario small-body | app ≤300 MB, motore ≤500 MB; crescita a regime ≤10% negli ultimi 10 minuti |
| Streaming di 10 minuti e client lento | incremento memoria limitato; byte/ordine corretti, aggiornamento visibile entro 500 ms |
| Storico di 100.000 flow | prima pagina ≤500 ms, query metadata p95 ≤300 ms, caricamento body cancellabile |
| 100 cicli start/stop + crash/fallimenti parziali | nessun processo figlio orfano e nessuna modifica a proxy/processi estranei |
| Disco pieno, body/frame oltre quota | errore esplicito e dati già salvati leggibili; capture degradata dichiarata |

Non aumentare semplicemente il cap da 500 a 100.000. Tenere bounded la vista live, usare lo storico paginato e offrire accesso ai flow fuori cache.

## Riutilizzo Rockxy e licenze

FRTMProxy usa Unlicense; il sorgente Rockxy è AGPL-3.0-or-later salvo materiali terzi identificati. Copiare sorgenti Rockxy richiede rispettarne la licenza e non consente di presentare quel codice derivato come public domain. Il piano parte da implementazione autonoma sul motore già incluso, preservando il posizionamento attuale. Se si sceglie riuso diretto, definire prima il perimetro del derivato e gli obblighi di distribuzione, mantenere copyright/licenze e tracciare file, commit e modifiche. Un nuovo file o un processo separato non elimina automaticamente tali obblighi.

| Riferimento Rockxy | Cosa studiare | Implementazione minima FRTMProxy |
|---|---|---|
| `Shared/ProxyBackupRecoveryPolicy.swift`, `ProxyRecoveryJournal.swift` e relativi test | Ownership e recupero per network service | Rafforzare snapshot/restore attuali, senza replicare tutta l'infrastruttura helper |
| `Core/ProxyEngine/UpstreamResponseHandler.swift` | Riga live dagli header e completamento sullo stesso ID | Hook mitmproxy + eventi JSONL incrementali |
| `Core/Plugins/ScriptRuntime.swift` e test scripting | Hook prima del forward e gestione errori | JavaScriptCore esistente + pausa correlata nel bridge |
| `Core/UpstreamProxy/UpstreamPACResolver.swift` | API CFNetwork, route e timeout | CFNetwork nativo + routing supportato dal motore |
| `Core/Utilities/SensitiveDataRedactor.swift`, policy MCP | Confini della redazione | Estendere `AutomationRedactor`, evitare una seconda policy divergente |
| `Core/Detection/AITrafficDetector*`, inspector/assistant | Presentazione di evidenze e budget | Estendere `ProtocolInspector` e MCP; provider solo dopo preview/redazione |
| `.github/workflows/build.yml` | Build/test/lint e verifiche release | Workflow semplice per tutte le PR; non importare le condizioni branch-specific di Rockxy |

Questi sono riferimenti di studio, non una proposta di copia integrale. Non usare nome, loghi o componenti downstream privati. Conservare anche notices del motore e delle dipendenze già incluse.

## Prime PR da aprire

1. **Baseline e CI**: fixture unica, runner end-to-end, CI Python/Swift, checksum/versione motore e dipendenze fissate. Allegare risultato attuale.
2. **Lifecycle sicuro**: rimuovere kill per nome, readiness, rollback con ownership; test porta occupata e processo estraneo.
3. **TLS e localhost**: verifica upstream di default, eccezioni esplicite, target loopback catturabili e pairing escluso.
4. **Script sul flow corrente**: pausa request/response, risultato correlato, esecuzione bounded e prova dal client.
5. **Streaming live**: headers/chunk/complete/error e una sola riga, limiti e test cancel/disconnect.
6. **Body/header fedeli**: original bytes protetti, preview bounded, multivalue headers, migrazione compatibile.

Sequenza principale: P0 → P1/P2 → P3 → P4 → P5. Effort totale preliminare 10–17 settimane/persona, senza promettere una data di rilascio: il lavoro effettivo si ricalibra dopo baseline e spike scripting/PAC. Stabilità e streaming hanno precedenza sull'assistente AI.

## Cosa rimane fuori

Cloud sync, team collaboration in tempo reale, SSO/billing, marketplace, motore HTTP riscritto e astrazioni generiche. Si rivalutano solo con un requisito concreto. HTTP/3 va prima verificato nel motore/versione embedded con una fixture QUIC: catturare fallback HTTP/2 non equivale a supporto HTTP/3. I protocolli dichiarati esplorativi da Rockxy non diventano automaticamente requisiti di parità.

La roadmap è conclusa quando i workflow della matrice passano la stessa prova su entrambi i prodotti e FRTMProxy mantiene recupero sicuro, dati fedeli e limiti visibili sotto carico.


## Stato dopo la prima implementazione (1 ottobre 2026)

Implementate le prime basi P0/P1/P2 e parti di P3/P4: CI e fixture, lifecycle/ownership/TLS, script sul flow corrente, streaming SSE/NDJSON, original body cifrati, header ripetuti, export HAR, focus/noise e analisi MCP locale. Il dettaglio verificato e i limiti sono in [PROXY_VALIDATION.md](PROXY_VALIDATION.md).

Questo stato non chiude le fasi: restano benchmark, crash/stress sul sistema reale, aggiornamento del motore, retention coordinata dei body, workflow avanzati e release verificata. La parità con Rockxy non è ancora dimostrata.

### Avanzamento del 2 ottobre 2026

Schema SQLite 2 con riferimenti dei body condivisi, migrazione dei payload precedenti e coda persistente di pulizia recuperabile; quota bridge ricalcolata dopo cancellazioni. Export HAR dell'intera sessione chiusa paginato, con file precedente preservato in caso di dati mancanti/corrotti. Motore aggiornato a mitmproxy 12.2.3 tramite bundle ufficiale firmato, versione/hash archivio e runtime fissati; ripristino locale tramite `make engine`, verifica delle librerie e dei link simbolici. Resta da dimostrare la parità sull'intera matrice.


### Storico e recupero degli orfani

MCP ora espone sessioni, query paginata dello storico e lookup di flow fuori dalla cache live; riusa la redazione esistente e i payload cifrati. La scansione prosegue anche dopo pagine senza match ed espone il conteggio di payload corrotti. La pulizia degli orfani conserva file recenti/referenziati e richiede un lock esclusivo, incompatibile con la cattura attiva. Verificate 156 prove Swift, 8 Python e 9 end-to-end sul bundle compilato. Restano aperti gli altri workflow P3/P4 e i gate prestazionali/release di P5.


### Ricerca nell’inspector e isolamento UI

Aggiunta ricerca JSONPath nel sottoinsieme dichiarato e ricerca key/value con percorsi, calcolo cancellabile fuori dal thread UI e limiti espliciti. Gli header ripetuti restano distinti anche durante la ricerca. Servizio proxy e view model ora condividono l’isolamento MainActor, inclusi callback di log e terminazione. Verificati precisione degli interi, escape, null/booleani, rifiuto di sintassi non supportata, limiti e annullamento. Restano colonne personalizzate, composer avanzato, routing/PAC, setup/release e prove sotto carico.


### Composer locale e affidabilità dell’invio

Consegnate cronologia cifrata e variabili locali con sostituzione singola, ripristino delle richieste senza invio automatico, preservazione dello stato illeggibile, limiti e diagnostica. Il client esistente basato su curl ora verifica la CA del proxy, impone routing e timeout, supporta annullamento del solo processo posseduto e separa body/header conservando duplicati e righe vuote. I redirect sono visibili senza reinvio automatico. Verificate 162 prove Swift, 8 Python e 11 end-to-end. Restano replay binario/header request fedeli, diff strutturale, colonne, routing/PAC, setup/release e gate sotto carico; la parità completa non è ancora dimostrata.


### Fedeltà del replay nel composer

Eliminata la combinazione degli header request tramite dizionario, aggiunto invio binario Base64 e body anche per GET/HEAD. Il caricamento dal flow legge l’originale cifrato con limite di 2 MiB e preserva i byte compressi; originali mancanti o preview incomplete producono un errore e disabilitano il reinvio accidentale. Framing ricalcolato dai byte inviati; query/percorso passati senza globbing o normalizzazione dei segmenti. Verificati 163 test Swift e 12 end-to-end, incluse richiesta binaria, header duplicati/vuoti e URL con parentesi/segmenti `..`. Restano limiti del replay tramite collection e dei vecchi import senza originali, oltre agli altri gate della roadmap.


### Diff strutturale, header e byte

Il confronto ora distingue percorsi/tipi JSON, occorrenze ripetute degli header e blocchi dei byte originali cifrati entro limiti espliciti. Il testo mantiene diff di inserzioni/rimozioni tramite libreria standard. Calcolo singolo fuori dal thread UI, cancellabile; warning per preview troncate e import legacy. Rimossi LCS quadratico e rendering duplicato. Verificati 167 test Swift; restano gli altri workflow e gate della matrice di parità.


### Colonne header personalizzate

Aggiunte fino a otto colonne header request/response con configurazione locale persistente, riordino, ricerca nell’editor e ordinamento dei valori ripetuti. Preview limitate, assenza distinta dal valore vuoto, navigazione orizzontale e descrizioni accessibili. Verificati 169 test Swift. Restano integrazione delle preferenze nel workspace, tab persistenti e gli altri gate della roadmap.


### Preferenze dell’inspector nel workspace

Manifest esteso con colonne header e ordinamento opzionali, import legacy senza sovrascrittura, preview esplicita e applicazione anche senza risorse. Validazione prima delle mutazioni, rifiuto dell’export se la configurazione locale è corrotta, test su filesystem e view model. Verificati 170 test Swift. Restano scope/tab condivisi e gli altri gate funzionali, prestazionali e di release.


### Focus e noise control condivisi

Workspace esteso con focus e noise opzionali, preview dei filtri e applicazione senza modifica della cattura. Menu reattivo agli import, limite e diagnostica di persistenza, preservazione dei dati illeggibili e reset esplicito con copia locale. Mantenuti i nomi legacy duplicati; i vecchi workspace non sovrascrivono questi campi. Verificati 172 test Swift. Restano tab persistenti e gli altri workflow/gate della roadmap.


### Carico HTTP e budget del bridge

Lo stress ha trovato consumo oltre 500 MiB con grandi body. Aggiunto limite cache di 64 MiB, budget per i breakpoint e raccolta delle reference cycle qualificata per il runtime Python 3.14.0–3.14.4. Tre prove complete (1.256, 1.256, 3.256 richieste) conservano byte e terminal events senza duplicati; picchi RSS 335,91–353,75 MiB. Runner stdlib, report campionati e CI smoke aggiunti. Passano 10 test Python e 12 end-to-end sul bundle compilato. Il report distingue latenza assoluta da overhead e motore da app; la prova sostenuta da 180.000 richieste e gli altri gate rimangono aperti.


### Cache live Swift e breakpoint coerenti

Cache live limitata a 500 flow / 64 MiB di payload stimati e preview WebSocket a 1.000 frame / 4 MiB per flow. Eventi di registrazione precedono la potatura e continuano dopo l’evizione, con metadati mancanti dichiarati. Breakpoint aggiornati per flow senza interpretare snapshot parziali come elenco completo delle attese. Verificati 176 test Swift. Resta da misurare RSS, reattività UI e backlog del writer dell’intera app; il primo tentativo sostenuto del motore è fallito (vedere aggiornamento sotto).


### Batch del writer e retry affidabili

Scritture suddivise per count/byte, preservando ordine e record singoli grandi; errori mantenuti per i flow non ancora recuperati, senza che batch successivi riusciti mascherino un flush incompleto. Verificati 178 test Swift. Il budget globale di coda/RSS del writer resta aperto; il primo tentativo sostenuto del motore è fallito (vedere aggiornamento sotto).


### Cattura sostenuta: primo fallimento e verifica della quota

Primo tentativo 180.000 richieste: 179.600 client completati, 180.000 eventi terminali, 64,90/s, timeout finali. Gate non superato. Eliminata la scansione completa della directory dei body ogni cinque secondi in append: ora contatore delle scritture e scansione iniziale/su pressione di quota, mantenendo quota e recupero dopo cancellazioni. Verificati 11 test Python e 12 end-to-end. Report precedente conservato in `docs/benchmarks/2026-10-02-proxy-sustained-before.json`; la replica deve confermare l’effetto sotto carico. Il runner verifica anche il raggiungimento del rate target e conta tutti gli errori client. Scansione su quota/startup e budget globale del writer restano da verificare.

### 5 October: UI recovery and bounded writer

Work continues on `codex/rockxy-maturity-plan`. Composer header validation/limit/focus, variable draft cancellation and save failure, rule matcher validation/palette/scrolling, column visibility and diff overflow have been revised. XCTest captured a missing composer footer; correction and full visual acceptance are tracked in [UI_RECOVERY_LOG.md](UI_RECOVERY_LOG.md), separately from passing logic tests.

The writer now reserves count/estimated payload for pending, in-flight and retry snapshots. Saturation stops capture visibly, preserves accepted retry data and marks the session incomplete using SQLite schema 3. Native tests cover byte/count limits, failed writes and migration. No whole-app RSS or UI latency claim is made. The 180,000-request engine replication is running; the roadmap and parity gates remain open until their required evidence is complete.

### Verified recovery increment

186 native, 11 Python and 13 real-proxy integration tests pass. Composer workflows pass across dark/light S/M/L; matcher Save/reopen passes in both themes. A 30-minute engine replication achieves 180,000 terminal IDs without errors or duplicates at 100 req/s. The [recovery register](UI_RECOVERY_LOG.md) records remaining visual coverage and explicitly separates the engine measurement from whole-app performance. P3/P4/P5 exit criteria and comparative Rockxy parity are still open.

### Captured HAR import

Implemented review/confirmation and atomic import into closed captured sessions, separate from mock Collections. Binary originals are encrypted and referenced; duplicate headers and timing are retained. Native tests pass in the first 190-test run. Final timestamp refinements and the complete GUI import sequence still require acceptance; the roadmap remains active.
