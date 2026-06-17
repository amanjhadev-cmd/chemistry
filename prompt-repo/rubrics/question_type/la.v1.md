# LA (Long Answer) Question Type Rubric

**Structure**
- `question` — open-ended prompt requiring sustained answer.
- `options` — null (LA has no options).
- `answer` — full model answer, typically 100-250 words.
- `explanation` — marking scheme breakdown (e.g. "1 mark for definition, 2 for derivation, 2 for example").

**Curriculum defaults**
- 5 marks per item unless `curriculum_constraints.marks` overrides.
- Answer length 100-250 words unless overridden.
- Expected to integrate at least 2 sub-concepts from the chapter.

**Forbidden patterns**
- Yes/no questions framed as long answers.
- "Explain everything about X" — too open. Must specify scope.
- Questions answerable in one sentence.

**Quality bar**
- The answer must explicitly cite the section / law / formula it draws from.
- The model answer must be syllabus-consistent (no advanced concepts that NCERT introduces later).
- Mark distribution in `explanation` must sum to `curriculum_constraints.marks.max`.
