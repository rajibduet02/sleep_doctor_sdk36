# SleepDoctor App

Files, descriptions and resources can be found at links below:  


- Materials (Icons, Bluetooth Definition, ...): [Materials](https://seafile.oput.de/smart-link/1f12f82d-de34-4baa-a1d1-84d4646a110c/)
- Bundle Id: de.iptasys.sleepdoctor

# SleepDoctor Details:
- Font (everywhere): Roboto 
- App Name: SleepDoctor

# Manually building Android release apk
1. Add key.properties file from Seafile to project at [project]/android/key.properties (mustn't be added to git!)
2. Signing in build gradle is already defined
3. Update version name + code in pubspec.yaml
4. Build APK with Android Studio: Build->Flutter->Build APK
5. APK can be found here: [project]\build\app\outputs\apk\release

# Getting Started
## Install Flutter
Its recommended to follow the steps in this installation guide: https://www.youtube.com/watch?v=hL7pkX1Pfko
However, the basic steps are:
- Visit the ([Flutter Installation Guide](https://flutter.dev/docs/get-started/install)) for the steps below 
- Download Flutter via pull of the github repo or just download the latest version on ([Flutter installation guide](https://flutter.dev/docs/get-started/install))
- IMPORTANT: Add flutter/bin folder to the operating system paths. (For Mac and linux): Make sure which shell you use. Typing echo $SHELL in your Terminal tells you which shell you’re using. If you’re using Bash, edit $HOME/.bash_profile or $HOME/.bashrc. If you’re using Z shell, edit $HOME/.zshrc. If you’re using a different shell, the file path and filename will be different on your machine.
- restart the terminal
- run "flutter --version" to check if flutter was installed successfully


## Run Flutter for different IDEs
Android Studio:
- Install plugins see: ([Flutter Plugin For Android Studio](https://flutter.dev/docs/get-started/editor?tab=androidstudio)) 
- Test Basic App: ([Basic App run in Android Studio](https://flutter.dev/docs/get-started/test-drive?tab=androidstudio))

VSCode:
- Install extension see: ([Flutter Extensions For VSCode](https://flutter.dev/docs/get-started/editor?tab=vscode))  
- Test Basic App: ([Basic App run in VSCode](https://flutter.dev/docs/get-started/test-drive?tab=vscode))

## Import Flutter project in Android Studio 
- If you get the warning "Dart SDK is not configured":
    - Open the Android Settings (ctrl+alt+s)
    - Select under "Languages and Frameworks" the option "Dart"
    - Check "Enable Dart support for the project..."
    - In "Dart SDK path" click in "..." and navigate to flutter SDK directory. Under that directory, you'll find the "bin/cache/dart-sdk" that should be used.
    - Click Apply
    - Re-open the project  
    
- If you get the warning "pub get has not been" click on "Get dependencies" 

#Run Flutter App on real Android device 
- Enable the USB debugging option on your device
- Connect the device to your computer via USB 
- Open the terminal and navigate to your project folder
- Execute the command: "flutter run"
- Enable the installation process on your phone  

# Flutter Commands
## See [Helpful Flutter Commands on Medium](https://medium.com/flutter-community/flutter-and-the-command-line-a-love-story-a3648ef2411)

## Available commands: (e.g. flutter analyze)
- flutter analyze        -->   Analyze the project's Dart code.
- flutter assemble       -->   Assemble and build flutter resources.
- flutter attach         -->   Attach to a running application.
- flutter bash-completion -->  Output command line shell completion setup scripts.
- flutter build           -->  Flutter build commands.
- flutter channel         -->  List or switch flutter channels.
- flutter clean          -->   Delete the build/ and .dart_tool/ directories.
- flutter config         -->   Configure Flutter settings.
- flutter create         -->   Create a new Flutter project.
- flutter devices        -->   List all connected devices.
- flutter doctor         -->   Show information about the installed tooling.
- flutter downgrade      -->   Downgrade Flutter to the last active version for the current channel.
- flutter drive          -->   Runs Flutter Driver tests for the current project.
- flutter emulators      -->   List, launch and create emulators.
- flutter format         -->   Format one or more dart files.
- flutter gen-l10n       -->   Generate localizations for the Flutter project.
- flutter install        -->   Install a Flutter app on an attached device.
- flutter logs           -->   Show log output for running Flutter apps.
- flutter precache       -->   Populates the Flutter tool's cache of binary artifacts.
- flutter pub            -->   Commands for managing Flutter packages.
- flutter run            -->   Run your Flutter app on an attached device.
- flutter screenshot     -->   Take a screenshot from a connected device.
- flutter symbolize      -->   Symbolize a stack trace from an AOT compiled flutter application.
- flutter test           -->   Run Flutter unit tests for the current project.
- flutter upgrade        -->   Upgrade your copy of Flutter.


## Further information on how Getting Started with Flutter:

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://flutter.dev/docs/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://flutter.dev/docs/cookbook)

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.