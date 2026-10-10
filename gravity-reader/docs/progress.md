# Implementation ledger — plan: docs/plan.md
Ruling: Follow explicit user autonomy instead of repeated skill approval gates; scope confirmed as iPhone GRAVITY OCR/TTS.
Ruling: Native Mac app needs local Apple CLT to build; Linux cannot produce or validate a signed Mac binary. Deliver one launcher with detection and precise first-run instructions.
Ruling: ROOM means selected output route, not automatic iPhone microphone injection. Hardware/app transmission remains real-device validation.
Task 1: complete — compiled Swift6.0.3 in Swift5 mode on Linux; test harness went 12/21 RED (stub) →21/21 GREEN. Native UI/runtime APIs are not part of this PASS.
Task 2: implemented — native adapters/UI parse PASS; runtime and Mac typecheck explicitly pending.
Final review: fresh agent /root/gravity_review found four important issues; all patched. Comment prefix regression RED 24/26→GREEN; generation gate RED25/29→GREEN; dense-row regression RED29/30→GREEN. Mac-only buffer/engine lifecycle fixes inspection-reviewed, runtime pending.
Ruling: Apple explicitly disallows iPhone mic in iPhone Mirroring. Present it as PRIVATE-only; ROOM needs another display/input route, real-device pending.
Ruling: Local first build automatically runs core and Mac OCR self-check before launching, minimizing additional manual test steps.
Task 3: source launcher/package implemented, shell parse and Linux guards PASS. Mac actual build/runtime deferred solely for absent hardware/SDK.
Final checks: fresh 30/30 core tests and 24-frame replay PASS; all Mac Swift parse PASS; shell parse PASS. No native Mac typecheck/run claim.
