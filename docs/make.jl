using Documenter, LITS
const PSYPATH = dirname(pathof(LITS))

makedocs(
    modules = [LITS],
    format = Documenter.HTML(mathengine = Documenter.MathJax()),
    sitename = "LITS.jl",
    pages = Any[ # Compat: `Any` for 0.4 compat
        "Home" => "index.md",
        # "User Guide" => "man/guide.md",
        "Tutorials" => Any[
            "Tutorial 0: Data Creation" => "Examples/example_data.md",
            "Tutorial 1: OMIB" => "Examples/example_OMIB.md",
            "Tutorial 2: Dynamic Lines" => "Examples/example_lines.md",
        ],
        "Models" => Any[
            "Network" => "Models/network.md",
            "Reference Frames" => "Models/srf.md",
            "Generator" => "Models/gens.md",
            "Inverter" => "Models/inverters.md",
            "Small Signal" => "Models/small.md",
        ],
    ],
)

deploydocs(
    repo = "github.com/NREL-SIIP/PowerSimulationsDynamics.jl",
    branch = "gh-pages",
    target = "build",
    #deps = Deps.pip("pygments", "mkdocs", "python-markdown-math"),
    make = nothing,
)
