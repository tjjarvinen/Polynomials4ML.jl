"""
complex spherical harmonics
"""
struct CYlmBasis{T}
	alp::ALPolynomials{T}
   # ----------------------------
	pool::ArrayCache{Complex{T}, 1}
   ppool::ArrayCache{Complex{T}, 2}
	pool_d::ArrayCache{SVector{3, Complex{T}}, 1}
   ppool_d::ArrayCache{SVector{3, Complex{T}}, 2}
end

CYlmBasis(maxL::Integer, T::Type=Float64) = 
      CYlmBasis(ALPolynomials(maxL, T))

CYlmBasis(alp::ALPolynomials{T}) where {T} = 
      CYlmBasis(alp, 
		         ArrayCache{Complex{T}, 1}(), 
               ArrayCache{Complex{T}, 2}(), 
               ArrayCache{SVector{3, Complex{T}}, 1}(), 
               ArrayCache{SVector{3, Complex{T}}, 2}())

Base.show(io::IO, basis::CYlmBasis) = 
      print(io, "CYlmBasis(L=$(maxL(basis)))")

"""
max L degree for which the alp coefficients have been precomputed
"""
maxL(sh::CYlmBasis) = sh.alp.L

_valtype(sh::CYlmBasis{T}, x::AbstractVector{S}) where {T <: Real, S <: Real} = 
			Complex{promote_type(T, S)}

_gradtype(sh::CYlmBasis{T}, x::AbstractVector{S})  where {T <: Real, S <: Real} = 
			SVector{3, Complex{promote_type(T, S)}}

import Base.==
==(B1::CYlmBasis, B2::CYlmBasis) =
		(B1.alp == B2.alp) && (typeof(B1) == typeof(B2))

Base.length(basis::CYlmBasis) = sizeY(maxL(basis))


# ---------------------- FIO

# write_dict(SH::CYlmBasis{T}) where {T} =
# 		Dict("__id__" => "ACE_CYlmBasis",
# 			  "T" => write_dict(T),
# 			  "maxL" => maxL(SH))

# read_dict(::Val{:ACE_CYlmBasis}, D::Dict) =
# 		CYlmBasis(D["maxL"], read_dict(D["T"]))



# ---------------------- Indexing

"""
`sizeY(maxL):`
Return the size of the set of spherical harmonics ``Y_{l,m}(θ,φ)`` of
degree less than or equal to the given maximum degree `maxL`
"""
sizeY(maxL) = (maxL + 1) * (maxL + 1)

"""
`index_y(l,m):`
Return the index into a flat array of real spherical harmonics `Y_lm`
for the given indices `(l,m)`. `Y_lm` are stored in l-major order i.e.
```
	[Y(0,0), Y(1,-1), Y(1,0), Y(1,1), Y(2,-2), ...]
```
"""
index_y(l::Integer, m::Integer) = m + l + (l*l) + 1

"""
Inverse of `index_y`: given an index into a vector of Ylm values, return the 
`l, m` indices.
"""
function idx2lm(i::Integer) 
	l = floor(Int, sqrt(i-1) + 1e-10)
	m = i - (l + (l*l) + 1)
	return l, m 
end 


# ---------------------- evaluation interface code 

function evaluate(basis::CYlmBasis, R::AbstractVector{<: Real})
	Y = acquire!(basis.pool, length(basis), _valtype(basis, R))
	evaluate!(parent(Y), basis, R)
	return Y 
end

function evaluate!(Y, basis::AbstractCYlmBasis, R::AbstractVector{<: Real})
	@assert length(R) == 3
	L = maxL(basis)
	S = cart2spher(R) 
	P = evaluate(basis.alp, S)
	cYlm!(Y, maxL(basis), S, P)
	release!(P)
	return Y
end


# function ACE.evaluate_d(SH::AbstractCYlmBasis, R::AbstractVector)
# 	B, dB = evaluate_ed(SH, R) 
# 	release!(B)
# 	return dB 
# end 

# function ACE.evaluate_ed(SH::AbstractCYlmBasis, R::AbstractVector)
# 	Y = acquire!(SH.B_pool, length(SH), _valtype(SH, R))
# 	dY = acquire!(SH.dB_pool, length(SH), _gradtype(SH, R))
# 	evaluate_ed!(parent(Y), parent(dY), SH, R)
# 	return Y, dY
# end

