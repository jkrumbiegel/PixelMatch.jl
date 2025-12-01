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
               diff_color_alt=nothing, diff_mask=false)

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

# Returns
A tuple of (number of mismatched pixels, diff image).
"""
function pixelmatch(img1::AbstractMatrix{<:Colorant}, img2::AbstractMatrix{<:Colorant}; 
                   threshold=0.1,
                   include_aa::Bool=false,
                   alpha::Real=0.1,
                   aa_color::Colorant=RGB(1.0, 1.0, 0.0),
                   diff_color::Colorant=RGB(1.0, 0.0, 0.0),
                   diff_color_alt::Union{Nothing, Colorant}=nothing,
                   diff_mask::Bool=false)
    
    # Handle default threshold
    actual_threshold::Float64 = threshold
    
    height, width = size(img1)
    
    # Validate inputs
    if size(img1) != size(img2)
        throw(ArgumentError("Image sizes do not match. Image 1 size: $(size(img1)), image 2 size: $(size(img2))"))
    end
    
    # Create properly initialized output array
    # Start with transparent pixels for diff_mask mode, or will be filled appropriately otherwise
    output = fill(RGBA{eltype(img1).parameters[1]}(0, 0, 0, 0), height, width)
    
    # Convert images to RGBA for processing
    img1_rgba = convert.(RGBA{Float64}, img1)
    img2_rgba = convert.(RGBA{Float64}, img2)
    
    # Check if images are identical
    if img1_rgba == img2_rgba
        if !diff_mask
            # Fill output with grayscale version
            for i in eachindex(output)
                output[i] = convert(eltype(output), draw_gray_pixel(img1_rgba[i], alpha))
            end
        end
        return (0, output)
    end
    
    # Maximum acceptable square distance between two colors
    # 35215 is the maximum possible value for the YIQ difference metric
    max_delta = 35215 * actual_threshold * actual_threshold
    
    diff_color_alt_actual = diff_color_alt === nothing ? diff_color : diff_color_alt
    diff = 0
    
    # Compare each pixel
    for y in 1:height
        for x in 1:width
            i = (y - 1) * width + (x - 1)  # Convert to 0-based linear index like JavaScript
            
            # Calculate color difference
            delta = img1_rgba[y, x] == img2_rgba[y, x] ? 0.0 : color_delta(img1_rgba[y, x], img2_rgba[y, x], i, false)
            
            # The color difference is above the threshold
            if abs(delta) > max_delta
                # Check if it's anti-aliasing
                is_excluded_aa = !include_aa && (
                    is_antialiased(img1_rgba, img2_rgba, x, y, width, height) || 
                    is_antialiased(img2_rgba, img1_rgba, x, y, width, height)
                )
                
                if is_excluded_aa
                    # Anti-aliasing detected; draw as aa_color
                    if !diff_mask
                        output[y, x] = convert(eltype(output), aa_color)
                    end
                else
                    # Substantial difference found
                    if delta < 0
                        output[y, x] = convert(eltype(output), diff_color_alt_actual)
                    else
                        output[y, x] = convert(eltype(output), diff_color)
                    end
                    diff += 1
                end
            elseif !diff_mask
                # Pixels are similar; draw background as grayscale
                output[y, x] = convert(eltype(output), draw_gray_pixel(img1_rgba[y, x], alpha))
            end
        end
    end
    
    return (diff, output)
end

"""
Check if a pixel is likely part of anti-aliasing.
Based on "Anti-aliased Pixel and Intensity Slope Detector" paper by V. Vysniauskas, 2009
"""
function is_antialiased(img::AbstractMatrix{RGBA{Float64}}, img2::AbstractMatrix{RGBA{Float64}}, x1::Int, y1::Int, width::Int, height::Int)
    x0 = max(x1 - 1, 1)
    y0 = max(y1 - 1, 1)
    x2 = min(x1 + 1, width)
    y2 = min(y1 + 1, height)
    
    pos_pixel = img[y1, x1]
    zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0
    min_delta = 0.0
    max_delta = 0.0
    min_x = 0
    min_y = 0
    max_x = 0
    max_y = 0
    
    # Go through 8 adjacent pixels
    for x in x0:x2
        for y in y0:y2
            if x == x1 && y == y1
                continue
            end
            
            # Brightness delta between center pixel and adjacent one (both from same image)
            pos_center = (y1 - 1) * width + (x1 - 1)  # Convert to 0-based index
            pos_adj = (y - 1) * width + (x - 1)  # Convert to 0-based index
            delta = color_delta(img[y1, x1], img[y, x], pos_center, true)
            
            # Count equal, darker and brighter adjacent pixels
            if delta == 0
                zeroes += 1
                # If found more than 2 equal siblings, it's definitely not anti-aliasing
                if zeroes > 2
                    return false
                end
            elseif delta < min_delta
                min_delta = delta
                min_x = x
                min_y = y
            elseif delta > max_delta
                max_delta = delta
                max_x = x
                max_y = y
            end
        end
    end
    
    # If there are no both darker and brighter pixels among siblings, it's not anti-aliasing
    if min_delta == 0 || max_delta == 0
        return false
    end
    
    # Check if darkest or brightest pixel has many siblings in both images
    return (has_many_siblings(img, min_x, min_y, width, height) && has_many_siblings(img2, min_x, min_y, width, height)) ||
           (has_many_siblings(img, max_x, max_y, width, height) && has_many_siblings(img2, max_x, max_y, width, height))
end

"""
Check if a pixel has 3+ adjacent pixels of the same color.
"""
function has_many_siblings(img::AbstractMatrix{RGBA{Float64}}, x1::Int, y1::Int, width::Int, height::Int)
    x0 = max(x1 - 1, 1)
    y0 = max(y1 - 1, 1)
    x2 = min(x1 + 1, width)
    y2 = min(y1 + 1, height)
    
    val = img[y1, x1]
    # Convert to 32-bit-like hash for comparison (similar to JavaScript Uint32Array)
    val_hash = hash((round(Int, red(val)*255), round(Int, green(val)*255), round(Int, blue(val)*255), round(Int, alpha(val)*255)))
    
    zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0
    
    # Go through 8 adjacent pixels
    for x in x0:x2
        for y in y0:y2
            if x == x1 && y == y1
                continue
            end
            # Use hash comparison instead of exact floating point comparison
            pixel_hash = hash((round(Int, red(img[y, x])*255), round(Int, green(img[y, x])*255), round(Int, blue(img[y, x])*255), round(Int, alpha(img[y, x])*255)))
            if val_hash == pixel_hash
                zeroes += 1
            end
            if zeroes > 2
                return true
            end
        end
    end
    return false
end

"""
Calculate color difference according to the paper "Measuring perceived color difference
using YIQ NTSC transmission color space in mobile applications" by Y. Kotsarenko and F. Ramos
"""
function color_delta(c1::RGBA{Float64}, c2::RGBA{Float64}, pos::Int, y_only::Bool)
    # Scale to 0-255 range to match JavaScript implementation
    r1, g1, b1, a1 = red(c1) * 255, green(c1) * 255, blue(c1) * 255, alpha(c1) * 255
    r2, g2, b2, a2 = red(c2) * 255, green(c2) * 255, blue(c2) * 255, alpha(c2) * 255
    
    dr = r1 - r2
    dg = g1 - g2
    db = b1 - b2
    da = a1 - a2
    
    if dr == 0 && dg == 0 && db == 0 && da == 0
        return 0.0
    end
    
    # Blend pixels with background if there's transparency
    if a1 < 255 || a2 < 255
        # Use the same background pattern as JavaScript
        k = pos * 4  # Convert to byte position like JavaScript
        rb = 48 + 159 * (k % 2)
        gb = 48 + 159 * (floor(Int, k / 1.618033988749895) % 2)
        bb = 48 + 159 * (floor(Int, k / 2.618033988749895) % 2)
        
        dr = (r1 * a1 - r2 * a2 - rb * da) / 255
        dg = (g1 * a1 - g2 * a2 - gb * da) / 255
        db = (b1 * a1 - b2 * a2 - bb * da) / 255
    end
    
    y = dr * 0.29889531 + dg * 0.58662247 + db * 0.11448223
    
    if y_only
        return y
    end
    
    i = dr * 0.59597799 - dg * 0.27417610 - db * 0.32180189
    q = dr * 0.21147017 - dg * 0.52261711 + db * 0.31114694
    
    delta = 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q
    
    # Encode whether the pixel lightens or darkens in the sign
    return y > 0 ? -delta : delta
end

"""
Draw a grayscale pixel blended with white.
"""
function draw_gray_pixel(pixel::RGBA{Float64}, alpha_blend::Real)
    r, g, b, a = red(pixel), green(pixel), blue(pixel), alpha(pixel)
    # Scale to 0-255 for calculation, then back to 0-1
    r_255, g_255, b_255, a_255 = r * 255, g * 255, b * 255, a * 255
    val_255 = 255 + (r_255 * 0.29889531 + g_255 * 0.58662247 + b_255 * 0.11448223 - 255) * alpha_blend * a_255 / 255
    
    # JavaScript uses integer truncation when assigning to Uint8Array
    val_uint8 = trunc(UInt8, val_255)
    val = val_uint8 / 255
    
    return RGBA(val, val, val, 1.0)
end

include("test_macro.jl")

end # module PixelMatch
