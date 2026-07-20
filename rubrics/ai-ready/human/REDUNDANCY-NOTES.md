# Questionnaire Redundancy Notes

Cross-question overlaps in the human questionnaire (Sections 0–6). Most of
this repetition is **inherited from the paper's own 26 elements** (e.g. 0.d
License overlaps 4.c Disseminated; 0.a/0.b Findable/Accessible overlap
5.a/5.b Persistent/Repository; 0.c Interoperable overlaps 2.c Schema and
6.a/6.c) — the questionnaire mirrors the paper's structure, so the same
evidence gets judged under multiple lenses. Documented here so we can decide
what to dedupe in the packet vs. in the questions themselves.

## The big one: license / reuse terms (~5 askings)

| Evidence | Appears in | Lens |
|---|---|---|
| `license` (+ resolvable / CC0 flags) | **Q0.2**, **Q4.2** | reusable vs. disseminated — served identically, judged near-identically (both flag CC0, both accept DUA substitute) |
| `conditionsOfAccess` (DUA narrative) | **Q0.1**, **Q0.2**, **Q4.2**, **Q6.2** (as "access instructions") | metadata-openness, license substitute, dissemination terms, fetch procedure |
| `prohibitedUses` | **Q0.2**, **Q3.1**, **Q4.2** | reuse terms, out-of-scope uses, dissemination terms |

A grader sees license/reuse-terms material in **5 distinct questions across 4
sections**, and scores the license itself twice (Q0.2, Q4.2) with the same
criteria. Risk: inconsistent double-scoring of the same fact.

## Other duplicate askings

| Evidence | Appears in | Notes |
|---|---|---|
| PID + repository (`root_identifier`, `publisher_info`, `archive_indicators`) | **Q0.1**, **Q5.1** | Near-duplicate questions. Only real deltas: Q0.1 adds vocabularies/metadata-openness; Q5.1 adds domain-fit, download hosts, retention/certification. |
| `confidentialityLevel` | **Q0.1**, **Q4.1**, **Q4.2** | Three lenses: metadata-openness, required privacy strictness, access classification. |
| Schema coverage on tabular datasets (`datasets_with_schema_count`) | **Q0.2**, **Q2.2** | Served identically twice; scored twice. |
| Schemas referencing standards (`schemas_referencing_standards_count`) | **Q2.2** (LOINC/OMOP/GA4GH), **Q6.1** (Frictionless/JSON Schema) | Same field, different standard families — defensible but easy to conflate. |
| Format mix (`format_distribution`) | **Q0.2** ("published spec"), **Q6.3** ("widely readable") | Same evidence, near-same judgment. |
| Governance committee (`dataGovernanceCommittee`) | **Q4.1**, **Q5.2** | Ethical oversight vs. stewardship — same named body scored twice. |
| Maintenance plan (`rai:dataReleaseMaintenancePlan`) | **Q4.1** (as "management plan"), **Q5.2** (as "maintenance plan") | **Same field served under two labels.** |
| Contact (`contactEmail`) | **Q4.2**, **Q5.2** ("actionable contact") | Note: the metadata spec currently serves `contact_email` only to Q4.2 — Q5.2 asks for a contact it isn't given. Either serve it there too or drop the contact clause from Q5.2. |
| Provenance walkability | **Q1.2** (chain quality per step), **Q5.3** (overall connectivity/orphans) | Both say "walk from outputs back to raw inputs with no gaps/dead ends." Different altitude, but a broken chain will be penalized twice. |
| Missingness (`rai:dataCollectionMissingData`) | **Q2.2** (encoding convention), **Q2.3** (reasons/mechanism) | Intra-section; the convention-vs-reasons split is deliberate — keep, but the packet serves the same raw field to both. |
| Repository recognition lists | **Q0.1** (FAIR repos), **Q5.1** (GREI + specialists) | Two different allow-lists for "is this a real repository" — should be one list used twice, if kept in both. |

## Options

1. **Dedupe in the packet only (cheapest, keeps paper alignment).** Keep all
   17 questions, but when a field repeats, render it once per section with a
   tag like *(also shown in Q0.2 — score consistently)*. Grader instructions:
   carry your earlier judgment of the same fact unless the new lens changes it
   (e.g. license quality judged in Q0.2; Q4.2 only re-examines it against
   sensitivity/classification).
2. **Score-once, cross-reference.** Give each fact one home question and
   remove it from the others' criteria: license → Q0.2; PID+repository →
   Q0.1 (Q5.1 keeps only domain-fit + retention/certification); governance +
   maintenance plan → Q5.2 (Q4.1 keeps only privacy oversight/processing);
   schema coverage → Q2.2 (drop from Q0.2); format mix → Q6.3 (drop from
   Q0.2). Cleaner, but per-section subtotals no longer map 1:1 onto the
   paper's elements.
3. **Merge near-duplicate questions** (Q0.1+Q5.1). Biggest question-count
   savings, biggest departure from the paper's section structure.

**Recommendation:** option 1 now (packet rendering + "score consistently"
tags), consider option 2 for license, governance/maintenance, and schema
coverage — the three cases where the *criteria*, not just the evidence, are
duplicated.
