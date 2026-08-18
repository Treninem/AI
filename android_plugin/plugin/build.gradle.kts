import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "AuroraFoxRuntime"
val pluginPackageName = "com.aurorafox.runtime"
val godotAddonDir = file("../../addons/$pluginName")

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
        }
    }
}

dependencies {
    implementation("org.godotengine:godot:4.7.1.stable")
    val sherpaAar = file("libs/sherpa-onnx-1.13.4.aar")
    if (sherpaAar.exists()) {
        implementation(files(sherpaAar))
    }
}

val copyDebugAar by tasks.registering(Copy::class) {
    dependsOn("assembleDebug")
    from(layout.buildDirectory.dir("outputs/aar"))
    include("$pluginName-debug.aar")
    into(file("$godotAddonDir/bin/debug"))
}

val copyReleaseAar by tasks.registering(Copy::class) {
    dependsOn("assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar"))
    include("$pluginName-release.aar")
    into(file("$godotAddonDir/bin/release"))
}

tasks.register("installGodotPlugin") {
    dependsOn(copyDebugAar, copyReleaseAar)
    doLast {
        println("AuroraFoxRuntime AARs copied to ${godotAddonDir.absolutePath}")
    }
}
