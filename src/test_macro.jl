"""
    @test_pixelmatch name image [keyword args...]

Compare an image against a reference file using PixelMatch. The `name` should be
the path stem without extension (`_suffix.png` is added automatically).

Files created:
- `name_ref.png` - reference image
- `name_rec.png` - recorded/actual image (when test runs)
- `name_diff.png` - diff image (when images differ)

If the reference doesn't exist, it will be created. If images differ, an
interactive HTML diff viewer is shown (when available in VSCode) and the
user is prompted to update the reference.

Use `JULIA_REFERENCETESTS_UPDATE=true` to force-update all references without prompting.

Supports the same `skip=cond` and `broken=cond` keyword arguments as `Test.@test`:
- `skip=true` does not evaluate `image` and records a skipped test.
- `broken=true` expects the image to differ from the reference; if it actually
  matches, the test is recorded as an unexpected pass (`Error`).

# Example
```julia
@test_pixelmatch "references/my_plot" render(fig)
@test_pixelmatch "references/wip"     render(fig) broken=true
@test_pixelmatch "references/slow"    render(fig) skip=Sys.iswindows()
```
"""
macro test_pixelmatch(name, expr, kwargs...)
    dir = Base.source_dir()
    skip_ex, broken_ex, other_kws = _extract_skip_broken(kwargs)
    quote
        _test_pixelmatch_dispatch(abspath(joinpath($dir, $(esc(name)))), $(esc(:(() -> $expr)));
            skip = $(esc(skip_ex)),
            broken = $(esc(broken_ex)),
            $(map(esc, other_kws)...))
    end
end

macro test_pixelmatch_fails(name, expr, numpixels, kwargs...)
    dir = Base.source_dir()
    quote
        test_pixel_mismatch = $(esc(numpixels))
        _test_pixelmatch(abspath(joinpath($dir, $(esc(name)))), $(esc(expr)); $(esc.(kwargs)...), test_pixel_mismatch)
    end
end

function _extract_skip_broken(kwargs)
    skip_ex = false
    broken_ex = false
    other = Any[]
    for kw in kwargs
        if kw isa Expr && kw.head === :(=) && kw.args[1] === :skip
            skip_ex = kw.args[2]
        elseif kw isa Expr && kw.head === :(=) && kw.args[1] === :broken
            broken_ex = kw.args[2]
        else
            push!(other, kw)
        end
    end
    return skip_ex, broken_ex, other
end

function _test_pixelmatch_dispatch(path_stem::String, render; skip::Bool = false, broken::Bool = false, kwargs...)
    if skip && broken
        error("invalid @test_pixelmatch call: cannot set both skip and broken keywords")
    end
    name = basename(path_stem)
    if skip
        Test.@testset "$name" begin
            Test.@test true skip=true
        end
        return
    end
    _test_pixelmatch(path_stem, render(); broken, kwargs...)
end

function _test_pixelmatch(path_stem::String, obj_to_record; test_pixel_mismatch::Union{Integer,Nothing} = nothing, broken::Bool = false, kwargs...)
    update = tryparse(Bool, get(ENV, "JULIA_REFERENCETESTS_UPDATE", "false")) === true
    
    ref_path = path_stem * "_ref.png"
    rec_path = path_stem * "_rec.png"
    diff_path = path_stem * "_diff.png"
    
    name = basename(path_stem)
    mkpath(dirname(path_stem))

    if obj_to_record isa AbstractMatrix{<:Colorant}
        PNGFiles.save(rec_path, obj_to_record)
    else
        open(rec_path, "w") do io
            show(io, MIME"image/png"(), obj_to_record)
        end
    end
    recorded = PNGFiles.load(rec_path)

    # for running the tests locally where isinteractive() returns true
    interactive = INTERACTIVE_MODE[] && isinteractive()

    Test.@testset "$name" begin
        reference_exists = isfile(ref_path)

        if !reference_exists
            if interactive || update
                @info "Creating missing reference image: $ref_path"
                cp(rec_path, ref_path; force = true)
            else
                Test.@test reference_exists
            end
        else
            # Load reference image
            img_ref = PNGFiles.load(ref_path)

            if size(img_ref) != size(recorded)
                if update
                    @info "Reference size $(size(img_ref)) does not match recorded size $(size(recorded)) and JULIA_REFERENCETESTS_UPDATE=true, updating reference image"
                    PNGFiles.save(ref_path, recorded)
                else
                    Test.@test size(img_ref) == size(recorded) broken=broken
                end
            else
                # Compare images using PixelMatch
                num_pixels_diff, diff_image = pixelmatch(img_ref, recorded; kwargs...)

                if test_pixel_mismatch !== nothing
                    test_pixel_mismatch <= 0 && error("The number of expected mismatching pixels must be larger than zero, was $test_pixel_mismatch")
                    Test.@test test_pixel_mismatch == num_pixels_diff broken=broken
                    PNGFiles.save(diff_path, diff_image)
                else
                    if num_pixels_diff > 0
                        # Save diff image
                        PNGFiles.save(diff_path, diff_image)

                        if !broken
                            # Print paths for inspection
                            println("Reference test failed: $name")
                            println("  Reference: $ref_path")
                            println("  Recorded:    $rec_path")
                            println("  Diff:      $diff_path")
                            println("  Pixels different: $num_pixels_diff")
                        end

                        if update
                            @info "JULIA_REFERENCETESTS_UPDATE=true, updating reference image"
                            cp(rec_path, ref_path; force = true)
                        elseif interactive && !broken
                            # Display HTML diff viewer if available
                            if Base.displayable(MIME("juliavscode/html"))
                                display(MIME("juliavscode/html"), html_diff_viewer(; name, num_pixels_diff, ref_path, rec_path, diff_path))
                            end
                            print("Replace reference with recorded result? (y/n): ")
                            response = readline()
                            if lowercase(strip(response)) == "y"
                                cp(rec_path, ref_path; force = true)
                                @info "Reference image updated."
                            else
                                Test.@test num_pixels_diff == 0
                            end
                        else
                            Test.@test num_pixels_diff == 0 broken=broken
                        end
                    else
                        Test.@test num_pixels_diff == 0 broken=broken
                    end
                end
            end
        end
    end
