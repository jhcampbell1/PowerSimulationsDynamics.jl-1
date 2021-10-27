precompile = @timed using PowerSimulationsDynamics

using PowerSimulationsDynamics
const PSID = PowerSimulationsDynamics
using Sundials
using PowerSystems
const PSY = PowerSystems
using OrdinaryDiffEq

open("precompile_time.txt", "a") do io
    write(io, "| $(ARGS[1]) | $(precompile.time) |\n")
end

raw_file_dir = "test/data_tests/240busWECC_2018_PSS32_fixed_shunts.raw"
dyr_file = "test/data_tests/240busWECC_2018_PSS.dyr"
sys = System(
    raw_file_dir,
    dyr_file;
    bus_name_formatter = x -> string(x["name"]) * "-" * string(x["index"]),
);

sim_ida, time_build_ida = @timed Simulation(
    ResidualModel,
    sys,
    pwd(),
    (0.0, 20.0), #time span
    BranchTrip(1.0, Line, "CORONADO    -1101-PALOVRDE    -1401-i_10");,
)

open("execute_time.txt", "a") do io
    write(io, "| $(ARGS[1]) | 999 |\n")
end

sim_rodas, time_build_rodas = @timed Simulation(
    MassMatrixModel,
    sys, #system
    pwd(),
    (0.0, 20.0), #time span
    BranchTrip(1.0, Line, "CORONADO    -1101-PALOVRDE    -1401-i_10"),
) #Type of Fault

open("execute_time.txt", "a") do io
    write(io, "| $(ARGS[1]) | 999 |\n")
end

status = execute!(sim_rodas, Rodas4(), dtmax = 0.01)
res_rodas = read_results(sim_rodas)

status = execute!(sim_ida, IDA(), dtmax = 0.01)
res_ida = read_results(sim_ida)
