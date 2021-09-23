using ParametrisedConvexApproximators
const PCApprox = ParametrisedConvexApproximators

using FlightSims
const FS = FlightSims
using Plots
using Transducers
using NumericalIntegration
using LinearAlgebra
using UnPack
using DrWatson
using Flux
using Random
using DataFrames
using Convex
using Mosek, MosekTools
using JLD2, FileIO
using Printf
using BenchmarkTools
using Dash
using DashHtmlComponents, DashCoreComponents

# Progress bar; see https://github.com/JuliaFolds/Transducers.jl/issues/468
using Logging: global_logger
using TerminalLoggers: TerminalLogger
global_logger(TerminalLogger())


function get_traj_data(env, Δt, tf)
    x0 = FS.State(env)()
    prob, df = sim(
                   x0,
                   Dynamics!(env);
                   tf=tf,
                   savestep=Δt,
                  )
    df
end

"""
If dim="2d", it renders time vs trajectory graph (x, y, z corresponds to NED).
If dim="3d", it renders 3d trajectory (ENU).
"""
function plot_figures!(fig, df, pos_cmd_func, dim)
    ts = df.time
    poss = df.sol |> Map(datum -> datum.multicopter.state.p) |> collect
    poss_cmd = ts |> Map(pos_cmd_func) |> collect
    if dim == "2d"
        plot!(fig,
              ts, hcat(poss...)';
              label=["actual (x)" "actual (y)" "actual (z)"],
              lw=3.0,
              ls=:solid,
              color=[:black :blue :green],
             )
        plot!(fig,
              ts, hcat(poss_cmd...)';
              label=["desired (x)" "desired (y)" "desired (z)"],
              lw=3.0,
              ls=:dot,
              color=[:red :magenta :brown],
             )
    elseif dim == "3d"
        poss_enu = poss |> Map(FS.ned2enu) |> collect
        pos_enu_N_by_3 = hcat(poss_enu...)'
        plot!(fig,
              pos_enu_N_by_3[:, 1], pos_enu_N_by_3[:, 2], pos_enu_N_by_3[:, 3];
              label="actual",
              lw=3.0,
              ls=:solid,
              color=:black,
             )
        poss_cmd_enu = poss_cmd |> Map(FS.ned2enu) |> collect
        pos_cmd_enu_N_by_3 = hcat(poss_cmd_enu...)'
        plot!(fig,
              pos_cmd_enu_N_by_3[:, 1], pos_cmd_enu_N_by_3[:, 2], pos_cmd_enu_N_by_3[:, 3];
              label="desired",
              lw=3.0,
              ls=:dot,
              color=:red,
             )
    else
        error("Not supported dimension")
    end
end

function run_sim(pos_cmd_func, tf)
    env = FS.BacksteppingPositionController_StaticAllocator_MulticopterEnv(pos_cmd_func)
    Δt = 0.01
    df = get_traj_data(env, Δt, tf)
end

function evaluate_sim(df, config)
    @unpack tf = config
    ts = df.time
    poss = df.sol |> Map(datum -> datum.multicopter.state.p) |> collect
    pos_cmds = ts |> Map(PosCmdFunc(config)) |> collect
    e_poss = poss .- pos_cmds
    e_pos_norms = e_poss |> Map(e_pos -> norm(e_pos)) |> collect
    e_pos_norm_squareds = e_poss |> Map(e_pos -> norm(e_pos)^2) |> collect
    integral_e_norm_average = (1/tf) * integrate(ts, e_pos_norms)
    integral_e_norm_squared_average = (1/tf) * integrate(ts, e_pos_norm_squareds)
    results = Dict()
    results["integral_e_norm_average"] = [integral_e_norm_average]  # make it an array
    results["integral_e_norm_squared_average"] = [integral_e_norm_squared_average]  # make it an array
    results
end


function PosCmdFunc(config)
    @unpack θ, tf, pos_cmdf = config
    pos_cmd0 = zeros(3)
    pos_param1 = θ[1:3]
    pos_param2 = θ[4:6]
    function pos_cmd_func(t)
        pos_cmd0*(1-t/tf)^3 + pos_param1*(1-t/tf)^2*(t/tf)^1 + pos_param2*(1-t/tf)^1*(t/tf)^2 + pos_cmdf*(t/tf)^3
    end
end

function main_single(config; fig=nothing, dim="2d")
    @unpack θ, tf, pos_cmdf = config
    df = run_sim(PosCmdFunc(config), tf)
    # plot
    if fig != nothing
        plot_figures!(fig, df, PosCmdFunc(config), dim)
    end
    _result = Dict()
    _result["df"] = df
    result = merge(config, _result)
end

function generate_sim_data(dir_save, configs; will_save=false)
    if will_save
        enumerate(configs) |> withprogress |> MapSplat() do i, config
            wsave(datadir(dir_save, "sim_$(i).jld2"), main_single(config))
        end |> tcollect
        return configs
    end
end

function generate_and_training_approximator(dir_save, xuf_data_train, xuf_data_test; will_save=false)
    path_approximator = datadir(dir_save, "approximator.jld2")
    if will_save
        n = length(xuf_data_train.x[1])
        m = length(xuf_data_test.u[1])
        i_max = 20
        h_array = [64, 64]
        act = Flux.leakyrelu
        approximator = pMA(n, m, i_max, h_array, act)
        @show typeof(approximator)
        # # training
        @time train_approximator!(approximator, xuf_data_train, xuf_data_test;
                                  loss=(x, u, f) -> Flux.Losses.mse(approximator(x, u), f),
                                  opt=ADAM(1e-3),
                                  epochs=30,
                                  batchsize=4,
                           )
        save(path_approximator, Dict("pma" => approximator,))
    end
    path_approximator
end

function sample_from_box(n, x_min, x_max)
    x_min .+ (x_max .- x_min) .* rand(n)
end

function infer!(approximator, x, u, u_bounds)
    prob = Convex.minimize(approximator(x, u))
    prob.constraints += u .>= u_bounds[1]
    prob.constraints += u .<= u_bounds[2]
    solve!(prob, Mosek.Optimizer(); silent_solver=true)
end

function load_processed_data(dir_save, configs; will_load_raw_data=false)
    path_df_compressed = joinpath(datadir("processed"), "df_compressed.jld2")
    if will_load_raw_data
        df_sim = collect_results(dir_save)
        evaluations = zip(df_sim.df, configs) |> MapSplat(evaluate_sim) |> collect
        df_evaluation = vcat(DataFrame.(evaluations)...)
        # compress
        df_compressed = DataFrame()
        df_compressed[:, :integral_e_norm_average] = df_evaluation.integral_e_norm_average
        df_compressed[:, :pos_cmdf] = df_sim.pos_cmdf
        df_compressed[:, :θ] = df_sim.θ
        save(path_df_compressed, Dict("df_compressed" => df_compressed,))
    end
    df_compressed = load(path_df_compressed)["df_compressed"]
end

function generate_configs(n, m, bounds, N_pos_cmdf, N_θ)
    N = N_pos_cmdf * N_θ
    println("$(N) scenarios...")


    pos_cmdfs = 1:N_pos_cmdf |> Map(i -> sample_from_box(n, bounds.pos_cmdf...)) |> collect
    θs = 1:N_θ |> Map(i -> sample_from_box(m, bounds.θ...)) |> collect
    tfs = [10.0]
    configs = Dict(
                   "θ" => θs,
                   "pos_cmdf" => pos_cmdfs,
                   "tf" => tfs,
                  ) |> dict_list
end
