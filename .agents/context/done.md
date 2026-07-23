# Definition of done

A change is complete only when all applicable evidence is recorded:

1. The change stays within the target boundary and preserves unrelated work.
2. `python3 scripts/check_environment_contract.py --as-of YYYY-MM-DD` passes.
3. `swift test` passes; use `./scripts/test-with-coverage.sh` when behavior or
   coverage-sensitive code changed.
4. Both release products build when executable or release behavior changed.
5. The app bundle and plist validate when packaging or resources changed.
6. `scripts/pre-cr-test.sh` passes after its test-bundle prerequisite is built.
7. `scripts/release-check.sh` is run for release claims, and any missing live
   capture/accessibility evidence is reported as blocked.
8. `.tracker/PROJECT_TRUTH.md` is updated as a current snapshot after the
   atomic code commit; it is not used as an append-only changelog.

Do not claim a release or live UI acceptance from compiler, unit-test, or
process-level evidence alone.
