# Display, saving and browser preview.

Base.show(io::IO, ::MIME"image/svg+xml", fig::Figure) = svg(io, fig)

function Base.show(io::IO, fig::Figure)
    n = length(fig.axes)
    print(io, "Figure(", fig.size[1], "×", fig.size[2], ", ", n, n == 1 ? " axis)" : " axes)")
end

function Base.show(io::IO, ax::Axis)
    print(io, "Axis(rows ", ax.rows, ", cols ", ax.cols, ", ", length(ax.plots), " plots)")
end

"""
    save(path, fig; standalone=false) -> path

Write `fig` to `path` as SVG (`.svg`), as an HTML page holding the SVG
(`.html`), as a TikZ picture for LaTeX (`.tex`, see [`tikz`](@ref)), or as
a CeTZ drawing for Typst (`.typ`, see [`cetz`](@ref)). `standalone = true`
makes a `.tex` or `.typ` file a document that compiles on its own. For PNG
or PDF, compile the `.tex` file or convert the SVG with a tool such as
`rsvg-convert` or Inkscape.
"""
function save(path::AbstractString, fig::Figure; standalone::Bool=false)
    ext = lowercase(splitext(path)[2])
    if ext == ".svg"
        open(io -> svg(io, fig), path, "w")
    elseif ext == ".html" || ext == ".htm"
        open(path, "w") do io
            print(io, "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>")
            _esc(io, isempty(fig.title) ? "Figure" : fig.title)
            print(io, "</title></head>\n<body style=\"margin:0;background:#fff\">\n")
            svg(io, fig)
            print(io, "</body></html>\n")
        end
    elseif ext == ".tex"
        open(io -> tikz(io, fig; standalone), path, "w")
    elseif ext == ".typ"
        open(io -> cetz(io, fig; standalone), path, "w")
    else
        throw(ArgumentError("save writes .svg, .html, .tex or .typ files; got \"$path\""))
    end
    return path
end

"""
    preview(fig) -> path

Write `fig` to a temporary HTML file and open it in the default browser.
"""
function preview(fig::Figure)
    path = save(tempname() * ".html", fig)
    cmd = Sys.iswindows() ? `cmd /c start "" $path` :
          Sys.isapple() ? `open $path` : `xdg-open $path`
    run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
    return path
end

# In an interactive session, displaying a Figure goes to the first display
# that can show SVG (VS Code's plot pane, IJulia, ...); in a plain terminal
# REPL it opens in the browser instead of printing a summary.
struct BrowserDisplay <: AbstractDisplay end

function Base.display(::BrowserDisplay, fig::Figure)
    for d in reverse(Base.Multimedia.displays)
        d isa BrowserDisplay && continue
        d isa TextDisplay && continue
        nameof(typeof(d)) === :REPLDisplay && continue
        displayable(d, MIME"image/svg+xml"()) && return display(d, MIME"image/svg+xml"(), fig)
    end
    try
        preview(fig)
    catch err
        @warn "could not open a browser; use save(\"figure.svg\", fig)" exception = err
    end
    return nothing
end

function __init__()
    if isinteractive() && !any(d -> d isa BrowserDisplay, Base.Multimedia.displays)
        pushdisplay(BrowserDisplay())
    end
    return nothing
end
