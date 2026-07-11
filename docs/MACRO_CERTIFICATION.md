# Macro certification

Run the fixture scaffold, then certify a macro in one replayable command:

    bash generators/macro_fixture_scaffold.sh --macro-id example.macro --output-dir generated/macros/fixtures --json
    bash tools/macro_certify.sh --macro macro.json --fixtures generated/macros/fixtures --output generated/macros/macro-certificate.json --json

The certificate hashes the canonical macro and every fixture, signs that hash with
the local signer, and records every proof obligation. The mandatory fixture set
is positive, negative, adversarial, partial_parse, dirty_worktree, and rollback.
Any missing or failed obligation emits an exact remediation and sets
trusted=false and apply_mode_allowed=false. Changing either the macro or fixture
content changes inputs.content_hash, so an old certificate cannot be reused.
