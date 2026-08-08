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
![KNN Boundary](./images/vessel_classification_boundary.png)

### Custom Quadratic Logistic Regression Boundary
![LogReg Boundary](./images/vessel_logreg_boundary.png)

### Custom Random Forest Boundary
![RF Boundary](./images/vessel_rf_boundary.png)

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

## Code Reference

* [train_vessel_classifier.m](file:///d:/dev/research/research/matlab/train_vessel_classifier.m)
* [classify_new_directory.m](file:///d:/dev/research/research/matlab/classify_new_directory.m)
* [extract_vessel_timeframes.m](file:///d:/dev/research/research/matlab/extract_vessel_timeframes.m)
