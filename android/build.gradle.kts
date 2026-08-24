allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    // Some plugins (flutter_pcm_sound) declare their own compileSdk in their
    // plugin-level build.gradle, independent of the app module's - here that
    // was 33, too low for AndroidX deps those same plugins pull in (need
    // 34+). Force every Android library subproject to match the app's
    // compileSdk (37) instead of patching each plugin individually. Must run
    // *after* the plugin's own build.gradle sets its compileSdkVersion, not
    // before - otherwise that later line just overwrites ours back to 33.
    //
    // evaluationDependsOn(":app") above triggers :app's Flutter Gradle
    // Plugin to eagerly evaluate every Flutter-plugin subproject as part of
    // its own configuration, so by the time this loop reaches some of them
    // they're *already* evaluated - afterEvaluate() throws on an
    // already-evaluated project, so check state.executed first and apply
    // immediately in that case instead of registering a callback.
    val forceCompileSdk: () -> Unit = {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.compileSdk = 37
    }
    if (project.state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
