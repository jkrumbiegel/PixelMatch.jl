struct FailureRecord
    name::String
    status::Symbol
    num_pixels_diff::Union{Int,Nothing}
    ref_path::Union{String,Nothing}
    rec_path::Union{String,Nothing}
    diff_path::Union{String,Nothing}
    ref_size::Union{Tuple{Int,Int},Nothing}
    rec_size::Union{Tuple{Int,Int},Nothing}
end

mutable struct Collector
    lock::ReentrantLock
    records::Vector{FailureRecord}
end

const ACTIVE_COLLECTOR = Ref{Union{Nothing,Collector}}(nothing)

function _record_failure(; name, status, num_pixels_diff=nothing,
                         ref_path=nothing, rec_path=nothing, diff_path=nothing,
                         ref_size=nothing, rec_size=nothing)
    c = ACTIVE_COLLECTOR[]
    c === nothing && return
    exists(p) = p !== nothing && isfile(p) ? p : nothing
    rec = FailureRecord(name, status, num_pixels_diff,
                        exists(ref_path), exists(rec_path), exists(diff_path),
                        ref_size, rec_size)
    lock(c.lock) do
        push!(c.records, rec)
    end
    return
end

"""
    @pixelmatch_report [enabled=true] [out_file="pixelmatch-report.html"] begin
        ...
    end

Run the given block (typically containing `@test_pixelmatch` calls) and, if any of those
tests fail, write a self-contained HTML report of the failing comparisons to `out_file`.

The report embeds the reference, recorded and (where available) diff images so the file
can be opened on its own. It captures every failure mode, including size mismatches and
missing references, which produce no diff image.

When `enabled` is false, the block runs unchanged and no report is written. Gate `enabled`
on whatever condition you like, e.g. only generate the report on CI:

    @pixelmatch_report enabled=get(ENV, "CI", "false") == "true" begin ... end

Generation happens in the same process that runs the tests, so PixelMatch does not need
to be loadable from a separate step. Being a macro, it wraps the block in a `try`/`finally`
in place, adding no closure or stack frame. Calls to `@test_pixelmatch` outside an active
`@pixelmatch_report` block record nothing and behave exactly as before.

Evaluates to whatever the block evaluates to.

# Example
```julia
PixelMatch.@pixelmatch_report out_file=joinpath(@__DIR__, "pixelmatch-report.html") begin
    @test_pixelmatch "references/plot_a" render(fig_a)
    @test_pixelmatch "references/plot_b" render(fig_b)
end
```
"""
macro pixelmatch_report(args...)
    isempty(args) && error("@pixelmatch_report requires a block to run")
    body = last(args)
    enabled = true
    out_file = "pixelmatch-report.html"
    for kw in args[1:end-1]
        (kw isa Expr && kw.head === :(=)) ||
            error("@pixelmatch_report expects keyword arguments before the block, got $kw")
        key, val = kw.args[1], kw.args[2]
        if key === :enabled
            enabled = val
        elseif key === :out_file
            out_file = val
        else
            error("unknown keyword `$key` for @pixelmatch_report")
        end
    end
    quote
        local active = $(esc(enabled)) && ACTIVE_COLLECTOR[] === nothing
        local outfile = $(esc(out_file))
        local collector = active ? Collector(ReentrantLock(), FailureRecord[]) : nothing
        active && (ACTIVE_COLLECTOR[] = collector)
        try
            $(esc(body))
        finally
            if active
                ACTIVE_COLLECTOR[] = nothing
                if !isempty(collector.records)
                    write_report(outfile, collector.records)
                    @info "PixelMatch wrote a report of $(length(collector.records)) failing reference test(s) to $(abspath(outfile))"
                end
            end
        end
    end
end

const _REPORT_TEMPLATE = read(joinpath(@__DIR__, "report_template.html"), String)

write_report(path::AbstractString, records::AbstractVector{FailureRecord}) =
    open(io -> print(io, report_html(records)), path, "w")

function report_html(records::AbstractVector{FailureRecord})
    n = length(records)
    cards = IOBuffer()
    for r in records
        _print_card(cards, r)
    end
    return replace(_REPORT_TEMPLATE,
        "{{SUMMARY}}" => "$n failing reference test$(n == 1 ? "" : "s")",
        "{{CARDS}}" => String(take!(cards)))
