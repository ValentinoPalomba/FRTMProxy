# Product

## Register

product

## Users

Sviluppatori mobile (iOS/Android), web e backend che devono ispezionare, mockare, registrare/riprodurre
e modellare traffico HTTP/S in tempo reale durante lo sviluppo e il debug. Il contesto d'uso è una
sessione di lavoro focalizzata: l'utente sta debuggando un bug di rete, verificando un payload, simulando
una risposta d'errore o condizioni di rete degradate. È un utente esperto, fluente in strumenti come
Proxyman, Charles, Wireshark — e in tool moderni come Linear, Raycast, Figma. Lavora spesso a schermo
pieno, per periodi lunghi, tipicamente in ambiente scuro (IDE dark).

## Product Purpose

FRTMProxy è un controller nativo macOS per un `mitmdump` embedded: intercetta e manipola traffico HTTP/S
senza che l'utente tocchi la riga di comando. Fa inspection, Map Local (mock), breakpoint, record/replay
(Collections + HAR + Git), compose/replay di richieste, scripting JS e traffic shaping.
Successo = l'utente completa il suo task di debug **più velocemente e con più fiducia** che con la CLI o
con i competitor, e lo strumento "sparisce" dentro il task.

## Brand Personality

Preciso, sobrio, veloce, fidato. Tre parole: **strumento-di-precisione**. La personalità è quella dei
migliori tool per sviluppatori (Linear, Raycast): densità informativa senza rumore, gerarchia netta,
feedback immediato, zero decorazione gratuita. Il colore parla solo quando comunica stato o azione.
Dark-first. La UI trasmette competenza e controllo, non "friendliness" consumer.

## Anti-references

- **Look consumer/friendly**: font arrotondati, colori vivaci decorativi, emoji, card morbide ovunque.
  (La UI attuale usa `.rounded` e un accent teal acceso: da sobrificare.)
- **AI slop**: spacing casuale, `cornerRadius` incoerenti, empty state generici "nothing here",
  componenti simili-ma-diversi (5 reimplementazioni di tab/chip), stringhe miste IT/EN.
- **Enterprise pesante**: Charles/Wireshark-style con toolbar sovraccariche e dialog modali per tutto.
- **Motion decorativo**: animazioni d'ingresso orchestrate, bounce/elastic, transizioni che fanno aspettare.

## Design Principles

1. **Il tool sparisce nel task.** Ogni elemento serve un'azione del workflow di debug; niente decorazione.
2. **Earned familiarity.** Affordance standard macOS/pro-tool; nessuna reinvenzione di controlli o modali.
   Un utente di Proxyman/Linear si fida al primo sguardo.
3. **Coerenza prima di tutto.** Un solo vocabolario di spacing, radius, colore, motion, componenti — usato
   ovunque. La stessa "cosa" ha sempre lo stesso aspetto.
4. **Il colore è semantica.** Accent solo per azione primaria, selezione, stato. Neutri per tutto il resto.
5. **Motion = stato.** L'animazione comunica un cambiamento (feedback, selezione, arrivo di un flow), mai
   spettacolo. 120–240 ms, ease-out, sempre con alternativa reduce-motion.
6. **Densità utile.** Alta densità informativa (liste flow lunghe, pannelli densi) senza affollamento:
   la gerarchia regge la densità.

## Accessibility & Inclusion

Target: **solido e pragmatico** (non full WCAG AAA). Contrasto **WCAG AA** (≥4.5:1 body, ≥3:1 large) su
tutti i temi principali, verificato. `accessibilityLabel`/traits su elementi non testuali chiave (righe
flow, badge metodo/stato, chip, pulsanti icona-only). Rispetto di `prefers-reduced-motion`
(`accessibilityReduceMotion`). La scala tipografica resta la scala custom S/M/L esistente (no Dynamic Type
completo in questa fase). Palette verificata anche per daltonismo: lo stato non è mai affidato al solo colore
(sempre accompagnato da testo/icona/badge).
