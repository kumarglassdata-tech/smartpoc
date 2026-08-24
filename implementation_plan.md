# Goal Description

Implement client-side Speaker Verification ("Enroll Voice") as a fallback activation method when the "Hey Myna" wake-word toggle is disabled. The system will guide the user to read a short story 4 times to extract voice embeddings via the ECAPA-TDNN ONNX model, save them locally per-user in JSON format, and allow them to test verification against other speakers.

## User Review Required

> [!WARNING]  
> **DSP Implementation Complexity in Dart**
> The reference Python script uses `librosa` and `torchaudio`/`kaldi` standard DSP functions (Mel filterbanks, pre-emphasis, Short-Time Fourier Transform). Translating these exact mathematical operations to pure Dart so the ONNX model receives the exact distribution it expects is highly non-trivial but achievable. I will implement a Dart-based `KaldiFbank` class that mirrors the Python `_kaldi_fbank` logic.

## Open Questions

> [!IMPORTANT]  
> 1. **ONNX Model Availability**: The reference script mentions `voxceleb_ECAPA512.onnx`. Do you already have this model downloaded and placed in the `assets/models/` directory? (If not, I'll assume we need to add it to `pubspec.yaml` assets).
> 2. **Authentication / User ID**: The requirements mention "individual user login candidate individual json file". I will use the email from `AuthProvider` as the unique ID for saving the JSON profile. Is this acceptable?
> 3. **Audio Recording Plugin**: The project currently uses `record` and `flutter_pcm_sound`. I will use the `record` package to capture the 16kHz PCM audio needed for enrollment.

## Proposed Changes

---

### UI & Navigation

#### [MODIFY] `lib/settings_screen.dart`
- Update the `onChanged` callback for the "Wake word" switch.
- If the user turns it off (`value == false`), navigate to the new `EnrollVoiceScreen` before applying the change.

#### [NEW] `lib/auth/enroll_voice_screen.dart`
- Create a new Stateful widget displaying a pleasant 5-7 sentence paragraph.
- Implement a step-by-step UI:
  - **Enrollment Phase**: Ask the user to record themselves reading the paragraph 4 times. Update progress (0/4 -> 4/4).
  - **Testing Phase**: Once enrolled, display a "Test Voice" section where anyone can speak into the mic, and the app will display whether it is the enrolled user or "Other/Unknown" based on cosine similarity.

---

### Speaker Verification Logic (Client-Side)

#### [NEW] `lib/interaction_engine/speaker_verification_client.dart`
- **Core logic translated from Python**:
  - `loadModel()`: Load `voxceleb_ECAPA512.onnx` via the `flutter_onnxruntime` package.
  - `extractEmbedding(Int16List pcmData)`: 
    - Trim silence (based on RMS energy).
    - Convert to Kaldi Log-Mel Filterbanks (Pre-emphasis, Hamming window, FFT, Mel-scale triangular filters, Cepstral Mean Normalization).
    - Run the resulting `(1, T, 80)` tensor through the ONNX session to get a `(1, 192)` float embedding.
    - L2 normalize the embedding.
  - `cosineSimilarity(a, b)`: Helper to compare two embeddings.

#### [NEW] `lib/interaction_engine/speaker_profile.dart`
- **Profile Management**:
  - Load and save profiles to `<AppDocumentsDir>/speaker_profiles/<user_email>.json`.
  - Maintain a list of up to 5 embeddings.
  - Provide a `classify()` method that averages the stored embeddings and checks the cosine similarity against the `USER_SIM_THRESHOLD` (e.g. `0.60`).

---

### Permissions & Assets

#### [MODIFY] `pubspec.yaml`
- Ensure `assets/models/voxceleb_ECAPA512.onnx` is registered.
- (Ensure `path_provider` and `record` are ready for use, which they already appear to be).

## Verification Plan

### Manual Verification
1. Open the Settings screen and toggle "Wake word" to OFF.
2. Verify that the app navigates to the `EnrollVoiceScreen`.
3. Complete the 4-step reading enrollment. Verify that the `<email>.json` file is written to the device's local storage with the embeddings.
4. Use the "Test" button on the screen:
   - Speak as the enrolled user and verify it says "User".
   - Have someone else speak (or play a recording of someone else) and verify it says "Other/Unknown".
