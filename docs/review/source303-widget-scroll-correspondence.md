# Source303 widget scroll correspondence

Prepared 2026-11-01 19:43 UTC from `e45d93dbd15f7a3b01eda66eb17ed420b751788f`, tree `f975ed96067ee4e55157993f5b937d86f4d9dc46` after preserving [Source302's original failures](source302-original-widget-failures.md).

Only the existing synthetic Node/About test file changes. The Node case reacquires its current ScrollPosition for each assertion after command pumps instead of retaining a position object across theme/frame updates. The About case performs the original CLI's bounded reveal phase after its million-pixel wheel event and before its unchanged licences-end wait/assert/input-refusal checks: observe first, then 250-pixel physical wheel steps, with the same inclusive zero-to-twenty loop. A lazy list or outer viewport may need further physical wheel events; this is a test/script correspondence correction, not a proven cause of the prior failure.

Reversing those exact edits reproduces the entire previous test file. Both themes, the same mounted Node owner, 121 complete registry packages, genuine discovery field, every original assertion, forty-key clip counterexamples, production agent, scripts, SDK/input barriers, selection, worker and command limits remain. No controller is jumped directly and no clipping or matching guard is relaxed. Fresh zero-finding analysis and all 790 ordinary cases remain required before full Windows/independent inspection and all four native/reader/image families. Those are requirements, not outcomes.

Acceptance stays 72/80 rows, nineteen preparations, 26 literal outputs, 68 missing and zero accepted matches. All failed originals remain unretried. Native101/103 remain UNKNOWN; Native104 is not admitted. The existing PR stays Draft with English text and edgepillar attribution.
