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
}
// Plugins whose Java code still targets Java 8 make javac warn that 8 is
// obsolete on every build; it is theirs to change, not ours.
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}
// cargokit (the Rust build glue in super_native_extensions 0.9.1 and
// irondash_engine_context 0.5.5, both under super_drag_and_drop) runs its
// build tool with project.exec { }, which Gradle 9 removed. Groovy falls back
// to an extra property of that name, so give those two projects an `exec`
// that does the same through ExecOperations. Remove once super_drag_and_drop
// is on a release without cargokit (0.10 builds Rust with build hooks).
interface InjectedExecOperations {
    @get:javax.inject.Inject
    val execOperations: org.gradle.process.ExecOperations
}
subprojects {
    if (name == "super_native_extensions" || name == "irondash_engine_context") {
        val execOperations = objects.newInstance<InjectedExecOperations>().execOperations
        val project = this
        extra["exec"] = KotlinClosure1<groovy.lang.Closure<*>, org.gradle.process.ExecResult>({
            val configureSpec = this
            execOperations.exec { project.configure(this, configureSpec) }
        })
    }
    // Both also compile against SDK 31, and the AndroidX libraries they now
    // resolve refuse anything below 33.
    if (name == "super_native_extensions" || name == "irondash_engine_context") {
        pluginManager.withPlugin("com.android.library") {
            extensions.getByType<com.android.build.api.variant.LibraryAndroidComponentsExtension>()
                .finalizeDsl { it.compileSdk = 36 }
        }
    }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
