struct DiNode{T}
    in::Set{T}
    out::Set{T}

    DiNode{T}() where {T} = new{T}(Set{T}(), Set{T}())
end

struct DiGraph{T}
    nodedict::Dict{T,DiNode{T}}
    DiGraph{T}() where {T} = new{T}(Dict{T,DiNode{T}}())
end

traversalsequence(graph::DiGraph{T}) where {T} = traversalsequence!(deepcopy(graph))

function traversalsequence!(graph::DiGraph{T}) where {T}
    headseq = Vector{T}()
    tailseq = Vector{T}()
    queue = Vector{T}() # Ordered set is better
    strongclusters = Dict{T,Set{T}}()

    function add_to_queue_if_root_or_leaf_and_prune_graph!(id)
        if length(graph.nodedict[id].in) * length(graph.nodedict[id].out) == 0
            push!(queue, id)
        end
    end

    # Only valid if there are no branches or roots left
    function find_cycle_in_trimmed_graph()
        id = first(keys(graph.nodedict))

        seqset = Set{T}()
        seq = Vector{T}() # replacement for an ordered set

        idᵢ = id
        while !(idᵢ ∈ seqset)
            push!(seqset, idᵢ)
            push!(seq, idᵢ)
            idᵢ = first(graph.nodedict[idᵢ].out)
        end

        # Only keep the cyclic part
        for (i, idⱼ) in enumerate(seq)
            if idⱼ == idᵢ
                return seq[i:end]
            end
        end

        return raise(
            ErrorException(
                "Could not find cycle in graph.nodedict $(graph.nodedict) starting from $(id)",
            ),
        )
    end

    # for a group of ids merge together into single node
    function merge_ids_in_graph!(ids)
        idₙ = ids[1] # reuse the first ID
        nodeₙ = DiNode{T}()

        for idᵢ in ids
            nodeᵢ = graph.nodedict[idᵢ]

            for idⱼ in nodeᵢ.out
                if idⱼ != idₙ
                    push!(nodeₙ.out, idⱼ)
                    pop!(graph.nodedict[idⱼ].in, idᵢ)
                    push!(graph.nodedict[idⱼ].in, idₙ)
                end
            end

            for idⱼ in nodeᵢ.in
                if idⱼ != idₙ
                    push!(nodeₙ.in, idⱼ)
                    pop!(graph.nodedict[idⱼ].out, idᵢ)
                    push!(graph.nodedict[idⱼ].out, idₙ)
                end
            end

            # remove idᵢ from collective histroy
            pop!(graph.nodedict, idᵢ)
            if idᵢ ∈ nodeₙ.out
                pop!(nodeₙ.out, idᵢ)
            end
            if idᵢ ∈ nodeₙ.in
                pop!(nodeₙ.in, idᵢ)
            end
        end

        graph.nodedict[idₙ] = nodeₙ
        strongclusters[idₙ] = Set{T}(ids) ∪ get(strongclusters, idₙ, [])

        # merge cluster with other strong clusters
        for idₘ in setdiff!(ids ∩ keys(strongclusters), [idₙ])
            push!(strongclusters[idₙ], pop!(strongclusters, idₘ)...)
        end

        return idₙ
    end

    for (id, node) in graph.nodedict
        add_to_queue_if_root_or_leaf_and_prune_graph!(id)
    end

    while (length(graph.nodedict) != 0)
        if length(queue) == 0
            # find a cycle and merge it
            seq = find_cycle_in_trimmed_graph()
            idₙ = merge_ids_in_graph!(seq)
            add_to_queue_if_root_or_leaf_and_prune_graph!(idₙ)

        else
            idᵢ = pop!(queue)
            nodeᵢ = get(graph.nodedict, idᵢ, nothing)
            nodeᵢ === nothing && continue

            # trim either a root or a branch
            if length(nodeᵢ.in) == 0
                push!(headseq, idᵢ)
                for idⱼ in nodeᵢ.out
                    pop!(graph.nodedict[idⱼ].in, idᵢ)
                    add_to_queue_if_root_or_leaf_and_prune_graph!(idⱼ)
                end

            elseif length(nodeᵢ.out) == 0
                insert!(tailseq, 1, idᵢ)
                for idⱼ in nodeᵢ.in
                    pop!(graph.nodedict[idⱼ].out, idᵢ)
                    add_to_queue_if_root_or_leaf_and_prune_graph!(idⱼ)
                end
            end

            pop!(graph.nodedict, idᵢ)
        end
    end

    sequence = [
        collect(get(strongclusters, i, (i,))) for i in Iterators.flatten((headseq, tailseq))
    ]
    return sequence
end

function DiGraph(edges::Vector{<:Union{Vector{T},Tuple{T,T}}}) where {T}
    graph = DiGraph{T}()
    for (i, j) in edges
        if !haskey(graph.nodedict, i)
            graph.nodedict[i] = DiNode{T}()
        end
        if !haskey(graph.nodedict, j)
            graph.nodedict[j] = DiNode{T}()
        end

        push!(graph.nodedict[i].out, j)
        push!(graph.nodedict[j].in, i)
    end

    return graph
end

function DiGraph(mapping::Dict{T,<:Union{Vector{T},Set{T}}}) where {T}
    graph = DiGraph{T}()

    for (i, outs) in mapping
        if !haskey(graph.nodedict, i)
            graph.nodedict[i] = DiNode{T}()
        end

        for j in outs
            if !haskey(graph.nodedict, j)
                graph.nodedict[j] = DiNode{T}()
            end

            push!(graph.nodedict[i].out, j)
            push!(graph.nodedict[j].in, i)
        end
    end

    return graph
end
