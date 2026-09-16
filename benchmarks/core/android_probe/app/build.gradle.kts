plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.aurorafox.corebenchmark"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aurorafox.corebenchmark"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        ndk {
            abiFilters += listOf("x86_64")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // The production runtime module and the Godot Android dependency both
    // provide the standard C++ runtime. The benchmark APK only needs one copy;
    // picking it here keeps the probe packaging deterministic without changing
    // the production Android plugin or its dependency graph.
    packaging {
        jniLibs {
            pickFirsts += "**/libc++_shared.so"
        }
    }
}

dependencies {
    implementation(project(":runtime"))
}
