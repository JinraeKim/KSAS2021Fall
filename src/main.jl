"""
will_*: it controls the behaviour of this function, e.g.,
`will_save_traj = true` will generate simulation data and save it.
Otherwise, it will load the saved simulation data.
"""
function main(; seed=2021)
    gr()
    Random.seed!(seed)
    # configuration
    dir_traj = "trajs"
    dir_approx = "approxs"
    will_save_traj = false
    will_load_raw_data = false
    will_save_approx = false
    N_pos_cmdf = 50  # no. of initial conditions
    N_θ = 50  # no. of trajectory generator parameters
    n, m = 3, 6
    bounds = (; pos_cmdf=(-3*ones(n), 3*ones(n)), θ=(-10*ones(m), 10*ones(m)))
    configs = generate_configs(n, m, bounds, N_θ, N_pos_cmdf)
    @time generate_sim_data(dir_traj, configs; will_save=will_save_traj)
    println("Load sim data...")
    @time df_compressed = load_processed_data(datadir(dir_traj), configs;
                                              will_load_raw_data=will_load_raw_data,
                                             )
    pos_cmdfs = df_compressed.pos_cmdf
    θs = df_compressed.θ
    integral_e_norm_averages = df_compressed.integral_e_norm_average
    Js = integral_e_norm_averages  # costs
    # construct approximator
    xuf_data = xufData(pos_cmdfs, θs, Js)  # condition, decision
    xuf_data_train, xuf_data_test = partitionTrainTest(xuf_data)
    path_approximator = generate_and_training_approximator(dir_approx, xuf_data_train, xuf_data_test;
                                                           will_save=will_save_approx,
                                                          )
    approximator = load(path_approximator)["pma"]
    # simulation test
    pos_cmdf_tested = [2, 3, -1]
    θ̂ = Convex.Variable(m)
    infer!(approximator, pos_cmdf_tested, θ̂, bounds.θ)
    @show θ̂.value
    _config_test = configs[1]
    _config_test["pos_cmdf"] = pos_cmdf_tested
    config_test_proposed = copy(_config_test)
    config_test_proposed["θ"] = θ̂.value
    config_test_compared = copy(_config_test)
    config_test_compared["θ"] = bounds.θ[2]
    # figures
    ts_tick = 0:1:10 |> collect
    tstr = ts_tick |> Map(t -> @sprintf("%0.0f", t)) |> collect
    tstr_empty = ts_tick |> Map(t -> "") |> collect
    fig_proposed = plot(;
                        ylim=(-5, 5),
                        title="position [m]",
                        legend=:bottomleft,
                        ylabel="proposed",
                       )
    res_proposed = main_single(config_test_proposed; fig=fig_proposed)
    evaluation_proposed = evaluate_sim(res_proposed["df"], config_test_proposed)
    @show evaluation_proposed["integral_e_norm_average"]
    xticks!(ts_tick, tstr_empty)
    fig_compared = plot(;
                        ylim=(-5, 5),
                        legend=:bottomleft,
                        ylabel="compared",
                       )
    res_compared = main_single(config_test_compared; fig=fig_compared)
    evaluation_compared = evaluate_sim(res_compared["df"], config_test_compared)
    @show evaluation_compared["integral_e_norm_average"]
    xticks!(ts_tick, tstr)
    fig = plot(fig_proposed, fig_compared;
               layout=(2, 1),
               size=(800, 800),
              )
    savefig(fig, plotsdir("trajectory_generation.pdf"))
    savefig(fig, plotsdir("trajectory_generation.png"))
    display(fig)
end

function plot_interactive(
        fig,
        config_tested,
        t,
        θ_1_selected,
        θ_2_selected,
        θ_3_selected,
        θ_4_selected,
        θ_5_selected,
        θ_6_selected;
        seed=2021)
	Random.seed!(seed)
    plotlyjs()  # backend
    config_tested["θ"][1] = θ_1_selected
    config_tested["θ"][2] = θ_2_selected
    config_tested["θ"][3] = θ_3_selected
    config_tested["θ"][4] = θ_4_selected
    config_tested["θ"][5] = θ_5_selected
    config_tested["θ"][6] = θ_6_selected
    sim_result = main_single(config_tested; fig=fig, dim="3d")
    df = sim_result["df"]
    ts = df.time
    states = df.sol |> Map(datum -> datum.multicopter.state) |> collect
    idx = findmin(abs.(ts .- t))[2]
    state = states[idx]
    multicopter = LeeHexacopterEnv()
    plot!(fig, multicopter, state;)
end
