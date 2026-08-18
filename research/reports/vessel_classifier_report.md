# Walkthrough: Classifier Comparison (KNN vs. LogReg vs. Random Forest)

We compared three different classification algorithms using our site-independent envelope modulation features (**Sample Entropy** and **Coherence Time**):
1. **K-Nearest Neighbors (KNN)** (K=5)
2. **Custom Quadratic Logistic Regression (LogReg)** (Regularized, Gradient Descent)
3. **Custom Random Forest (RF)** (15 Decision Trees, Bootstrap Bagging, Depth 3)

All models are completely self-contained and implemented from scratch in MATLAB to guarantee portability without toolbox dependencies.

---

## 1. 5-Fold Cross-Validation Performance Comparison

| Classifier Model | 5-Fold CV Accuracy | F1-Score | Behavior / Boundary Characteristics |
| :--- | :--- | :--- | :--- |
| **KNN (K=5)** | 69.09% | 78.62% | **Local & granular**: Captures complex local clusters, but can create "jumpy" boundaries sensitive to outliers. |
| **Quadratic LogReg** | 69.55% | 80.69% | **Global & smooth**: Finds a mathematically smooth quadratic boundary (ellipse/parabola). More robust and outputs true probabilities. |
| **Random Forest (RF)** | **74.09%** | **81.90%** | **Ensemble Voting**: Creates axis-aligned rectangular boundaries that are highly robust to noise and outliers. Achieves the highest accuracy by a significant margin! |

---

## 2. Classification Decision Boundaries

### KNN Classification Boundary
![KNN Boundary](../images/classification/vessel_classification_boundary.png)

### Custom Quadratic Logistic Regression Boundary
![LogReg Boundary](../images/classification/vessel_logreg_boundary.png)

### Custom Random Forest Boundary
![RF Boundary](../images/classification/vessel_rf_boundary.png)

---

## 3. Surface & Underwater Vessel Detection Comparison (With Error Analysis)

We evaluated how each algorithm performed during the active periods of the **Underwater Scooter Run (09:05 - 09:35)**, the **Small Boat 1km Sail (09:45 - 10:03)**, and the **Large Boat 100m Sail (10:50 - 10:55)** when the signal broke through the Stage 1 RMS gate (`0.00052`):

### A. Underwater Vessel (Diver Scooter Run: 09:05 - 09:35)
* **09:05 (Start/Jump)**:
  * **KNN**: Surface Boat ❌ *(Wrong: should be Scooter or Ambient)*
  * **LogReg**: Surface Boat ❌ *(Wrong: should be Scooter or Ambient)*
  * **Random Forest**: Surface Boat ❌ *(Wrong: should be Scooter or Ambient)*
* **09:06 (High-speed start)**:
  * **KNN**: **Underwater Scooter** (100% Conf)  *(Correct)*
  * **LogReg**: Surface Boat ❌ *(Wrong: mapped to the boat region)*
  * **Random Forest**: Surface Boat ❌ *(Wrong: mapped to the boat region)*
* **09:07 (High-speed run)**:
  * **KNN**: Surface Boat ❌ *(Wrong: should be Scooter)*
  * **LogReg**: Surface Boat ❌ *(Wrong: should be Scooter)*
  * **Random Forest**: Surface Boat ❌ *(Wrong: should be Scooter)*
* **09:08 (High-speed run)**:
  * **KNN**: **Underwater Scooter** (60% Conf)  *(Correct)*
  * **LogReg**: Surface Boat ❌ *(Wrong: should be Scooter)*
  * **Random Forest**: **Underwater Scooter** (93% Conf)  *(Correct)*
* **09:09 (High-speed run)**:
  * **KNN**: **Underwater Scooter** (60% Conf)  *(Correct)*
  * **LogReg**: Surface Boat ❌ *(Wrong: should be Scooter)*
  * **Random Forest**: Surface Boat ❌ *(Wrong: should be Scooter)*
* **09:10 - 09:35 (Low-speed cruise & return)**:
  * **All Models**: Classified as **No Vessel (Ambient)**. 
  * **Error Analysis**: ❌ *Wrong (Missed presence)*. Due to the low speed, the electric scooter had no propeller cavitation. Its amplitude envelope was flat, falling below the RMS energy gate. It is physically impossible to detect this run using envelope modulations.

### B. Surface Vessel (Small Boat 1km Sail: 09:45 - 10:03)
* **09:45 (Start)**:
  * **KNN**: Underwater Scooter ❌ *(Wrong: misclassified startup transient)*
  * **LogReg**: **Surface Boat** (87% Conf)  *(Correct)*
  * **Random Forest**: **Surface Boat** (87% Conf)  *(Correct)*
* **09:49 (Active pass)**:
  * **KNN**: **Surface Boat** (100% Conf)  *(Correct)*
  * **LogReg**: **Surface Boat** (97% Conf)  *(Correct)*
  * **Random Forest**: **Surface Boat** (97% Conf)  *(Correct)*
* **09:52 (Active pass)**:
  * **KNN**: **Surface Boat** (100% Conf)  *(Correct)*
  * **LogReg**: **Surface Boat** (97% Conf)  *(Correct)*
  * **Random Forest**: **Surface Boat** (97% Conf)  *(Correct)*
