### A Pluto.jl notebook ###
# v0.16.1

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ 8fc18a6c-1c35-11ec-2865-41c07b7ceb60
import Pkg

# ╔═╡ 24fda581-5738-4c66-9fda-f601e57a3daf
Pkg.activate(".")

# ╔═╡ 44312821-23f0-49b9-9342-9ba536fac06d
begin
	using KSAS2021Fall
	using Plots
	using PlutoUI
	using Random
	using Transducers
	using FlightSims
end

# ╔═╡ 40c87b3e-7c2b-41e6-8205-127cdaf49393
Random.seed!(2021)

# ╔═╡ 50ab94ee-e907-4b45-9643-b346b351b77d
begin
	N_pos_cmdf = 1  # no. of initial conditions
    N_θ = 1  # no. of trajectory generator parameters
    n, m = 3, 6
    _θ_min = -10
    _θ_max = 10
    bounds = (; pos_cmdf=(-3*ones(n), 3*ones(n)), θ=(_θ_min*ones(m), _θ_max*ones(m)))
    _configs = KSAS2021Fall.generate_configs(n, m, bounds, N_pos_cmdf, N_θ)
    # fig
    config_tested = _configs[1]
end

# ╔═╡ bbd06fb6-54ce-4df8-840e-1ea5ddea0a4e
function plot_interactive(
        config_tested,
        θ_1_selected,
        θ_2_selected,
        θ_3_selected,
        θ_4_selected,
        θ_5_selected,
        θ_6_selected;
        seed=2021)
	fig = plot(;
		   xlim=(-3, 3),
		   ylim=(-3, 3),
		   zlim=(-3, 3),
		   aspect_ratio=:equal,
		   legend=:outertopright,
		   size=(1000, 1000),
		  )
	gr()
    config_tested["θ"][1] = θ_1_selected
    config_tested["θ"][2] = θ_2_selected
    config_tested["θ"][3] = θ_3_selected
    config_tested["θ"][4] = θ_4_selected
    config_tested["θ"][5] = θ_5_selected
    config_tested["θ"][6] = θ_6_selected
    print("Running sim...")
    sim_result = KSAS2021Fall.main_single(config_tested; fig=fig, dim="3d")
    print("Done!")
	df = sim_result["df"]
	fig, df
end

# ╔═╡ 91921f80-7a19-4dd6-889c-2603574fdfaa
θ_1_slider = @bind θ_1 html"<input type='range' min='-10.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ bded4fa4-ed0b-4718-903a-12762186c800
θ_2_slider = @bind θ_2 html"<input type='range' min='-10.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ c2411a30-2771-4c2b-94df-b360c37a6231
θ_3_slider = @bind θ_3 html"<input type='range' min='-10.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ 971e42ca-200f-42a2-b70a-6b0332a497a8
θ_4_slider = @bind θ_4 html"<input type='range' min='-10.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ f6364267-64b6-482e-9888-ae0356f7e8bd
θ_5_slider = @bind θ_5 html"<input type='range' min='-10.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ 47196c4e-0170-476b-b6e4-a4e06c3eb760
θ_6_slider = @bind θ_6 html"<input type='range' min='-10.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ 72f20767-a2a4-4efd-9ae1-3303196848c8
function draw_multicopter!(_fig, df, t, camera_1, camera_2)
	fig = deepcopy(_fig)
    ts = df.time
    states = df.sol |> Transducers.Map(datum -> datum.multicopter.state) |> collect
	idx = findmin(abs.(ts .- t))[2]
	state = states[idx]
	multicopter = FlightSims.LeeHexacopterEnv()
    FlightSims.plot!(fig, multicopter, state;
		camera=(camera_1, camera_2),
	)
	fig
end

# ╔═╡ a69915e9-42b6-42fc-a4e6-12904d5850ad
camera_1_slider = @bind camera_1 html"<input type='range' min='-30.0' max='60.0' step='0.01' value='30.0'>"

# ╔═╡ 586323eb-8c5b-47c7-8336-6fdac718ec90
camera_2_slider = @bind camera_2 html"<input type='range' min='-30.0' max='60.0' step='0.01' value='30.0'>"

# ╔═╡ d6ed9dd9-2852-41d7-85d3-db8059ccfb4a
t_slider = @bind t html"<input type='range' min='0.0' max='10.0' step='0.01' value='0.0'>"

# ╔═╡ d6994995-99a8-4e32-8802-e8df249feba8
_fig, df = plot_interactive(config_tested, θ_1, θ_2, θ_3, θ_4, θ_5, θ_6)  # intermediate result

# ╔═╡ ae21d177-fe8e-40c9-b003-b41ddd5402f1
fig = draw_multicopter!(_fig, df, t, camera_1, camera_2)  # the result!

# ╔═╡ Cell order:
# ╠═8fc18a6c-1c35-11ec-2865-41c07b7ceb60
# ╠═24fda581-5738-4c66-9fda-f601e57a3daf
# ╠═44312821-23f0-49b9-9342-9ba536fac06d
# ╠═40c87b3e-7c2b-41e6-8205-127cdaf49393
# ╠═50ab94ee-e907-4b45-9643-b346b351b77d
# ╠═bbd06fb6-54ce-4df8-840e-1ea5ddea0a4e
# ╠═72f20767-a2a4-4efd-9ae1-3303196848c8
# ╠═a69915e9-42b6-42fc-a4e6-12904d5850ad
# ╠═586323eb-8c5b-47c7-8336-6fdac718ec90
# ╠═ae21d177-fe8e-40c9-b003-b41ddd5402f1
# ╠═d6ed9dd9-2852-41d7-85d3-db8059ccfb4a
# ╠═91921f80-7a19-4dd6-889c-2603574fdfaa
# ╠═bded4fa4-ed0b-4718-903a-12762186c800
# ╠═c2411a30-2771-4c2b-94df-b360c37a6231
# ╠═971e42ca-200f-42a2-b70a-6b0332a497a8
# ╠═f6364267-64b6-482e-9888-ae0356f7e8bd
# ╠═47196c4e-0170-476b-b6e4-a4e06c3eb760
# ╠═d6994995-99a8-4e32-8802-e8df249feba8
