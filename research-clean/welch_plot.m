
files = [
    % "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2_snake\merged_output.wav"
    % "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m\merged_output.wav"
    "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav"
    "C:\Users\Roy\Recordings\hear_my_ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav"
    "C:\\Users\\Roy\\Recordings\\hear_my_ship\\V1\\Motor Boats\\Motorboat_08.08.23_132757_20secCPA.wav"
    ];

for i = 1:length(files)
    read_process_and_spectrogram(files(i));
end


function read_and_process(filepath)

    [data, sr] = audioread(filepath);
    
    if size(data, 2) > 1
        data = mean(data, 2);
    end

    target_sr = 8000; 
    
    [P, Q] = rat(target_sr / sr); 
    
    data_resampled = resample(data, P, Q);    
    nperseg = 1024 * 32;     
    nperseg = min(nperseg, length(data_resampled));
    
    window = hann(nperseg); 
    noverlap = floor(nperseg / 2);
    
    [psd, freqs] = pwelch(data_resampled, window, noverlap, nperseg, target_sr);
    
    figure('Position', [100, 100, 800, 480]); 
    semilogy(freqs, psd, 'Color', 'blue', 'LineWidth', 1.5);
    
    title("High Resolution PSD (0 - 4 kHz)");
    xlabel("Frequency (Hz)");
    ylabel("Power/Frequency (Density)");
    grid on;
    grid minor;
        
    xlim([0, 4000]); 
end


function read_process_and_spectrogram(filepath)
    
    [data, sr] = audioread(filepath);
    
    if size(data, 2) > 1
        data = mean(data, 2);
    end
    
    target_sr = 8000; 
    [P, Q] = rat(target_sr / sr); 
    data_resampled = resample(data, P, Q);
    
    nperseg_psd = 1024 * 32; 
    nperseg_psd = min(nperseg_psd, length(data_resampled));
    
    window_psd = hann(nperseg_psd); 
    noverlap_psd = floor(nperseg_psd / 2);
    
    [psd, freqs] = pwelch(data_resampled, window_psd, noverlap_psd, nperseg_psd, target_sr);
    
    figure('Position', [100, 100, 900, 700]); 
    
    subplot(2, 1, 1);
    semilogy(freqs, psd, 'Color', 'blue', 'LineWidth', 1.5);
    title("High Resolution PSD (0 - 4 kHz)");
    xlabel("Frequency (Hz)");
    ylabel("Power/Frequency (Density)");
    grid on; grid minor;
    xlim([0, 4000]); 
    
    subplot(2, 1, 2);
    
    win_spec = 1024; 
    noverlap_spec = floor(win_spec * 0.75);
    nfft_spec = 2048;
    
    spectrogram(data_resampled, win_spec, noverlap_spec, nfft_spec, target_sr, 'yaxis');
    
    title("Spectrogram (0 - 4 kHz)");
     
    colormap parula; 
end