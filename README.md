# PixelMatch.jl

A Julia translation (using Claude, mostly) of the [pixelmatch](https://github.com/mapbox/pixelmatch) JavaScript library for pixel-level image comparison.

## Installation

```julia
using Pkg
Pkg.add("https://github.com/jkrumbiegel/PixelMatch.jl")
```

## Usage

```julia
using PixelMatch
using Images, Colors

img1 = load("image1.png")
img2 = load("image2.png")

num_diff_pixels, diff_img = pixelmatch(img1, img2)

# Save the diff image
save("diff.png", diff_img)
```

There's also a convenience macro `@test_pixelmatch`.
It takes a path (without extension) relative to the place where it's called and a Julia expression whose output can be written to png. Then it checks that there are no different pixels, if there are and the `"juliavscode/html"` MIME type can be displayed (i.e. you're running tests in VSCode) an html diff viewer will be shown that is useful for comparing recording and reference.

```julia
@test_pixelmatch "relative/path/to/file" something_showable_as_png
```

Three files are written, `folder/name_rec.png`, `folder/name_ref.png` and if there's a difference, `folder/name_diff.png`. Both `*_rec.png` and `*_diff.png` should be added to `.gitignore`.

## CI failure reports

When reference tests fail on CI, it's useful to download the offending images and inspect them. Wrap your `@test_pixelmatch` calls in `@pixelmatch_report` and it writes a single self-contained HTML file with every failing comparison, embedding the reference, recorded and diff images so you can toggle between them:

```julia
PixelMatch.@pixelmatch_report out_file=joinpath(@__DIR__, "pixelmatch-report.html") begin
    @test_pixelmatch "references/plot_a" render(fig_a)
    @test_pixelmatch "references/plot_b" render(fig_b)
end
```

The block always executes. Pass `enabled=false` to skip report generation, gating it on whatever condition you like, e.g. only on CI:

```julia
PixelMatch.@pixelmatch_report enabled=get(ENV, "CI", "false") == "true" out_file=joinpath(@__DIR__, "pixelmatch-report.html") begin
    @test_pixelmatch "references/plot_a" render(fig_a)
end
```

Unlike globbing for `*_diff.png`, this captures every failure mode, including size mismatches and missing references, which produce no diff image. The report is only written when there is at least one failure.

The report is a single HTML file with all CSS, JavaScript and images inlined, so it works as an unzipped GitHub Actions artifact (`actions/upload-artifact@v7` or later with `archive: false`) that the browser can open directly. `if-no-files-found: ignore` keeps the step quiet when tests fail for a reason unrelated to reference images, in which case no report is written:

```yaml
      - uses: julia-actions/julia-runtest@v1
      - uses: actions/upload-artifact@v7
        if: failure()
        with:
          name: pixelmatch-report
          path: test/pixelmatch-report.html
          archive: false
          if-no-files-found: ignore
```
