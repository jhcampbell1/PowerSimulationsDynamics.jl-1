function _power_flow_solution!(
    initial_guess::Vector{Float64},
    sys::PSY.System,
    inputs::SimulationInputs,
)
    res = PSY.solve_powerflow!(sys)
    if !res
        @error("PowerFlow failed to solve")
        return BUILD_FAILED
    end
    bus_size = length(PSY.get_bus_numbers(sys))
    @debug "Updating Voltage guess"
    for bus in PSY.get_components(PSY.Bus, sys)
        bus_n = PSY.get_number(bus)
        bus_ix = get_lookup(inputs)[bus_n]
        initial_guess[bus_ix] = PSY.get_magnitude(bus) * cos(PSY.get_angle(bus))
        initial_guess[bus_ix + bus_size] = PSY.get_magnitude(bus) * sin(PSY.get_angle(bus))
        @debug "$(PSY.get_name(bus)) V_r = $(initial_guess[bus_ix]), V_i = $(initial_guess[bus_ix + bus_size])"
    end
    return BUILD_INCOMPLETE
end

function _initialize_static_injection!(inputs::SimulationInputs)
    @debug "Updating Source internal voltages"
    static_injection_devices = get_static_injectors_data(inputs)
    if !isempty(static_injection_devices)
        try
            for s in static_injection_devices
                initialize_static_device!(s)
            end
        catch e
            bt = catch_backtrace()
            @error "Static Injection Failed to Initialize" exception = e, bt
            return BUILD_FAILED
        end
    end
    return BUILD_INCOMPLETE
end

function _initialize_dynamic_injection!(
    initial_guess::Vector{Float64},
    inputs::SimulationInputs,
    system::PSY.System,
)
    @debug "Updating Dynamic Injection Component Initial Guess"
    initial_inner_vars = zeros(get_inner_vars_count(inputs))
    try
        for dynamic_device in get_dynamic_injectors_data(inputs)
            static = PSY.get_component(
                dynamic_device.static_type,
                system,
                PSY.get_name(dynamic_device),
            )
            @debug "$(PSY.get_name(dynamic_device)) - $(typeof(dynamic_device.device))"
            n_states = PSY.get_n_states(dynamic_device)
            _inner_vars = @view initial_inner_vars[get_inner_vars_index(dynamic_device)]
            x0_device = initialize_dynamic_device!(dynamic_device, static, _inner_vars)
            @assert length(x0_device) == n_states
            ix_range = get_ix_range(dynamic_device)
            initial_guess[ix_range] = x0_device
        end
    catch e
        bt = catch_backtrace()
        @error "Dynamic Injection Failed to Initialize" exception = e, bt
        return BUILD_FAILED
    end
    return BUILD_INCOMPLETE
end

function _initialize_dynamic_branches!(
    initial_guess::Vector{Float64},
    inputs::SimulationInputs,
)
    @debug "Updating Component Initial Guess"
    branches_start = get_branches_pointer(inputs)
    try
        for br in get_dynamic_branches(inputs)
            @debug PSY.get_name(br) typeof(br)
            n_states = PSY.get_n_states(br)
            ix_range = range(branches_start, length = n_states)
            branches_start = branches_start + n_states
            x0_branch = initialize_dynamic_device!(br)
            @assert length(x0_branch) == n_states
            initial_guess[ix_range] = x0_branch
        end
    catch e
        bt = catch_backtrace()
        @error "Dynamic Branches Failed to Initialize" exception = e, bt
        return BUILD_FAILED
    end
    return BUILD_INCOMPLETE
end

