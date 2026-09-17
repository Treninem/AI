pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Keep the benchmark dependency graph identical to the production
        // Android runtime: OCR is resolved from JitPack in android_plugin.
        maven { url = uri("https://jitpack.io") }
    }
}

rootProject.name = "AuroraFoxCoreBenchmark"
include(":app", ":runtime")
project(":runtime").projectDir = file("../../../android_plugin/plugin")
