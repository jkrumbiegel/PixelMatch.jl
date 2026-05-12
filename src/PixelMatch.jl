module PixelMatch

using ColorTypes
import PNGFiles
import Base64
import Test

INTERACTIVE_MODE = Ref(true)

export @test_pixelmatch
export pixelmatch

"""
    pixelmatch(img1, img2; threshold=0.1, include_aa=false,
               alpha=0.1, aa_color=RGB(1.0, 1.0, 0.0), diff_color=RGB(1.0, 0.0, 0.0),
               diff_color_alt=nothing, diff_mask=false, checkerboard=true)

Compare two equally sized images, pixel by pixel.

# Arguments
- `img1`: First image as a matrix of color values
- `img2`: Second image as a matrix of color values
- `threshold`: Matching threshold (0 to 1); smaller is more sensitive, defaults to 0.1
- `include_aa`: Whether to include anti-aliasing detection
- `alpha`: Opacity of original image in diff output
- `aa_color`: Color of anti-aliased pixels in diff output
- `diff_color`: Color of different pixels in diff output
- `diff_color_alt`: Alternative color for dark-on-light differences
- `diff_mask`: Draw the diff over a transparent background (a mask)
- `checkerboard`: Blend semi-transparent pixels against a checkerboard pattern (true) or plain white (false)

# Returns
A tuple of (number of mismatched pixels, diff image).
"""
function pixelmatch(img1::AbstractMatrix{<:Colorant}, img2::AbstractMatrix{<:Colorant};
                    threshold::Real=0.1,
                    include_aa::Bool=false,
                    alpha::Real=0.1,
                    aa_color::Colorant=RGB(1.0, 1.0, 0.0),
                    diff_color::Colorant=RGB(1.0, 0.0, 0.0),
                    diff_color_alt::Union{Nothing, Colorant}=nothing,
                    diff_mask::Bool=false,
                    checkerboard::Bool=true)

    if size(img1) != size(img2)
        throw(ArgumentError("Image sizes do not match. Image 1 size: $(size(img1)), image 2 size: $(size(img2))"))
    end

    height, width = size(img1)
    OutColor = RGBA{eltype(eltype(img1))}
    output = fill(zero(OutColor), height, width)

    aa_col = convert(OutColor, aa_color)
    diff_col = convert(OutColor, diff_color)
    alt_col = convert(OutColor, diff_color_alt === nothing ? diff_color : diff_color_alt)

    max_delta = 35215.0 * threshold * threshold
    alpha_f = Float64(alpha)
    diff = 0

    @inbounds for x in 1:width, y in 1:height
        p1 = img1[y, x]
        p2 = img2[y, x]
        r1, g1, b1, a1 = rgba_bytes(p1)

        if p1 == p2
            if !diff_mask
                output[y, x] = gray_pixel(OutColor, r1, g1, b1, a1, alpha_f)
            end
            continue
        end

        r2, g2, b2, a2 = rgba_bytes(p2)
        pos = (y - 1) * width + (x - 1)
        delta = color_delta(r1, g1, b1, a1, r2, g2, b2, a2, pos, checkerboard)

        if abs(delta) > max_delta
            excluded_aa = !include_aa && (
                is_antialiased(img1, img2, x, y, width, height, checkerboard) ||
                is_antialiased(img2, img1, x, y, width, height, checkerboard)
            )
            if excluded_aa
                if !diff_mask
                    output[y, x] = aa_col
                end
            else
                output[y, x] = delta < 0 ? alt_col : diff_col
                diff += 1
            end
        elseif !diff_mask
            output[y, x] = gray_pixel(OutColor, r1, g1, b1, a1, alpha_f)
        end
    end

    return diff, output
end

@inline function rgba_bytes(c::Colorant)
    rgba = convert(RGBA{Float64}, c)
    return red(rgba) * 255, green(rgba) * 255, blue(rgba) * 255, alpha(rgba) * 255
end

"""
Color difference per Kotsarenko & Ramos, "Measuring perceived color difference using
YIQ NTSC transmission color space in mobile applications". Operates in 0–255 byte space
to match the JavaScript reference implementation byte-for-byte.
"""
@inline function color_delta(r1, g1, b1, a1, r2, g2, b2, a2, pos::Integer, checkerboard::Bool)
    dr = r1 - r2
    dg = g1 - g2
    db = b1 - b2
    da = a1 - a2

    if dr == 0 && dg == 0 && db == 0 && da == 0
        return 0.0
    end

    if a1 < 255 || a2 < 255
        rb, gb, bb = background(pos, checkerboard)
        dr = (r1 * a1 - r2 * a2 - rb * da) / 255
        dg = (g1 * a1 - g2 * a2 - gb * da) / 255
        db = (b1 * a1 - b2 * a2 - bb * da) / 255
    end

    y = dr * 0.29889531 + dg * 0.58662247 + db * 0.11448223
    i = dr * 0.59597799 - dg * 0.27417610 - db * 0.32180189
    q = dr * 0.21147017 - dg * 0.52261711 + db * 0.31114694

    delta = 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q
    return y > 0 ? -delta : delta