function check_valid_values(initial_guess::Vector{Float64}, inputs::SimulationInputs)
    invalid_initial_guess = String[]
    for i in get_bus_range(inputs)
        if initial_guess[i] > 1.3 || initial_guess[i] < -1.3
            push!(invalid_initial_guess, "Voltage entry $i")
        end
    end

    for device in get_dynamic_injectors_data(inputs)
        device_initial_guess = initial_guess[get_ix_range(device)]
        device_index = get_global_index(device)
        if haskey(device_index, :ω)
            dev_freq = initial_guess[device_index[:ω]]
            if dev_freq > 1.2 || dev_freq < 0.8
                push!(invalid_initial_guess, "$(PSY.get_name(device)) - :ω")
            end
        end
        all(isfinite, initial_guess) && continue
        invalid_set = findall(!isfinite, device_initial_guess)
        for state in get_global_index(device)
            if state.second ∈ i
                push!(invalid_initial_guess, "$device - $(p.first)")
            end
        end
    end

    if !isempty(invalid_initial_guess)
        @error("Invalid initial condition values $invalid_initial_guess")
        return BUILD_FAILED
    end
    return BUILD_IN_PROGRESS
end

# Default implementation for both models. This implementation is to future proof if there is
# a divergence between the required build methods
function _calculate_initial_guess!(sim::Simulation)
    inputs = get_simulation_inputs(sim)
    @assert sim.status == BUILD_INCOMPLETE
    while sim.status == BUILD_INCOMPLETE
        @debug "Start state intialization routine"
        sim.status = _power_flow_solution!(sim.x0_init, get_system(sim), inputs)
        sim.status = _initialize_static_injection!(inputs)
        sim.status = _initialize_dynamic_injection!(sim.x0_init, inputs, get_system(sim))
        if has_dyn_lines(inputs)
            sim.status = _initialize_dynamic_branches!(sim.x0_init, inputs)
        else
            @debug "No Dynamic Branches in the system"
        end
        sim.status = check_valid_values(sim.x0_init, inputs)
    end
    return
end

function precalculate_initial_conditions!(sim::Simulation)
    _calculate_initial_guess!(sim)
    return sim.status != BUILD_FAILED
end

"""
Returns a Dictionary with the resulting initial conditions of the simulation
"""
function read_initial_conditions(sim::Simulation)
    system = get_system(sim)
    simulation_inputs = get_simulation_inputs(sim)
    bus_size = get_bus_count(simulation_inputs)
    V_R = Dict{Int, Float64}()
    V_I = Dict{Int, Float64}()
    Vm = Dict{Int, Float64}()
    θ = Dict{Int, Float64}()
    for bus in PSY.get_components(PSY.Bus, system)
        bus_n = PSY.get_number(bus)
        bus_ix = get_lookup(simulation_inputs)[bus_n]
        V_R[bus_n] = sim.x0_init[bus_ix]
        V_I[bus_n] = sim.x0_init[bus_ix + bus_size]
        Vm[bus_n] = sqrt(sim.x0_init[bus_ix]^2 + sim.x0_init[bus_ix + bus_size]^2)
        θ[bus_n] = angle(sim.x0_init[bus_ix] + sim.x0_init[bus_ix + bus_size] * 1im)
    end
    results = Dict{String, Any}("V_R" => V_R, "V_I" => V_I, "Vm" => Vm, "θ" => θ)
    for device in PSY.get_components(PSY.DynamicInjection, system)
        states = PSY.get_states(device)
        name = PSY.get_name(device)
        global_index = get_global_index(simulation_inputs)[name]
        x0_device = Dict{Symbol, Float64}()
        for s in states
            x0_device[s] = sim.x0_init[global_index[s]]
        end
        results[name] = x0_device
    end
    dyn_branches = PSY.get_components(PSY.DynamicBranch, system)
    if !isempty(dyn_branches)
        for br in dyn_branches
            states = PSY.get_states(br)
            name = PSY.get_name(br)
            global_index = get_global_index(simulation_inputs)[name]
            x0_br = Dict{Symbol, Float64}()
            for s in states
                x0_br[s] = sim.x0_init[global_index[s]]
            end
            printed_name = "Line " * name
            results[printed_name] = x0_br
        end
    end
    return results
end
