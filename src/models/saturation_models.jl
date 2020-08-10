"""
    Saturation function for quadratic saturation models for machines
        Se(x) = B * (x - A)^2 / x
"""
function saturation_function(
    machine::Union{PSY.RoundRotorQuadratic, PSY.SalientPoleQuadratic},
    x,
)
    Sat_A, Sat_B = PSY.get_saturation_coeffs(machine)
    return Sat_B * (x - Sat_A)^2 / x
end

"""
    Saturation function for exponential saturation models for machines
        Se(x) = B * x^A
"""
function saturation_function(
    machine::Union{PSY.RoundRotorExponential, PSY.SalientPoleExponential},
    x,
)
    Sat_A, Sat_B = PSY.get_saturation_coeffs(machine)
    return Sat_B * x^Sat_A
end
