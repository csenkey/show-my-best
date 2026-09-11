# Show My Best

A native macOS app for viewing and rating Istvan's best photos, built around the
output of the `photo-competition-curator` Claude skill.

The skill runs separately in the Claude app and writes the data files (`catalogue.csv`,
`submissions.csv`, and the planned `competitions.csv`) into the photo folder. Show My Best
presents them as a gallery, lets Istvan review and rate photos, and writes his ratings back
so later skill runs build on them.

Status: discovery. See [docs/discovery-notes.md](docs/discovery-notes.md) for the decisions
made so far and the open questions. A requirements specification and design document will
follow.
