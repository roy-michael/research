// script.js
const c = 1500; // Speed of sound (m/s)
let txChart, rxChart;

// DOM Elements
const elements = {
    depthSrc: document.getElementById('depthSrc'),
    srcDepthGroup: document.getElementById('srcDepthGroup'),
    freq0: document.getElementById('freq0'),
    heaveAmp: document.getElementById('heaveAmp'),
    heaveFreq: document.getElementById('heaveFreq'),
    range: document.getElementById('range'),
    depthRec: document.getElementById('depthRec'),
    roughness: document.getElementById('roughness'),
    
    valDepthSrc: document.getElementById('depthSrc-val'),
    valFreq0: document.getElementById('freq0-val'),
    valHeaveAmp: document.getElementById('heaveAmp-val'),
    valHeaveFreq: document.getElementById('heaveFreq-val'),
    valRange: document.getElementById('range-val'),
    valDepthRec: document.getElementById('depthRec-val'),
    valRoughness: document.getElementById('roughness-val'),

    metricTheta: document.getElementById('metric-theta'),
    metricBeta: document.getElementById('metric-beta'),
    metricDoppler: document.getElementById('metric-doppler')
};

// Event Listeners
Object.keys(elements).forEach(key => {
    if (elements[key] && elements[key].tagName === 'INPUT') {
        elements[key].addEventListener('input', updateSimulation);
    }
});
function initCharts() {
    const ctxTx = document.getElementById('txChart').getContext('2d');
    const ctxRx = document.getElementById('rxChart').getContext('2d');

    const commonOptions = {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        elements: { 
            point: { radius: 0 }, 
            line: { borderWidth: 2, tension: 0.3 } 
        },
        scales: {
            x: { 
                type: 'linear', 
                grid: { color: 'rgba(255, 255, 255, 0.1)' },
                ticks: { color: '#94a3b8' },
                title: { display: true, text: 'Time (s)', color: '#94a3b8' }
            },
            y: { 
                grid: { color: 'rgba(255, 255, 255, 0.1)' },
                ticks: { color: '#94a3b8' },
                min: -2, max: 2
            }
        },
        plugins: { 
            legend: { display: false },
            zoom: {
                pan: {
                    enabled: true,
                    mode: 'x'
                },
                zoom: {
                    wheel: {
                        enabled: true,
                    },
                    pinch: {
                        enabled: true
                    },
                    mode: 'x'
                }
            }
        }
    };

    txChart = new Chart(ctxTx, {
        type: 'line',
        data: { datasets: [{ label: 'p_tx(t)', borderColor: '#3b82f6', data: [] }] },
        options: commonOptions
    });

    rxChart = new Chart(ctxRx, {
        type: 'line',
        data: { datasets: [{ label: 'p_rx(t)', borderColor: '#ec4899', data: [] }] },
        options: commonOptions
    });
    
    document.getElementById('resetZoomBtn').addEventListener('click', () => {
        txChart.resetZoom();
        rxChart.resetZoom();
    });
}

let updateTimeout = null;

function updateSimulation() {
    // Update value displays immediately for snappy UI feel
    elements.valDepthSrc.textContent = elements.depthSrc.value;
    elements.valFreq0.textContent = elements.freq0.value;
    elements.valHeaveAmp.textContent = elements.heaveAmp.value;
    elements.valHeaveFreq.textContent = elements.heaveFreq.value;
    elements.valRange.textContent = elements.range.value;
    elements.valDepthRec.textContent = elements.depthRec.value;
    elements.valRoughness.textContent = elements.roughness.value;

    // Debounce network requests by 15ms so rapid dragging doesn't queue up requests
    if (updateTimeout) clearTimeout(updateTimeout);
    updateTimeout = setTimeout(() => {
        executeSimulation();
    }, 15);
}

function executeSimulation() {
    // Get values
    const f0 = parseFloat(elements.freq0.value);
    const Aw = parseFloat(elements.heaveAmp.value);
    const fw = parseFloat(elements.heaveFreq.value);
    const R = parseFloat(elements.range.value);
    const Hrec = parseFloat(elements.depthRec.value);
    const R0 = parseFloat(elements.roughness.value);
    const depthSrc = parseFloat(elements.depthSrc.value);
    
    // Fetch from Python backend
    const query = new URLSearchParams({
        f0: f0,
        Aw: Aw,
        fw: fw,
        R: R,
        Hrec: Hrec,
        R0: R0,
        depthSrc: depthSrc
    }).toString();

    fetch(`/api/simulate?${query}`)
        .then(response => response.json())
        .then(data => {
            if (data.error) {
                console.error("Simulation error:", data.error);
                return;
            }

            // Update Metrics
            elements.metricTheta.textContent = (data.theta_g * 180 / Math.PI).toFixed(2) + '°';
            elements.metricBeta.textContent = data.beta.toFixed(2);
            elements.metricDoppler.textContent = data.deltaF.toFixed(2) + ' Hz';

            // Convert compact arrays to chart points
            const txPoints = data.t.map((tVal, i) => ({ x: tVal, y: data.tx[i] }));
            const rxPoints = data.t.map((tVal, i) => ({ x: tVal, y: data.rx[i] }));

            // Update charts smoothly
            txChart.data.datasets[0].data = txPoints;
            rxChart.data.datasets[0].data = rxPoints;
            txChart.update('none'); // 'none' skips animation for instant rendering
            rxChart.update('none');
        })
        .catch(err => console.error("Fetch error:", err));
}

// Initialize
initCharts();
updateSimulation();
