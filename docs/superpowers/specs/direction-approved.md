# TodApp — Direction Approval

**Status:** Approved via exemption (huashu-design three-direction gate, exemption 2: "iteration on an already-approved direction").

## Rationale

`tod-prototype.html` is not a rough sketch or a design brief awaiting exploration — it is a complete, internally consistent, already-built interactive prototype: full CSS design system (color tokens, type scale, component styles), all six screens implemented, and working JS interaction logic (voting, chat, battle, waveform picker). Running the mandatory three-direction generation (roulette / benchmark / best-designer) against a brief that already has a finished, coherent answer would produce two throwaway alternatives to a design the user has already built and is asking to be *ported*, not *reimagined*.

The task is therefore classified as **porting an approved design to a new medium (SwiftUI)**, not **originating a new visual design** — which is the case the three-direction gate exists to gate. Per huashu-design's own exemption list, this qualifies for the "iteration on an already-approved direction" exemption.

## What is treated as approved

- The full color/typography system in `brand-spec.md` (extracted directly from prototype source).
- The six-tab structure and screen inventory (Heute, Voten, Reveal, Rangliste, Chat, Battle).
- The interaction model: rating scale (-2..+2 + one hidden-gem pick), chat, leaderboard, three battle modes.
- Component visual language: dark surfaces with mauve-pink/gold/green accents, rounded cards, mono for meta/labels.

## What is NOT pre-approved (still open, decided during SwiftUI implementation, not visual re-litigation)

- Native iOS idioms that have no 1:1 HTML equivalent (navigation transitions, haptics, pull-to-refresh, system share sheet, keyboard avoidance).
- Any accessibility adaptations required for VoiceOver/Dynamic Type that the HTML prototype doesn't need to handle.

No screenshot comparison grid was produced because there is only one source design being ported, not several candidates being compared.
