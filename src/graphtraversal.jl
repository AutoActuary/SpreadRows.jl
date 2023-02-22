struct DiNode{T}
    in::Set{T}
    out::Set{T}

    DiNode{T}() where {T} = new{T}(Set{T}(), Set{T}())
end

struct DiGraph{T}
    nodedict::Dict{T,DiNode{T}}
    DiGraph{T}() where {T} = new{T}(Dict{T,DiNode{T}}())
end

function traversalsequence(graph::DiGraph{T}; preferred_order=nothing) where {T}
    return traversalsequence!(deepcopy(graph); preferred_order=preferred_order)
end

function traversalsequence!(graph::DiGraph{T}; preferred_order=nothing) where {T}
    order_lookup = DefaultDict{T,Int}(
        typemax(Int),
        (
            node => order for
            (order, node) in enumerate(preferred_order !== nothing ? preferred_order : [])
        )...,
    )
    head_seq = Vector{T}()
    tail_seq = Vector{T}()
    head_queue = SortedSet{Tuple{Int,T}}() # store order and item
    tail_queue = SortedSet{Tuple{Int,T}}() # store order and item
    strong_clusters = Dict{T,SortedSet{Tuple{Int,T}}}()

    # Functionality to pop from the head or tail queue
    pop_head_queue!() = last(pop!(head_queue))
    pop_tail_queue!() = begin
        delete!(
            tail_queue,
            begin
                item = last(tail_queue)
            end,
        )
        last(item)
    end

    # Functionality to add to the head or tail queue
    function add_to_queue_if_root_or_leaf_and_prune_graph!(id)
        if length(graph.nodedict[id].in) == 0
            push!(head_queue, (order_lookup[id], id))
        elseif length(graph.nodedict[id].out) == 0
            push!(tail_queue, (order_lookup[id], id))
        end
    end

    # Find cyclic nodes (not leaves or roots allowed -- pre-trimmed branches)
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

    # Merge group of ids (like cyclic nodes) into a single super node
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
        strong_clusters[idₙ] = union!(
            get(strong_clusters, idₙ, SortedSet{Tuple{Int,T}}()),
            ((order_lookup[id], id) for id in ids),
        )

        # merge cluster with other strong clusters
        for idₘ in setdiff!(ids ∩ keys(strong_clusters), [idₙ])
            strong_clusters[idₙ] = union!(strong_clusters[idₙ], pop!(strong_clusters, idₘ))
        end

        return idₙ
    end

    # The traversal algorithm
    for (id, node) in graph.nodedict
        add_to_queue_if_root_or_leaf_and_prune_graph!(id)
    end

    while (length(graph.nodedict) != 0)
        if length(head_queue) == 0 && length(tail_queue) == 0
            # find a cycle and merge it
            seq = find_cycle_in_trimmed_graph()
            idₙ = merge_ids_in_graph!(seq)
            add_to_queue_if_root_or_leaf_and_prune_graph!(idₙ)

        else
            idᵢ = isempty(head_queue) ? pop_tail_queue!() : pop_head_queue!()
            nodeᵢ = get(graph.nodedict, idᵢ, nothing)
            nodeᵢ === nothing && continue

            # trim either a root or a leaf
            if length(nodeᵢ.in) == 0
                push!(head_seq, idᵢ)
                for idⱼ in nodeᵢ.out
                    pop!(graph.nodedict[idⱼ].in, idᵢ)
                    add_to_queue_if_root_or_leaf_and_prune_graph!(idⱼ)
                end

            elseif length(nodeᵢ.out) == 0
                insert!(tail_seq, 1, idᵢ)
                for idⱼ in nodeᵢ.in
                    pop!(graph.nodedict[idⱼ].out, idᵢ)
                    add_to_queue_if_root_or_leaf_and_prune_graph!(idⱼ)
                end
            end

            pop!(graph.nodedict, idᵢ)
        end
    end

    sequence = [
        last.(get(strong_clusters, i, [(nothing, i)])) for
        i in Iterators.flatten((head_seq, tail_seq))
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
