# Backfilling competitions from the catalogue (MIG-5)

`Tools/migrate.swift` does the mechanical half of §8. MIG-5 is the half it
cannot do: building `competitions.csv` and `competition_matches.csv` out of the
60 catalogue rows that carry `competition_fit_notes`, because every competition
has to be re-checked online before its deadline, fee and rights terms can be
written down. Inventing those from the prose would put a wrong deadline in
front of a decision about entering, and a wrong rights flag in front of a
decision about signing away a licence.

So it is a skill job. Once the updated `photo-competition-curator` skill is
installed, ask it in the Claude app:

> Backfill competitions.csv and competition_matches.csv in REAL_BEST from the
> rows that already have competition_fit_notes. Re-check each competition
> online first — deadline, fee, eligibility, capture-date rule, previously-
> unpublished rule, prize and rights terms. Leave out any competition you
> cannot verify and list those for me. Don't touch istvan_rating or
> claude_rating, and don't write any critiques in this run.

What to expect back:

- `competitions.csv` with one row per competition it could verify, each with a
  `recommendation_call` and the reasoning behind it, `rights_flag` set, and
  `last_checked` set to today.
- `competition_matches.csv` with one row per photo-to-competition pairing,
  `role` as `primary` or `alternate`, and a `reason` naming both ratings.
- A list of competitions from the prose it could **not** verify — most of the
  notes name contests from earlier in 2026, so expect several to have closed.

The app picks both files up within two seconds of them being written. Anything
matched to a photo Istvan has not rated shows only as a count, never as the
photo (IND-4), so a backfill cannot leak Claude's opinion of an unrated photo.

## Checking the result

```bash
swift run SelfTest --inspect ~/Pictures/6x6Stories/REAL_BEST
```

The sidecar section reports how many competitions and matches were read, and
names any file that would not parse.