end

function _print_card(io::IO, r::FailureRecord)
    statustext =
        r.status === :mismatch ? "$(r.num_pixels_diff) pixel$(r.num_pixels_diff == 1 ? "" : "s") differ" :
        r.status === :size_mismatch ? "size mismatch: reference $(_sz(r.ref_size)), recorded $(_sz(r.rec_size))" :
        "missing reference"

    has_ref = r.ref_path !== nothing
    has_rec = r.rec_path !== nothing
    has_diff = r.diff_path !== nothing
    default = has_diff ? "diff" : (has_rec ? "rec" : "ref")

    ref_dim = has_ref ? _png_display_size(r.ref_path) : nothing
    rec_dim = has_rec ? _png_display_size(r.rec_path) : nothing
    diff_dim = ref_dim !== nothing ? ref_dim : rec_dim

    print(io, """<section class="card">
<div class="card-head"><span class="name">$(_html_escape(r.name))</span><span class="status status-$(r.status)">$(_html_escape(statustext))</span></div>
<div class="controls">""")
    if has_ref && has_rec
        print(io, """<button type="button" data-role="toggle"$(has_diff ? "" : " class=\"active\"")>Showing Recorded</button>""")
    elseif has_rec
        print(io, """<button type="button" disabled>Recorded</button>""")
    elseif has_ref
        print(io, """<button type="button" disabled>Reference</button>""")
    end
    has_diff && print(io, """<button type="button" data-role="diff" class="active">Diff</button>""")
    print(io, """</div>
<div class="stage">""")
    has_ref && print(io, _img("ref", r.ref_path, default, ref_dim))
    has_rec && print(io, _img("rec", r.rec_path, default, rec_dim))
    has_diff && print(io, _img("diff", r.diff_path, default, diff_dim))
    print(io, """</div>
</section>
""")
end

function _img(view, path, default, dim)
    sizeattr = dim === nothing ? "" : " width=\"$(dim[1])\" height=\"$(dim[2])\""
    return """<img class="img-$view" data-view="$view" alt="$view"$sizeattr style="display:$(view == default ? "block" : "none")" src="$(_img_src(path))">"""
end

_img_src(path) = "data:image/png;base64," * Base64.base64encode(read(path))

const _PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

_beuint(b, i) = (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16) | (UInt32(b[i+2]) << 8) | UInt32(b[i+3])

"""
Display size of a PNG in CSS pixels, honoring the `pHYs` chunk so images saved at a
higher pixel density (e.g. 2× HiDPI renders) appear at their intended physical size.
Returns `(width, height)`, falling back to the raw pixel dimensions when no usable
`pHYs` information is present, or `nothing` if the file is not a parseable PNG.
"""
function _png_display_size(path)
    bytes = read(path)
    n = length(bytes)
    (n < 8 || @view(bytes[1:8]) != _PNG_SIGNATURE) && return nothing

    pxw = pxh = 0
    ppux = ppuy = 0
    unit = 0x00
    seen_ihdr = false
    pos = 9
    while pos + 7 <= n
        len = Int(_beuint(bytes, pos))
        data0 = pos + 8
        ctype = String(@view bytes[pos+4:pos+7])
        if ctype == "IHDR" && data0 + 7 <= n
            pxw = Int(_beuint(bytes, data0))
            pxh = Int(_beuint(bytes, data0 + 4))
            seen_ihdr = true
        elseif ctype == "pHYs" && data0 + 8 <= n
            ppux = Int(_beuint(bytes, data0))
            ppuy = Int(_beuint(bytes, data0 + 4))
            unit = bytes[data0 + 8]
            break
        elseif ctype == "IEND"
            break
        end
        pos = data0 + len + 4
    end
    seen_ihdr || return nothing

    if unit == 0x01 && ppux > 0 && ppuy > 0
        return (max(round(Int, pxw * 96 / (ppux * 0.0254)), 1),
                max(round(Int, pxh * 96 / (ppuy * 0.0254)), 1))
    end
    return (pxw, pxh)
end

_sz(t) = t === nothing ? "?" : "$(t[1])×$(t[2])"

function _html_escape(s)
    s = replace(string(s), "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    return s
end
