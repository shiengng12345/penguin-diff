Config Compare — Third-party licenses and notices

This folder preserves the supplied license and attribution texts for the exact locked dependency versions. inventory.json identifies each component, its version, source revision when available, license declaration and original text hashes.

The inventory deliberately includes locked build, development and platform-only sources; inclusion does not mean that every component is linked into this application. Rust packages missing license files in their published crate archives use the license from the corresponding upstream repository at the crate-recorded Git revision. These source URLs are provenance only; the application does not fetch them.

The vendored oxc_parser has local resource/stack guards. Its unchanged upstream license is retained; vendor/oxc_parser/UPSTREAM.json and stack-budget.patch in the source distribution describe those modifications.

All texts remain under their original terms. No license text or author attribution has been rewritten.
