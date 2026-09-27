# Contributing to Akkoma

Akkoma is a community project, contributed to by all sorts of people.
Hence, our contribution guidelines are quite simple - but we do ask a few things of potential contributors.

All contributions should follow the `CODE_OF_CONDUCT.md`

## AI Usage

On a project with a requirement to be safe for everyone to use, and one with a generally exposed attack surface,
we ask that contributors refrain from the usage of agentic AI for the purposes of code production, or otherwise generating
large parts of functions and modules via LLMs.

Akkoma faces the wider fediverse and must correctly behave on input from both well-meaning actors, and those
that may be acting in worse faith. Hence, we must be able to reason about how Akkoma will behave given different inputs.
The same goes for contributors; if you are submitting a pull request, you must be able to reason about how your
change behaves, and how that will fit into the wider project.

The project maintainers must also be able to understand what you have implemented, as well as trust that you are
offering changes that you have authored in good faith.

Agentic systems will implement on your behalf and deny you the insight that comes with modifying the system yourself.
They also prevent the maintainers from having confidence in your changes.
