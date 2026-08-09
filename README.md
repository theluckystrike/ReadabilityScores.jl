# ReadabilityScores.jl

Flesch reading ease, Flesch–Kincaid grade level and the Gunning fog index for
English text, computed from a **single tokenisation pass**. No dependencies
outside the standard library.

```julia
julia> using ReadabilityScores

julia> readability("The endpoint returns a JSON object containing the authentication token.")
(words = 10, sentences = 1, syllables = 20, complex_words = 2, words_per_sentence = 10.0,
 syllables_per_word = 2.0, flesch_reading_ease = 27.485000000000014,
 flesch_kincaid_grade = 11.91, gunning_fog = 12.0)
```

Individual formulas take either a string or a pre-computed `TextCounts`:

```julia
julia> c = textcounts("The cat sat on the mat. The dog did not.");

julia> (c.words, c.sentences, c.syllables, c.complex_words)
(10, 2, 10, 0)

julia> flesch_reading_ease(c), flesch_kincaid_grade(c), gunning_fog(c)
(117.16000000000003, -1.8399999999999999, 2.0)
```

## Why one pass, and why the counts are public

All three formulas are built from the same two ratios — words per sentence and
syllables per word — plus, for fog, the share of words with three or more
syllables. Computing them separately is three walks over the text and three
chances for the tokenisers to disagree about what a sentence is. `textcounts`
walks once and every score is derived from that one `TextCounts`, so the scores
can never be describing different segmentations of the same input.

The counts are exported rather than hidden because a score without its counts
is not interpretable, which the next section is about.

## The scores disagree with each other, and that is real

This is the part most readability libraries do not say out loud. Reading ease
and grade level can rank the *same pair of texts in opposite directions*. Two
excerpts, both scored with this package:

| excerpt | words | sentences | syllables | words/sent | syll/word | reading ease | Flesch–Kincaid | Gunning fog |
|---|---|---|---|---|---|---|---|---|
| contract clause | 28 | 1 | 45 | 28.00 | 1.607 | **42.45** | **14.29** | 16.91 |
| API reference   | 20 | 2 | 40 | 10.00 | 2.000 | **27.49** | **11.91** | 12.00 |

Reading ease says the contract clause is the **easier** of the two (42.45 vs
27.49). Flesch–Kincaid says the same contract clause is the **harder** of the
two (grade 14.29 vs 11.91). Both are computed correctly, from the same counts,
in the same pass.

The cause is visible in the coefficients. Reading ease weights syllables per
word at 84.6 against 1.015 for words per sentence — a ratio of about 83:1. The
grade formula weights them 11.8 against 0.39 — about 30:1. Reading ease is
therefore roughly 2.75x more lopsided towards word length. The contract clause
is one 28-word sentence of short words; the API reference is two short
sentences of long words. Reading ease barely notices the 28-word sentence and
punishes the long words; the grade formula notices both.

Practical consequence: **do not mix the two scales in one report, and do not
treat "reading ease went up" as "grade level went down".** Pick the scale that
matches the decision you are making, publish the counts next to it, and if you
must show both, show them as two different opinions rather than one number.

This is asserted in the test suite (`test/runtests.jl`, the
`reading ease and grade level DISAGREE in direction` testset) so that a future
change to the tokeniser cannot quietly erase the inversion.

## Definitions and their limits

* **Word** — a token starting with an ASCII letter, which may then contain
  letters, `'` or `-`. `over-engineer` is one word; `10,000` is not a word at
  all, so a number-dense table will read as having fewer, longer words than a
  human would say it has.
* **Sentence** — a run of text separated by `.`, `!` or `?`. Repeated
  terminators do not inflate the count and a trailing run with no terminator
  still counts. Abbreviations such as `e.g.` will over-count sentences; this is
  the standard failure of every regex-level sentence splitter.
* **Syllable** — maximal runs of `a e i o u y`, minus one for a silent trailing
  `e` (but not `-le`, `-ee`, `-ye`), floored at 1. It is a heuristic, not a
  dictionary: `queue` scores 2 and `business` scores 3.
* **Complex word** (Gunning fog) — three or more syllables. The original fog
  index also excludes proper nouns, familiar compounds and verbs that only
  reach three syllables through an `-es`/`-ed`/`-ing` ending. Those exclusions
  need a lexicon, so they are omitted here and this implementation reads
  slightly harder than a hand-scored fog index on inflected-verb-heavy prose.

The heuristics are documented rather than tuned because a stable wrong answer
is more useful than an unstable one: scores from this package are reproducible
and comparable to each other, and the numbers in the table above reproduce
exactly the values an independent implementation of the same definitions
produced in another language.

## Installation

```julia
julia> using Pkg; Pkg.add("ReadabilityScores")
```

## API

| function | returns |
|---|---|
| `textcounts(text)` | `TextCounts(words, sentences, syllables, complex_words)` |
| `syllable_count(word)` | `Int`, 0 for a token with no ASCII letters |
| `flesch_reading_ease(text_or_counts)` | `Float64`, higher is easier, `NaN` if wordless |
| `flesch_kincaid_grade(text_or_counts)` | `Float64` US grade, higher is harder |
| `gunning_fog(text_or_counts)` | `Float64` US grade, higher is harder |
| `readability(text)` | `NamedTuple` with the counts, both ratios and all three scores |

## Related

An interactive version of these formulas, with the same reading-ease vs.
grade-level caveat spelled out for non-programmers, is at
[BeLikeNative's readability scorer](https://belikenative.com/tools/readability-scorer/).

## License

MIT.
