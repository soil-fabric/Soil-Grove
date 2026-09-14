# Soil-Grove
A grove for soil nodules

The products of the Soil suite that sit *on top of* Soil and use its index to
carry work and events over time. They live together in one repository because
they cannot version independently: they share a foundation, and a change to it
touches all of them at once.

- `Soil-Queue` — durable work with due times, backoff, retry and resumption
- `Soil-Event-Log` — an append-only record, read by a moving cursor *(to come)*
- `Soil-Message-Queue` — fan-out to independent subscribers *(to come)*

What is **not** here is the foundation itself. `SoilCursor`, `SoilIndexRange`
and the prefix encoding describe positions and sections of a `SoilIndex`, which
is Soil's own subject, and they have users outside this suite. They live in
Soil.

Every product is its own package with its own baseline group, so loading Soil
does not drag the suite in, and loading the suite does not force you to take
all of it.

Code lives in `source/`.
