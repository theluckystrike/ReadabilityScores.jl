using ReadabilityScores
using Test

# Two excerpts used throughout: a contract clause and a piece of API reference.
# Built with `*` rather than a backslash line continuation inside the string
# literal: that syntax needs Julia 1.7, and Project.toml declares julia = "1.6".
const CONTRACT = "The party of the first part shall indemnify and hold harmless " *
    "the party of the second part against any and all claims arising consequent to " *
    "the execution hereof."
const APIDOC = "The endpoint returns a JSON object containing the authentication " *
    "token. Include this token in the Authorization header for subsequent requests."

@testset "ReadabilityScores" begin

    @testset "syllable_count" begin
        @test syllable_count("cat") == 1
        @test syllable_count("water") == 2
        @test syllable_count("banana") == 3
        @test syllable_count("indemnify") == 4
        @test syllable_count("") == 0
        @test syllable_count("1234") == 0
        # silent trailing e is dropped ...
        @test syllable_count("make") == 1
        @test syllable_count("code") == 1
        # ... but not for -le, -ee or -ye
        @test syllable_count("table") == 2
        @test syllable_count("agree") == 2
        # a one-group word never drops to zero
        @test syllable_count("the") == 1
        @test syllable_count("be") == 1
    end

    @testset "tokenisation" begin
        c = textcounts("The cat sat on the mat. The dog did not.")
        @test c.words == 10
        @test c.sentences == 2
        @test c.syllables == 10
        @test c.complex_words == 0

        # a trailing run with no terminator is still a sentence
        @test textcounts("One. Two").sentences == 2
        # repeated terminators do not inflate the count
        @test textcounts("Hello... world.").sentences == 2
        # Hyphens and apostrophes stay inside a word, so "over-engineer" is one
        # token. A number is not a word at all, so "10,000" contributes nothing
        # and this text has three words, not four.
        c2 = textcounts("Don't over-engineer 10,000 things.")
        @test c2.words == 3
        @test textcounts("over-engineer").words == 1
        @test textcounts("10,000").words == 0
        # empty input is well defined
        @test textcounts("") == TextCounts(0, 0, 0, 0)
        @test isnan(flesch_reading_ease(""))
        @test isnan(gunning_fog(""))
    end

    @testset "formula arithmetic" begin
        # Hand-checkable: 10 words, 2 sentences, 10 syllables.
        c = textcounts("The cat sat on the mat. The dog did not.")
        wps, spw = 10 / 2, 10 / 10
        @test flesch_reading_ease(c) ≈ 206.835 - 1.015 * wps - 84.6 * spw
        @test flesch_kincaid_grade(c) ≈ 0.39 * wps + 11.8 * spw - 15.59
        @test gunning_fog(c) ≈ 0.4 * (wps + 100 * 0 / 10)
        # string and counts overloads agree
        s = "The cat sat on the mat. The dog did not."
        @test flesch_reading_ease(s) == flesch_reading_ease(c)
        @test flesch_kincaid_grade(s) == flesch_kincaid_grade(c)
        @test gunning_fog(s) == gunning_fog(c)
    end

    @testset "readability bundles one pass" begin
        r = readability(APIDOC)
        c = textcounts(APIDOC)
        @test r.words == c.words
        @test r.sentences == c.sentences
        @test r.syllables == c.syllables
        @test r.complex_words == c.complex_words
        @test r.words_per_sentence ≈ c.words / c.sentences
        @test r.syllables_per_word ≈ c.syllables / c.words
        @test r.flesch_reading_ease == flesch_reading_ease(c)
        @test r.flesch_kincaid_grade == flesch_kincaid_grade(c)
        @test r.gunning_fog == gunning_fog(c)
    end

    @testset "monotonic in the obvious direction" begin
        simple = "The dog ran. The cat sat. The sun rose."
        hard = "Notwithstanding the aforementioned considerations, the " *
            "organisational infrastructure necessitates comprehensive reconfiguration."
        @test flesch_reading_ease(simple) > flesch_reading_ease(hard)
        @test flesch_kincaid_grade(simple) < flesch_kincaid_grade(hard)
        @test gunning_fog(simple) < gunning_fog(hard)
    end

    @testset "reading ease and grade level DISAGREE in direction" begin
        # This is the documented limitation, asserted rather than hidden.
        # The contract clause is one long sentence of mostly short words; the
        # API reference is two shorter sentences of long words.
        ce, ae = flesch_reading_ease(CONTRACT), flesch_reading_ease(APIDOC)
        cg, ag = flesch_kincaid_grade(CONTRACT), flesch_kincaid_grade(APIDOC)

        # Reading ease calls the contract EASIER ...
        @test ce > ae
        # ... while Flesch-Kincaid calls the same contract a HIGHER grade.
        @test cg > ag

        # Cause: the two formulas weight the same two ratios very differently.
        # Reading ease weights syllables/word 84.6 against 1.015 for
        # words/sentence, a ratio of about 83. The grade formula weights them
        # 11.8 against 0.39, a ratio of about 30 - so reading ease is roughly
        # 2.75x more lopsided towards word length. The contract's long sentence
        # is therefore nearly invisible to reading ease and plainly visible to
        # the grade formula.
        cc, ac = textcounts(CONTRACT), textcounts(APIDOC)
        @test cc.words / cc.sentences > ac.words / ac.sentences   # longer sentences
        @test cc.syllables / cc.words < ac.syllables / ac.words   # shorter words
        @test (84.6 / 1.015) / (11.8 / 0.39) > 2.5
    end

    @testset "fog reads the contract as hardest" begin
        @test gunning_fog(CONTRACT) > gunning_fog(APIDOC)
        @test gunning_fog(CONTRACT) > flesch_kincaid_grade(CONTRACT)
    end
end
