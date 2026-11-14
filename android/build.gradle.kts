allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    if (project.name != "app") {
        plugins.withId("com.android.library") {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val setCompileSdk = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                    setCompileSdk.invoke(androidExt, 35)
                } catch (_: Exception) {}
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
