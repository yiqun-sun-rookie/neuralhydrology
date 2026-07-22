function multiseed_params_driver(seeds, out_dir)
% Multi-seed rerun of the published WALRUS params synthetic experiment.
% Self-contained replication of main_params.m at the PUBLISHED-WORKSPACE
% design point (process noise 1e-6*diag, cell-1 semantics; the script text
% drifted -- see docs/plans/2026-07-22-matlab-multiseed-params-design.md).
% Draw order mirrors the published pipeline exactly, including the unused
% dv/dg/hq/hs lhsdesign draws, so each seed is a faithful re-realization.
% Only the interacting multiple-model loop is run; per-seed output is the
% minimal set (imm_probs, candidates, qobs).

    snapshot = 'G:\github\pycharm\projects\paper-imm-variable-params\tmp\external\nutstore_func_public_snapshot_20260722';
    addpath(fullfile(snapshot, 'hydro\walrus\scripts'));
    addpath(fullfile(snapshot, 'hydro\walrus\scripts\func_defaults'));
    addpath(fullfile(snapshot, 'hydro\walrus\scripts\walrus_step\func_shared'));
    addpath(fullfile(snapshot, 'hydro\walrus_state_space_fixed_step\scripts'));
    addpath(fullfile(snapshot, 'matlab\scripts'));
    addpath('G:\github\pycharm\projects\paper-imm-variable-params\for_submit\synthetic\scripts\subfunctions');
    data_file = 'G:\github\pycharm\projects\paper-imm-variable-params\synthetic\data\PEQ_Regge_hour.txt';

    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    % Forcing and shared parameters are seed-independent; load once.
    data = readtable(data_file);
    [data_s, data_e] = deal(2000010101, 2000060101);
    data_cumsum = walrus_preprocessing(data(data.date >= data_s & data.date <= data_e, :), 1);
    qobs_base = walrus_get_q_obs(data_cumsum);
    [p, etpot, ~, ~, ~] = func_walrus_get_inputs_t(data_cumsum);
    params = walrus_get_params('regge_fixed_tm_step_cw_cg_cq');
    cd = params.cd; cs = params.cs;

    for seed = seeds(:)'
        fprintf('=== seed %d start %s ===\n', seed, datestr(now, 31));
        try
            run_one_seed(seed, out_dir, qobs_base, p, etpot, cd, cs);
            fprintf('=== seed %d done %s ===\n', seed, datestr(now, 31));
        catch err
            report = getReport(err, 'extended', 'hyperlinks', 'off');
            fid = fopen(fullfile(out_dir, sprintf('seed_%d.error.txt', seed)), 'w');
            fprintf(fid, '%s', report);
            fclose(fid);
            fprintf('=== seed %d FAILED: %s ===\n', seed, err.message);
        end
    end
end

