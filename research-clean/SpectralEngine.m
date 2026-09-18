classdef SpectralEngine
    % Handles Fourier physics, PSD generation, and CFAR macro-lobe tracking.
    methods (Static)

        function [psd_db, f_grid, df, k_welch] = compute_welch_psd(signal, fs, f_min, f_max, twin_sec, df_target)
        % Computes high-resolution Welch PSD and interpolates onto a uniform frequency grid.
        nwin = 2^nextpow2(fs * twin_sec);
        win  = hamming(nwin);
        nov  = floor(nwin * 0.75);
        nfft = max(nwin, 8192);
        
        [psd_raw, f_raw] = pwelch(signal, win, nov, nfft, fs);
        k_welch = floor((length(signal) - nov) / (nwin - nov));
        
        df = df_target;
        f_grid = (f_min : df : f_max)';
        psd_interp = interp1(f_raw, psd_raw, f_grid, 'pchip');
        psd_db = 10 * log10(max(psd_interp, eps));
        end
        
        
        % MODULE 6: PROMINENCE-BASED MACRO-LOBE WATERSHED SEGMENTATION


        function [t_spec, f_spec_crop, p_spec_db] = compute_spectrogram_matrix(signal, fs, f_min, f_max)
        % Generates 2D time-frequency spectrogram slice cropped to analysis passband.
        nwin = 2^nextpow2(fs * 0.250);
        nov  = floor(nwin * 0.90);
        nfft = max(nwin, 4096);
        
        [~, f_raw, t_spec, p_raw] = spectrogram(signal, hamming(nwin), nov, nfft, fs);
        mask_f = (f_raw >= f_min) & (f_raw <= f_max);
        
        f_spec_crop = f_raw(mask_f);
        p_spec_db   = 10 * log10(max(p_raw(mask_f, :), eps));
        end
        
        % MODULE 9A: FIGURE 1 - SPECTRAL PSD, MACRO-LOBES & CFAR TONALS


        function [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
            segment_macro_lobes(psd_db, f_grid, df, prom_split_db)
        % Extracts broadband acoustic structures relative to ambient ocean baseline,
        % resolving independent lobes via topographic saddle-point prominence splitting.
        % Keeps dominant lobe selection strictly anchored to highest integrated linear energy.
        
        N = length(psd_db);
        
        % Smooth ambient ocean baseline via sliding minimum and percentile tracking
        win_bg_bins = 2 * ceil(100.0 / df) + 1;
        ocean_floor_raw = movmin(psd_db, win_bg_bins);
        ocean_floor_smooth = smoothdata(ocean_floor_raw, 'gaussian', round(40.0 / df));
        ocean_ambient_db = prctile(ocean_floor_smooth, 15);
        
        % Net power elevation above ambient floor
        delta_ambient_db = psd_db - ocean_floor_smooth;
        p_lin_net = max(0, 10.^(psd_db / 10) - 10.^(ocean_floor_smooth / 10));
        total_net_energy = trapz(f_grid, p_lin_net);
        
        % Topographic saddle-point valley extraction on smoothed spectral envelope
        psd_env = smoothdata(psd_db, 'gaussian', max(3, round(6.0 / df)));
        is_local_min = [false; (psd_env(2:end-1) < psd_env(1:end-2)) & ...
            (psd_env(2:end-1) <= psd_env(3:end)); false];
        valleys = find(is_local_min);
        
        % Peak summits
        is_pk = [false; (psd_env(2:end-1) > psd_env(1:end-2)) & ...
            (psd_env(2:end-1) >= psd_env(3:end)); false];
        peaks = find(is_pk);
        
        valid_valleys = [];
        for v = 1:length(valleys)
            idx_v = valleys(v);
            left_pks  = peaks(peaks < idx_v);
            right_pks = peaks(peaks > idx_v);
            if ~isempty(left_pks) && ~isempty(right_pks)
                pk_l = left_pks(end);
                pk_r = right_pks(1);
                drop_l = psd_env(pk_l) - psd_env(idx_v);
                drop_r = psd_env(pk_r) - psd_env(idx_v);
                min_drop = min(drop_l, drop_r);
        
                is_ambient_floor_return = (delta_ambient_db(idx_v) <= 3.0);
                is_isolated_carrier_split = (min_drop >= 7.0) && (delta_ambient_db(idx_v) <= 5.0);
        
                if is_ambient_floor_return || is_isolated_carrier_split
                    valid_valleys = [valid_valleys; idx_v];
                end
            end
        
        
        end
        
        % Partition regions
        boundaries = unique([1; valid_valleys; N]);
        cand_lobes = [];
        
        for b = 1:length(boundaries) - 1
            i_start = boundaries(b);
            i_end   = boundaries(b + 1);
            f_sub   = f_grid(i_start:i_end);
            p_sub   = psd_db(i_start:i_end);
            p_net_sub = p_lin_net(i_start:i_end);
        
            [pk_val, pk_local] = max(p_sub);
            pk_freq = f_sub(pk_local);
            e_lobe  = trapz(f_sub, p_net_sub);
            pct_e   = 100 * (e_lobe / max(total_net_energy, eps));
        
            % Retain regions exhibiting measurable excess energy and elevation
            if (pct_e >= 1.0) && ((pk_val - ocean_floor_smooth(i_start + pk_local - 1)) >= 2.5)
                i_core_start = i_start;
                while (i_core_start < i_start + pk_local - 1) && (delta_ambient_db(i_core_start) <= 1.0)
                    i_core_start = i_core_start + 1;
                end
                i_core_end = i_end;
                while (i_core_end > i_start + pk_local - 1) && (delta_ambient_db(i_core_end) <= 1.0)
                    i_core_end = i_core_end - 1;
                end
        
                lobe = struct();
                lobe.f_start      = f_grid(i_core_start);
                lobe.f_end        = f_grid(i_core_end);
                lobe.bandwidth    = lobe.f_end - lobe.f_start;
                lobe.peak_freq    = pk_freq;
                lobe.peak_psd     = pk_val;
                lobe.energy_lin   = e_lobe;
                lobe.pct_energy   = pct_e;
        
                cand_lobes = [cand_lobes; lobe];
            end
        
        
        end
        
        if isempty(cand_lobes)
            [max_val, max_idx] = max(psd_db);
            dom_lobe = struct('f_start', f_grid(1), 'f_end', f_grid(end), ...
                'bandwidth', f_grid(end) - f_grid(1), ...
                'peak_freq', f_grid(max_idx), 'peak_psd', max_val, ...
                'energy_lin', total_net_energy, 'pct_energy', 100, ...
                'internal_tonals', []);
            macro_lobes = dom_lobe;
        else
            % Dominant lobe selection strictly maintained as maximum integrated linear energy
            [~, max_e_idx] = max([cand_lobes.energy_lin]);
            dom_lobe = cand_lobes(max_e_idx);
            macro_lobes = cand_lobes;
        end
        end
        
        
        % MODULE 8: SPECTROGRAM MATRIX COMPUTATION

    end
end
