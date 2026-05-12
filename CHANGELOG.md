# Changelog

## Unreleased

## 1.1.1 - 2026-05-12

- Fixed a bug in `@test_pixelmatch` where a size mismatch between reference and recorded images would silently pass instead of failing the test. [#4](https://github.com/jkrumbiegel/PixelMatch.jl/pull/4)

## 1.1.0 - 2025-12-01

- Added the `@test_pixelmatch` macro which is a similar convenience macro to `@test_reference` from ReferenceTests.jl, just with a different naming scheme, the saving of diff images and displaying of a test difference viewer in VSCode.
