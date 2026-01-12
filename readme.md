# FRTMProxy

FRTMProxy è un'app macOS costruita in SwiftUI per sniffare, ispezionare e debuggare il traffico HTTP/S in tempo reale con un occhio di riguardo all'esperienza d'uso. All'interno trovi un proxy MITM pronto all'uso, un inspector veloce e un editor per mappare risposte locali in pochi clic.

![Tema scuro](media/Screenshot%202025-11-19%20alle%2009.15.07.png)
![Tema chiaro](media/Screenshot%202025-11-19%20alle%2009.15.16.png)

> **Nota**: l'applicazione non è pensata per l'esecuzione in produzione, ma come strumento interno per il debugging delle API.

---

## Highlights

- **Inspector dual-pane** – Richieste e risposte affiancate, copiate in un colpo con shortcut dedicate (URL, cURL, body, map local).
- **Flow explorer da power user** – Tabella custom tipo spreadsheet con filtri testuali, chip rapidi per mapped/error e badge metodo/status colorati.
- **Domain filtering (opzionale)** – Se attivo, il proxy intercetta solo gli host pinnati (e lascia il resto in tunnel) per ridurre interferenze con altre app.
- **Editor CodeMirror** – Visualizzazione Raw / Pretty / Hex con syntax highlight, line numbers e read-only in sync con il flow selezionato.
- **Map Local Studio** – Editor request/response con key-value field per header e query, stato di sincronizzazione e pulsanti Save/Close.
- **Proxy service integrato** – Backend Mitmproxy orchestrato via `MitmproxyService` e `ProxyViewModel`, con binding Combine per tutti gli stati UI.

---

## Architettura in breve

| Layer | Descrizione |
| --- | --- |
| `App/` | Entry point (`FRTMProxyApp`, `AppRootView`) e setup `AppDelegate`. |
| `ViewModels/` | ObservableObject che orchestrano proxy, inspector e map editor (`ProxyViewModel`, `MapEditorViewModel`). |
| `Inspector/` | Tutte le view SwiftUI dell'inspector: lista flow, pannello split request/response, map editor, header bar, ecc. |
| `Components/` | Building block riutilizzabili (FlowTableView, CodeEditorView basato su CodeMirror, ControlButton, SurfaceCard…). |
| `Models/` | Modelli condivisi (`MitmFlow`, `MapRule`) + extension helper. |
| `Services/` | `MitmproxyService` + `ProxyServiceProtocol` per comunicare con il backend Python/mitmproxy. |
| `Utils/` | Helper vari (formatter, clipboard, networking config). |

Ogni macro sezione è pensata per essere facilmente sostituibile o testabile e segue naming chiaro per evitare spaghetti-code.

---

## Requisiti

- macOS 14.0+
- Xcode 15.1+
- Swift 5.9
- Python 3 + mitmproxy (per il backend CLI, già gestito da `MitmproxyService`)

---

## Getting Started

```bash
git clone https://github.com/<org>/FRTMProxy.git
cd FRTMProxy
open FRTMProxy.xcodeproj
```

1. Seleziona lo schema **FRTMProxy** e builda (`⌘B`).
2. Installare mitmproxy sul Mac: `brew install mitmproxy`.
3. Apri le preferenze di rete di macOS e imposta il proxy HTTP/Su HTTPS verso `127.0.0.1` porta `8080`.
4. Avvia FRTMProxy e premi **Start** per far partire il proxy interno.
5. Avvia il simulatore iOS (o un device reale collegato allo stesso Wi-Fi), **senza VPN attiva**, e navighi su `mitm.it`.
6. Scarica e installa il certificato per iOS, poi autorizzalo da Impostazioni > Generali > Info > Impostazioni certificati.
7. Torna al simulatore e inizia a navigare: vedrai apparire i flow in tempo reale dentro FRTMProxy.

### Device reale via QR (senza configurare manualmente il proxy Wi‑Fi)

1. Avvia FRTMProxy e premi **Start**.
2. Apri **Manage → Device**.
3. Scansiona il QR dal device (stessa rete Wi‑Fi, senza VPN) e installa il profilo scaricato (il proxy è configurato automaticamente per la rete Wi‑Fi corrente).
4. Abilita la fiducia della CA: Impostazioni → Generali → Info → Impostazioni certificati.
5. Se l’SSID non viene rilevato su macOS 15.3+, abilita i permessi di localizzazione per FRTMProxy (Impostazioni di Sistema → Privacy e Sicurezza → Servizi di Localizzazione).
   - Opzionale (macOS 15.3+): abilita anche l’entitlement `com.apple.developer.networking.wifi-info` (“Access Wi‑Fi Information”). Nel progetto trovi `FRTMProxy/FRTMProxy.wifi-info.entitlements` da usare al posto di `FRTMProxy/FRTMProxy.entitlements` quando firmi con un certificato di sviluppo.

### iOS Simulator (installazione guidata CA)

Apri **Manage → Device** e usa la sezione **iOS Simulator** per:
- verificare i simulator “booted”
- installare la CA di mitmproxy via `simctl`

---

## Comandi rapidi nell'interfaccia

- `Clear`: resetta la lista dei flow.
- `Rules`: apre il rules manager per abilitare/disabilitare map local salvate.
- `Start / Stop`: controllano il processo mitmproxy sottostante.
- Ricerca: supporta keyword e filtri `host:`, `method:`, `status:` (es. `2xx`, `>=400`), `type:` (content-type, es. `json`) e `device:` (client IP). Prefisso `-` per escludere (es. `-type:image`).
- Tabella flow: clic su una riga apre il pannello inspector; doppio clic copia l'URL.
- Inspector: pulsanti `URL`, `cURL`, `Body`, `Map Local` accedono ai principali shortcut.
- Map Editor: `Save` salva la risposta fittizia, `Close` chiude il pannello mantenendo lo stato locale.

---

## Tecnologie principali

- **SwiftUI** per tutte le view (macOS target).
- **Combine** per il binding reattivo tra service e view model.
- **CodeMirror-Swift** per l'editor JSON a colori.
- **mitmproxy** (richiamato via Python bridge) per il proxying del traffico.

---

## Roadmap / idee future

- Supporto WebSocket & gRPC
- Salvataggio progetti + esportazione flow
- Theme editor e layout multi-colonna
- Shortcut avanzate (⌘C per copia rapida di raw/pretty)

---

## Contribuire

1. Forka il repo e crea un branch `feature/nome-feature`.
2. Assicurati che l'UI resti coerente con il design system esistente.
3. Apri una pull request descrivendo il bug/feature e allegando screenshot/gif.

Per qualsiasi dubbio usa le issue o scrivi direttamente al team di rete.

---

Buon debugging! 🚀
