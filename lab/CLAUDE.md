# Lab house rules

These rules bind every agent that runs in `lab/` (analyst, spec-writer, verifier).

1. The target must be software the user owns or is authorized to examine. If ownership or authorization is unclear, stop and ask. A license can forbid reverse engineering even where the law does not. Do not start from a guess, a screenshot of someone else's product, or a file the user cannot explain the right to examine.

2. Tag every claim as one of three kinds, and keep the evidence on the same line:
   - observation: directly seen, with the address or call site
   - inference: reasoned from observations, with the observations it rests on
   - unknown: needed for the feature and not yet proven

   An inference never becomes an observation. An unknown never becomes a requirement. Under confidence 6, look again at already resolved neighbors; still under 6, mark the function unknown and move on.

3. Do not commit these five mistakes:
   - running REA and the Rebuilder under the same OS account
   - skipping the leak grep because the spec "looks clean"
   - giving the Rebuilder evidence.md for context
   - fixing the rebuild by hand after the Verifier rejects it
   - pointing the Analyst at a whole app instead of one feature

4. One feature, one sentence, one pass. The analyst writes `analysis/evidence.md` only. The spec writer writes `handoff/SPEC.md` only, behavior and public interfaces, with every unknown copied under "Open questions". The verifier writes `report.md` only and ends it with `RESULT wrong=<n> crash=<n>`. Nobody edits another role's output to force a pass.

5. The only file that crosses into `clean/` is `handoff/SPEC.md`, after the leak grep. Addresses, offsets, decompiled names, assembly, and original source stay in `lab/`. The Rebuilder does not get `evidence.md`, `doctor.json`, or the binary.

6. Run the original program in a VM or sandbox. The verifier executes it.

7. Stay inside behavior recovery for that one owned feature. Do not write exploit steps, credential capture, or instructions for attacking a system the user does not own.
