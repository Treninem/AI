import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "AuroraFoxRuntime"
val pluginPackageName = "com.aurorafox.runtime"
val godotAddonDir = file("../../addons/$pluginName")
val sherpaVersion = "1.13.4"
val sherpaAar = file("libs/sherpa-onnx-$sherpaVersion.aar")
val pdfBoxAndroidVersion = "2.0.27.0"
val tesseractAndroidVersion = "4.9.0"
val generatedOcrAssets = layout.buildDirectory.dir("generated/aurorafoxOcrAssets")
val ocrModels = listOf(
    Triple("eng.traineddata", "https://github.com/tesseract-ocr/tessdata_fast/raw/4.1.0/eng.traineddata", "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"),
    Triple("rus.traineddata", "https://github.com/tesseract-ocr/tessdata_fast/raw/4.1.0/rus.traineddata", "e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225"),
)

fun sha256(file: File): String {
    val md = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(64 * 1024)
        while (true) { val read = input.read(buffer); if (read <= 0) break; md.update(buffer, 0, read) }
    }
    return md.digest().joinToString("") { "%02x".format(it) }
}

val prepareOcrAssets by tasks.registering {
    outputs.dir(generatedOcrAssets)
    doLast {
        val tessdata = generatedOcrAssets.get().dir("tessdata").asFile.apply { mkdirs() }
        ocrModels.forEach { (name, url, expectedSha) ->
            val target = File(tessdata, name)
            if (!target.isFile || sha256(target) != expectedSha) {
                val tmp = File(tessdata, "$name.tmp")
                URI(url).toURL().openStream().use { input -> tmp.outputStream().use { output -> input.copyTo(output) } }
                val actual = sha256(tmp)
                check(actual == expectedSha) { "OCR model SHA-256 mismatch for $name: $actual" }
                if (target.exists()) target.delete()
                check(tmp.renameTo(target) || run { tmp.copyTo(target, overwrite = true); tmp.delete(); true }) { "Could not install $name" }
            }
        }
    }
}

android {
    namespace = pluginPackageName
    compileSdk = 35
    buildFeatures { buildConfig = true }
    defaultConfig {
        minSdk = 26
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
        setProperty("archivesBaseName", pluginName)
        externalNativeBuild { cmake { cppFlags += listOf("-std=c++17"); arguments += listOf("-DANDROID_STL=c++_shared") } }
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }
    sourceSets.getByName("main").assets.srcDir(generatedOcrAssets)
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
}

tasks.named("preBuild").configure { dependsOn(prepareOcrAssets) }

dependencies {
    implementation("org.godotengine:godot:4.7.1.stable")
    implementation("com.tom-roush:pdfbox-android:$pdfBoxAndroidVersion")
    implementation("com.github.adaptech-cz.Tesseract4Android:tesseract4android:$tesseractAndroidVersion")
    if (sherpaAar.exists()) compileOnly(files(sherpaAar))
}

val copyDebugAar by tasks.registering(Copy::class) {
    dependsOn("assembleDebug")
    from(layout.buildDirectory.dir("outputs/aar")) { include("$pluginName-debug.aar") }
    if (sherpaAar.exists()) from(sherpaAar)
    into(file("$godotAddonDir/bin/debug"))
}

val copyReleaseAar by tasks.registering(Copy::class) {
    dependsOn("assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar")) { include("$pluginName-release.aar") }
    if (sherpaAar.exists()) from(sherpaAar)
    into(file("$godotAddonDir/bin/release"))
}

tasks.register("installGodotPluginRelease") {
    dependsOn(copyReleaseAar)
    doLast {
        val releasePlugin = file("$godotAddonDir/bin/release/$pluginName-release.aar")
        val releaseSherpa = file("$godotAddonDir/bin/release/sherpa-onnx-$sherpaVersion.aar")
        check(releasePlugin.exists()) { "AuroraFoxRuntime release AAR build output is missing" }
        check(releaseSherpa.exists()) { "sherpa-onnx release AAR was not installed into Godot addon" }
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
    }
}
