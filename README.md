# Show My Best

A native macOS app for viewing and rating Istvan's best photos, built around the
output of the `photo-competition-curator` Claude skill.

The skill runs separately in the Claude app and writes the data files (`catalogue.csv`,
`submissions.csv`, and the planned `competitions.csv`) into the photo folder. Show My Best
presents them as a gallery, lets Istvan review and rate photos, and writes his ratings back
so later skill runs build on them.

Status: requirements drafted, design next.

- [docs/requirements-spec.md](docs/requirements-spec.md): what the app and the skill must do.
- [docs/discovery-notes.md](docs/discovery-notes.md): the decisions behind it and findings
  from the real catalogue.
