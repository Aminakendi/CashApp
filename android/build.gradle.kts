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
    afterEvaluate {
        val project = this
        if (project.name == "telephony") {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(androidExt, 34)
                } catch (e: Exception) {
                    try {
                        androidExt.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(androidExt, 34)
                    } catch (e2: Exception) {}
                }

                try {
                    val method = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    method.invoke(androidExt, "com.shounakmulay.telephony")
                } catch (e: Exception) {
                    // Ignore
                }
            }

            project.tasks.configureEach {
                if (name.startsWith("compile") && name.endsWith("Kotlin")) {
                    try {
                        val kotlinOptions = this.javaClass.getMethod("getKotlinOptions").invoke(this)
                        val setJvmTarget = kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java)
                        setJvmTarget.invoke(kotlinOptions, "11")
                    } catch (e: Exception) {
                        // Ignore
                    }
                }
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
