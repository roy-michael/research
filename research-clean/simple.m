clear;clc;close all;

[data_ship, sr_ship] = audioread("D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav");
[data_scooter, sr_scooter] = audioread("D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav");

sr = min(sr_scooter, sr_ship);
len_sec = length(data_ship)/sr_ship;
slice_duration_sec = 0.25;
slice_len = sr * slice_duration_sec;
np = 500;
start_idx = 1;

ship_part = resample_and_split(data_ship, sr_ship, sr, start_idx, slice_len);
ship_fft = fftshift(abs(fft(ship_part)));

scooter_part = resample_and_split(data_scooter, sr_scooter, sr, start_idx, slice_len);
scooter_fft = fftshift(abs(fft(scooter_part)));

[scooter_ev_up, scooter_ev_low] = envelope(scooter_part, np, 'analytic');
[scooter_ev_up_fft, scooter_ev_low_fft] = envelope(scooter_fft, np, 'analytic');


% Calculate the frequency axis for the FFT plot
N = length(ship_fft);
Faxis_fft = (-N/2:N/2-1)*(sr/N);
Faxis = linspace(0, slice_len, length(ship_part));

figure;plot(Faxis, scooter_part);title("Scooter Signal");
figure;plot(Faxis_fft, scooter_fft);title("Scoter Signal FFT");

figure;plot(Faxis_fft, scooter_ev_low_fft, Faxis_fft, scooter_fft);title("Scooter FFT Envelope");
figure;plot(Faxis, scooter_ev_low, Faxis, scooter_part);title("Scooter Signal Envelope");

% ------------------------------------------------
figure;plot(Faxis, ship_part);title("Ship Signal");
figure;plot(Faxis_fft, ship_fft);title("Ship Signal FFT");

[ship_ev_up, ship_ev_low] = envelope(ship_part, np, 'peak');
[ship_ev_up_fft, ship_ev_low_fft] = envelope(ship_fft, np, 'peak');

figure;plot(Faxis_fft, ship_ev_low_fft, Faxis_fft, ship_fft);title("Ship FFT Envelope");
figure;plot(Faxis, ship_ev_low, Faxis, ship_part);title("Ship Signal Envelope");

[sc_inter_freq, sc_inter_idx] = find_intersections(scooter_ev_low_fft, scooter_fft, Faxis_fft);
[sp_inter_freq, sp_inter_idx] = find_intersections(ship_ev_low_fft, ship_fft, Faxis_fft);

[sc_dom_freq, sc_max_val] = find_dominant_freq_in_fft(scooter_fft, Faxis_fft, 500);
[sp_dom_freq, sp_max_val] = find_dominant_freq_in_fft(ship_fft, Faxis_fft);


function result = resample_and_split(data, sr_orig, sr_target, start_idx, num_samples)

if sr_orig > sr_target
    [P, Q] = rat(sr_target / sr_orig);
    data = resample(data, P, Q);
end

result = data(start_idx:num_samples, :);
end

function [dominantFreqs, maxPowers] = find_dominant_freq_in_fft(fft_data, faxis, min_freq)
    if nargin < 3
        min_freq = 20; % Default to 20 Hz to avoid DC leakage if not specified
    end

    % Create a copy and remove DC component (and its spectral leakage)
    fft_no_dc = fft_data;
    
    % Zero out frequencies below min_freq
    fft_no_dc(abs(faxis) < min_freq) = 0; 
    
    % Use only the positive frequency side to avoid double-counting symmetric negative peaks
    pos_mask = faxis >= 0;
    pos_faxis = faxis(pos_mask);
    pos_fft = fft_no_dc(pos_mask);
    
    % Find distinct local peaks
    [pks, locs] = findpeaks(pos_fft);
    
    % Sort peaks by power in descending order
    [sorted_pks, sort_idx] = sort(pks, 'descend');
    
    % Take the top 5 most dominant peaks
    num_peaks_to_find = 5;
    num_peaks = min(num_peaks_to_find, length(sorted_pks));
    
    if num_peaks == 0
        dominantFreqs = [];
        maxPowers = [];
    else
        % Extract corresponding frequencies and powers
        dominantFreqs = pos_faxis(locs(sort_idx(1:num_peaks)));
        maxPowers = sorted_pks(1:num_peaks);
    end
end



function [freqs, idx] = find_intersections(env_arr, arr, faxis)
% FIND_INTERSECTIONS  Return crossing frequencies and indices where arr crosses env_arr.
%   intersections.freq - vector of interpolated frequencies of crossings
%   intersections.idx  - vector of integer sample indices of the left sample of each crossing
%
% Inputs:
%   env_arr - envelope (same length as arr)
%   arr     - spectrum (same length)
%   faxis   - frequency axis (same length) - if empty, returns indices only

if nargin < 3
    faxis = [];
end

if ~isequal(size(env_arr), size(arr))
    error('env_arr and arr must be the same size.');
end

d = arr - env_arr;
% find sign changes or exact zeros
signChange = (d(1:end-1) .* d(2:end)) <= 0;
idx = find(signChange);

freqs = zeros(numel(idx),1);
for k = 1:numel(idx)
    i = idx(k);
    x1 = d(i); x2 = d(i+1);
    if x2 == x1
        frac = 0;
    else
        frac = x1 / (x1 - x2);   % fraction from i to i+1 where crossing occurs
    end
    if ~isempty(faxis)
        freqs(k) = faxis(i) + frac * (faxis(i+1) - faxis(i));
    else
        freqs(k) = i + frac;
    end
end

end
