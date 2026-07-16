# SiteMark README Redesign

## Goal

Turn the repository README into a trustworthy product landing page for Chinese
engineering users while retaining enough English and technical detail for
international contributors. A visitor should understand within one screen that
SiteMark uses the Android system camera, works locally, contains no ads, and is
still an alpha awaiting production signing and physical-device validation.

## Approaches considered

1. **Product-first bilingual landing page (selected).** Lead with the product
   promise and real screenshots, then explain features, privacy, status, and
   development. This best serves both prospective users and contributors.
2. **Developer-first documentation.** Put architecture and build commands near
   the top. This is efficient for maintainers but hides the product value from
   non-developers.
3. **Minimal marketing page.** Use a short slogan and large visuals. This looks
   clean but does not provide enough evidence about permissions, storage, or
   release readiness.

## Page structure

1. Product name, concise Chinese tagline, one-line English summary, and badges
   for CI, Android 12+, Apache-2.0, offline, and alpha status.
2. A 2 x 2 gallery of real Android 16 emulator screenshots:
   project list, capture form, external system camera, and rendered watermark.
3. A short “why SiteMark” section centered on the system camera experience,
   lack of advertising/cloud dependencies, private originals, and traceable
   exports.
4. A factual capability table describing the SiteMark approach without making
   unverifiable claims about named competitors.
5. The six-step capture and export workflow.
6. Current installation and release status. The page must explicitly state that
   no production-signed public APK exists yet. CI artifacts are developer/test
   builds, not stable releases.
7. Exact release permissions and storage behavior, including the absence of
   camera, internet, background-location, and broad-media permissions.
8. Project watermark settings and export contents.
9. Architecture and local build instructions for contributors.
10. Verified environment, remaining manufacturer-device gates, roadmap, and
    links to privacy, security, contributing, notices, and the license.

## Screenshot assets

- Store committed assets under `docs/images/readme/` with descriptive English
  filenames.
- Capture the actual app and AOSP external camera from the existing API 36 AVD.
- Use Chinese UI where applicable and synthetic project/site data only.
- Crop no evidence into a misleading state. The external camera screenshot must
  visibly be the AOSP camera activity rather than a mockup.
- Keep individual files reasonably compressed and use HTML image sizing in the
  README so mobile and desktop layouts remain readable.

## Content rules

- Chinese is the primary narrative language. Important headings and compact
  summaries include English translations; long sections do not duplicate every
  paragraph word-for-word.
- Avoid a direct “better than competitor X” table. Compare architectural
  choices only: system camera, offline processing, private original, published
  output, and open-source status.
- Do not claim forensic tamper resistance. SHA-256 is described as traceability
  metadata.
- Do not present the unsigned local release APK or debug artifact as an end-user
  download.
- Keep commands and detailed architecture below the product and trust sections.

## Verification

- Confirm every relative link and image target exists in the branch.
- Render the Markdown through GitHub's Markdown API and inspect the resulting
  HTML for missing images, malformed tables, and heading order.
- Check the README at mobile-friendly widths through GitHub after pushing.
- Run `git diff --check`; application test suites do not need to be rerun for a
  documentation-only change unless source files change.

## Success criteria

- The first screen communicates the product promise and alpha status.
- Four real screenshots appear without requiring visitors to open another page.
- Permissions, local storage, current release availability, and remaining
  device-validation work are unambiguous.
- A contributor can still find architecture, setup, verification, and policy
  links without searching the repository.
