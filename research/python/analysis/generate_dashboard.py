import os
import sys
import json
import argparse
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from config import get_output_dir

# Dynamic colors and badges logic
COLORS = ['#ff5722', '#00a2e8', '#77ac30', '#f43f5e', '#38bdf8', '#8b5cf6']
BADGE_CLASSES = ['badge-petrol', 'badge-electric', 'badge-croatia', 'badge-red', 'badge-blue', 'badge-purple']

# Fallback styles if classes don't exist
EXTRA_STYLES = """
        .badge-red { background: rgba(244, 63, 94, 0.2); color: #f43f5e; }
        .badge-blue { background: rgba(56, 189, 248, 0.2); color: #38bdf8; }
        .badge-purple { background: rgba(139, 92, 246, 0.2); color: #8b5cf6; }
"""

html_template = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{DASHBOARD_TITLE}</title>
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
            background: linear-gradient(135deg, #38bdf8 0%, #a855f7 100%);
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
        .badge-petrol { background: rgba(237, 108, 2, 0.2); color: #ed6c02; }
        .badge-electric { background: rgba(0, 162, 232, 0.2); color: #00a2e8; }
        .badge-croatia { background: rgba(119, 172, 48, 0.2); color: #77ac30; }
{EXTRA_STYLES}
    </style>
</head>
<body>
    <header>
        <h1>{DASHBOARD_TITLE}</h1>
        <p class="subtitle">{DASHBOARD_SUBTITLE}</p>
    </header>

    <div class="dashboard-container">
        <div class="card">
            <div class="card-title">
                <span>Welch Power Spectral Density (PSD)</span>
                <div class="controls">
                    <button id="toggle-welch-noise" class="active" onclick="toggleNoise('welch')">Toggle Background Noise</button>
                </div>
            </div>
            <div id="welch-chart" class="chart-wrapper"></div>
        </div>

        <div class="card">
            <div class="card-title">
                <span>DEMON Envelope Modulation Spectrum</span>
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

        const dynamicColors = __COLORS_PLACEHOLDER__;
        const dynamicLabels = __LABELS_PLACEHOLDER__;
        const dynamicBadges = __BADGES_PLACEHOLDER__;

        function renderCharts() {
            renderWelch();
            renderDemon();
            renderTable();
        }

        function renderWelch() {
            const traces = [];
            
            // Loop through each dataset
            Object.keys(data.welch).forEach(dataset => {
                const freq = data.welch[dataset].freq;
                const psd = data.welch[dataset].psd;
                const col = dynamicColors[dataset];
                const label = dynamicLabels[dataset];

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

                // 2. Main Signal Peaks and Bandwidths
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
                const col = dynamicColors[dataset];
                const label = dynamicLabels[dataset];

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
                const label = dynamicLabels[dataset];
                const badge = dynamicBadges[dataset];
                
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

def generate_dashboard(json_path, dataset_name, title, subtitle):
    if not os.path.exists(json_path):
        print(f"Error: {json_path} does not exist.")
        return

    with open(json_path, 'r') as f:
        raw_data = json.load(f)

    datasets = list(raw_data['welch'].keys())
    
    dynamic_colors = {}
    dynamic_labels = {}
    dynamic_badges = {}
    
    for i, ds in enumerate(datasets):
        dynamic_colors[ds] = COLORS[i % len(COLORS)]
        dynamic_labels[ds] = ds.replace('_', ' ')
        dynamic_badges[ds] = BADGE_CLASSES[i % len(BADGE_CLASSES)]

    html_output = html_template.replace("{DASHBOARD_TITLE}", title)
    html_output = html_output.replace("{DASHBOARD_SUBTITLE}", subtitle)
    html_output = html_output.replace("{EXTRA_STYLES}", EXTRA_STYLES)
    html_output = html_output.replace("__DATA_PLACEHOLDER__", json.dumps(raw_data))
    html_output = html_output.replace("__COLORS_PLACEHOLDER__", json.dumps(dynamic_colors))
    html_output = html_output.replace("__LABELS_PLACEHOLDER__", json.dumps(dynamic_labels))
    html_output = html_output.replace("__BADGES_PLACEHOLDER__", json.dumps(dynamic_badges))

    out_dir = get_output_dir(dataset_name)
    html_path = out_dir / f"{dataset_name}_dashboard.html"

    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html_output)

    print(f"Interactive dashboard successfully generated at {html_path}")

def main():
    parser = argparse.ArgumentParser(description="Generate interactive HTML dashboard from JSON data.")
    parser.add_argument("--json", required=True, help="Path to the JSON data file")
    parser.add_argument("--dataset-name", required=True, help="Name of the dataset")
    parser.add_argument("--title", default="Acoustic Signature Live Dashboard", help="Dashboard title")
    parser.add_argument("--subtitle", default="Interactive Welch PSD & DEMON analysis", help="Dashboard subtitle")
    
    args = parser.parse_args()
    generate_dashboard(args.json, args.dataset_name, args.title, args.subtitle)

if __name__ == '__main__':
    main()
