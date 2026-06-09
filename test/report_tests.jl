using Test
using PixelMatch
using PixelMatch: FailureRecord, Collector, ACTIVE_COLLECTOR, report_html, @pixelmatch_report, _png_display_size
using ColorTypes
using PNGFiles
using MetaTesting: fails, nonpassing_results

PixelMatch.INTERACTIVE_MODE[] = false

const _FIX = joinpath(@__DIR__, "fixtures")
_img(name) = PNGFiles.load(joinpath(_FIX, "$name.png"))
_count(pat, s) = length(collect(eachmatch(pat, s)))

function _synthetic_png(w, h; ppm=nothing)
    io = IOBuffer()
    be(x) = write(io, UInt8[(x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff])
    write(io, UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    be(13); write(io, codeunits("IHDR")); be(w); be(h); write(io, UInt8[8, 6, 0, 0, 0]); be(0)
    if ppm !== nothing
        be(9); write(io, codeunits("pHYs")); be(ppm); be(ppm); write(io, UInt8[1]); be(0)
    end
    be(0); write(io, codeunits("IEND")); be(0)
    path = tempname() * ".png"
    write(path, take!(io))
    return path
end

@testset "report" begin
    @testset "png display size" begin
        @test _png_display_size(joinpath(_FIX, "1a.png")) == (512, 256)
        @test _png_display_size(_synthetic_png(200, 100)) == (200, 100)
        @test _png_display_size(_synthetic_png(200, 100; ppm=7559)) == (100, 50)
        notpng = tempname() * ".png"; write(notpng, "not a png")
        @test _png_display_size(notpng) === nothing
    end

    @testset "failure recording" begin
        dir = mktempdir()
        c = Collector(ReentrantLock(), FailureRecord[])
        ACTIVE_COLLECTOR[] = c
        try
            mismatch_stem = joinpath(dir, "mismatch")
            cp(joinpath(_FIX, "1a.png"), mismatch_stem * "_ref.png")
            @test fails() do
                @test_pixelmatch mismatch_stem _img("1b") threshold = 0.05
            end

            size_stem = joinpath(dir, "sizemismatch")
            cp(joinpath(_FIX, "1a.png"), size_stem * "_ref.png")
            small = fill(RGBA(0.5, 0.5, 0.5, 1.0), 5, 5)
            @test fails() do
                @test_pixelmatch size_stem small
            end

            missing_stem = joinpath(dir, "missingref")
            @test fails() do
                @test_pixelmatch missing_stem _img("1a")
            end

            broken_stem = joinpath(dir, "brokencase")
            cp(joinpath(_FIX, "1a.png"), broken_stem * "_ref.png")
            nonpassing_results() do
                @test_pixelmatch broken_stem _img("1b") broken = true threshold = 0.05
            end

            pass_stem = joinpath(dir, "passcase")
            cp(joinpath(_FIX, "1a.png"), pass_stem * "_ref.png")
            @test_pixelmatch pass_stem _img("1a")
        finally
            ACTIVE_COLLECTOR[] = nothing
        end

        @test length(c.records) == 3
        byname = Dict(r.name => r for r in c.records)

        m = byname["mismatch"]
        @test m.status == :mismatch
        @test m.num_pixels_diff > 0
        @test m.diff_path !== nothing && isfile(m.diff_path)
        @test m.ref_path !== nothing && m.rec_path !== nothing

        s = byname["sizemismatch"]
        @test s.status == :size_mismatch
        @test s.diff_path === nothing
        @test s.rec_size == (5, 5)
        @test s.ref_size !== nothing && s.ref_size != (5, 5)

        mr = byname["missingref"]
        @test mr.status == :missing_ref
        @test mr.ref_path === nothing
        @test mr.rec_path !== nothing && isfile(mr.rec_path)
        @test mr.rec_size !== nothing
    end

    @testset "report_html structure" begin
        recs = [
            FailureRecord("alpha", :mismatch, 143,
                joinpath(_FIX, "1a.png"), joinpath(_FIX, "1b.png"), joinpath(_FIX, "1diff.png"),
                (200, 256), (200, 256)),
            FailureRecord("beta", :size_mismatch, nothing,
                joinpath(_FIX, "1a.png"), joinpath(_FIX, "2a.png"), nothing,
                (200, 256), (100, 100)),
            FailureRecord("gamma", :missing_ref, nothing,
                nothing, joinpath(_FIX, "1a.png"), nothing,
                nothing, (200, 256)),
        ]
        html = report_html(recs)

        @test occursin("alpha", html)
        @test occursin("beta", html)
        @test occursin("gamma", html)
        @test occursin("data:image/png;base64,", html)

        @test _count(r"<section class=\"card\"", html) == 3
        @test _count(r"<button type=\"button\" data-role=\"toggle\"", html) == 2
        @test _count(r"<button type=\"button\" data-role=\"diff\"", html) == 1
        @test _count(r"<button type=\"button\" disabled>", html) == 1
    end

    @testset "pixelmatch_report end-to-end" begin
        dir = mktempdir()

        report = joinpath(@__DIR__, "pixelmatch-report.html")
        cp(joinpath(_FIX, "1a.png"), joinpath(dir, "scatter_ref.png"))
        cp(joinpath(_FIX, "1a.png"), joinpath(dir, "resized_ref.png"))
        @test fails() do
            @pixelmatch_report enabled = true out_file = report begin
                @test_pixelmatch joinpath(dir, "scatter") _img("1b") threshold = 0.05
                @test_pixelmatch joinpath(dir, "resized") fill(RGBA(0.6, 0.6, 0.7, 1.0), 120, 200)
                @test_pixelmatch joinpath(dir, "brand_new") _img("3a")
            end
        end
        @test isfile(report)
        html = read(report, String)
        @test occursin("data:image/png;base64,", html)
        @test _count(r"<section class=\"card\"", html) == 3

        out_pass = joinpath(dir, "report_pass.html")
        pass_stem = joinpath(dir, "passing")
        cp(joinpath(_FIX, "1a.png"), pass_stem * "_ref.png")
        @pixelmatch_report enabled = true out_file = out_pass begin
            @test_pixelmatch pass_stem _img("1a")
        end
        @test !isfile(out_pass)

        out_disabled = joinpath(dir, "report_disabled.html")
        dis_stem = joinpath(dir, "disabled")
        cp(joinpath(_FIX, "1a.png"), dis_stem * "_ref.png")
        @test fails() do
            @pixelmatch_report enabled = false out_file = out_disabled begin
                @test_pixelmatch dis_stem _img("1b") threshold = 0.05
            end
        end
        @test !isfile(out_disabled)
        @test ACTIVE_COLLECTOR[] === nothing

        @test (@pixelmatch_report enabled = false begin
            41 + 1
        end) == 42
    end
end
