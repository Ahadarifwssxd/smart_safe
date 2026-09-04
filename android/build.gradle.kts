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

    // Compatibility shim: older Flutter plugins (e.g. flutter_sms) don't declare
    // a `namespace`, which Android Gradle Plugin 8+ now REQUIRES. For any Android
    // module missing one, derive it from its AndroidManifest `package` (falling
    // back to the Gradle group). Registered here (earliest) so it runs before
    // the project is evaluated. Fixes "Namespace not specified" builds.
    afterEvaluate {
        val androidExt =
            extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null && androidExt.namespace == null) {
            // Namespace shim: older plugins (e.g. flutter_sms) don't declare one,
            // which AGP 8+ requires. Derive it from the manifest package.
            val manifestFile = file("src/main/AndroidManifest.xml")
            val pkg =
                if (manifestFile.exists())
                    Regex("package=\"(.+?)\"")
                        .find(manifestFile.readText())
                        ?.groupValues?.get(1)
                else null
            androidExt.namespace = pkg ?: project.group.toString()
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
