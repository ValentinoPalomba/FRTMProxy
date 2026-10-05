# FRTMProxy — spec di correzione e consolidamento

Data: 4 ottobre 2026. Stato: proposta operativa, da usare come criterio di accettazione.

## Obiettivo

Rendere affidabili e coerenti con FRTMProxy le funzionalità aggiunte durante il lavoro di avvicinamento a Rockxy. La priorità è completare i workflow quotidiani e correggere le regressioni visive. Le nuove capacità previste dalla roadmap riprendono dopo questa verifica.

Il design di riferimento è quello dell’app prima delle modifiche: palette, densità, gerarchia, componenti e comportamento delle schermate esistenti. Rockxy resta un riferimento funzionale; non detta il linguaggio visivo di FRTMProxy.

## Stato e problemi da accertare

- Segnalazione utente: numerosi problemi grafici, “Add Header” non funzionante e controlli incoerenti con il design system.
- Nel codice sono presenti nuovi campi, pulsanti e sheet con stili standard, diversi da quelli dell’app. Alcuni contenuti non hanno un’altezza limitata e possono alterare il layout.
- Sono state tentate correzioni a composer, variabili, filtri, colonne, ricerca JSON, diff ed editor dei matcher. Non costituiscono ancora una soluzione accettata.
- La suite Xcode più recente passa. Questo dimostra compilazione e verifiche automatiche della logica, non il corretto funzionamento visivo dei controlli.
- La riproduzione tramite Computer Use è stata impedita dai permessi del Mac. Rimane da osservare il difetto “Add Header” nella schermata esatta; non attribuirgli una causa senza evidenza.

## Perimetro

Rivedere tutte le superfici modificate: inspector e lista traffico, composer e cronologia/variabili, regole e matcher, ricerca di body/header, confronto dei flow, sessioni/export e workspace.

Conservare motore mitmproxy, bridge, modelli, persistenza e componenti già presenti. Cambiare il backend quando una riproduzione dimostra che il difetto dipende da esso. Evitare una riscrittura generale o nuove dipendenze.

## Requisiti visivi comuni

| Elemento | Regola |
|---|---|
| Colori | Palette del tema attivo passata dalla schermata proprietaria; nessuna palette parallela o colore d’errore fisso |
| Font e dimensioni | `DesignSystem.Fonts`, `Spacing`, `Radius` e `Metrics`; rispetto della scala S/M/L |
| Azioni | `ControlButton` per i pulsanti; azioni principali, secondarie e distruttive distinguibili come nel resto dell’app |
| Campi e ricerca | `ProxyTextFieldStyle` e `SearchField`; editor coerenti con quelli già presenti |
| Superfici | Componenti card esistenti e divisori della palette; niente contenitori decorativi aggiunti senza funzione |
| Stati | `StateView` dove adatto per vuoto, caricamento ed errore; errori leggibili senza comprimere le azioni |
| Layout | Titolo e azioni restano accessibili; liste lunghe scorrono dentro il pannello, senza far crescere indefinitamente la sheet |
| Accessibilità | Etichette per azioni e campi, ordine di focus sensato, tastiera, contrasto e Reduce Motion |

Un controllo standard macOS è ammesso quando è coerente con lo stesso controllo già usato nell’app. Non sostituire ogni controllo con un componente nuovo. Non modificare globalmente il design system per adattarlo a una singola feature.

## Workflow da correggere

### 1. Aggiunta e modifica degli header — priorità P0

Riprodurre separatamente “Add Header” nel composer e nell’editor dei matcher delle regole.

**Composer:** il click crea una sola riga con identità stabile, la rende visibile e porta il focus al nome. Nome e valore restano modificabili; aggiunta/rimozione di altre righe non modifica quella sbagliata. Aggiungere una riga oltre il bordo richiede scorrimento alla nuova riga. Il pulsante rimane raggiungibile.

L’invio conserva ordine e duplicati degli header applicativi. Una riga completamente vuota è un placeholder e non viene inviata; un valore senza nome produce un errore comprensibile. Un header con nome valido e valore vuoto rimane valido. Applicare il limite già previsto di 128 header con feedback esplicito. Il trasporto continua a calcolare il framing HTTP.

**Regole:** il click aggiunge un matcher visibile e modificabile. Nome, pattern, modalità e case sensitivity persistono dopo salvataggio e riapertura. Una riga parzialmente compilata non può scomparire silenziosamente al salvataggio. Rimozione e riordino non devono agire su un altro matcher.

**Accettazione:** percorso completo click → compilazione → salvataggio/invio → risultato osservato. Una fixture locale verifica gli header ricevuti; una regola verifica il match e il mancato match. Il solo test del metodo che aggiunge un elemento all’array non basta.

### 2. Composer e variabili — P0

Ripristinare gerarchia e componenti del composer esistente. URL, metodo, tab, header e body devono rimanere utilizzabili alle dimensioni supportate. Send, Cancel e Close hanno comportamenti distinti e non vengono coperti dal contenuto.

