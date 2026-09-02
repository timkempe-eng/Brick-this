# The verb

The product verb is **Dad**. It conjugates like any other one-syllable
consonant–vowel–consonant verb, so the final consonant doubles before a vowel
suffix — the same rule that turns *trim* into *trimmed* and *slam* into
*slamming*.

| Form | Word | Example |
|---|---|---|
| Imperative | Dad | "Dad your phone." |
| Third person | Dads | "The tag Dads your phone." |
| Past / participle | Dadded | "I Dadded my phone at nine." |
| Gerund | Dadding | "He's Dadding again." |
| Third person | Dads | "Your phone Dads itself at ten." |
| State | Dadded | "Your phone is Dadded." |
| Release | Un-Dad | "Un-Dad my phone." |
| Release, past | Un-Dadded | "Un-Dadded after two hours." |

Capital D throughout, including mid-sentence — it's a proper noun doing a verb's
job, like *Google it*. The hyphen in *Un-Dad* stays: *Undad* reads as a typo,
and it keeps the release verb visibly paired with the verb it undoes.

One hazard the old verb did not have: *dad* is an ordinary English word, so a
lowercase one is a real sentence rather than an obvious slip. "Ask your dad" is
fine prose; "dad your phone" is the product name spelled wrong. The check in
`scripts/lint-vocabulary.sh` is structural — it catches `.lowercased()` on a
verb form — so it cannot see a lowercase literal. Read new copy for it.

## Nouns

- **A Dad session** — one stretch of being Dadded.
- **A Dad tag** — the NFC sticker you tap.
- **A Mode** — a named set of apps to take away (Deep Work, Sleep, Gym).
- **A Dad streak** — consecutive days with at least one session.

## Copy rules

1. **The verb carries the sentence.** "Dad your phone" beats "activate Dad
   Mode." Brick's whole linguistic trick is that the product name is a thing you
   *do*, so use it as one.
2. **Past tense for state, imperative for action.** Status screens say
   "Dadded." Buttons say "Dad my phone."
3. **Never explain the joke.** No "(that means blocked!)". The verb teaches
   itself the second time someone sees it.
4. **The shield screen is the important one.** It's the only copy a user reads
   while being told no. One word — "Dadded." — then a short sentence, then a
   way out.

All of this lives in one file, [`Dad/Shared/DadVocabulary.swift`](../Dad/Shared/DadVocabulary.swift),
so the app, the shield extension and the Siri phrases can't drift apart.
