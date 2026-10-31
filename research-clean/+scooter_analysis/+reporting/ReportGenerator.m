classdef ReportGenerator
    % ReportGenerator - Text report and statistical summary generation for analysis results.
    %
    % Usage:
    %   scooter_analysis.reporting.ReportGenerator.writeFileReport(fr, out_dir);
    %   scooter_analysis.reporting.ReportGenerator.writePhaseLockComparisonReport({ba_h, ba_c, ba_auv}, out_path);
    
    methods (Static)
        
        function writeFileReport(fr, out_dir)
            % Write the per-file dominant_frequencies_report.txt including PLL Phase Lock & Inst. Freq verification.
            %
            % Args:
            %   fr      - scooter_analysis.results.FileResult
            %   out_dir - Directory to save the report
            
            if ~exist(out_dir, 'dir')
                mkdir(out_dir);
            end
            
            report_path = fullfile(out_dir, 'dominant_frequencies_report.txt');
            fid = fopen(report_path, 'w');
            
            if fid == -1
                fprintf('[ReportGenerator] Could not open report file: %s\n', report_path);
                return;
            end
            
            fprintf(fid, 'Analysis of: %s\n', fr.filepath);
            fprintf(fid, 'Total Duration: %.2f seconds (%.2f minutes)\n', ...
                fr.total_duration, fr.total_duration / 60);
            fprintf(fid, '========================================================================================================================================\n');
            fprintf(fid, 'Seg | Start (m) | End (m) | Dom Freq (Hz) | Peak PSD (dB) | Watershed BW (Hz) | PLL Inst Freq (Hz) | PLL Freq SD (Hz) | Phase Lock R | Phase SD (rad)\n');
            fprintf(fid, '----------------------------------------------------------------------------------------------------------------------------------------\n');
            
            for i = 1:length(fr.segments)
                sr = fr.segments(i);
                fprintf(fid, '%3d | %9.2f | %7.2f | %13.2f | %13.2f | %17.2f | %18.2f | %16.2f | %12.3f | %14.3f\n', ...
                    i, sr.start_time/60, sr.end_time/60, sr.dom_freq, sr.peak_psd, sr.med_bw, ...
                    sr.pll_freq_mean, sr.pll_freq_std, sr.pll_mean_plv, sr.pll_phase_std);
            end
            fclose(fid);
            
            fprintf('[ReportGenerator] Report saved: %s\n', report_path);
        end

        function stats_list = writePhaseLockComparisonReport(items, out_path, bin_dur_sec)
            % Compute, print, and export comprehensive Phase Lock (PLL) & Instantaneous
            % Frequency Verification statistics across datasets.
            %
            % Args:
            %   items       - Cell array of BatchAnalyzer, FileResult, or result structs
            %   out_path    - Optional file path to save the text report
            %   bin_dur_sec - Aggregation window duration in seconds (default: 60)

            if nargin < 2; out_path = ''; end
            if nargin < 3 || isempty(bin_dur_sec); bin_dur_sec = 60.0; end

            if ~iscell(items)
                items = {items};
            end

            stats_list = {};
            for k = 1:numel(items)
                item = items{k};
                if isempty(item); continue; end

                st = struct();
                if isa(item, 'scooter_analysis.pipeline.BatchAnalyzer')
                    st.name       = item.DatasetName;
                    bw_bin        = item.getBinnedBandwidthResult(bin_dur_sec);
                    pll_bin       = item.getBinnedPhaseLockResult(bin_dur_sec);
                    pll_roll      = item.getRollingPhaseLockResult(bin_dur_sec);
                    dom_freqs     = item.getAllDomFreqs();
                    inst_freqs    = item.getAllSliceInstFreqs();
                elseif isa(item, 'scooter_analysis.results.FileResult')
                    st.name       = item.filename;
                    bw_bin        = item.getBinnedBandwidthResult(bin_dur_sec);
                    pll_bin       = item.getBinnedPhaseLockResult(bin_dur_sec);
                    pll_roll      = item.getRollingPhaseLockResult(bin_dur_sec);
                    dom_freqs     = item.dom_freqs;
                    inst_freqs    = item.getAllSliceInstFreqs();
                elseif isstruct(item)
                    if isfield(item, 'meta') && isfield(item.meta, 'name')
                        st.name = item.meta.name;
                    else
                        st.name = sprintf('Dataset %d', k);
                    end
                    bw_bin   = item;
                    pll_bin  = item;
                    pll_roll = item;
                    dom_freqs  = [];
                    inst_freqs = [];
                    if isfield(item, 'slice_bw') && isfield(item.slice_bw, 'all_main_bws')
                        [sm, ss, st_t, s_std] = BandwidthTracker.compute_binned_bandwidth(item.slice_bw.all_main_bws, 0.500, bin_dur_sec);
                        bw_bin = struct('all_main_bws', item.slice_bw.all_main_bws, 'slice_means', sm, 'slice_sems', ss, 'slice_times', st_t, 'slice_stds', s_std);
                    end
                    if isfield(item, 'pll_result') && isfield(item.pll_result, 'all_slice_plv')
                        p = item.pll_result;
                        pll_bin = BandwidthTracker.compute_binned_phase_lock( ...
                            p.all_slice_plv, p.all_slice_inst_freq_stds, p.all_slice_phase_stds, p.all_slice_freq_verif_errs, 0.500, bin_dur_sec);
                        pll_bin.all_plvs = p.all_slice_plv;
                        pll_bin.all_inst_freq_stds = p.all_slice_inst_freq_stds;
                        pll_bin.all_phase_stds = p.all_slice_phase_stds;
                        pll_bin.all_freq_verif_errs = p.all_slice_freq_verif_errs;
                        [t_c, plv_s, ent_s, fair_s] = BandwidthTracker.compute_rolling_phase_stability( ...
                            p.all_slice_plv, p.all_slice_mean_phases, p.all_slice_inst_freq_stds, 0.500, bin_dur_sec, 5.0);
                        pll_roll = struct('t_centers', t_c, 'plv_series', plv_s, 'phase_ent_series', ent_s, 'freq_lock_series', fair_s);
                        if isfield(p, 'all_slice_inst_freqs'); inst_freqs = p.all_slice_inst_freqs; end
                        dom_freqs = inst_freqs;
                    end
                else
                    continue;
                end

                % Extract vectors safely
                all_bws = [];
                if isfield(bw_bin, 'all_main_bws'); all_bws = bw_bin.all_main_bws; end
                bw_slice_means = [];
                if isfield(bw_bin, 'slice_means'); bw_slice_means = bw_bin.slice_means; end
                bw_slice_stds = [];
                if isfield(bw_bin, 'slice_stds'); bw_slice_stds = bw_bin.slice_stds; end

                all_plvs = [];
                if isfield(pll_bin, 'all_plvs'); all_plvs = pll_bin.all_plvs; end
                all_fstds = [];
                if isfield(pll_bin, 'all_inst_freq_stds'); all_fstds = pll_bin.all_inst_freq_stds; end
                all_pstds = [];
                if isfield(pll_bin, 'all_phase_stds'); all_pstds = pll_bin.all_phase_stds; end
                all_verrs = [];
                if isfield(pll_bin, 'all_freq_verif_errs'); all_verrs = pll_bin.all_freq_verif_errs; end

                plv_means = [];
                if isfield(pll_bin, 'plv_means'); plv_means = pll_bin.plv_means; end
                plv_stds = [];
                if isfield(pll_bin, 'plv_stds'); plv_stds = pll_bin.plv_stds; end
                fstd_means = [];
                if isfield(pll_bin, 'freq_std_means'); fstd_means = pll_bin.freq_std_means; end
                fstd_stds = [];
                if isfield(pll_bin, 'freq_std_stds'); fstd_stds = pll_bin.freq_std_stds; end

                pent_series = [];
                if isfield(pll_roll, 'phase_ent_series'); pent_series = pll_roll.phase_ent_series; end
                flock_series = [];
                if isfield(pll_roll, 'freq_lock_series'); flock_series = pll_roll.freq_lock_series; end

                st.num_slices_05s = length(all_plvs);
                st.num_bins_60s   = sum(isfinite(plv_means));
                st.dom_freq_mean  = mean(dom_freqs, 'omitnan');
                st.dom_freq_std   = std(dom_freqs, 'omitnan');
                st.inst_freq_mean = mean(inst_freqs, 'omitnan');
                st.inst_freq_std  = std(inst_freqs, 'omitnan');

                st.verif_err_mean = mean(all_verrs, 'omitnan');
                st.verif_err_std  = std(all_verrs, 'omitnan');
                st.verif_err_med  = median(all_verrs, 'omitnan');

                st.bw_60s_mean    = mean(bw_slice_means, 'omitnan');
                st.bw_60s_within_sd = mean(bw_slice_stds, 'omitnan');
                st.bw_60s_macro_sd  = std(bw_slice_means, 'omitnan');

                st.plv_slice_mean = mean(all_plvs, 'omitnan');
                st.plv_slice_std  = std(all_plvs, 'omitnan');
                st.plv_slice_med  = median(all_plvs, 'omitnan');
                st.plv_60s_mean   = mean(plv_means, 'omitnan');
                st.plv_60s_within_sd = mean(plv_stds, 'omitnan');
                st.plv_60s_macro_sd  = std(plv_means, 'omitnan');

                st.fstd_slice_mean = mean(all_fstds, 'omitnan');
                st.fstd_slice_std  = std(all_fstds, 'omitnan');
                st.fstd_60s_mean   = mean(fstd_means, 'omitnan');
                st.fstd_60s_within_sd = mean(fstd_stds, 'omitnan');
                st.fstd_60s_macro_sd  = std(fstd_means, 'omitnan');

                st.phase_std_mean = mean(all_pstds, 'omitnan');
                st.phase_std_std  = std(all_pstds, 'omitnan');
                st.phase_ent_mean = mean(pent_series, 'omitnan');
                st.phase_ent_std  = std(pent_series, 'omitnan');
                st.freq_lock_mean = mean(flock_series, 'omitnan');
                st.freq_lock_std  = std(flock_series, 'omitnan');
                st.all_bws        = all_bws;

                stats_list{end+1} = st;
            end

            if isempty(stats_list)
                return;
            end

            lines = {};
            lines{end+1} = '====================================================================================================';
            lines{end+1} = sprintf('PHASE LOCK (PLL) & INSTANTANEOUS FREQUENCY VERIFICATION SUMMARY (%ds WINDOWS)', round(bin_dur_sec));
            lines{end+1} = '====================================================================================================';

            for k = 1:length(stats_list)
                s = stats_list{k};
                lines{end+1} = sprintf('\nDataset: %s  (N = %d windows of %ds | %d slices of 0.5s)', ...
                    s.name, s.num_bins_60s, round(bin_dur_sec), s.num_slices_05s);
                lines{end+1} = '----------------------------------------------------------------------------------------------------';
                lines{end+1} = sprintf('  Dominant Frequency (Welch Peak)      : %7.2f ± %6.2f Hz', s.dom_freq_mean, s.dom_freq_std);
                lines{end+1} = sprintf('  PLL Tracked Instantaneous Frequency  : %7.2f ± %6.2f Hz', s.inst_freq_mean, s.inst_freq_std);
                lines{end+1} = sprintf('  Inst. Freq Verification |f_PLL-f_FFT|: %7.2f ± %6.2f Hz (Median: %.2f Hz)', ...
                    s.verif_err_mean, s.verif_err_std, s.verif_err_med);
                lines{end+1} = sprintf('  Watershed Bandwidth (%ds Slice Mean) : %7.2f ± %6.2f Hz (Macro SD: %.2f Hz)', ...
                    round(bin_dur_sec), s.bw_60s_mean, s.bw_60s_within_sd, s.bw_60s_macro_sd);
                lines{end+1} = sprintf('  PLL Inst. Freq Spread sigma_f (%ds)  : %7.2f ± %6.2f Hz (Macro SD: %.2f Hz)', ...
                    round(bin_dur_sec), s.fstd_60s_mean, s.fstd_60s_within_sd, s.fstd_60s_macro_sd);
                lines{end+1} = sprintf('  Phase Locking Value R (%ds Mean)     : %7.3f ± %6.3f    (Macro SD: %.3f | Median: %.3f)', ...
                    round(bin_dur_sec), s.plv_60s_mean, s.plv_60s_within_sd, s.plv_60s_macro_sd, s.plv_slice_med);
                lines{end+1} = sprintf('  Wrapped Phase Error SD sigma_phi     : %7.3f ± %6.3f rad', ...
                    s.phase_std_mean, s.phase_std_std);
                lines{end+1} = sprintf('  Normalized Phase Entropy H_phi (%ds) : %7.3f ± %6.3f', ...
                    round(bin_dur_sec), s.phase_ent_mean, s.phase_ent_std);
                lines{end+1} = sprintf('  Inst. Freq Stability Fairness (%ds)  : %7.3f ± %6.3f', ...
                    round(bin_dur_sec), s.freq_lock_mean, s.freq_lock_std);
            end
            lines{end+1} = '====================================================================================================';

            report_str = strjoin(lines, '\n');
            fprintf('\n%s\n\n', report_str);

            if ~isempty(out_path)
                out_dir = fileparts(out_path);
                if ~isempty(out_dir) && ~exist(out_dir, 'dir')
                    mkdir(out_dir);
                end
                fid = fopen(out_path, 'w');
                if fid ~= -1
                    fprintf(fid, '%s\n', report_str);
                    fclose(fid);
                    fprintf('[ReportGenerator] Phase lock comparison statistics saved: %s\n', out_path);
                end
            end
        end
        
    end
end
