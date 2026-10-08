import java.util.Properties
import java.io.File
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    // Google Mobile Ads SDK 25.4.0이 전이 의존성으로 가져오는 2.7.0은 target SDK 36
    // 기기에서 WorkDatabase 초기화에 실패한다. 앱의 min SDK 24와 호환되는 안정판으로 고정한다.
    implementation("androidx.work:work-runtime:2.11.2")
    // 한국어 스크립트 모델은 APK에 번들한다(절대 규칙 1 — 네트워크 다운로드 금지).
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}

// 52_architect_week4_design.md §5.1 — AdMob App ID는 Manifest meta-data 전용이라
// dart-define으로 넣을 수 없다. gitignore된 android/ads.properties에서 읽는다.
// 파일이 없으면(클론 직후 등) 구글 공식 테스트 App ID로 폴백해 빌드가 깨지지 않게 한다.
val adsProps = Properties()
val adsPropsFile = rootProject.file("ads.properties")
if (adsPropsFile.exists()) {
    adsPropsFile.inputStream().use { adsProps.load(it) }
}

val googleTestAdPublisherId = "ca-app-pub-3940256099942544"
val releaseAdUnitIdPattern = Regex("^ca-app-pub-\\d{16}/\\d+$")
val releaseAdAppIdPattern = Regex("^ca-app-pub-\\d{16}~\\d+$")

fun decodeDartDefineValues(encodedDefines: String?): Map<String, String> =
    encodedDefines.orEmpty().split(',').mapNotNull { encodedDefine ->
        val decodedDefine = runCatching {
            String(Base64.getDecoder().decode(encodedDefine), Charsets.UTF_8)
        }.getOrNull() ?: return@mapNotNull null
        val separator = decodedDefine.indexOf('=')
        if (separator <= 0) return@mapNotNull null
        decodedDefine.substring(0, separator) to decodedDefine.substring(separator + 1)
    }.toMap()

fun isProductionAdUnitId(value: String?): Boolean =
    value != null && releaseAdUnitIdPattern.matches(value) &&
        !value.startsWith("$googleTestAdPublisherId/")

fun isProductionAdAppId(value: String?): Boolean =
    value != null && releaseAdAppIdPattern.matches(value) &&
        !value.startsWith("$googleTestAdPublisherId~")

val releaseAdMobAppId = adsProps.getProperty("admobAppId")?.trim()
val releaseAdMobAppIdProblem = when {
    !isProductionAdAppId(releaseAdMobAppId) ->
        "AdMob App ID is missing, invalid, or a Google test ID in android/ads.properties"
    else -> null
}

val releaseAdUnitConfigurationProblem = run {
    val dartDefines = decodeDartDefineValues(providers.gradleProperty("dart-defines").orNull)
    val missingOrInvalid = listOf("ADMOB_BANNER_UNIT_ID", "ADMOB_INTERSTITIAL_UNIT_ID")
        .filterNot { defineName -> isProductionAdUnitId(dartDefines[defineName]) }
    if (missingOrInvalid.isEmpty()) null
    else "Release AdMob unit IDs are missing, invalid, or Google test IDs; use tool/build_android_apk.ps1"
}

// T13 — 릴리스 키는 리포지토리 밖에서만 읽는다. 속성 파일은 아래 형식을 쓴다.
// storePassword=..., keyAlias=..., keyPassword=...
// 값은 어떤 Gradle 출력에도 포함하지 않는다.
val releaseKeystoreProperties = Properties()
val releaseKeystorePropertiesFile = File("F:/keys/PDF_daeri/key.properties")
if (releaseKeystorePropertiesFile.isFile) {
    releaseKeystorePropertiesFile.inputStream().use { releaseKeystoreProperties.load(it) }
}

fun signingProperty(name: String): String? =
    releaseKeystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

// CLAUDE.md가 지정한 외부 키 보관 위치다. Properties 파일의 Windows 경로 이스케이프에
// 의존하지 않아, 저장소 위치와 비밀값을 각각 한 곳에서만 관리한다.
val releaseKeystoreFile = File("F:/keys/PDF_daeri/release.jks")
val requiredSigningProperties = listOf("storePassword", "keyAlias", "keyPassword")
val missingSigningProperties = requiredSigningProperties.filter { signingProperty(it) == null }
val releaseSigningProblem = when {
    !releaseKeystorePropertiesFile.isFile -> "external key.properties file is missing"
    missingSigningProperties.isNotEmpty() ->
        "required properties are blank or missing: ${missingSigningProperties.joinToString(", ")}"
    !releaseKeystoreFile.isFile -> "external release.jks file is missing"
    else -> null
}
val releaseSigningReady = releaseSigningProblem == null

android {
    namespace = "com.kamanbi.pdf_daeri"
    compileSdk = flutter.compileSdkVersion
    // Keep release builds on NDK r28, which emits 16KB-page-compatible ELF
    // alignment for any native code built by this app.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kamanbi.pdf_daeri"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["admobAppId"] =
            releaseAdMobAppId ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = signingProperty("storePassword")
                keyAlias = signingProperty("keyAlias")
                keyPassword = signingProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 누락된 키로 debug 서명하는 폴백은 금지한다. 아래 release 작업 가드가
            // 필요한 외부 속성이 없을 때 실행을 중단한다.
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
            // ML Kit Text Recognition의 미사용 스크립트(중국어·일본어·데바나가리) 참조를
            // R8이 "누락된 클래스"로 오인하는 문제 해결(proguard-rules.pro 주석 참조).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// 어떤 방식으로 release APK/AAB를 요청해도 검증되지 않은 AdMob 설정은 패키징되지 않는다.
// 모든 release 태스크가 이 검증을 먼저 실행하며, ID 값은 로그에 절대 포함하지 않는다.
val verifyReleaseAdMobConfiguration = tasks.register("verifyReleaseAdMobConfiguration") {
    doLast {
        val problems = listOfNotNull(releaseAdMobAppIdProblem, releaseAdUnitConfigurationProblem)
        if (problems.isNotEmpty()) {
            throw GradleException("Release AdMob configuration is invalid: ${problems.joinToString("; ")}")
        }
    }
}

tasks.configureEach {
    if (name.contains("release", ignoreCase = true) &&
        name != "verifyReleaseAdMobConfiguration"
    ) {
        dependsOn(verifyReleaseAdMobConfiguration)
    }
}

// debug 개발 흐름은 키 파일 없이도 유지하되, release 계열 작업은 실제 서명 구성이
// 준비되지 않으면 산출물 생성 전에 중단한다.
if (!releaseSigningReady) {
    tasks.configureEach {
        if (name.endsWith("Release", ignoreCase = true)) {
            doFirst {
                error(
                    "Release signing is not configured: ${releaseSigningProblem.orEmpty()}",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