function run_one_seed(seed, out_dir, qobs, p, etpot, cd, cs)
    rng(seed, "twister");

    %% Initial Conditions (as published)
    state0 = [140, 1000, 4, 1200, 0.15]; p0 = (diag(0.001 * state0)) ^ 2;

    %% Noises Truth -- PUBLISHED-WORKSPACE values: cell 1 = 1e-6*diag, used everywhere
    tmp = state0; tmp(5) = 0;
    q_truth_cov = 1e-6 * diag(tmp);
    r = 1e-4 * state0(5);
    noise_q_truth_s1 = sqrt(diag(q_truth_cov))' .* randn(floor(length(qobs) / 3), length(state0));
    noise_q_truth_s2 = sqrt(diag(q_truth_cov))' .* randn(floor(length(qobs) / 3) + 1, length(state0));
    noise_q_truth_s3 = sqrt(diag(q_truth_cov))' .* randn(floor(length(qobs) / 3), length(state0));
    noise_r_truth = sqrt(diag(r))' .* randn(length(qobs), 1);
    noise_q_truth = [noise_q_truth_s1; noise_q_truth_s2; noise_q_truth_s3];

    %% System Model Truth
    cw_truth = [600, 400, 500]; cv_truth = [50, 30, 40]; cg_truth = [1.8e7, 1.6e7, 1.7e7]; cq_truth = [6, 3, 5];
    statetran_truth = cell(length(cw_truth), 1);
    for x0 = 1: length(cw_truth)
        statetran_truth{x0} = @(x, dt, p_t, etpot_t, noise)statetran_fcn(x, dt, p_t, etpot_t, noise, cw_truth(x0), cv_truth(x0), cg_truth(x0), cq_truth(x0), cd, cs);
    end

    %% Open Loop Run to Get Obs
    states_obs = zeros(length(qobs), length(state0));
    states_obs(1, :) = state0;
    t1_2 = length(noise_q_truth_s1);
    t2_3 = length(noise_q_truth_s1) + length(noise_q_truth_s2);
    for x0 = 2: length(qobs)
        if x0 <= t1_2
            states_obs(x0, :) = statetran_truth{1}(states_obs(x0 - 1, :), 1, p(x0 - 1), etpot(x0 - 1), noise_q_truth(x0, :));
        else
            if x0 <= t2_3
                states_obs(x0, :) = statetran_truth{2}(states_obs(x0 - 1, :), 1, p(x0 - 1), etpot(x0 - 1), noise_q_truth(x0, :));
            else
                states_obs(x0, :) = statetran_truth{3}(states_obs(x0 - 1, :), 1, p(x0 - 1), etpot(x0 - 1), noise_q_truth(x0, :));
            end
        end
    end
    states_obs(:, end) = states_obs(:, end) + noise_r_truth;
    qobs = states_obs(:, end);

    %% Generate random parameters (published draw order)
    n = 10;
    bounds = [700 300; % cw
              60 20; % cv
              1.9e7 1.5e7; % cg
              7 2]; % cq
    cw = bounds(1, 1) - lhsdesign(n, 1) * (bounds(1, 1) - bounds(1, 2));
    cv = bounds(2, 1) - lhsdesign(n, 1) * (bounds(2, 1) - bounds(2, 2));
    cg = bounds(3, 1) - lhsdesign(n, 1) * (bounds(3, 1) - bounds(3, 2));
    cq = bounds(4, 1) - lhsdesign(n, 1) * (bounds(4, 1) - bounds(4, 2));
    cw = [cw; cw_truth(1:2)'];
    cv = [cv; cv_truth(1:2)'];
    cg = [cg; cg_truth(1:2)'];
    cq = [cq; cq_truth(1:2)'];

    %% System Model All
    statetran_all = cell(n, 1);
    for x0 = 1: n
        statetran_all{x0} = @(x, dt, p_t, etpot_t, noise)statetran_fcn(x, dt, p_t, etpot_t, noise, cw(x0), cv(x0), cg(x0), cq(x0), cd, cs);
    end
    statetran_all{end + 1} = statetran_truth{1};
    statetran_all{end + 1} = statetran_truth{2};

    %% Burned draws (published pipeline draws these and never uses them)
    bounds_q_s = [1e-7 * tmp', 1e-2 * tmp'];
    dv = bounds_q_s(1, 1) - lhsdesign(n, 1) * (bounds_q_s(1, 1) - bounds_q_s(1, 2)); %#ok<NASGU>
    dg = bounds_q_s(2, 1) - lhsdesign(n, 1) * (bounds_q_s(2, 1) - bounds_q_s(2, 2)); %#ok<NASGU>
    hq = bounds_q_s(3, 1) - lhsdesign(n, 1) * (bounds_q_s(3, 1) - bounds_q_s(3, 2)); %#ok<NASGU>
    hs = bounds_q_s(4, 1) - lhsdesign(n, 1) * (bounds_q_s(4, 1) - bounds_q_s(4, 2)); %#ok<NASGU>

    %% Filter process noise (published-workspace: same cell-1 matrix for all)
    q_s_all = cell(1, length(statetran_all));
    for x0 = 1: length(statetran_all)
        q_s_all{1, x0} = q_truth_cov;
    end

    %% Initialize sub-filters and IMM (published settings)
    measure = @(state, noise)measure_fcn(state, noise);
    filters = cell(length(statetran_all), 1);
    for x0 = 1: length(statetran_all)
        filters{x0, 1} = trackingUKF('StateTransitionFcn', statetran_all{x0}, 'MeasurementFcn', measure,...
            'StateCovariance', p0, 'State', state0, 'ProcessNoise', q_s_all{x0}, 'MeasurementNoise', r,...
            'Alpha', 0.6874, 'Beta', 2, 'Kappa', -2);
    end
    imm_subs = cell(length(statetran_all), 1);
    for x0 = 1: length(imm_subs)
        imm_subs{x0, 1} = clone(filters{x0, 1});
    end
    imm = trackingIMM('State', state0, 'StateCovariance', p0,...
        'TrackingFilters', imm_subs, 'ModelConversionFcn', @switch_mdl, 'MeasurementNoise', r);
    imm.TransitionProbabilities = 0.99;

    %% Run IMM
    imm_probs = zeros(length(qobs), length(imm_subs));
    imm_probs(1, :) = imm.ModelProbabilities';
    for x0 = 2: length(qobs)
        predict(imm, 1, p(x0 - 1), etpot(x0 - 1), 0);
        correct(imm, qobs(x0), 0);
        imm_probs(x0, :) = imm.ModelProbabilities';
    end

    save(fullfile(out_dir, sprintf('seed_%d.mat', seed)), ...
        'imm_probs', 'cw', 'cv', 'cg', 'cq', 'seed', 'qobs', 't1_2', 't2_3', '-v7');
end