La sheet delle variabili ha area scorrevole e azioni sempre visibili. L’aggiunta rende individuabile la nuova riga. Gli errori della cronologia/persistenza non devono espandere la barra del titolo. Caricare una richiesta dalla cronologia ripristina i dati senza inviarli. Cambiare layout o tab non perde la bozza.

### 3. Inspector, filtri e colonne — P0

Verificare larghezze, allineamento di intestazioni/celle, selezione, scroll orizzontale e verticale. Le nuove azioni devono integrarsi nei controlli dell’inspector, senza introdurre barre ridondanti o sottrarre inutilmente spazio al traffico.

L’editor delle colonne usa campi e azioni dell’app. Add mostra la nuova colonna; Save la applica; Cancel conserva la configurazione precedente. Header assente, valore vuoto e duplicati restano distinguibili.

Focus e noise control devono spiegare lo stato attivo con un’indicazione compatta. Nascondere traffico non interrompe la cattura. Le sheet usano bozze: Cancel non applica modifiche.

### 4. Ricerca e confronto — P1

Ricerca JSON/header integrata nella gerarchia del pannello. Risultati limitati a un’area scorrevole: espandere la ricerca non rende inaccessibile il body o il tab selezionato. Cambio flow/query annulla il lavoro precedente e non mostra risultati obsoleti.

Il diff mantiene identificazione chiara di A e B, selettori leggibili, tabella con overflow gestito e stati di caricamento/errore. Testo lungo, byte e molti cambiamenti non devono bloccare il layout. Preservare avvisi relativi a preview troncate e originali mancanti.

### 5. Sessioni, export e workspace — P1

Uniformare esclusivamente i controlli introdotti e verificare i workflow completi: apertura storico, paginazione, selezione, export redatto/completo, import con preview e annullamento. Le azioni indisponibili devono avere una ragione comprensibile. Conservare dati esistenti, redazione, compatibilità e gestione della corruzione.

## Metodo di lavoro

1. **Inventario delle regressioni.** Confrontare le schermate modificate con la baseline. Per ciascun difetto annotare schermata, passi, risultato atteso/osservato e configurazione visiva. Distinguere confermato, ipotesi, corretto e verificato.
2. **Correzione di un workflow alla volta.** Prima header e composer, poi inspector/filtri, infine ricerca/diff/storico. Cercare la causa nel percorso stato → binding → azione → layout → persistenza/trasporto. Riutilizzare i componenti esistenti.
3. **Verifica dell’incremento.** Build, verifiche mirate della logica e prova del workflow nell’interfaccia. Conservare screenshot prima/dopo con fixture prive di dati personali. I test logici non sostituiscono l’ispezione visiva.
4. **Revisione concreta.** Preparare una build identificabile e una lista breve dei difetti risolti con evidenze. Presentare le schermate corrette per la verifica dell’utente. Non dichiarare risolto ciò che non è stato riprodotto e controllato.

## Matrice minima di accettazione

| Scenario | Esito richiesto |
|---|---|
| Tema chiaro/scuro e tema personalizzato presente nell’app | Tutti i nuovi controlli usano la palette corretta |
| Scala S, M, L | Nessun testo/controllo tagliato; densità coerente |
| Dimensioni minime supportate e finestra ampia | Nessuna sovrapposizione; azioni principali raggiungibili |
| Nessun dato, un elemento, lista lunga | Stato vuoto corretto e scorrimento senza crescita della sheet |
| Header/URL/errore lunghi | Overflow gestito e azioni leggibili |
| Tastiera | Tab raggiunge i campi; Enter/Escape coerenti con salvataggio/annullamento; focus visibile |
| Aggiunta, modifica, rimozione e riapertura | Una sola modifica per azione e stato conservato correttamente |
| Traffico aggiornato durante l’interazione | Selezione e bozza non vengono resettate |
| Fallimento di salvataggio o invio | Errore visibile, dati conservati e possibilità di correggere/riprovare |

Prima della consegna non devono restare difetti P0/P1 noti nel perimetro. Le evidenze visive devono coprire tutte le schermate modificate almeno in chiaro/scuro; layout più complessi vanno verificati anche a tutte le scale e alle dimensioni minime. Se l’accesso alla UI manca, la verifica rimane esplicitamente aperta.

## Ripresa della maturazione tecnica

Dopo l’accettazione dei workflow, riprendere la [roadmap Rockxy](ROCKXY_MATURITY_PLAN.md) dando precedenza a:

- budget globale del writer: saturazione esplicita, conservazione dei dati accettati e sessioni incomplete riconoscibili;
- verifica della replica sostenuta e misurazione di memoria/reattività dell’intera app, non del solo motore;
- robustezza di crash/ripristino, originali e retention sotto errori disco;
- capacità mancanti e distribuzione verificata, in incrementi completi e misurabili.

La parità con Rockxy richiede la stessa matrice di workflow su entrambi i prodotti. Il numero di feature, una build riuscita o una suite verde non la dimostrano.

## Deliverable

Spec e registro delle regressioni aggiornati, correzioni raggruppate per workflow, controlli riusati coerentemente, prove funzionali e visive, build riproducibile e riepilogo onesto dei limiti residui. Nessuna nuova funzionalità viene presentata come completa prima di questi passaggi.
