"""
    ReadabilityScores

Classic English readability formulas computed from a single tokenisation pass.

The package deliberately exposes the intermediate counts ([`TextCounts`](@ref))
as well as the scores, because the scores are only interpretable next to the
counts they were derived from. See the README for the reading-ease vs.
grade-level disagreement this makes visible.
"""
module ReadabilityScores

export TextCounts,
       textcounts,
       syllable_count,
       flesch_reading_ease,
       flesch_kincaid_grade,
       gunning_fog,
       readability

"""
    TextCounts

Counts produced by one pass over a text.

* `words` – tokens that start with an ASCII letter and may contain `'` or `-`.
* `sentences` – runs of text separated by `.`, `!` or `?`; a trailing run with
  no terminator still counts as a sentence, and a text with any content has at
  least one sentence.
* `syllables` – sum of [`syllable_count`](@ref) over the words.
* `complex_words` – words of three or more syllables (the Gunning fog input).
"""
struct TextCounts
    words::Int
    sentences::Int
    syllables::Int
    complex_words::Int
end

const _VOWELS = ('a', 'e', 'i', 'o', 'u', 'y')

_isalpha(c::Char) = ('a' <= c <= 'z') || ('A' <= c <= 'Z')

"""
    syllable_count(word) -> Int

Vowel-group heuristic: count maximal runs of `a e i o u y`, then drop one for a
silent trailing `e` (but not for `-le`, `-ee` or `-ye`). Any word containing at
least one ASCII letter scores at least 1. A word with no ASCII letters scores 0.

This is a heuristic, not a dictionary lookup. It is documented and stable so
that scores are reproducible, not because it is always right: `queue` scores 2
and `business` scores 3.
"""
function syllable_count(word::AbstractString)
    groups = 0
    prev_vowel = false
    letters = 0
    last1 = ' '
    last2 = ' '
    for ch in word
        _isalpha(ch) || continue
        c = lowercase(ch)
        letters += 1
        is_vowel = c in _VOWELS
        groups += (is_vowel && !prev_vowel) ? 1 : 0
        prev_vowel = is_vowel
        last2 = last1
        last1 = c
    end
    letters == 0 && return 0
    @assert groups >= 0 "vowel-group count went negative"
    silent_e = last1 == 'e' && !(last2 in ('l', 'e', 'y')) && groups > 1
    groups -= silent_e ? 1 : 0
    return max(groups, 1)
end

"""
    textcounts(text) -> TextCounts

Tokenise `text` once and return every count the formulas need. Words, sentences
and syllables all come out of the same walk, so the three scores in
[`readability`](@ref) can never disagree about what they measured.
"""
function textcounts(text::AbstractString)
    words = 0
    syllables = 0
    complex_words = 0
    sentences = 0
    buf = IOBuffer()
    in_word = false
    pending = false
    for ch in text
        if _isalpha(ch) || (in_word && (ch == '\'' || ch == '-'))
            print(buf, ch)
            in_word = true
            pending = true
            continue
        end
        if in_word
            s = syllable_count(String(take!(buf)))
            in_word = false
            words += 1
            syllables += s
            complex_words += (s >= 3) ? 1 : 0
        end
        if ch == '.' || ch == '!' || ch == '?'
            sentences += pending ? 1 : 0
            pending = false
        elseif !isspace(ch)
            pending = true
        end
    end
    if in_word
        s = syllable_count(String(take!(buf)))
        words += 1
        syllables += s
        complex_words += (s >= 3) ? 1 : 0
    end
    sentences += pending ? 1 : 0
    @assert words >= complex_words "complex words cannot exceed total words"
    @assert sentences >= 0 "sentence count went negative"
    return TextCounts(words, sentences, syllables, complex_words)
end

_ratios(c::TextCounts) = (c.words / max(c.sentences, 1), c.syllables / c.words)

"""
    flesch_reading_ease(text_or_counts) -> Float64

`206.835 - 1.015 * words/sentence - 84.6 * syllables/word`.

Higher is easier. Returns `NaN` for a text with no words.
"""
function flesch_reading_ease(c::TextCounts)
    c.words == 0 && return NaN
    wps, spw = _ratios(c)
    @assert wps > 0 "words per sentence must be positive"
    return 206.835 - 1.015 * wps - 84.6 * spw
end

"""
    flesch_kincaid_grade(text_or_counts) -> Float64

`0.39 * words/sentence + 11.8 * syllables/word - 15.59`, in US school grades.
Higher means harder. Returns `NaN` for a text with no words.
"""
function flesch_kincaid_grade(c::TextCounts)
    c.words == 0 && return NaN
    wps, spw = _ratios(c)
    @assert spw > 0 "syllables per word must be positive"
    return 0.39 * wps + 11.8 * spw - 15.59
end

"""
    gunning_fog(text_or_counts) -> Float64

`0.4 * (words/sentence + 100 * complex_words/words)`, in US school grades,
where a complex word is one of three or more syllables.

The original formula also excludes proper nouns, familiar compounds and verbs
that only reach three syllables through an `-es`/`-ed`/`-ing` ending. Those
exclusions need a lexicon, so this implementation omits them and will read
slightly harder than a hand-scored fog index on text full of inflected verbs.
"""
function gunning_fog(c::TextCounts)
    c.words == 0 && return NaN
    wps = c.words / max(c.sentences, 1)
    @assert c.words > 0 "cannot score a text with no words"
    @assert c.complex_words >= 0 "complex word count went negative"
    return 0.4 * (wps + 100 * c.complex_words / c.words)
end

for f in (:flesch_reading_ease, :flesch_kincaid_grade, :gunning_fog)
    @eval $f(text::AbstractString) = $f(textcounts(text))
end

"""
    readability(text) -> NamedTuple

Score `text` with all three formulas from one tokenisation pass, and return the
counts alongside them.

```jldoctest
julia> r = readability("The cat sat on the mat. The dog did not.");

julia> (r.words, r.sentences, r.syllables)
(10, 2, 10)
```
"""
function readability(text::AbstractString)
    c = textcounts(text)
    @assert c.words >= 0 "word count went negative"
    @assert c.syllables >= c.words || c.words == 0 "every word has >= 1 syllable"
    return (words = c.words,
            sentences = c.sentences,
            syllables = c.syllables,
            complex_words = c.complex_words,
            words_per_sentence = c.words / max(c.sentences, 1),
            syllables_per_word = c.words == 0 ? NaN : c.syllables / c.words,
            flesch_reading_ease = flesch_reading_ease(c),
            flesch_kincaid_grade = flesch_kincaid_grade(c),
            gunning_fog = gunning_fog(c))
end

end # module
