# generate_croatia_dashboard.py
import json
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
output_dir = os.path.join(script_dir, '..', 'output')

json_path = os.path.join(output_dir, 'croatia_spectral_data.json')
html_path = os.path.join(output_dir, 'croatia_spectral_dashboard.html')

if not os.path.exists(json_path):
    print(f"Error: {json_path} does not exist yet. Please run the MATLAB script first.")
    exit(1)

with open(json_path, 'r') as f:
    raw_data = json.load(f)

# Structure of HTML with Plotly
html_template = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Croatia Datasets Interactive Spectral Dashboard</title>
    <script src="https://cdn.plot.ly/plotly-2.24.1.min.js"></script>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: rgba(30, 41, 59, 0.7);
            --border-color: rgba(255, 255, 255, 0.1);
            --text-color: #f8fafc;
            --text-muted: #94a3b8;
            --primary: #38bdf8;
            --accent: #f43f5e;
        }

        body {
            background-color: var(--bg-color);
            color: var(--text-color);
            font-family: 'Outfit', sans-serif;
            margin: 0;
            padding: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        header {
            width: 100%;
            max-width: 1200px;
            margin-bottom: 24px;
            text-align: center;
        }

        h1 {
            font-weight: 800;
            font-size: 2.5rem;
            margin: 0 0 8px 0;
            background: linear-gradient(135deg, #a855f7 0%, #38bdf8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .subtitle {
            color: var(--text-muted);
            font-size: 1.1rem;
            margin: 0;
        }

        .dashboard-container {
            width: 100%;
            max-width: 1200px;
            display: grid;
            grid-template-columns: 1fr;
            gap: 24px;
        }

        .card {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 24px;
            backdrop-filter: blur(12px);
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
        }

        .card-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-top: 0;
            margin-bottom: 16px;
            border-bottom: 1px solid var(--border-color);
            padding-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .chart-wrapper {
            width: 100%;
            height: 500px;
        }

        .controls {
            display: flex;
            gap: 12px;
            margin-bottom: 16px;
        }

        button {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid var(--border-color);
            color: var(--text-color);
            padding: 8px 16px;
            border-radius: 8px;
            cursor: pointer;
            font-family: inherit;
            transition: all 0.3s ease;
        }

        button:hover {
            background: rgba(255, 255, 255, 0.1);
            border-color: var(--primary);
        }

        button.active {
            background: var(--primary);
            color: #0f172a;
            font-weight: 600;
            border-color: var(--primary);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 16px;
            text-align: left;
        }

        th, td {
            padding: 12px;
            border-bottom: 1px solid var(--border-color);
        }

        th {
            color: var(--text-muted);
            font-weight: 600;
        }

        tr:hover td {
            background: rgba(255, 255, 255, 0.02);
        }

        .badge {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 6px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        .badge-2307 { background: rgba(255, 87, 34, 0.2); color: #ff5722; }
        .badge-2407-1 { background: rgba(0, 162, 232, 0.2); color: #00a2e8; }
        .badge-2407-2 { background: rgba(119, 172, 48, 0.2); color: #77ac30; }
        .badge-2507-1 { background: rgba(237, 108, 2, 0.2); color: #ed6c02; }
        .badge-2507-2 { background: rgba(126, 47, 142, 0.2); color: #7e2f8e; }
    </style>
</head>
<body>
    <header>
        <h1>Croatia Acoustic Signature Dashboard</h1>
        <p class="subtitle">Interactive Welch PSD & DEMON analysis of Croatia datasets (0-4 kHz)</p>
    </header>

    <div class="dashboard-container">
        <div class="card">
            <div class="card-title">
                <span>Croatia Welch Power Spectral Density (PSD)</span>
                <div class="controls">
                    <button id="toggle-welch-noise" class="active" onclick="toggleNoise('welch')">Toggle Background Noise</button>
                </div>
            </div>
            <div id="welch-chart" class="chart-wrapper"></div>
        </div>

        <div class="card">
            <div class="card-title">
                <span>Croatia DEMON Envelope Modulation Spectrum</span>
                <div class="controls">
                    <button id="toggle-demon-noise" class="active" onclick="toggleNoise('demon')">Toggle Background Noise</button>
                </div>
            </div>
            <div id="demon-chart" class="chart-wrapper"></div>
        </div>

        <div class="card">
            <div class="card-title">Detected Main Signal Peaks & Bandwidths</div>
            <table>
                <thead>
                    <tr>
                        <th>Dataset</th>
                        <th>Analysis Type</th>
                        <th>Peak Frequency</th>
                        <th>Power level</th>
                        <th>-3 dB Bandwidth Range</th>
                    </tr>
                </thead>
                <tbody id="peak-table-body">
                    <!-- Inserted via Javascript -->
                </tbody>
            </table>
        </div>
    </div>

    <script>
        const data = __DATA_PLACEHOLDER__;
        
        let showWelchNoise = true;
        let showDemonNoise = true;

        const colors = {
            Croatia_2307_free: '#ff5722',
            Croatia_2407_1_600m: '#00a2e8',
            Croatia_2407_2_snake: '#77ac30',
            Croatia_2507_1_1k: '#ed6c02',
            Croatia_2507_2_joint: '#7e2f8e'
        };

        const labels = {
            Croatia_2307_free: 'Croatia 2307 Free',
            Croatia_2407_1_600m: 'Croatia 2407_1 600m',
            Croatia_2407_2_snake: 'Croatia 2407_2 Snake',
            Croatia_2507_1_1k: 'Croatia 2507_1 1k',
            Croatia_2507_2_joint: 'Croatia 2507_2 Joint'
        };

        const badgeClasses = {
            Croatia_2307_free: 'badge-2307',
            Croatia_2407_1_600m: 'badge-2407-1',
            Croatia_2407_2_snake: 'badge-2407-2',
            Croatia_2507_1_1k: 'badge-2507-1',
            Croatia_2507_2_joint: 'badge-2507-2'
        };

        function renderCharts() {
            renderWelch();
            renderDemon();
            renderTable();
        }

        function renderWelch() {
            const traces = [];
            
            Object.keys(data.welch).forEach(dataset => {
                const freq = data.welch[dataset].freq;
                const psd = data.welch[dataset].psd;
                const col = colors[dataset];
                const label = labels[dataset];

                // 1. Raw spectrum curve
                traces.push({
                    x: freq.map(f => f / 1000), // convert to kHz
                    y: psd,
                    type: 'scatter',
                    mode: 'lines',
                    name: `${label} (Noise)`,
                    line: { color: col, width: 1 },
                    opacity: showWelchNoise ? 0.2 : 0.0,
                    hoverinfo: 'skip'
                });

                // 2. Peaks and Bandwidths
                const peaks = data.peaks[dataset].welch_peaks;
                peaks.forEach((peak, idx) => {
                    const fLow = peak.bw_low;
                    const fHigh = peak.bw_high;
                    
                    const segFreq = [];
                    const segPsd = [];
                    for(let i=0; i<freq.length; i++) {
                        if(freq[i] >= fLow && freq[i] <= fHigh) {
                            segFreq.push(freq[i] / 1000);
                            segPsd.push(psd[i]);
                        }
                    }

                    // Bandwidth segment trace
                    traces.push({
                        x: segFreq,
                        y: segPsd,
                        type: 'scatter',
                        mode: 'lines',
                        name: idx === 0 ? `${label}` : undefined,
                        legendgroup: dataset,
                        showlegend: idx === 0,
                        line: { color: col, width: 3 },
                        hovertemplate: `<b>${label} Peak</b><br>Freq: %{x:.3f} kHz<br>PSD: %{y:.2f} dB<br>BW: ${(fLow/1000).toFixed(3)}-${(fHigh/1000).toFixed(3)} kHz<extra></extra>`
                    });

                    // Peak marker trace
                    traces.push({
                        x: [peak.freq / 1000],
                        y: [peak.psd],
                        type: 'scatter',
                        mode: 'markers',
                        legendgroup: dataset,
                        showlegend: false,
                        marker: { color: col, symbol: 'triangle-up', size: 10 },
                        hovertemplate: `<b>${label} Peak</b><br>Freq: %{x:.3f} kHz<br>PSD: %{y:.2f} dB<br>BW: ${(fLow/1000).toFixed(3)}-${(fHigh/1000).toFixed(3)} kHz<extra></extra>`
                    });
                });
            });

            const layout = {
                paper_bgcolor: 'rgba(0,0,0,0)',
                plot_bgcolor: 'rgba(0,0,0,0)',
                xaxis: { title: 'Frequency [kHz]', color: '#94a3b8', range: [0, 4], gridcolor: 'rgba(255,255,255,0.05)' },
                yaxis: { title: 'PSD [dB re 1 \\u03bcPa\\u00b2/Hz]', color: '#94a3b8', gridcolor: 'rgba(255,255,255,0.05)' },
                legend: { font: { color: '#f8fafc' } },
                margin: { t: 20, b: 40, l: 60, r: 20 },
                hovermode: 'closest'
            };

            Plotly.newPlot('welch-chart', traces, layout, { responsive: true });
        }

        function renderDemon() {
            const traces = [];
            
            Object.keys(data.demon).forEach(dataset => {
                const freq = data.demon[dataset].freq;
                const psd = data.demon[dataset].psd;
                const col = colors[dataset];
                const label = labels[dataset];

                // 1. Raw spectrum curve
                traces.push({
                    x: freq,
                    y: psd,
                    type: 'scatter',
                    mode: 'lines',
                    name: `${label} (Noise)`,
                    line: { color: col, width: 1 },
                    opacity: showDemonNoise ? 0.2 : 0.0,
                    hoverinfo: 'skip'
                });

                // 2. Peaks and Bandwidths
                const peaks = data.peaks[dataset].demon_peaks;
                peaks.forEach((peak, idx) => {
                    const fLow = peak.bw_low;
                    const fHigh = peak.bw_high;
                    
                    const segFreq = [];
                    const segPsd = [];
                    for(let i=0; i<freq.length; i++) {
                        if(freq[i] >= fLow && freq[i] <= fHigh) {
                            segFreq.push(freq[i]);
                            segPsd.push(psd[i]);
                        }
                    }

                    // Bandwidth segment trace
                    traces.push({
                        x: segFreq,
                        y: segPsd,
                        type: 'scatter',
                        mode: 'lines',
                        name: idx === 0 ? `${label}` : undefined,
                        legendgroup: dataset,
                        showlegend: idx === 0,
                        line: { color: col, width: 3 },
                        hovertemplate: `<b>${label} Modulation Peak</b><br>Freq: %{x:.1f} Hz<br>PSD: %{y:.2f} dB<br>BW: ${fLow.toFixed(1)}-${fHigh.toFixed(1)} Hz<extra></extra>`
                    });

                    // Peak marker trace
                    traces.push({
                        x: [peak.freq],
                        y: [peak.psd],
                        type: 'scatter',
                        mode: 'markers',
                        legendgroup: dataset,
                        showlegend: false,
                        marker: { color: col, symbol: 'circle', size: 8 },
                        hovertemplate: `<b>${label} Modulation Peak</b><br>Freq: %{x:.1f} Hz<br>PSD: %{y:.2f} dB<br>BW: ${fLow.toFixed(1)}-${fHigh.toFixed(1)} Hz<extra></extra>`
                    });
                });
            });

            const layout = {
                paper_bgcolor: 'rgba(0,0,0,0)',
                plot_bgcolor: 'rgba(0,0,0,0)',
                xaxis: { title: 'Modulation Frequency [Hz]', color: '#94a3b8', range: [0, 4000], gridcolor: 'rgba(255,255,255,0.05)' },
                yaxis: { title: 'DEMON PSD [dB re 1 \\u03bcPa\\u00b2/Hz]', color: '#94a3b8', gridcolor: 'rgba(255,255,255,0.05)' },
                legend: { font: { color: '#f8fafc' } },
                margin: { t: 20, b: 40, l: 60, r: 20 },
                hovermode: 'closest'
            };

            Plotly.newPlot('demon-chart', traces, layout, { responsive: true });
        }

        function renderTable() {
            const tbody = document.getElementById('peak-table-body');
            tbody.innerHTML = '';

            Object.keys(data.peaks).forEach(dataset => {
                const label = labels[dataset];
                const badge = badgeClasses[dataset];
                
                // Welch Peaks
                data.peaks[dataset].welch_peaks.forEach(peak => {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td><span class="badge ${badge}">${label}</span></td>
                        <td>Welch PSD</td>
                        <td>${(peak.freq/1000).toFixed(3)} kHz</td>
                        <td>${peak.psd.toFixed(2)} dB</td>
                        <td>${(peak.bw_low/1000).toFixed(3)} - ${(peak.bw_high/1000).toFixed(3)} kHz</td>
                    `;
                    tbody.appendChild(tr);
                });

                // DEMON Peaks
                data.peaks[dataset].demon_peaks.forEach(peak => {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td><span class="badge ${badge}">${label}</span></td>
                        <td>DEMON modulation</td>
                        <td>${peak.freq.toFixed(1)} Hz</td>
                        <td>${peak.psd.toFixed(2)} dB</td>
                        <td>${peak.bw_low.toFixed(1)} - ${peak.bw_high.toFixed(1)} Hz</td>
                    `;
                    tbody.appendChild(tr);
                });
            });
        }

        function toggleNoise(type) {
            if(type === 'welch') {
                showWelchNoise = !showWelchNoise;
                document.getElementById('toggle-welch-noise').classList.toggle('active', showWelchNoise);
                renderWelch();
            } else {
                showDemonNoise = !showDemonNoise;
                document.getElementById('toggle-demon-noise').classList.toggle('active', showDemonNoise);
                renderDemon();
            }
        }

        window.onload = renderCharts;
    </script>
</body>
</html>
"""

# Replace placeholder with JSON string
html_output = html_template.replace("__DATA_PLACEHOLDER__", json.dumps(raw_data))

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(html_output)

print(f"Interactive dashboard successfully generated at {html_path}")
