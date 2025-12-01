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
