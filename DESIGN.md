# Design

Sistema visivo target di FRTMProxy: **Linear/Raycast refined, dark-first**. Documenta il linguaggio verso
cui il polish sta convergendo. I 24 temi esistenti restano come opzioni utente; questo documento definisce
il **default (System)** e le regole trasversali che ogni tema deve rispettare.

## Theme

Dark-first. Il tema di default (`System`) usa una palette **neutra fredda** con un solo accent sobrio.
Chiaro/scuro entrambi supportati e verificati; il dark è il tema di riferimento del design. Strategia
colore: **Restrained** (neutri + 1 accent ≤10% della superficie).

## Color palette

Valori sRGB hex. Vocabolario semantico (12 ruoli, già in `DesignSystem.ColorPalette`).

### Dark (default / hero)
| Ruolo | Hex | Uso |
|---|---|---|
| background | `0B0D10` | sfondo finestra (near-black neutro freddo) |
| surface | `14171C` | pannelli, righe |
| surfaceElevated | `1B1F26` | popover, card, header sticky |
| border | `272C34` | bordi 1px, separatori |
| textPrimary | `E7EAEF` | testo principale (≈13:1 su bg) |
| textSecondary | `9AA3AF` | testo muted (≥4.5:1 su bg e surface) |
| accent | `5E6AD2` | indaco sobrio (Linear) — azione primaria, selezione, focus; testo bianco AA 4.7:1 |
| accentSecondary | `4CC2B4` | teal desaturato — accenti secondari/link |
| success | `3FB950` | 2xx / stato ok |
| warning | `D29922` | rallentamenti / warning |
| danger | `F85149` | 4xx-5xx / errori |
| destructive | `F85149` | azioni distruttive |

### Light (secondaria)
Off-white neutro (`background F7F8FA`, `surface FFFFFF`, `surfaceElevated F1F2F5`, `border E4E6EB`,
`textPrimary 15181D`, `textSecondary 5B626C`), stesso accent indaco `5A63D8` (leggermente più scuro per
contrasto su chiaro).

### HTTP method colors
Tinte **sobrie e desaturate** (non i `.green/.blue/.orange/...` di sistema saturi), leggibili come badge:
GET `3FB950` · POST `5E6AD2` · PUT `D29922` · PATCH `A371F7` · DELETE `F85149` · altro → textSecondary.
Lo stato/metodo non è mai solo colore: sempre col testo del metodo.

## Typography

- **Una famiglia neutra**: SF Pro (system, `design: .default` — **niente `.rounded`**). SF Mono
  (`.monospaced`) per URL, header, body, dati e tabelle.
- Scala **fissa** (moltiplicata dalla scala UI S/M/L esistente, non fluida). Ratio ~1.2.
  Ruoli: `title` 17 semibold · `heading` 15 semibold · `body` 13 regular · `label` 12 medium ·
  `caption` 11 regular · `mono` 12 regular.
- Pesi: regular / medium / semibold. Niente bold pesante nell'UI.

## Spacing & Radius

Scala token (× fattore scala UI), fine il regime dei magic number:
- **Spacing**: `xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`.
- **Radius**: `sm 6 · md 8 · lg 12 · pill 999`. Contenuti (Linear/Raycast usano 6–8–12), niente 18–20.

## Components

Ogni componente interattivo ha stati espliciti: **default · hover · press · focus · disabled · selected**.
- Micro-interactions sobrie: press `scale 0.98` + leggero dim; hover = tint di background (`accent`/white a
  bassa opacità); focus = ring `accent` 1.5px. Tutte via **Motion tokens** e disattivate con reduce-motion.
- Vocabolario unico: un `PrimaryButtonStyle`/`SubtleButtonStyle`, un `Chip`, un `SegmentedTabs`, una
  `Card` theme-safe. Niente reimplementazioni ad hoc (dedup di tab/chip e `KeyEventMonitorView`).
- Empty/loading/error **uniformi** (un componente `StateView` invece di 5 varianti); loading = skeleton dove
  ha senso, non spinner al centro.
- Feedback unificato: **toast** in-app per successi/errori (es. avvio proxy fallito), non solo log.

## Motion

- Durate: `fast 120ms · base 180ms · slow 240ms`. Curva **ease-out** (nessun bounce/elastic).
- Motion solo per: cambio stato, feedback azione, selezione, arrivo/rimozione righe flow, comparsa toast.
- Nessuna sequenza orchestrata al load. Stagger ammesso solo su liste brevi quando informativo.
- `accessibilityReduceMotion` → crossfade/istantaneo.

## Layout

- Responsività **strutturale** (VSplitView lista/dettaglio, collasso pannelli, colonne responsive),
  non tipografia fluida.
- Densità alta nelle liste/pannelli; gerarchia via peso/colore/spacing, non via card annidate.
- z-index semantico: contenuto → sticky header → popover → sheet → toast.
