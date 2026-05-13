using Test
using PixelMatch
using PixelMatch: @test_pixelmatch_fails
using ColorTypes
using FileIO
using PNGFiles
using ReferenceTests
using MetaTesting: fails, nonpassing_results

PixelMatch.INTERACTIVE_MODE[] = false

# Helper function to read PNG images
function read_image(name::String)
    filepath = joinpath(@__DIR__, "fixtures", "$name.png")
    return load(filepath)
end

# Helper function to write PNG images (for debugging)
function write_image(name::String, image)
    filepath = joinpath(@__DIR__, "fixtures", "$name.png")
    save(filepath, image)
end

# Main test function that mirrors the JavaScript diffTest
function diff_test(img_path1::String, img_path2::String, diff_path::String, options::Dict, expected_mismatch::Int)    
    img1 = read_image(img_path1)
    img2 = read_image(img_path2)
    
    # Don't convert to Float64 - work with the native PNG format
    img1_processed = img1
    img2_processed = img2
    
    height, width = size(img1_processed)
    
    # Convert JavaScript options to Julia keyword arguments
    kwargs = Dict{Symbol, Any}()
    
    if haskey(options, "threshold")
        if options["threshold"] !== nothing
            kwargs[:threshold] = options["threshold"]
        end
    end
    
    if haskey(options, "alpha")
        kwargs[:alpha] = options["alpha"]
    end
    
    if haskey(options, "includeAA")
        kwargs[:include_aa] = options["includeAA"]
    end
    
    if haskey(options, "diffMask")
        kwargs[:diff_mask] = options["diffMask"]
    end
    
    if haskey(options, "aaColor")
        aa_color = options["aaColor"]
        kwargs[:aa_color] = RGBA(aa_color[1]/255, aa_color[2]/255, aa_color[3]/255, 1.0)
    end
    
    if haskey(options, "diffColor")
        diff_color = options["diffColor"]
        kwargs[:diff_color] = RGBA(diff_color[1]/255, diff_color[2]/255, diff_color[3]/255, 1.0)
    end
    
    if haskey(options, "diffColorAlt")
        diff_color_alt = options["diffColorAlt"]
        kwargs[:diff_color_alt] = RGBA(diff_color_alt[1]/255, diff_color_alt[2]/255, diff_color_alt[3]/255, 1.0)
    end
    
    # Test with output
    mismatch, output = pixelmatch(img1_processed, img2_processed; kwargs...)
    
    # Check results
    @test mismatch == expected_mismatch
    
    # Compare diff with expected diff
    expected_diff = read_image(diff_path)
    
    # Convert both to RGBA format to handle RGB vs RGBA mismatches
    output_rgba = RGBA.(output)
    expected_rgba = RGBA.(expected_diff)
    
    # Debug: save the generated diff for inspection
    if output_rgba != expected_rgba
        debug_path = diff_path * "_debug"
        write_image(debug_path, output_rgba)
        println("Mismatch in $diff_path - saved debug image as $debug_path.png")
    end
    
    @test output_rgba == expected_rgba
end

struct PNG
    path::String
end

Base.show(io::IO, ::MIME"image/png", p::PNG) = write(io, read(p.path))

