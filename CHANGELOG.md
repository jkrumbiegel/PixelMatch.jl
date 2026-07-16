# Changelog

## 1.6.0 - 2026-07-16

- `@test_pixelmatch` accepts a path to an existing PNG file as the recorded image, copying it verbatim so metadata like the `pHYs` DPI chunk is preserved. [#10](https://github.com/jkrumbiegel/PixelMatch.jl/pull/10)

## 1.5.1 - 2026-06-09

- The `@pixelmatch_report` gallery now lays out one comparison per row to stop images from jumping between rows on toggle. [#9](https://github.com/jkrumbiegel/PixelMatch.jl/pull/9)

## 1.5.0 - 2026-06-09

- Added `@pixelmatch_report`, which wraps a block of `@test_pixelmatch` calls and writes a self-contained HTML report of all failing comparisons for CI artifact upload. [#8](https://github.com/jkrumbiegel/PixelMatch.jl/pull/8)

## 1.4.0 - 2026-05-13

- `@test_pixelmatch` accepts `skip=cond` and `broken=cond`, matching `Test.@test`. [#7](https://github.com/jkrumbiegel/PixelMatch.jl/pull/7)

## 1.3.0 - 2026-05-12

- `pixelmatch` is now threaded, roughly 5–7× faster on medium and large images with 10 threads available. [#6](https://github.com/jkrumbiegel/PixelMatch.jl/pull/6)

## 1.2.0 - 2026-05-12

- Performance refactor of `pixelmatch`, ~2–3× faster with ~16× less allocation on the bundled test images. Also exposed a `checkerboard` keyword matching upstream pixelmatch 7.2. [#5](https://github.com/jkrumbiegel/PixelMatch.jl/pull/5)

## 1.1.1 - 2026-05-12

- Fixed a bug in `@test_pixelmatch` where a size mismatch between reference and recorded images would silently pass instead of failing the test. [#4](https://github.com/jkrumbiegel/PixelMatch.jl/pull/4)

## 1.1.0 - 2025-12-01

- Added the `@test_pixelmatch` macro which is a similar convenience macro to `@test_reference` from ReferenceTests.jl, just with a different naming scheme, the saving of diff images and displaying of a test difference viewer in VSCode.
