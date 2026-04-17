def main [] {
    print "Starting project preparation..."

    print "Building project..."
    dub build --parallel
    if $env.LAST_EXIT_CODE != 0 {
        error make { msg: "Build failed" }
    }

    let exe_name = if ($nu.os-info.name == "windows") { "envman.exe" } else { "envman" }
    let exe_path = $"./($exe_name)"
    
    if not ($exe_name | path exists) {
        error make { msg: "Executable not found" }
    }

    dub test
    if $env.LAST_EXIT_CODE != 0 {
        error make { msg: "Unittests failed." }
    }

    # self check
    print "Checking package integrity..."
    run-external $exe_path "pkg" "check"
    if $env.LAST_EXIT_CODE != 0 {
        error make { msg: "Package check failed" }
    }

    print "Generating Markdown documentation..."
    run-external $exe_path "--gd"
    if $env.LAST_EXIT_CODE != 0 { error make { msg: "Markdown generation failed" } }

    print "Generating HTML documentation..."
    run-external $exe_path "--gh"
    if $env.LAST_EXIT_CODE != 0 { error make { msg: "HTML generation failed" } }

    print ""
    print "Finished before-commit jobs."
}