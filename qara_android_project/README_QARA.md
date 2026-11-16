# قەرە (Qara) — Flutter Android AI assistant

## Included
- Kurdish Sorani chat interface with Markdown responses.
- Gemini `generateContent` and OpenAI-compatible `chat/completions` API support.
- Multiple provider profiles, model selection, and model-list retrieval.
- API keys stored locally with `flutter_secure_storage`.
- Local chat history and an editable memory note.
- Text-to-speech and microphone speech recognition.
- Optional Android microphone foreground service for the wake phrase `قەرە`.

## Build requirements
- Flutter 3.35.7 (stable)
- Java 17
- Android Gradle Plugin 8.9.1
- Gradle 8.11.1
- Kotlin 2.2.20

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## First run
1. Open API settings.
2. Add a Gemini, OpenAI, or OpenAI-compatible provider and its API key.
3. Choose the active provider and model.
4. Enable voice output if desired.
5. To use background wake listening, grant microphone and notification permissions and tap the hearing icon. A persistent Android notification is shown while the microphone service is active.

## Android / Redmi note
The wake listener is opt-in and uses Android `SpeechRecognizer`, not a dedicated offline wake-word model. Recognition language availability and long-running behavior depend on the device's speech service, language packs, and battery policy. On Xiaomi/MIUI/HyperOS, allow background/autostart activity and remove battery restrictions if the OS stops the service. The wake phrase updates the notification; tap it to return to Qara. It does not secretly record audio or automatically open a conversation.

Speech recognition may use the device's configured recognition service and may process audio outside the phone. Keep background listening disabled unless you accept this behavior. The persistent notification indicates when listening is active.

## API endpoints
- Gemini base: `https://generativelanguage.googleapis.com/v1beta`
- Gemini example model: `gemini-2.5-flash`
- OpenAI base: `https://api.openai.com/v1`
- OpenAI example model: `gpt-4o-mini`
- OpenAI-compatible services must support `/chat/completions` and `/models` with compatible response formats.

An API key inside a distributed mobile app can be extracted by a determined user. Secure local storage protects casual access on the device but does not make a client-side key a server secret. For a public product, use an authenticated backend and keep provider keys on the server.

## Release signing
CI uses debug signing for a test-installable APK. Configure a private upload keystore before public distribution. Never commit the keystore or passwords to the repository.