end

"""
Y-only delta used by the anti-aliasing detector. Skips I/Q so the per-neighbor cost
is half that of the full color delta.
"""
@inline function brightness_delta(r1, g1, b1, a1, r2, g2, b2, a2, pos::Integer, checkerboard::Bool)
    dr = r1 - r2
    dg = g1 - g2
    db = b1 - b2
    da = a1 - a2

    if dr == 0 && dg == 0 && db == 0 && da == 0
        return 0.0
    end

    if a1 < 255 || a2 < 255
        rb, gb, bb = background(pos, checkerboard)
        dr = (r1 * a1 - r2 * a2 - rb * da) / 255
        dg = (g1 * a1 - g2 * a2 - gb * da) / 255
        db = (b1 * a1 - b2 * a2 - bb * da) / 255
    end

    return dr * 0.29889531 + dg * 0.58662247 + db * 0.11448223
end

@inline function background(pos::Integer, checkerboard::Bool)
    checkerboard || return 255.0, 255.0, 255.0
    k = pos * 4
    rb = 48 + 159 * (k % 2)
    gb = 48 + 159 * (floor(Int, k / 1.618033988749895) % 2)
    bb = 48 + 159 * (floor(Int, k / 2.618033988749895) % 2)
    return Float64(rb), Float64(gb), Float64(bb)
end

"""
Check if a pixel is likely part of anti-aliasing.
Based on "Anti-aliased Pixel and Intensity Slope Detector" paper by V. Vysniauskas, 2009.
"""
function is_antialiased(img1::AbstractMatrix{<:Colorant}, img2::AbstractMatrix{<:Colorant},
                        x1::Int, y1::Int, width::Int, height::Int, checkerboard::Bool)
    x0 = max(x1 - 1, 1)
    y0 = max(y1 - 1, 1)
    x2 = min(x1 + 1, width)
    y2 = min(y1 + 1, height)

    cr, cg, cb, ca = rgba_bytes(img1[y1, x1])
    pos_center = (y1 - 1) * width + (x1 - 1)

    zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0
    min_delta = 0.0
    max_delta = 0.0
    min_x = 0; min_y = 0
    max_x = 0; max_y = 0

    @inbounds for x in x0:x2, y in y0:y2
        (x == x1 && y == y1) && continue
        nr, ng, nb, na = rgba_bytes(img1[y, x])
        delta = brightness_delta(cr, cg, cb, ca, nr, ng, nb, na, pos_center, checkerboard)

        if delta == 0
            zeroes += 1
            zeroes > 2 && return false
        elseif delta < min_delta
            min_delta = delta; min_x = x; min_y = y
        elseif delta > max_delta
            max_delta = delta; max_x = x; max_y = y
        end
    end

    (min_delta == 0 || max_delta == 0) && return false

    return (has_many_siblings(img1, min_x, min_y, width, height) && has_many_siblings(img2, min_x, min_y, width, height)) ||
           (has_many_siblings(img1, max_x, max_y, width, height) && has_many_siblings(img2, max_x, max_y, width, height))
end

"""
Check if a pixel has 3+ adjacent pixels of the same color.
"""
function has_many_siblings(img::AbstractMatrix{<:Colorant}, x1::Int, y1::Int, width::Int, height::Int)
    x0 = max(x1 - 1, 1)
    y0 = max(y1 - 1, 1)
    x2 = min(x1 + 1, width)
    y2 = min(y1 + 1, height)

    center = img[y1, x1]
    zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0

    @inbounds for x in x0:x2, y in y0:y2
        (x == x1 && y == y1) && continue
        if img[y, x] == center
            zeroes += 1
            zeroes > 2 && return true
        end
    end
    return false
end

"""
Grayscale pixel blended with white. Matches the JS byte-truncation semantics so the
diff output is bit-identical to the reference implementation.
"""
@inline function gray_pixel(::Type{C}, r, g, b, a, alpha_blend) where {C}
    val_255 = 255 + (r * 0.29889531 + g * 0.58662247 + b * 0.11448223 - 255) * alpha_blend * a / 255
    val_uint8 = trunc(UInt8, val_255)
    val = val_uint8 / 255
    return C(val, val, val, 1.0)
end

include("test_macro.jl")

end # module PixelMatch
