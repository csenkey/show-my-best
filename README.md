# Show My Best

A native macOS app for viewing and rating Istvan's best photos, built around the
output of the `photo-competition-curator` Claude skill.

The skill runs separately in the Claude app and writes the data files (`catalogue.csv`,
`submissions.csv`, and the planned `competitions.csv`) into the photo folder. Show My Best
presents them as a gallery, lets Istvan review and rate photos, and writes his ratings back
so later skill runs build on them.

Status: v0.1 implemented — the screens from the design project are built and the
catalogue writing rules are in place. The skill changes (§7) and the data migration
(§8) are still to do.

```bash
Tools/build-app.sh                              # builds build/ShowMyBest.app
swift run SelfTest                              # the acceptance checks, no Xcode needed
swift run SelfTest --inspect <library folder>   # read-only report on a real library
```

- [docs/requirements-spec.md](docs/requirements-spec.md): what the app and the skill must do.
- [docs/discovery-notes.md](docs/discovery-notes.md): the decisions behind it and findings
  from the real catalogue.
- [docs/implementation-notes.md](docs/implementation-notes.md): how it is built, where each
  requirement lives, and what is not done yet.
- [docs/competition-backfill.md](docs/competition-backfill.md): the one migration step the
  app cannot do, because it needs each competition re-checked online.
- [skill/photo-competition-curator/](skill/photo-competition-curator/): the Claude skill that
  writes the data files, kept here so it and the spec stay in step. Copy it into Claude's
  skills folder to install it.
