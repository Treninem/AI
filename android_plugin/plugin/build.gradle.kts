import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "AuroraFoxRuntime"
val pluginPackageName = "com.aurorafox.runtime"
val godotAddonDir = file("../../addons/$pluginName")
val sherpaVersion = "1.13.4"
val sherpaAar = file("libs/sherpa-onnx-$sherpaVersion.aar")

android {
    namespace = pluginPackageName
    compileSdk = 35

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        minSdk = 26
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
        setProperty("archivesBaseName", pluginName)

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

dependencies {
    implementation("org.godotengine:godot:4.7.1.stable")
    if (sherpaAar.exists()) {
        // Do not try to embed a local AAR inside AuroraFoxRuntime. Godot exports
        // sherpa-onnx as a separate AAR next to this plugin.
        compileOnly(files(sherpaAar))
    }
}

val copyDebugAar by tasks.registering(Copy::class) {
    dependsOn("assembleDebug")
    from(layout.buildDirectory.dir("outputs/aar")) {
        include("$pluginName-debug.aar")
    }
    if (sherpaAar.exists()) {
        from(sherpaAar)
    }
    into(file("$godotAddonDir/bin/debug"))
}

val copyReleaseAar by tasks.registering(Copy::class) {
    dependsOn("assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar")) {
        include("$pluginName-release.aar")
    }
    if (sherpaAar.exists()) {
        from(sherpaAar)
    }
    into(file("$godotAddonDir/bin/release"))
}

tasks.register("installGodotPluginRelease") {
    dependsOn(copyReleaseAar)
    doLast {
        val releasePlugin = file("$godotAddonDir/bin/release/$pluginName-release.aar")
        val releaseSherpa = file("$godotAddonDir/bin/release/sherpa-onnx-$sherpaVersion.aar")
        check(releasePlugin.exists()) { "AuroraFoxRuntime release AAR build output is missing" }
        check(releaseSherpa.exists()) { "sherpa-onnx release AAR was not installed into Godot addon" }
        println("AuroraFoxRuntime release + sherpa-onnx AARs copied to ${godotAddonDir.absolutePath}")
    }
}

tasks.register("installGodotPlugin") {
    dependsOn(copyDebugAar, copyReleaseAar)
    doLast {
        val debugPlugin = file("$godotAddonDir/bin/debug/$pluginName-debug.aar")
        val releasePlugin = file("$godotAddonDir/bin/release/$pluginName-release.aar")
        val debugSherpa = file("$godotAddonDir/bin/debug/sherpa-onnx-$sherpaVersion.aar")
        val releaseSherpa = file("$godotAddonDir/bin/release/sherpa-onnx-$sherpaVersion.aar")
        check(debugPlugin.exists() && releasePlugin.exists()) { "AuroraFoxRuntime AAR build output is missing" }
        check(debugSherpa.exists() && releaseSherpa.exists()) { "sherpa-onnx AAR was not installed into Godot addon" }
        println("AuroraFoxRuntime + sherpa-onnx AARs copied to ${godotAddonDir.absolutePath}")
    }
}