# function evaluate_ed!(Y, dY, SH::AbstractCYlmBasis, R::AbstractVector)
# 	@assert length(R) == 3
# 	L = maxL(SH)
# 	S = cart2spher(R)
# 	P, dP = _evaluate_ed(SH.alp, S)
# 	cYlm_ed!(Y, dY, maxL(SH), S, P, dP)
# 	release!(P)
# 	release!(dP)
# 	return Y, dY
# end




# ---------------------- serial evaluation code 



"""
evaluate complex spherical harmonics
"""
function cYlm!(Y, L, S::SphericalCoords, P::AbstractVector)
	@assert length(P) >= sizeP(L)
	@assert length(Y) >= sizeY(L)
   @assert abs(S.cosθ) <= 1.0

	ep = 1 / sqrt(2) + im * 0
	for l = 0:L
		Y[index_y(l, 0)] = P[index_p(l, 0)] * ep
	end

   sig = 1
   ep_fact = S.cosφ + im * S.sinφ
	for m in 1:L
		sig *= -1
		ep *= ep_fact            # ep =   exp(i *   m  * φ)
		em = sig * conj(ep)      # em = ± exp(i * (-m) * φ)
		for l in m:L
			p = P[index_p(l,m)]
         # (-1)^m * p * exp(-im*m*phi) / sqrt(2)
			@inbounds Y[index_y(l, -m)] = em * p  
         #          p * exp( im*m*phi) / sqrt(2) 
			@inbounds Y[index_y(l,  m)] = ep * p   
		end
	end

	return Y
end



# """
# evaluate gradients of complex spherical harmonics
# """
# function cYlm_ed!(Y, dY, L, S::SphericalCoords, P, dP)
# 	@assert length(P) >= sizeP(L)
# 	@assert length(Y) >= sizeY(L)
# 	@assert length(dY) >= sizeY(L)

# 	# m = 0 case
# 	ep = 1 / sqrt(2)
# 	for l = 0:L
# 		Y[index_y(l, 0)] = P[index_p(l, 0)] * ep
# 		dY[index_y(l, 0)] = dspher_to_dcart(S, 0.0, dP[index_p(l, 0)] * ep)
# 	end

#    sig = 1
#    ep_fact = S.cosφ + im * S.sinφ

# 	for m in 1:L
# 		sig *= -1
# 		ep *= ep_fact            # ep =   exp(i *   m  * φ)
# 		em = sig * conj(ep)      # ep = ± exp(i * (-m) * φ)
# 		dep_dφ = im *   m  * ep
# 		dem_dφ = im * (-m) * em
# 		for l in m:L
# 			p_div_sinθ = P[index_p(l,m)]
# 			@inbounds Y[index_y(l, -m)] = em * p_div_sinθ * S.sinθ
# 			@inbounds Y[index_y(l,  m)] = ep * p_div_sinθ * S.sinθ

# 			dp_dθ = dP[index_p(l,m)]
# 			@inbounds dY[index_y(l, -m)] = dspher_to_dcart(S, dem_dφ * p_div_sinθ, em * dp_dθ)
# 			@inbounds dY[index_y(l,  m)] = dspher_to_dcart(S, dep_dφ * p_div_sinθ, ep * dp_dθ)
# 		end
# 	end

# 	return Y, dY
# end


# ---------------------- batched evaluation code 



# """
# evaluate complex spherical harmonics
# """
# function cYlm!(Y, L, S::AbstractVector{<: SphericalCoords}, P::AbstractMatrix)
# 	@assert length(P) >= sizeP(L)
# 	@assert length(Y) >= sizeY(L)
#    @assert abs(S.cosθ) <= 1.0

# 	ep = 1 / sqrt(2) + im * 0
# 	for l = 0:L
# 		Y[index_y(l, 0)] = P[index_p(l, 0)] * ep
# 	end

#    sig = 1
#    ep_fact = S.cosφ + im * S.sinφ
# 	for m in 1:L
# 		sig *= -1
# 		ep *= ep_fact            # ep =   exp(i *   m  * φ)
# 		em = sig * conj(ep)      # ep = ± exp(i * (-m) * φ)
# 		for l in m:L
# 			p = P[index_p(l,m)]
# 			@inbounds Y[index_y(l, -m)] = em * p   # (-1)^m * p * exp(-im*m*phi) / sqrt(2)
# 			@inbounds Y[index_y(l,  m)] = ep * p   #          p * exp( im*m*phi) / sqrt(2)
# 		end
# 	end

# 	return Y
# end
