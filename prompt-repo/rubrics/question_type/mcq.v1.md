# MCQ Question Type Rubric

**Structure**
- `question` — complete sentence ending in `?` or a clear incomplete statement.
- `options` — object with keys `A`, `B`, `C`, `D` (4 options unless `curriculum_constraints.options_count_for_mcq` says otherwise).
- `answer` — exactly one of the option keys: `"A"`, `"B"`, `"C"`, or `"D"`.
- `explanation` — 1-2 sentences explaining WHY the answer is correct AND why the most attractive distractor is wrong.

**Forbidden patterns**
- "All of the above"
- "None of the above"
- "Both A and C" / "A and B only"
- Any option that is a meta-statement about other options.

**Distractor quality**
- All four options grammatically parallel.
- Lengths within ~30% of each other.
- Each distractor traceable to a specific misconception or computational error.

**Common rejection reasons**
- Two options are arguably correct.
- Answer key disagrees with the chapter knowledge.
- Stem leaks the answer through grammar (e.g. singular/plural cues).
- Numerical answer present without units when the chapter teaches with units.