@testset "PixelMatch.jl Tests" begin
    
    # Test all the exact same cases as in the JavaScript tests
    options = Dict("threshold" => 0.05)
    
    @testset "Image comparison tests" begin
        diff_test("1a", "1b", "1diff", options, 143)
        diff_test("1a", "1b", "1diffdefaultthreshold", Dict("threshold" => nothing), 106)
        diff_test("1a", "1b", "1diffmask", Dict("threshold" => 0.05, "includeAA" => false, "diffMask" => true), 143)
        diff_test("1a", "1a", "1emptydiffmask", Dict("threshold" => 0, "diffMask" => true), 0)
        
        diff_test("2a", "2b", "2diff", Dict(
            "threshold" => 0.05,
            "alpha" => 0.5,
            "aaColor" => [0, 192, 0],
            "diffColor" => [255, 0, 255]
        ), 12437)
        
        diff_test("3a", "3b", "3diff", options, 212)
        diff_test("4a", "4b", "4diff", options, 36049)
        diff_test("5a", "5b", "5diff", options, 6) # TODO: Fix anti-aliasing - currently gets 0
        diff_test("6a", "6b", "6diff", options, 51)
        diff_test("6a", "6a", "6empty", Dict("threshold" => 0), 0)
        diff_test("7a", "7b", "7diff", Dict("diffColorAlt" => [0, 255, 0]), 2448)
        diff_test("8a", "5b", "8diff", options, 32896)
    end
    
    @testset "Error handling tests" begin
        # Test size mismatch
        img1 = fill(RGBA(0.5, 0.5, 0.5, 1.0), 10, 10)
        img2 = fill(RGBA(0.5, 0.5, 0.5, 1.0), 5, 5)
        
        @test_throws ArgumentError pixelmatch(img1, img2)
    end

    @testset "@test_pixelmatch macro" begin
        foldername = "macro_test_temp"
        test_dir = joinpath(@__DIR__, foldername)
        mkpath(test_dir)
        
        # change out of the test folder just to see that the relative paths in @test_pixelmatch
        # are actually resolved relative to the macro placement and not pwd
        cd("..") do
            try
                test_image = read_image("1a")
                different_image = read_image("1b")
                diff_between_both = read_image("1diff")

                ref_path = joinpath(test_dir, "matching_ref.png")
                cp(joinpath(@__DIR__, "fixtures", "1a.png"), ref_path)
                
                @test_pixelmatch joinpath(foldername, "matching") test_image
                rec_path = joinpath(test_dir, "matching_rec.png")
                @test isfile(rec_path)
                diff_path = joinpath(test_dir, "matching_diff.png")
                @test !isfile(diff_path)

                # check if an object that can be shown as image/png also works
                @test_pixelmatch joinpath(foldername, "matching") PNG(joinpath(test_dir, "matching_ref.png"))

                # copy same image as before to a different name to get different rec/diff images
                ref_path2 = joinpath(test_dir, "different_ref.png")
                cp(joinpath(@__DIR__, "fixtures", "1a.png"), ref_path2)
                
                rec_path2 = joinpath(test_dir, "different_rec.png")
                diff_path2 = joinpath(test_dir, "different_diff.png")
                @test_pixelmatch_fails joinpath(foldername, "different") different_image 143 threshold=0.05

                @test_reference joinpath(@__DIR__, "html_diff_viewer") PixelMatch.html_diff_viewer(; name = "Different", num_pixels_diff = 143, ref_path = ref_path2, rec_path = rec_path2, diff_path = diff_path2, shorten_embeds = true)
                # whether the viewer works can only be checked manually
                if isinteractive() && Base.displayable(MIME("juliavscode/html"))
                    display(MIME("juliavscode/html"), PixelMatch.html_diff_viewer(; name = "Different", num_pixels_diff = 143, ref_path = ref_path2, rec_path = rec_path2, diff_path = diff_path2))
                end
                
                @test isfile(rec_path2)
                @test isfile(diff_path2)
                
                cp(diff_path2, joinpath(test_dir, "diff_ref.png"))
                @test_pixelmatch joinpath(foldername, "diff") diff_between_both

                # Regression test: a size mismatch between reference and recorded
                # must cause the macro's nested @test to fail.
                cp(joinpath(@__DIR__, "fixtures", "1a.png"), joinpath(test_dir, "size_mismatch_ref.png"))
                size_mismatch_image = fill(RGBA(0.5, 0.5, 0.5, 1.0), 5, 5)
                @test fails() do
                    @test_pixelmatch joinpath(foldername, "size_mismatch") size_mismatch_image
                end

                @testset "skip keyword" begin
                    # skip=true must not evaluate the image expression, must not write
                    # files, must not fail even when no reference exists, and must
                    # record a single Broken(:skipped) result.
                    rendered = Ref(false)
                    render_with_flag() = (rendered[] = true; test_image)
                    results = nonpassing_results() do
                        @test_pixelmatch joinpath(foldername, "skipped") render_with_flag() skip=true
                    end
                    @test rendered[] == false
                    @test !isfile(joinpath(test_dir, "skipped_rec.png"))
                    @test !isfile(joinpath(test_dir, "skipped_ref.png"))
                    broken_results = filter(r -> r isa Test.Broken, results)
                    @test length(broken_results) == 1
                    @test broken_results[1].test_type == :skipped

                    # skip=false must behave as if the keyword was absent.
                    cp(joinpath(@__DIR__, "fixtures", "1a.png"), joinpath(test_dir, "not_skipped_ref.png"))
                    @test_pixelmatch joinpath(foldername, "not_skipped") test_image skip=false
                    @test isfile(joinpath(test_dir, "not_skipped_rec.png"))
                end

                @testset "broken keyword" begin
                    # broken=true on a mismatching image must record Broken(:test)
                    # and must not fail the surrounding testset.
                    cp(joinpath(@__DIR__, "fixtures", "1a.png"), joinpath(test_dir, "broken_mismatch_ref.png"))
                    results = nonpassing_results() do
                        @test_pixelmatch joinpath(foldername, "broken_mismatch") different_image broken=true threshold=0.05
                    end
                    @test count(r -> r isa Test.Fail, results) == 0
                    @test count(r -> r isa Test.Error, results) == 0
                    broken_results = filter(r -> r isa Test.Broken, results)
                    @test length(broken_results) == 1
                    @test broken_results[1].test_type == :test

                    # broken=true on a matching image is an unexpected pass and must
                    # be recorded as Test.Error(:test_unbroken).
                    cp(joinpath(@__DIR__, "fixtures", "1a.png"), joinpath(test_dir, "broken_match_ref.png"))
                    results = nonpassing_results() do
                        @test_pixelmatch joinpath(foldername, "broken_match") test_image broken=true
                    end
                    error_results = filter(r -> r isa Test.Error, results)
                    @test length(error_results) == 1
                    @test error_results[1].test_type == :test_unbroken

                    # broken=false must behave as if the keyword was absent.
                    cp(joinpath(@__DIR__, "fixtures", "1a.png"), joinpath(test_dir, "broken_false_ref.png"))
                    @test_pixelmatch joinpath(foldername, "broken_false") test_image broken=false
                end

                @testset "skip and broken together is an error" begin
                    @test_throws "cannot set both skip and broken" begin
                        @test_pixelmatch joinpath(foldername, "skip_and_broken") test_image skip=true broken=true
                    end
                end
            finally
                rm(test_dir; recursive=true, force=true)
            end
        end
    end
end
