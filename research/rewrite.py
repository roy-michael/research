import re

with open('c:/Users/Roy/dev/research/research/reports/envelope_intersections_report.md', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Remove the old Section 1 and Section 2
# Old Section 1 starts at "## 1. AUV Dataset" and goes until "## 2. Hear My Ship Datasets"
# Old Section 2 starts at "## 2. Hear My Ship Datasets" and goes until "## Summary"
text = re.sub(r'## 1\. AUV Dataset.*?## 2\. Hear My Ship Datasets', '## 2. Hear My Ship Datasets', text, flags=re.DOTALL)
text = re.sub(r'## 2\. Hear My Ship Datasets.*?## Summary', '## Summary', text, flags=re.DOTALL)

# 2. Renumber Sections
text = text.replace('## 3. Time Domain Envelopes', '## 1. Time Domain Envelopes')
text = text.replace('### 3.1 AUV', '### 1.1 AUV')
text = text.replace('### 3.3 Hear My Ship: Ferries', '### 1.2 Hear My Ship: Ferries')
text = text.replace('### 3.5 Hear My Ship: Motor Boats', '### 1.3 Hear My Ship: Motor Boats')
text = text.replace('### 3.6 Hear My Ship: Sail Boats', '### 1.4 Hear My Ship: Sail Boats')
text = text.replace('### 3.7 Hear My Ship: Tour Boats', '### 1.5 Hear My Ship: Tour Boats')
text = text.replace('### 3.8 Hear My Ship: Yachts', '### 1.6 Hear My Ship: Yachts')

text = text.replace('## 4. Time-Domain Zero-Crossing Bandwidth', '## 2. Time-Domain Zero-Crossing Bandwidth')
text = text.replace('## 5. Croatia Scooter Speed Transitions', '## 3. Croatia Scooter Speed Transitions')
text = text.replace('## 6. Chronological Tonal Evolution (20-Second Slices)', '## 4. Chronological Tonal Evolution (20-Second Slices)')
text = text.replace('## 7. Multi-Source Isolation: The Local Minima Method', '## 5. Multi-Source Isolation: The Local Minima Method')
text = text.replace('## 8. Consolidated Representative PSD Profiles', '## 6. Consolidated Representative PSD Profiles')

# 3. Add ALL timeline plots to the Timeline section (Now Section 4)
timeline_section_replacement = '''## 4. Chronological Tonal Evolution (20-Second Slices)

To visually map the frequency variance of the continuous maneuvers, the continuous acoustic datasets were chunked into sequential 20-second buffers. For each 20s slice, the dominant spectral peak(s) (Peak Frequency) and their calculated envelope intersections (Bandwidth) were extracted. 

In the scatter plots below, the **Y-Axis** represents the measured Peak Frequency (Hz), and the **Error Bars** represent the measured Bandwidth for that specific 20s slice. 

> [!TIP]
> Notice how wildly the Peak Frequency jumps over time as the driver hits the throttle or changes speeds, yet the vertical error bars (Bandwidth) remain razor-thin and tightly locked at $\sim 11\text{-}13\text{ Hz}$ across the entire duration!

### AUV Array (CPA)
![AUV Array (CPA)](images/bandwidth/AUV-Array-(CPA)-timeline.png)

### Croatia - 2307
![Croatia 2307](images/bandwidth/Croatia-2307-timeline.png)

### Croatia - 2307_free
![Croatia 2307_free](images/bandwidth/Croatia-2307-free-timeline.png)

### Croatia - 2407_1_600m
![Croatia 2407 600m](images/bandwidth/Croatia-2407-1-600m-timeline.png)

### Croatia - 2407_2_snake
![Croatia 2407_2_snake](images/bandwidth/Croatia-2407-2-snake-timeline.png)

### Croatia - 2507_1_1k
![Croatia 2507 1k](images/bandwidth/Croatia-2507-1-1k-timeline.png)

### Croatia - 2507_2_joint
![Croatia 2507_2_joint](images/bandwidth/Croatia-2507-2-joint-timeline.png)

### Departmental Cruise
![Departmental Cruise](images/bandwidth/Departmental-Cruise-timeline.png)
'''

# Find the old section 6 block and replace it
text = re.sub(r'## 4\. Chronological Tonal Evolution \(20-Second Slices\).*?## 5\. Multi-Source Isolation', timeline_section_replacement + '\n\n## 5. Multi-Source Isolation', text, flags=re.DOTALL)

with open('c:/Users/Roy/dev/research/research/reports/envelope_intersections_report.md', 'w', encoding='utf-8') as f:
    f.write(text)