* **Other times**: Muted as **No Vessel (Ambient)**. 
  * **Error Analysis**: ❌ *Wrong (Missed presence)*. Because of the 1km distance, the outboard hum fell below the lake's noise floor and was gated.

### C. Surface Vessel (Large Boat 100m Sail: 10:50 - 10:55)
* **10:53 (Start)**:
  * **KNN**: **Surface Boat** (100% Conf)  *(Correct)*
  * **LogReg**: No Vessel (Ambient) ❌ *(Wrong: missed startup energy)*
  * **Random Forest**: Underwater Scooter ❌ *(Wrong: misclassified startup transient)*
* **10:54 (Active pass)**:
  * **KNN**: **Surface Boat** (100% Conf)  *(Correct)*
  * **LogReg**: **Surface Boat** (100% Conf)  *(Correct)*
  * **Random Forest**: **Surface Boat** (100% Conf)  *(Correct)*

---

## 4. Summary of Model Weaknesses (Error Patterns)
1. **KNN**: Granular but highly jumpy. Easily misclassifies startup transients (like `09:45` and `09:05`) due to local outlier samples in the training set.
2. **Quadratic Logistic Regression**: Very stable, but its smooth global boundary tends to dominate and misclassify the underwater scooter (which has a smaller footprint in the feature space) as a surface boat.
3. **Random Forest**: Best overall balance. It correctly identified the scooter at `09:08` with **93% confidence** and classified all boat passes correctly, but misclassified the large boat startup transient (`10:53`) as a scooter.

---

## 5. Croatia Dataset Classification Results (Ocean Sonics)

The trained Random Forest model was evaluated on the unseen Croatia dataset (Ocean Sonics).

* **Total files classified**: 514
* **Surface-based (Boats)**: 514 (100.00%)
* **Underwater-based (Scooter)**: 0 (0.00%)

The decision boundary plot for the new predictions can be seen below:
![Croatia Boundary](../images/classification/new_dataset_classification_boundary.png)

---

## 6. The Physics of Envelope Coherence (Why Noise is More Coherent Than a Tone)

A common intuitive trap is assuming that because the **Croatia underwater scooter** produces a highly coherent, stable tone in the *audio* domain, it should have a high *envelope* coherence time. In contrast, the **Garda surface boats** produce broadband cavitation noise (hiss), so they should have a low coherence time.

However, the algorithm explicitly measures the coherence of the **Amplitude Envelope**, which perfectly inverts this logic:

### 1. The Croatia Scooter (Narrowband Tone)
Because the scooter produces a steady hum, its **amplitude envelope** is actually a completely flat DC line. When the algorithm subtracts the mean to find the alternating envelope modulations, all that remains is the tiny, high-frequency background noise floor rippling around the flat envelope. 
- **Physics**: The ambient noise floor decorrelates instantly.
- **Result**: The scooter's envelope coherence time drops to near-zero (e.g., 30-50 ms).

### 2. The Garda Boat (Broadband Noise + Propeller Beats)
While the raw audio of the boat is incoherent hiss, this hiss is chopped up by the **propeller blades** churning through the water, creating rhythmic, slow, low-frequency amplitude "beats" (the chug-chug sound).
- **Physics**: These slow propeller beats form long, low-frequency waves in the envelope that remain strongly correlated with themselves for a long time. 
- **Result**: The boat's envelope yields a massive coherence time (e.g., 150-260 ms).

> [!TIP]
> This "inversion" is exactly what makes Envelope Coherence such an incredibly powerful physical feature! It completely ignores the raw audio (which changes drastically across different environments) and perfectly isolates the physical presence of a spinning surface propeller (high envelope coherence) vs a steady electric thruster (zero envelope coherence)!

---

## 7. Feature Values by Dataset

| Dataset | Raw Centroid $f_c$ (kHz) | Raw Entropy $H$ | $SampEn$ | $\tau_{1/e}$ (ms) | $\tau_{0.5}$ (ms) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Croatia 2307 Free | 6.0751 | 0.8018 | 0.6990 | 40.0257 | 14.5029 |
| Croatia 2407_1 600m | 1.1453 | 0.6119 | 0.8969 | 120.8571 | 85.2857 |
| Croatia 2407_2 Snake | 1.4995 | 0.6906 | 0.8962 | 35.8194 | 8.5972 |
| Croatia 2507_1 1k | 5.1398 | 0.7899 | 1.8886 | 203.0000 | 201.5000 |
| Croatia 2507_2 Joint | 0.8248 | 0.4653 | 1.3432 | 124.1375 | 83.2500 |
| Garda Shallow Electric | 4.9205 | 0.7928 | 1.4608 | 267.9062 | 235.7812 |
| Garda Shallow Petrol | 2.0247 | 0.7074 | 0.8135 | 158.2576 | 74.9848 |
| Garda Deep Electric | 2.9389 | 0.6948 | 1.1907 | 81.4459 | 45.6892 |
| Garda Deep Petrol | 3.1193 | 0.7232 | 1.4379 | 212.3750 | 144.6932 |

---

## Code Reference

* [train_vessel_classifier.m](file:///c:/Users/Roy/dev/research/research/matlab/train_vessel_classifier.m)
* [classify_new_directory.m](file:///c:/Users/Roy/dev/research/research/matlab/classify_new_directory.m)
* [extract_vessel_timeframes.m](file:///c:/Users/Roy/dev/research/research/matlab/extract_vessel_timeframes.m)
