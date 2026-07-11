# Patch minimality benchmark

Two semantic edits touch exactly two lines in one TypeScript file. Generated and
explicitly protected edits are blocked by default. The plan must scope formatter
work to lines 1–2, report zero protected writes, and offer serial and
language-batched lower-conflict schedules.
