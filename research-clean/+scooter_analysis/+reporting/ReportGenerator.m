classdef ReportGenerator
    % ReportGenerator - Text report generation for analysis results.
    %
    % Usage:
    %   scooter_analysis.reporting.ReportGenerator.writeFileReport(fr, out_dir);
    
    methods (Static)
        
        function writeFileReport(fr, out_dir)
            % Write the per-file dominant_frequencies_report.txt
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
            fprintf(fid, '======================================================\n');
            fprintf(fid, 'Segment Index | Start Time (m) | End Time (m) | Dominant Freq (Hz) | Peak PSD (dB) | Bandwidth (Hz)\n');
            
            for i = 1:length(fr.segments)
                sr = fr.segments(i);
                fprintf(fid, '  %4d       | %12.2f | %10.2f | %18.2f | %12.2f | %14.2f\n', ...
                    i, sr.start_time/60, sr.end_time/60, sr.dom_freq, sr.peak_psd, sr.med_bw);
            end
            fclose(fid);
            
            fprintf('[ReportGenerator] Report saved: %s\n', report_path);
        end
        
    end
end
