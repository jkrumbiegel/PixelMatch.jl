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
