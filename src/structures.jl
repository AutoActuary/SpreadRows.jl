struct SheetIterator
    inner::Symbol
    outer::Symbol
    iterator
end

struct SheetFormula
    expr
    broadcast::Bool
    line::Union{LineNumberNode, Nothing}
end


mutable struct SheetConfig
    iterator::Union{SheetIterator, Nothing}
    funcdef::Union{Dict, Nothing}
    loopdef::Pair{Symbol, Any}
    formulas::OrderedDict{Symbol, SheetFormula}
    graph::DiGraph{Symbol}
    ordered_clusters::Vector{Vector{Symbol}}
    source::Union{LineNumberNode, Nothing}
end


struct __PROTECTVERSION__ end
SheetConfig(__PROTECTVERSION__, expr; source=nothing) = begin
    MacroTools.splitdef(expr)
    
end
SheetConfig(__PROTECTVERSION__, expr1, expr2; source=nothing) = begin

end


SheetConfig(exprloop::Expr,
            exprbody::Expr;
            source::Union{LineNumberNode, Nothing}=nothing) = begin

    loopdef = expr_to_loop_definition(exprloop)
    x, _ = loopdef
    formulas = expr_to_formulas(exprbody, x; line=source)
    graph = formulas_to_digraph(formulas)
    ordered_clusters = generate_calculation_sequence(graph; preferred_sequence=keys(formulas))

    SheetConfig(nothing, nothing, loopdef, formulas, graph, ordered_clusters, source)
end


struct CalculationSequenceError <: Exception
    var::String
end
CalculationSequenceError() = begin
    errmessage = join(split(
        """
        The `@T` macro was unable to order the given formula(s) in a way that 
        resulted in a correct calculation flow using the current heuristics. 
        Note that `@T` cannot yet take indexing into account with (a) a mix 
        of forwards `A[t+1]` and backwards `A[t-1]` referencing, (b) with 
        runtime variables like the `c` in `A[c+t]`, (c) with nonlinear t 
        indexing like `A[t^2-3t]`, and (d) with non-t indexing like A[34].
        """, "\n"
    ))

    CalculationSequenceError(errmessage)
end

