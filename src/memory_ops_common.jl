add_vptr!(ls::LoopSet, op::Operation) = add_vptr!(ls, op.ref)
add_vptr!(ls::LoopSet, mref::ArrayReferenceMeta) = add_vptr!(ls, mref.ref.array, vptr(mref))
function add_vptr!(ls::LoopSet, array::Symbol, vptrarray::Symbol = vptr(array))
    if !includesarray(ls, array)
        push!(ls.includedarrays, array)
        pushpreamble!(ls, Expr(:(=), vptrarray, Expr(:call, lv(:stridedpointer), array)))
    end
    nothing
end
function subset_vptr!(ls::LoopSet, vptr::Symbol, indnum::Int, ind::Integer)
    subsetvptr = Symbol(vptr, "_subset_$(indnum)_with_$(ind)##")
    pushpreamble!(ls, Expr(:(=), subsetvptr, Expr(:call, lv(:subsetview), vptr, Expr(:call, Expr(:curly, :Val, indnum)), ind)))
    subsetvptr
end

function array_reference_meta!(ls::LoopSet, array::Symbol, rawindices, elementbytes::Int = 8)
    vptrarray = vptr(array)
    add_vptr!(ls, array, vptrarray) # now, subset
    
    indices = Symbol[]
    loopedindex = Bool[]
    parents = Operation[]
    loopdependencies = Symbol[]
    reduceddeps = Symbol[]
    loopset = ls.loopsymbols
    for ind ∈ rawindices        
        if ind isa Integer # subset
            vptrarray = subset_vptr!(ls, vptrarray, length(indices) + 1, ind - 1)
            length(indices) == 0 && push!(indices, Symbol("##DISCONTIGUOUSSUBARRAY##"))
        elseif ind isa Symbol
            push!(indices, ind)
            if ind ∈ loopset
                push!(loopedindex, true)
                push!(loopdependencies, ind)
            else
                push!(loopedindex, false)
            end
        elseif ind isa Expr
            parent = add_operation!(ls, gensym(:indexpr), ind, elementbytes)
            pushparent!(parents, loopdependencies, reduceddeps, parent)
            # var = get(ls.opdict, ind, nothing)
            push!(indices, name(parent))#mangledvar(parent)
            push!(loopedindex, false)
        else
            throw("Unrecognized loop index: $ind.")
        end
    end
    (length(parents) != 0 && first(indices) !== Symbol("##DISCONTIGUOUSSUBARRAY##")) && pushfirst!(indices, Symbol("##DISCONTIGUOUSSUBARRAY##"))
    mref = ArrayReferenceMeta(ArrayReference( array, indices ), loopedindex, vptrarray)
    ArrayReferenceMetaPosition(mref, parents, loopdependencies, reduceddeps)
end
function tryrefconvert(ls::LoopSet, ex::Expr, elementbytes::Int = 8)::Tuple{Bool,ArrayReferenceMetaPosition}
    ya, yinds = if ex.head === :ref
        ref_from_ref(ex)
    elseif ex.head === :call
        f = first(ex.args)
        if f === :getindex
            ref_from_getindex(ex)
        elseif f === :setindex!
            ref_from_setindex(ex)
        else
            return false, NOTAREFERENCEMP
        end
    else
        return false, NOTAREFERENCEMP
    end
    true, array_reference_meta!(ls, ya, yinds, elementbytes)
end