end

function html_diff_viewer(; name, num_pixels_diff, ref_path, rec_path, diff_path, shorten_embeds = false)
    # Convert images to base64 for HTML display
    ref_b64 = Base64.base64encode(read(ref_path))
    rec_b64 = Base64.base64encode(read(rec_path))
    diff_b64 = Base64.base64encode(read(diff_path))

    if shorten_embeds
        ref_b64 = first(ref_b64, 100)
        rec_b64 = first(rec_b64, 100)
        diff_b64 = first(diff_b64, 100)
    end

    html_content = """
    <div style="font-family: Arial, sans-serif; padding: 20px;">
        <h3>Image Comparison Failed: $(name)</h3>
        <p><strong>Pixels different:</strong> $num_pixels_diff</p>
        
        <div style="margin: 10px 0;">
            <button onclick="toggleRecordedReference()" id="btn-toggle" style="margin-right: 10px; padding: 8px 16px; background: #6c757d; color: white; border: none; border-radius: 4px; cursor: pointer;">Show Recorded</button>
            <button onclick="showDiff()" id="btn-diff" style="padding: 8px 16px; background: #dc3545; color: white; border: none; border-radius: 4px; cursor: pointer;">Diff</button>
        </div>
        
        <div style="border: 2px solid #ddd; border-radius: 8px; padding: 10px; background: #f8f9fa; max-width: 100%; overflow: auto;">
            <img id="img-recorded" src="data:image/png;base64,$rec_b64" style="max-width: 100%; height: auto; display: none;" />
            <img id="img-reference" src="data:image/png;base64,$ref_b64" style="max-width: 100%; height: auto; display: none;" />
            <img id="img-diff" src="data:image/png;base64,$diff_b64" style="max-width: 100%; height: auto; display: block;" />
        </div>
        
        <script>
            let showingRecorded = true;
            let showingDiff = true;
            
            function updateToggleButton() {
                if (showingDiff) {
                    document.getElementById('btn-toggle').textContent = showingRecorded ? 'Show Recorded' : 'Show Reference';
                } else {
                    document.getElementById('btn-toggle').textContent = showingRecorded ? 'Showing Recorded' : 'Showing Reference';
                }
            }
            
            function toggleRecordedReference() {
                if (showingDiff) {
                    // If showing diff, switch back to current recorded/reference view without toggling
                    document.getElementById('img-diff').style.display = 'none';
                    document.getElementById('btn-diff').style.background = '#6c757d';
                    showingDiff = false;
                    
                    // Show current state (don't toggle)
                    if (showingRecorded) {
                        document.getElementById('img-recorded').style.display = 'block';
                        document.getElementById('img-reference').style.display = 'none';
                    } else {
                        document.getElementById('img-recorded').style.display = 'none';
                        document.getElementById('img-reference').style.display = 'block';
                    }
                } else {
                    // Normal toggle between recorded and reference
                    if (showingRecorded) {
                        // Switch to reference
                        document.getElementById('img-recorded').style.display = 'none';
                        document.getElementById('img-reference').style.display = 'block';
                        showingRecorded = false;
                    } else {
                        // Switch to recorded
                        document.getElementById('img-reference').style.display = 'none';
                        document.getElementById('img-recorded').style.display = 'block';
                        showingRecorded = true;
                    }
                }
                
                updateToggleButton();
                document.getElementById('btn-toggle').style.background = '#007acc';
            }
            
            function showDiff() {
                // Hide recorded/reference images
                document.getElementById('img-recorded').style.display = 'none';
                document.getElementById('img-reference').style.display = 'none';
                document.getElementById('img-diff').style.display = 'block';
                
                // Update button styles
                document.getElementById('btn-toggle').style.background = '#6c757d';
                document.getElementById('btn-diff').style.background = '#dc3545';
                showingDiff = true;
            }
            
            // Initialize button text
            updateToggleButton();
        </script>
    </div>
    """

    return html_content
end
