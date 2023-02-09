macro spread(expr::Expr)
    return esc(spreadconfig_to_expr(SpreadConfig(expr; source=__source__)))
end

macro spread(expriter::Expr, exprbody::Expr)
    return esc(spreadconfig_to_expr(SpreadConfig(expriter, exprbody; source=__source__)))
end

function spreadconfig_to_expr(spreadconfig::SpreadConfig)

    # Iterator Symbols
    x = spreadconfig.iterator.inner
    X = spreadconfig.iterator.outer
    if X === nothing
        X = gensymx(x)
    end
    itr = spreadconfig.iterator.iterator

    # Don't mutate function definition
    funcdef = deepcopy(spreadconfig.funcdef)

    # if you want to pass keyword arguments to overwrite variable in the body
    with_inits = false
    if funcdef !== nothing
        for (i, kwarg) in enumerate(get(funcdef, :kwargs, []))
            if kwarg == :__
                with_inits = true
                deleteat!(funcdef[:kwargs], i)
                break
            end
        end
    end

    # if have the iteration definition as a function argument
    with_argiter = false
    if funcdef !== nothing
        for arg_kwarg in (get(funcdef, :args, []), get(funcdef, :kwargs, []))
            for (i, arg) in enumerate(arg_kwarg)
                if arg == :_
                    with_argiter = true
                    arg_kwarg[i] = itr === nothing ? X : Expr(:kw, X, itr)
                end
            end
        end
    end

    expr = Expr(:block)
    push!(expr.args, spreadconfig.source)
    if !with_argiter
        push!(expr.args, :($X = $(itr)))
    end

    if with_inits
        # Inject keyword arguments to the function header
        if !haskey(funcdef, :kwargs)
            funcdef[:kwargs] = []
        end
        for arg in keys(spreadconfig.formulas)
            push!(funcdef[:kwargs], Expr(:kw, arg, nothing))
        end

        # A variable indicating if a keyword overwrite is empty
        for var in keys(spreadconfig.formulas)
            push!(expr.args, :($(reproducable_init_symbol(var)) = $var === nothing))
        end
    end

    # Populate all the formula code
    for cluster in spreadconfig.ordered_clusters
        push!(
            expr.args,
            formula_cluster_to_expr(
                subsample(spreadconfig.formulas, cluster), x, X; with_inits
            ),
        )
    end

    (lastvar, _) = last(spreadconfig.formulas)
    push!(expr.args, lastvar)

    # If we have a function, return the inner variables as named tuples
    if funcdef !== nothing
        push!(
            expr.args,
            Expr(:tuple, [Expr(:(=), var, var) for var in keys(spreadconfig.formulas)]...),
        )

        funcdef[:body] = expr
        return ExprTools.combinedef(funcdef)

        # Else just throw them in the sourrounding scope
    else
        return expr
    end
end
